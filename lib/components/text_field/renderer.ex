defmodule ScenicWidgets.TextField.Renderer do
  @multiline_row_y_offset 4

  @moduledoc """
  Rendering logic for the TextField component.

  ## Architecture

  The TextField uses a two-panel layout when line numbers are enabled:

  ```
  TextField Frame
  ├── Line Number Gutter (fixed width, vertical scroll only)
  │   └── Scissor clip (gutter width × frame height)
  │       └── Group (translated by vertical scroll offset only)
  │           └── Line number primitives
  │
  └── Text Content Area (remaining width, full scroll)
      └── Scissor clip (content width × frame height)
          └── Group (translated by both scroll offsets)
              └── Text line primitives
              └── Cursor
              └── Selection
  ```

  Key features:
  - Line numbers scroll vertically WITH text but NOT horizontally
  - Both areas share the same vertical scroll state
  - Primitives are managed dynamically (no pre-allocation needed)
  - When `show_line_numbers: false`, only text content area is rendered
  """

  alias Scenic.Graph
  alias Scenic.Primitives
  alias ScenicWidgets.TextField.State
  alias ScenicWidgets.TextField.MatchingBrace
  alias ScenicWidgets.TextField.Wrapping
  require Logger

  @doc """
  Initial render of the TextField component.
  Scrollbars are rendered inside content_group to ensure proper z-order.
  """
  def initial_render(graph, %State{} = state) do
    graph
    |> render_background(state)
    |> render_border(state)
    |> render_gutter_and_content(state)
  end

  @doc """
  Materializes the folded and wrapped display projection when its inputs change.

  This belongs outside the wheel-event hot path: a display projection can be
  expensive for a large wrapped document, while scrolling changes only which
  cached rows are visible.
  """
  def prepare_display_cache(%State{} = state) do
    if display_cache_valid?(state) do
      state
    else
      {display_lines, mapping, memo} = build_display_projection_with_memo(state)

      %{
        state
        | display_cache_key: display_cache_key(state),
          display_lines: display_lines,
          display_line_mapping: mapping,
          wrap_memo: memo
      }
    end
  end

  defp display_cache_key(%State{} = state) do
    {state.lines, state.folds, state.wrap_mode, content_area_width(state), state.font,
     state.tab_width}
  end

  defp display_cache_valid?(%State{} = state) do
    is_list(state.display_lines) and is_list(state.display_line_mapping) and
      state.display_cache_key == display_cache_key(state)
  end

  # The folded+wrapped projection — `{display_lines, mapping}` — for this
  # state: the cached one when its inputs are unchanged, otherwise built (and
  # NOT stored: the caller may hold a state it cannot write back). Every
  # source→display question should go through here rather than re-wrapping
  # the document; on a large wrapped file that walk is the whole cost of a
  # cursor move.
  defp projection(%State{} = state) do
    if display_cache_valid?(state),
      do: {state.display_lines, state.display_line_mapping},
      else: build_display_projection(state)
  end

  @doc """
  Update render - intelligently updates only what changed.
  """
  def update_render(graph, old_state, new_state) do
    # If gutter width changed, need full rebuild of gutter and content areas
    if old_state.line_number_width != new_state.line_number_width do
      rebuild_gutter_and_content(graph, new_state)
    else
      graph
      |> update_border_if_changed(old_state, new_state)
      |> update_gutter_scroll(old_state, new_state)
      |> update_content_scroll(old_state, new_state)
      |> update_lines_if_changed(old_state, new_state)
      |> update_highlights_if_changed(old_state, new_state)
      |> update_semantic_if_changed(old_state, new_state)
      |> update_line_numbers_if_changed(old_state, new_state)
      |> update_fold_gutter_if_changed(old_state, new_state)
      |> update_selection_if_changed(old_state, new_state)
      |> update_search_matches_if_changed(old_state, new_state)
      |> update_matching_braces_if_changed(old_state, new_state)
      |> update_cursor_guides_if_changed(old_state, new_state)
      |> update_cursor_if_changed(old_state, new_state)
      |> update_scrollbars_if_changed(old_state, new_state)
    end
  end

  # Rebuild both gutter and content when gutter width changes
  defp rebuild_gutter_and_content(graph, %State{show_line_numbers: true} = state) do
    graph
    |> rebuild_gutter(state)
    |> rebuild_content_area(state)
  end

  defp rebuild_gutter_and_content(graph, %State{show_line_numbers: false} = state) do
    rebuild_content_area(graph, state)
  end

  @doc """
  Quick update for cursor visibility (blink animation).
  """
  def update_cursor_visibility(graph, %State{focused: focused, cursor_visible: cursor_visible}) do
    should_show_cursor = focused and cursor_visible

    graph
    |> Graph.modify(:cursor, fn primitive ->
      Primitives.update_opts(primitive, hidden: !should_show_cursor)
    end)
  end

  # ===== INITIAL RENDER HELPERS =====

  defp render_background(graph, %State{colors: %{background: :clear}}), do: graph

  defp render_background(graph, %State{frame: frame, colors: colors}) do
    graph
    |> Primitives.rect(
      {frame.size.width, frame.size.height},
      fill: colors.background,
      id: :background
    )
  end

  defp render_border(graph, %State{frame: frame, colors: colors, focused: focused} = state) do
    border_color = if focused, do: colors.focused_border, else: colors.border
    {w, h} = {frame.size.width, frame.size.height}
    sides = state.border_sides || [:top, :right, :bottom, :left]

    # One line per requested side, grouped under :border. The stroke lives on
    # the group so update_border_if_changed can restyle every side with a
    # single Graph.modify (children inherit the group's stroke).
    graph
    |> Primitives.group(
      fn g -> Enum.reduce(sides, g, &border_line(&2, &1, w, h)) end,
      stroke: {1, border_color},
      id: :border
    )
  end

  defp border_line(g, :top, w, _h), do: Primitives.line(g, {{0, 0}, {w, 0}})
  defp border_line(g, :bottom, w, h), do: Primitives.line(g, {{0, h}, {w, h}})
  defp border_line(g, :left, _w, h), do: Primitives.line(g, {{0, 0}, {0, h}})
  defp border_line(g, :right, w, h), do: Primitives.line(g, {{w, 0}, {w, h}})

  # Render both the gutter (line numbers) and text content areas
  defp render_gutter_and_content(graph, %State{show_line_numbers: false} = state) do
    # No line numbers - just render text content area taking full width
    render_text_content_area(graph, state, 0, state.frame.size.width)
  end

  defp render_gutter_and_content(
         graph,
         %State{show_line_numbers: true, line_number_width: gutter_width} = state
       ) do
    content_width = state.frame.size.width - gutter_width

    graph
    |> render_line_number_gutter(state, gutter_width)
    |> render_text_content_area(state, gutter_width, content_width)
  end

  # Render the line number gutter with its own scissor clip
  # Scrolls vertically with text but NOT horizontally
  defp render_line_number_gutter(graph, %State{} = state, gutter_width) do
    frame_height = state.frame.size.height
    scroll = state.scroll
    line_height = State.line_height(state)

    # Build line number to source line mapping for wrapped lines
    # This returns one entry per DISPLAY line
    {_display_lines, line_mapping} = projection(state)
    foldable_lines = ScenicWidgets.TextField.Folding.foldable_lines(state.lines)

    Primitives.group(
      graph,
      fn outer_g ->
        # Inner group that scrolls vertically
        Primitives.group(
          outer_g,
          fn inner_g ->
            # Render line numbers for each display line
            {gutter_first, gutter_last} = State.visible_display_range(state, length(line_mapping))

            line_mapping
            |> Enum.with_index(1)
            |> Enum.filter(fn {_entry, n} -> n >= gutter_first and n <= gutter_last end)
            |> Enum.reduce(inner_g, fn {{source_line_num, is_first_of_source}, display_line_num},
                                       g ->
              y_pos = (display_line_num - 1) * line_height + line_height
              # Right-align
              x_pos = gutter_width - 10

              # Only show line number for first display line of each source line
              line_text = if is_first_of_source, do: "#{source_line_num}", else: ""

              g
              |> maybe_render_fold_triangle(
                state,
                source_line_num,
                display_line_num,
                is_first_of_source,
                foldable_lines,
                line_height
              )
              |> Primitives.text(
                line_text,
                translate: {x_pos, y_pos},
                fill: state.colors.line_numbers,
                font_size: state.font.size,
                text_align: :right,
                id: {:line_number, display_line_num}
              )
            end)
          end,
          id: :gutter_content,
          # Only vertical scroll
          translate: {0, -scroll.offset_y}
        )
      end,
      id: :gutter_group,
      scissor: {gutter_width, frame_height}
    )
  end

  defp maybe_render_fold_triangle(
         graph,
         state,
         source_line,
         display_line,
         true,
         foldable_lines,
         line_height
       ) do
    folded? = MapSet.member?(state.folds || MapSet.new(), source_line)
    hovered? = state.fold_hover_line == source_line

    if MapSet.member?(foldable_lines, source_line) and (folded? or hovered?) do
      cx = 7
      # Line numbers are baseline-positioned at the bottom of the row. Their
      # optical centre is therefore below the geometric half-height.
      cy = display_line * line_height - state.font.size * 0.35
      size = 5

      points =
        if folded? do
          {{cx - 2, cy - size}, {cx - 2, cy + size}, {cx + size, cy}}
        else
          {{cx - size, cy - 2}, {cx + size, cy - 2}, {cx, cy + size}}
        end

      Primitives.triangle(graph, points,
        fill: state.colors.line_numbers,
        id: {:fold_toggle, source_line}
      )
    else
      graph
    end
  end

  defp maybe_render_fold_triangle(graph, _state, _source, _display, _first, _foldable, _height),
    do: graph

  defp update_fold_gutter_if_changed(graph, old_state, new_state) do
    cond do
      old_state.folds != new_state.folds ->
        graph
        |> rebuild_content_area(new_state)
        |> rebuild_gutter_if_shown(new_state)

      old_state.fold_hover_line != new_state.fold_hover_line ->
        rebuild_gutter_if_shown(graph, new_state)

      true ->
        graph
    end
  end

  # Render the main text content area with full scrolling
  defp render_text_content_area(graph, %State{} = state, x_offset, content_width) do
    frame_height = state.frame.size.height
    scroll = state.scroll
    line_height = State.line_height(state)
    text_padding = 10

    # Calculate wrapped display lines
    display_lines = wrap_lines(state)

    # text_y_offset no longer used - single-line mode uses text_base: :middle
    text_y_offset = 0

    Primitives.group(
      graph,
      fn outer_g ->
        outer_g
        |> render_cursor_guides(state, content_width, frame_height, text_padding, line_height)
        # Inner group that scrolls both directions
        |> Primitives.group(
          fn inner_g ->
            inner_g
            |> render_semantic_content(state)
            |> render_selection(state)
            |> render_search_matches(state)
            |> render_matching_braces(state, text_padding, line_height)
            |> render_text_lines(state, display_lines, text_padding, line_height, text_y_offset)
            |> render_cursor(state, text_padding, line_height, text_y_offset)
          end,
          id: :text_content,
          translate: {-scroll.offset_x, -scroll.offset_y}
        )
        # Render scrollbars INSIDE content_group, after text, so they're on top
        |> render_scrollbars_in_content(state, content_width, frame_height)
      end,
      id: :content_group,
      translate: {x_offset, 0},
      scissor: {content_width, frame_height}
    )
  end

  defp render_matching_braces(graph, state, padding, line_height) do
    geometries = matching_brace_geometries(state, padding, line_height)

    [:matching_brace_current, :matching_brace_partner]
    |> Enum.reduce(graph, fn id, acc ->
      {size, translate, hidden?} = Map.get(geometries, id, {{1, line_height}, {0, 0}, true})

      Primitives.rect(acc, size,
        id: id,
        translate: translate,
        fill: :clear,
        stroke: {1, {255, 215, 0}},
        hidden: hidden?
      )
    end)
  end

  defp render_cursor_guides(graph, state, width, height, padding, line_height) do
    {x, y} = cursor_guide_position(state, padding, line_height)
    color = {255, 215, 0, 30}

    graph
    |> Primitives.rect({width, line_height},
      id: :current_line_highlight,
      translate: {0, y},
      fill: color,
      hidden: not state.highlight_current_line
    )
    |> Primitives.rect({max(1, State.char_width(state)), height},
      id: :current_column_highlight,
      translate: {x, 0},
      fill: color,
      hidden: not state.highlight_current_column
    )
  end

  defp cursor_guide_position(state, padding, line_height) do
    {display_line, display_col} = source_to_display_cursor(state, state.cursor)
    display_text = Enum.at(wrap_lines(state), display_line - 1, "")
    before = String.slice(display_text, 0, max(0, display_col - 1))

    {
      padding + State.string_width(state, before) - state.scroll.offset_x,
      (display_line - 1) * line_height + @multiline_row_y_offset - state.scroll.offset_y
    }
  end

  defp matching_brace_geometries(%State{show_matching_brace: false}, _padding, _height),
    do: %{}

  defp matching_brace_geometries(state, padding, line_height) do
    case MatchingBrace.find(state.lines, state.cursor) do
      nil ->
        %{}

      {current, partner} ->
        [{current, :matching_brace_current}, {partner, :matching_brace_partner}]
        |> Map.new(fn {{line, col}, id} ->
          {display_line, display_col} = source_to_display_cursor(state, {line, col})
          display_text = Enum.at(wrap_lines(state), display_line - 1, "")
          before = String.slice(display_text, 0, max(0, display_col - 1))
          x = padding + State.string_width(state, before)
          y = (display_line - 1) * line_height + @multiline_row_y_offset

          width =
            max(2, State.string_width(state, String.at(display_text, display_col - 1) || " "))

          {id, {{width, line_height}, {x, y}, false}}
        end)
    end
  end

  # Render scrollbars inside content_group (positioned relative to content area)
  defp render_scrollbars_in_content(graph, %State{scroll: scroll}, content_width, frame_height) do
    scrollbar_width = 10
    scrollbar_padding = 2

    graph
    |> render_v_scrollbar_in_content(
      scroll,
      content_width,
      frame_height,
      scrollbar_width,
      scrollbar_padding
    )
    |> render_h_scrollbar_in_content(
      scroll,
      content_width,
      frame_height,
      scrollbar_width,
      scrollbar_padding
    )
  end

  defp render_v_scrollbar_in_content(
         graph,
         scroll,
         content_width,
         frame_height,
         scrollbar_width,
         scrollbar_padding
       ) do
    if Widgex.Scroll.ScrollState.scrollable_y?(scroll) do
      # Position at right edge of content area
      track_x = content_width - scrollbar_width - scrollbar_padding
      track_height = frame_height - scrollbar_padding * 2

      # Reduce height if horizontal scrollbar exists
      track_height =
        if Widgex.Scroll.ScrollState.scrollable_x?(scroll) do
          track_height - scrollbar_width - scrollbar_padding
        else
          track_height
        end

      {thumb_y_ratio, thumb_height_ratio} = Widgex.Scroll.ScrollState.scrollbar_thumb(scroll, :y)
      scale = track_height / scroll.viewport_height
      thumb_height = max(thumb_height_ratio * scale, 20)
      thumb_y = thumb_y_ratio * scale

      graph
      |> Primitives.rrect({scrollbar_width, track_height, 4},
        id: :scrollbar_y_track,
        fill: {80, 80, 80, 200},
        translate: {track_x, scrollbar_padding}
      )
      |> Primitives.rrect({scrollbar_width, thumb_height, 4},
        id: :scrollbar_y_thumb,
        fill: {160, 160, 160, 255},
        translate: {track_x, scrollbar_padding + thumb_y}
      )
    else
      graph
    end
  end

  defp render_h_scrollbar_in_content(
         graph,
         scroll,
         content_width,
         frame_height,
         scrollbar_width,
         scrollbar_padding
       ) do
    if Widgex.Scroll.ScrollState.scrollable_x?(scroll) do
      # Position at bottom of content area
      track_x = scrollbar_padding
      track_y = frame_height - scrollbar_width - scrollbar_padding
      track_width = content_width - scrollbar_padding * 2

      # Reduce width if vertical scrollbar exists
      track_width =
        if Widgex.Scroll.ScrollState.scrollable_y?(scroll) do
          track_width - scrollbar_width - scrollbar_padding
        else
          track_width
        end

      {thumb_x_ratio, thumb_width_ratio} = Widgex.Scroll.ScrollState.scrollbar_thumb(scroll, :x)
      scale = track_width / scroll.viewport_width
      thumb_width = max(thumb_width_ratio * scale, 20)
      thumb_x = thumb_x_ratio * scale

      graph
      |> Primitives.rrect({track_width, scrollbar_width, 4},
        id: :scrollbar_x_track,
        fill: {80, 80, 80, 200},
        translate: {track_x, track_y}
      )
      |> Primitives.rrect({thumb_width, scrollbar_width, 4},
        id: :scrollbar_x_thumb,
        fill: {160, 160, 160, 255},
        translate: {track_x + thumb_x, track_y}
      )
    else
      graph
    end
  end

  # Render all text lines
  # Uses explicit x-positioning for indentation because Scenic renders
  # leading spaces as zero-width
  # For single-line mode, uses text_base: :middle for perfect vertical centering
  defp render_text_lines(
         graph,
         %State{mode: mode, frame: frame} = state,
         display_lines,
         x_offset,
         line_height,
         _text_y_offset \\ 0
       ) do
    # Draw only the lines that can be seen (plus a small buffer). Each is
    # positioned at its ABSOLUTE y, so the content group's scroll translate
    # keeps working unchanged. Rendering an entire document builds one
    # primitive per line — seconds of work on a large file.
    {first, last} = State.visible_display_range(state, length(display_lines))
    row_segments = highlight_row_segments(state, display_lines, first, last)

    display_lines
    |> Enum.slice(first - 1, max(last - first + 1, 0))
    |> Enum.with_index(first)
    |> Enum.reduce(graph, fn {line_text, line_num}, g ->
      # For single-line mode, use text_base: :middle and center in frame
      # For multi-line, use standard baseline positioning
      # Small +2 adjustment accounts for visual centering vs typographic middle
      {y_pos, text_opts} =
        case mode do
          :single_line ->
            {frame.size.height / 2 + 2, [text_base: :middle]}

          _ ->
            {(line_num - 1) * line_height + line_height, []}
        end

      case Map.get(row_segments, line_num) do
        {segment_text, spans} when spans != [] ->
          render_highlighted_row(g, state, line_num, segment_text, spans, x_offset, y_pos)

        _ ->
          # Expand tabs and get indent width + trimmed content
          # Scenic renders leading spaces as zero-width, so we position explicitly
          {indent_width, content} = State.expand_tabs_with_indent(state, line_text)
          line_x = x_offset + indent_width

          Primitives.text(
            g,
            content,
            [
              {:translate, {line_x, y_pos}},
              {:fill, state.colors.text},
              {:font_size, state.font.size},
              {:font, state.font.name},
              {:id, {:text_line, line_num}}
              | text_opts
            ]
          )
      end
    end)
  end

  # ===== HIGHLIGHTED ROWS =====
  #
  # A row with token spans is drawn as one text primitive per RUN — Scenic
  # text has a single fill and font, so a keyword in bold next to plain text
  # is two primitives. Positions come from measured widths (every face of
  # the family shares the monospace advance), so runs sit on the same grid
  # as the plain row they replace. Only the rows in the render window are
  # ever split, and only while the published text still equals the row's
  # current text — a lexer that lags typing colours nothing wrong.

  # %{display_row => {segment_text_with_tabs_expanded, [{start, end, style}]}}
  # for the visible rows whose source line has current, non-empty highlights.
  defp highlight_row_segments(
         %State{highlights: highlights, highlight_styles: styles} = state,
         display_lines,
         first,
         last
       )
       when is_map(highlights) and map_size(highlights) > 0 and map_size(styles) > 0 and
              state.mode != :single_line do
    {_lines, mapping} = projection(state)

    display_lines
    |> windowed_source_runs(mapping, first, last)
    |> Enum.reduce(%{}, fn {source, {first_row, segments}}, acc ->
      source_text = Enum.at(state.lines, source - 1, "")

      case Map.get(highlights, source) do
        {^source_text, spans} when spans != [] ->
          segments
          |> segment_source_starts(source_text)
          |> Enum.with_index(first_row)
          |> Enum.reduce(acc, fn {{segment, seg_start}, row}, acc2 ->
            case row_spans(state, segment, seg_start, spans, styles) do
              {_expanded, []} -> acc2
              entry -> Map.put(acc2, row, entry)
            end
          end)

        _stale_or_missing ->
          acc
      end
    end)
  end

  defp highlight_row_segments(_state, _display_lines, _first, _last), do: %{}

  # Clip a source line's spans to one wrapped segment, translate them into
  # the segment's tab-expanded coordinates, and resolve their styles.
  defp row_spans(state, segment, seg_start, spans, styles) do
    seg_len = String.length(segment)
    {expanded, positions} = expand_tabs_positions(segment, state.tab_width || 4)

    clipped =
      spans
      |> Enum.flat_map(fn {s, e, class} ->
        a = max(s - seg_start, 0)
        b = min(e - seg_start, seg_len)

        case {b > a, Map.get(styles, class)} do
          {true, %{} = style} -> [{elem(positions, a), elem(positions, b), style}]
          _ -> []
        end
      end)

    {expanded, clipped}
  end

  # {expanded_text, positions} — positions is a tuple mapping every raw
  # grapheme index (and the end index) to its expanded column, so span
  # boundaries survive tab expansion.
  defp expand_tabs_positions(text, tab_width) do
    {chunks, positions, _col} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], [], 0}, fn
        "\t", {chunks, positions, col} ->
          width = tab_width - rem(col, tab_width)
          {[String.duplicate(" ", width) | chunks], [col | positions], col + width}

        grapheme, {chunks, positions, col} ->
          {[grapheme | chunks], [col | positions], col + 1}
      end)

    expanded = chunks |> Enum.reverse() |> IO.iodata_to_binary()
    end_col = String.length(expanded)
    positions_tuple = positions |> Enum.reverse() |> Kernel.++([end_col]) |> List.to_tuple()
    {expanded, positions_tuple}
  end

  defp render_highlighted_row(graph, state, line_num, expanded, spans, x_offset, y_pos) do
    total = String.length(expanded)

    # Styled spans plus the plain gaps between them, in order.
    {runs, cursor} =
      Enum.reduce(spans, {[], 0}, fn {s, e, style}, {acc, pos} ->
        acc = if s > pos, do: [{pos, s, nil} | acc], else: acc
        {[{s, e, style} | acc], max(e, pos)}
      end)

    runs = if cursor < total, do: [{cursor, total, nil} | runs], else: runs

    Primitives.group(
      graph,
      fn g ->
        Enum.reduce(Enum.reverse(runs), g, fn {s, e, style}, g2 ->
          text = String.slice(expanded, s, e - s)
          run_x = x_offset + State.string_width(state, String.slice(expanded, 0, s))
          run_width = State.string_width(state, text)
          render_run(g2, state, text, style, run_x, run_width, y_pos)
        end)
      end,
      id: {:text_line, line_num}
    )
  end

  defp render_run(graph, state, text, style, run_x, run_width, y_pos) do
    style = style || %{}
    fill = Map.get(style, :fill) || state.colors.text
    font = Map.get(style, :font) || state.font.name

    # Scenic draws leading spaces zero-width: shift the text start instead.
    trimmed = String.trim_leading(text, " ")

    lead_x =
      State.string_width(
        state,
        String.duplicate(" ", String.length(text) - String.length(trimmed))
      )

    graph =
      if trimmed == "" do
        graph
      else
        Primitives.text(graph, trimmed,
          translate: {run_x + lead_x, y_pos},
          fill: fill,
          font_size: state.font.size,
          font: font
        )
      end

    if Map.get(style, :underline) do
      y = y_pos + 3

      Primitives.line(graph, {{run_x, y}, {run_x + run_width, y}}, stroke: {1, fill})
    else
      graph
    end
  end

  # Render the cursor
  # text_y_offset is used for vertical centering in single-line mode
  defp render_cursor(
         graph,
         %State{
           cursor: {line, col},
           cursor_visible: visible,
           focused: focused,
           cursor_mode: cursor_mode,
           colors: colors,
           frame: frame,
           mode: mode
         } = state,
         x_offset,
         line_height,
         _text_y_offset \\ 0
       ) do
    # Get cursor position in display line coordinates
    {display_line, display_col} = source_to_display_cursor(state, {line, col})

    # Get the text before cursor to calculate accurate position
    display_lines = wrap_lines(state)
    current_line = Enum.at(display_lines, display_line - 1, "")
    text_before_cursor = String.slice(current_line, 0, max(0, display_col - 1))

    # Calculate cursor X position
    cursor_x = x_offset + State.string_width(state, text_before_cursor)

    # For single-line mode, center cursor vertically (text uses text_base: :middle)
    # For multi-line, use standard line-based positioning
    cursor_y =
      case mode do
        :single_line ->
          # Text is centered at frame_height/2 + 2 with text_base: :middle
          # Cursor needs no extra adjustment
          frame.size.height / 2 - line_height / 2

        _ ->
          # Standard multi-line: position at line top + small offset
          (display_line - 1) * line_height + @multiline_row_y_offset
      end

    # Calculate cursor width based on mode
    cursor_width =
      case cursor_mode do
        :cursor -> 2
        :block -> State.char_width(state)
        :hidden -> 0
      end

    should_show = focused and visible and cursor_mode != :hidden

    graph
    |> Primitives.rect(
      {cursor_width, line_height},
      translate: {cursor_x, cursor_y},
      fill: colors.cursor,
      hidden: !should_show,
      id: :cursor
    )
  end

  # Render hidden semantic content for accessibility
  defp render_semantic_content(graph, %State{} = state) do
    graph
    |> Primitives.text(
      State.get_text(state),
      id: :semantic_content,
      hidden: true,
      semantic: semantic_metadata(state)
    )
  end

  # Render selection highlighting
  defp render_selection(graph, %State{selection: nil}), do: graph

  defp render_selection(graph, %State{selection: {start_pos, end_pos}} = state) do
    # Normalize selection
    {{sel_start_line, sel_start_col}, {sel_end_line, sel_end_col}} =
      if start_pos <= end_pos, do: {start_pos, end_pos}, else: {end_pos, start_pos}

    if sel_start_line == sel_end_line and sel_start_col == sel_end_col do
      graph
    else
      render_selection_rectangles(
        graph,
        state,
        {sel_start_line, sel_start_col},
        {sel_end_line, sel_end_col}
      )
    end
  end

  # Handle selection in map format (from buffer state)
  defp render_selection(graph, %State{selection: %{start: start_pos, end: end_pos}} = state) do
    render_selection(graph, %{state | selection: {start_pos, end_pos}})
  end

  # Selection rectangles, one per visible DISPLAY row the selection touches.
  # Rows come from the projection (folds, wrapping) and columns are clipped
  # to each wrapped segment, so a selection across a wrapped paragraph paints
  # exactly the glyphs it covers. Only rows in the render window get
  # primitives; the rest are drawn when the window advances.
  defp render_selection_rectangles(
         graph,
         state,
         {sel_start_line, sel_start_col},
         {sel_end_line, sel_end_col}
       ) do
    x_offset = 10
    line_height = State.line_height(state)
    # Selection highlight - steel blue with good visibility on dark backgrounds
    selection_color = {:color_rgba, {70, 130, 180, 180}}

    {display_lines, mapping} = projection(state)
    {first, last} = State.visible_display_range(state, length(display_lines))

    windowed_source_runs(display_lines, mapping, first, last)
    |> Enum.filter(fn {source, _run} -> source >= sel_start_line and source <= sel_end_line end)
    |> Enum.reduce(graph, fn {source, {first_row, segments}}, acc_graph ->
      source_text = Enum.at(state.lines, source - 1, "")

      # Selected character range on this source line, 0-based, end-exclusive.
      from = if source == sel_start_line, do: sel_start_col - 1, else: 0

      to =
        if source == sel_end_line,
          do: sel_end_col - 1,
          else: String.length(source_text)

      segments
      |> segment_source_starts(source_text)
      |> Enum.with_index(first_row)
      |> Enum.reduce(acc_graph, fn {{segment, seg_start}, row}, g ->
        seg_len = String.length(segment)
        a = max(seg_start, from)
        b = min(seg_start + seg_len, to)
        # A blank line inside the selection still shows a sliver.
        covered? = b > a or (seg_len == 0 and to > from)

        if covered? and row >= first and row <= last do
          lead = State.string_width(state, String.slice(segment, 0, a - seg_start))
          width = max(1, State.string_width(state, String.slice(segment, a - seg_start, b - a)))

          Primitives.rect(
            g,
            {width, line_height},
            fill: selection_color,
            translate: {x_offset + lead, (row - 1) * line_height + @multiline_row_y_offset},
            id: {:selection_highlight, row}
          )
        else
          g
        end
      end)
    end)
  end

  # ===== SEARCH MATCH HIGHLIGHTING =====
  #
  # Only the matches on rows inside the render window become primitives. A
  # common word in a long document has thousands of matches; drawing every
  # one (and re-wrapping its line to place it) froze the editor for seconds
  # on each keystroke in the search box. Rows outside the window get their
  # highlights when the window next advances, exactly like the text itself.
  #
  # Positions come from the cached display projection, so folds and wrapping
  # are honoured for free, and columns are mapped through the same
  # source→display rule the cursor uses (spaces consumed at a wrap boundary),
  # so a highlight on a wrapped continuation row sits under its text instead
  # of drifting one character right per boundary.
  defp render_search_matches(graph, %State{search_matches: nil}), do: graph
  defp render_search_matches(graph, %State{search_matches: []}), do: graph

  defp render_search_matches(
         graph,
         %State{search_matches: matches, search_current_index: current_idx} = state
       ) do
    x_offset = 10
    line_height = State.line_height(state)
    match_color = {:color_rgba, {255, 255, 0, 120}}
    current_match_color = {:color_rgba, {255, 165, 0, 180}}

    {display_lines, mapping} = projection(state)
    {first, last} = State.visible_display_range(state, length(display_lines))
    runs = windowed_source_runs(display_lines, mapping, first, last)

    matches
    |> Enum.with_index()
    |> Enum.filter(fn {{line, _col, _text}, _idx} -> Map.has_key?(runs, line) end)
    |> Enum.group_by(fn {{line, _col, _text}, _idx} -> line end)
    |> Enum.reduce(graph, fn {line, line_matches}, acc_graph ->
      {first_row, segments} = Map.fetch!(runs, line)
      starts = segment_source_starts(segments, Enum.at(state.lines, line - 1, ""))

      Enum.reduce(line_matches, acc_graph, fn {{_line, col, match_text}, idx}, g ->
        {row_offset, x} = locate_in_segments(starts, col, state)
        row = first_row + row_offset

        if row < first or row > last do
          g
        else
          color = if idx == current_idx, do: current_match_color, else: match_color

          Primitives.rect(
            g,
            {max(1, State.string_width(state, match_text)), line_height},
            fill: color,
            translate: {x_offset + x, (row - 1) * line_height + @multiline_row_y_offset},
            id: {:search_match, idx}
          )
        end
      end)
    end)
  end

  # Source lines with at least one display row inside first..last, as
  # %{source_line => {first_display_row, [segment_text]}}. Walks the projection
  # once, in step with its mapping, and stops after the run that covers `last`.
  defp windowed_source_runs(display_lines, mapping, first, last) do
    collect_runs(display_lines, mapping, 1, first, last, nil, %{})
  end

  defp collect_runs([text | texts], [{source, _} | rest], row, first, last, run, acc) do
    case run do
      {^source, start, segments} ->
        collect_runs(texts, rest, row + 1, first, last, {source, start, [text | segments]}, acc)

      _ ->
        acc = flush_run(run, first, acc)

        if row > last,
          do: acc,
          else: collect_runs(texts, rest, row + 1, first, last, {source, row, [text]}, acc)
    end
  end

  defp collect_runs(_texts, _mapping, _row, first, _last, run, acc),
    do: flush_run(run, first, acc)

  defp flush_run(nil, _first, acc), do: acc

  defp flush_run({source, start, segments}, first, acc) do
    if start + length(segments) - 1 >= first,
      do: Map.put(acc, source, {start, Enum.reverse(segments)}),
      else: acc
  end

  # [{segment_text, source_start_index}] — where in the SOURCE line (0-based
  # grapheme index) each display segment begins. Word wrap consumes the spaces
  # at a boundary, so consecutive segments are not simply adjacent.
  defp segment_source_starts(segments, source_text) do
    graphemes = String.graphemes(source_text)

    {starts, _consumed, _had_previous} =
      Enum.reduce(segments, {[], 0, false}, fn segment, {acc, consumed, had_previous?} ->
        skipped =
          if had_previous? do
            graphemes |> Enum.drop(consumed) |> Enum.take_while(&(&1 == " ")) |> length()
          else
            0
          end

        start = consumed + skipped
        {[{segment, start} | acc], start + String.length(segment), true}
      end)

    Enum.reverse(starts)
  end

  # {segment_index, x_pixels} for a 1-based source column: the last segment
  # starting at or before it (the first segment always starts at 0).
  defp locate_in_segments(starts, col, state) do
    char_idx = col - 1

    {segment, start, index} =
      starts
      |> Enum.with_index()
      |> Enum.reduce({"", 0, 0}, fn {{segment, seg_start}, i}, chosen ->
        if seg_start <= char_idx, do: {segment, seg_start, i}, else: chosen
      end)

    within = min(max(char_idx - start, 0), String.length(segment))
    {index, State.string_width(state, String.slice(segment, 0, within))}
  end

  # Render scrollbars inside the main group (for z-order)
  defp render_scrollbars_inner(
         graph,
         %State{
           scroll: scroll,
           frame: frame,
           show_line_numbers: show_ln,
           line_number_width: ln_width
         } = _state
       ) do
    alias Widgex.Structs.Dimensions

    gutter_offset = if show_ln, do: ln_width, else: 0
    content_width = frame.size.width - gutter_offset
    {frame_height} = {frame.size.height}

    {frame_width, _} = frame.size.box

    # Render scrollbars directly (not via ScrollRenderer) for debugging
    # Vertical scrollbar on the right edge of content area
    if Widgex.Scroll.ScrollState.scrollable_y?(scroll) do
      scrollbar_width = 12
      scrollbar_padding = 4

      # Position at right edge of FULL frame (not content area)
      track_x = frame_width - scrollbar_width - scrollbar_padding
      track_height = frame_height - scrollbar_padding * 2

      # Calculate thumb position and size
      {thumb_y_ratio, thumb_height_ratio} = Widgex.Scroll.ScrollState.scrollbar_thumb(scroll, :y)
      scale = track_height / scroll.viewport_height
      # Minimum thumb size
      thumb_height = max(thumb_height_ratio * scale, 20)
      thumb_y = thumb_y_ratio * scale

      # DEBUG: Try hardcoded position at bottom-right corner
      # If this appears at top-left, there's a coordinate transform issue
      # Should be 500px from left
      test_x = 500
      # Should be 500px from top
      test_y = 500

      graph
      # Track - put at hardcoded position to debug
      |> Primitives.rrect({scrollbar_width, 200, 4},
        id: :scrollbar_y_track,
        fill: {255, 0, 0, 128},
        translate: {test_x, test_y}
      )
      # Thumb
      |> Primitives.rrect({scrollbar_width, thumb_height, 4},
        id: :scrollbar_y_thumb,
        fill: {255, 0, 0, 255},
        translate: {test_x, test_y + 10}
      )
      # Add horizontal scrollbar if needed
      |> maybe_render_horizontal_scrollbar(
        scroll,
        frame_width,
        frame_height,
        gutter_offset,
        scrollbar_width,
        scrollbar_padding
      )
    else
      graph
      |> maybe_render_horizontal_scrollbar(
        scroll,
        frame_width,
        frame_height,
        gutter_offset,
        12,
        4
      )
    end
  end

  defp maybe_render_horizontal_scrollbar(
         graph,
         scroll,
         frame_width,
         frame_height,
         gutter_offset,
         scrollbar_width,
         scrollbar_padding
       ) do
    if Widgex.Scroll.ScrollState.scrollable_x?(scroll) do
      # Horizontal scrollbar at bottom, starting after gutter
      track_width = frame_width - gutter_offset - scrollbar_padding * 2
      # If vertical scrollbar exists, reduce width
      track_width =
        if Widgex.Scroll.ScrollState.scrollable_y?(scroll) do
          track_width - scrollbar_width - scrollbar_padding
        else
          track_width
        end

      track_y = frame_height - scrollbar_width - scrollbar_padding
      track_x = gutter_offset + scrollbar_padding

      # Calculate thumb
      {thumb_x_ratio, thumb_width_ratio} = Widgex.Scroll.ScrollState.scrollbar_thumb(scroll, :x)
      scale = track_width / scroll.viewport_width
      thumb_width = max(thumb_width_ratio * scale, 20)
      thumb_x = thumb_x_ratio * scale

      graph
      # Track
      |> Primitives.rrect({track_width, scrollbar_width, 4},
        id: :scrollbar_x_track,
        # Blue for horizontal
        fill: {0, 0, 255, 128},
        translate: {track_x, track_y}
      )
      # Thumb
      |> Primitives.rrect({thumb_width, scrollbar_width, 4},
        id: :scrollbar_x_thumb,
        fill: {0, 0, 255, 255},
        translate: {track_x + thumb_x, track_y}
      )
    else
      graph
    end
  end

  # Render scrollbars using ScrollRenderer (original, kept for reference)
  defp render_scrollbars(
         graph,
         %State{
           scroll: scroll,
           frame: frame,
           show_line_numbers: show_ln,
           line_number_width: ln_width
         } = _state
       ) do
    alias Widgex.Scroll.ScrollRenderer
    alias Widgex.Structs.Dimensions

    # Calculate content frame (text area only, excluding gutter)
    # IMPORTANT: Must create a proper Dimensions struct so .box is correct
    gutter_offset = if show_ln, do: ln_width, else: 0
    content_width = frame.size.width - gutter_offset
    content_frame = %{frame | size: Dimensions.new({content_width, frame.size.height})}

    # Render scrollbars in a group translated by gutter offset
    graph
    |> Scenic.Primitives.group(
      fn g ->
        ScrollRenderer.render_scrollbars(g, scroll, content_frame)
      end,
      id: :scrollbars_group,
      translate: {gutter_offset, 0}
    )
  end

  # ===== UPDATE HELPERS =====

  defp update_border_if_changed(graph, %State{focused: old_focused}, %State{
         focused: new_focused,
         colors: colors
       })
       when old_focused != new_focused do
    border_color = if new_focused, do: colors.focused_border, else: colors.border

    graph
    |> Graph.modify(:border, fn primitive ->
      Primitives.update_opts(primitive, stroke: {1, border_color})
    end)
  end

  defp update_border_if_changed(graph, _old_state, _new_state), do: graph

  # Update gutter scroll position (vertical only)
  defp update_gutter_scroll(graph, %State{scroll: old_scroll, show_line_numbers: true}, %State{
         scroll: new_scroll,
         show_line_numbers: true
       })
       when old_scroll.offset_y != new_scroll.offset_y do
    try do
      Graph.modify(graph, :gutter_content, fn primitive ->
        Scenic.Primitive.put_style(primitive, :translate, {0, -new_scroll.offset_y})
      end)
    rescue
      _ -> graph
    end
  end

  defp update_gutter_scroll(graph, _old_state, _new_state), do: graph

  # Update content scroll position (both directions)
  # Scrolling far enough to change WHICH lines are visible means the drawn
  # set is now wrong (only visible lines are rendered), so the content area
  # must be rebuilt rather than merely translated.
  # Scrolling past the buffered margin changes WHICH lines should be drawn,
  # so the content area (and gutter) must be rebuilt, not merely translated.
  # Within the margin a translate is enough — that is what the buffer is for.
  defp update_content_scroll(graph, %State{} = old_state, %State{} = new_state) do
    if visible_window_changed?(old_state, new_state) do
      graph
      |> rebuild_content_area(new_state)
      |> rebuild_gutter_if_shown(new_state)
    else
      translate_content_scroll(graph, old_state, new_state)
    end
  end

  # Compare windows using scroll offset and frame geometry ONLY.
  #
  # Never call wrap_lines here: this runs on every render, and re-wrapping the
  # whole document per render stalls the component badly enough that scroll
  # input stops being serviced. The line count only clamps the window's end,
  # which is not needed to detect that the window moved.
  defp visible_window_changed?(old_state, new_state) do
    old_state.render_window != new_state.render_window
  end

  defp translate_content_scroll(graph, %State{scroll: old_scroll}, %State{scroll: new_scroll})
       when old_scroll.offset_x != new_scroll.offset_x or
              old_scroll.offset_y != new_scroll.offset_y do
    # No rescue here: if :text_content can't be modified the view silently
    # stops following the scroll state (the "state scrolls, pixels don't"
    # bug class) — crash loudly instead so the cause is visible.
    Graph.modify(graph, :text_content, fn primitive ->
      Scenic.Primitive.put_style(
        primitive,
        :translate,
        {-new_scroll.offset_x, -new_scroll.offset_y}
      )
    end)
  end

  defp translate_content_scroll(graph, _old_state, _new_state), do: graph

  # Rebuild the entire content area when line count increases
  # This is needed because we can't add new primitives to existing groups
  defp rebuild_content_area(
         graph,
         %State{show_line_numbers: true, line_number_width: gutter_width} = state
       ) do
    content_width = state.frame.size.width - gutter_width

    graph
    |> Graph.delete(:content_group)
    |> render_text_content_area(state, gutter_width, content_width)
  end

  defp rebuild_content_area(graph, %State{show_line_numbers: false} = state) do
    graph
    |> Graph.delete(:content_group)
    |> render_text_content_area(state, 0, state.frame.size.width)
  end

  # Rebuild the gutter when line count increases
  defp rebuild_gutter(
         graph,
         %State{show_line_numbers: true, line_number_width: gutter_width} = state
       ) do
    graph
    |> Graph.delete(:gutter_group)
    |> render_line_number_gutter(state, gutter_width)
  end

  defp rebuild_gutter(graph, %State{show_line_numbers: false}), do: graph

  # Update text lines when content changes
  # Must update both text content AND x-position due to explicit indent positioning
  # Any change to the text rebuilds the content area (and the gutter, whose
  # line numbers may have shifted) rather than modifying per-line primitives.
  #
  # The old path called Graph.modify on {:text_line, n} for every line. With
  # only the VISIBLE lines rendered, primitives outside the window do not
  # exist, and those modifies silently no-opped (they are rescued) — edits
  # off-screen would not appear when scrolled to. A rebuild is correct by
  # construction, and cheap precisely because rendering is virtualised: it
  # draws a screenful, not a document.
  defp update_lines_if_changed(
         graph,
         %State{lines: old_lines} = old_state,
         %State{lines: new_lines} = new_state
       )
       when old_lines != new_lines do
    old_display = wrap_lines(old_state)
    new_display = wrap_lines(new_state)

    if length(old_display) != length(new_display) do
      # Line count changed: which lines are drawn shifts, so rebuild (also
      # renumbers the gutter). Cheap because rendering is virtualised.
      graph
      |> rebuild_content_area(new_state)
      |> rebuild_gutter_if_shown(new_state)
    else
      # Same number of lines: edit the primitives that exist, i.e. only the
      # ones inside the rendered window. Rebuilding here instead would make
      # every keystroke O(document) — typing into a long file could not keep
      # up. Lines outside the window have no primitive and need none; they
      # are rendered from current state whenever the window next moves.
      #
      # Highlighted rows are groups of runs, not one text primitive, so with
      # highlighting on the (virtualised, screenful-sized) rebuild is the
      # simple correct path.
      if highlighting_active?(new_state) do
        rebuild_content_area(graph, new_state)
      else
        {first, last} = State.visible_display_range(new_state, length(new_display))
        update_visible_line_primitives(graph, new_state, new_display, first, last)
      end
    end
  end

  defp update_lines_if_changed(graph, _old_state, _new_state), do: graph

  defp highlighting_active?(%State{highlights: highlights, highlight_styles: styles}) do
    is_map(highlights) and map_size(highlights) > 0 and is_map(styles) and map_size(styles) > 0
  end

  # New token spans (or a new style map) redraw the visible rows.
  defp update_highlights_if_changed(graph, old_state, new_state) do
    if old_state.highlights != new_state.highlights or
         old_state.highlight_styles != new_state.highlight_styles do
      rebuild_content_area(graph, new_state)
    else
      graph
    end
  end

  defp rebuild_gutter_if_shown(graph, %State{show_line_numbers: true} = state),
    do: rebuild_gutter(graph, state)

  defp rebuild_gutter_if_shown(graph, _state), do: graph

  defp update_visible_line_primitives(graph, %State{} = state, display_lines, first, last) do
    # text_padding
    x_offset = 10
    line_height = State.line_height(state)
    frame_height = state.frame.size.height

    display_lines
    |> Enum.slice(first - 1, max(last - first + 1, 0))
    |> Enum.with_index(first)
    |> Enum.reduce(graph, fn {line_text, line_num}, g ->
      {indent_width, content} = State.expand_tabs_with_indent(state, line_text)
      line_x = x_offset + indent_width

      y_pos =
        case state.mode do
          :single_line -> frame_height / 2 + 2
          _ -> (line_num - 1) * line_height + line_height
        end

      try do
        Graph.modify(g, {:text_line, line_num}, fn primitive ->
          primitive
          |> Scenic.Primitive.put(content)
          |> Scenic.Primitive.put_style(:translate, {line_x, y_pos})
        end)
      rescue
        _ -> g
      end
    end)
  end

  defp update_semantic_if_changed(graph, old_state, new_state) do
    if semantic_changed?(old_state, new_state) do
      semantic = semantic_metadata(new_state)

      # No rescue: a swallowed modify failure here leaves the semantic table
      # frozen at stale values while the visible state moves on — the
      # "cursor moved on screen but tests read the old position" bug class.
      Graph.modify(graph, :semantic_content, fn primitive ->
        primitive =
          if old_state.lines != new_state.lines,
            do: Scenic.Primitive.put(primitive, State.get_text(new_state)),
            else: primitive

        Scenic.Primitive.put_style(primitive, :semantic, semantic)
      end)
    else
      graph
    end
  end

  defp semantic_changed?(old_state, new_state) do
    # The published frame is part of the semantic payload (consumers derive
    # coordinates from it), so a frame change alone must refresh it —
    # otherwise a resize/layout shift leaves stale geometry on record and
    # anything computing positions from it is off by the delta.
    old_state.lines != new_state.lines or
      old_state.cursor != new_state.cursor or
      old_state.selection != new_state.selection or
      old_state.editable != new_state.editable or
      old_state.mode != new_state.mode or
      old_state.frame != new_state.frame or
      scroll_changed?(old_state.scroll, new_state.scroll)
  end

  defp scroll_changed?(nil, nil), do: false
  defp scroll_changed?(nil, _), do: true
  defp scroll_changed?(_, nil), do: true

  defp scroll_changed?(old, new) do
    old.offset_x != new.offset_x or old.offset_y != new.offset_y
  end

  # Update line numbers when source line count changes
  # Always rebuild gutter to ensure correct line number display, especially for wrapped lines
  defp update_line_numbers_if_changed(
         graph,
         %State{lines: old_lines, show_line_numbers: true},
         %State{lines: new_lines, show_line_numbers: true} = new_state
       )
       when length(old_lines) != length(new_lines) do
    # Rebuild the gutter whenever source line count changes
    # This ensures wrapped continuation lines don't incorrectly show line numbers
    rebuild_gutter(graph, new_state)
  end

  defp update_line_numbers_if_changed(graph, _old_state, _new_state), do: graph

  # Update selection highlight when selection changes
  # Selection changes require rebuilding the content area since we can't
  # dynamically add/remove primitives from nested groups
  defp update_selection_if_changed(
         graph,
         %State{selection: old_sel},
         %State{selection: new_sel} = new_state
       )
       when old_sel != new_sel do
    rebuild_content_area(graph, new_state)
  end

  defp update_selection_if_changed(graph, _old_state, _new_state), do: graph

  # Update search match highlighting when matches or current index changes
  defp update_search_matches_if_changed(
         graph,
         %State{search_matches: old_matches, search_current_index: old_idx},
         %State{search_matches: new_matches, search_current_index: new_idx} = new_state
       )
       when old_matches != new_matches or old_idx != new_idx do
    rebuild_content_area(graph, new_state)
  end

  defp update_search_matches_if_changed(graph, _old_state, _new_state), do: graph

  defp update_matching_braces_if_changed(graph, old_state, new_state) do
    if old_state.cursor != new_state.cursor or old_state.lines != new_state.lines or
         old_state.show_matching_brace != new_state.show_matching_brace do
      geometries = matching_brace_geometries(new_state, 10, State.line_height(new_state))

      Enum.reduce([:matching_brace_current, :matching_brace_partner], graph, fn id, acc ->
        {size, translate, hidden?} =
          Map.get(geometries, id, {{1, State.line_height(new_state)}, {0, 0}, true})

        Graph.modify(acc, id, fn primitive ->
          primitive
          |> Scenic.Primitive.put(size)
          |> Primitives.update_opts(translate: translate, hidden: hidden?)
        end)
      end)
    else
      graph
    end
  end

  defp update_cursor_guides_if_changed(graph, old_state, new_state) do
    # Guides live in the translated content group, so scrolling moves them
    # automatically. Recomputing their source-to-display position here made a
    # wrapped wheel event walk the document before the cursor on every tick.
    if old_state.cursor != new_state.cursor do
      {x, y} = cursor_guide_position(new_state, 10, State.line_height(new_state))

      graph
      |> Graph.modify(:current_line_highlight, fn primitive ->
        Primitives.update_opts(primitive, translate: {0, y})
      end)
      |> Graph.modify(:current_column_highlight, fn primitive ->
        Primitives.update_opts(primitive, translate: {x, 0})
      end)
    else
      graph
    end
  end

  defp update_cursor_if_changed(
         graph,
         %State{cursor: old_cursor},
         %State{cursor: new_cursor} = new_state
       )
       when old_cursor != new_cursor do
    x_offset = 10
    line_height = State.line_height(new_state)
    frame_height = new_state.frame.size.height

    # Get cursor position in display line coordinates
    {display_line, display_col} = source_to_display_cursor(new_state, new_cursor)

    display_lines = wrap_lines(new_state)
    current_line = Enum.at(display_lines, display_line - 1, "")
    text_before_cursor = String.slice(current_line, 0, max(0, display_col - 1))

    cursor_x = x_offset + State.string_width(new_state, text_before_cursor)

    # For single-line mode, center cursor vertically (text uses text_base: :middle)
    # For multi-line, use standard line-based positioning
    cursor_y =
      case new_state.mode do
        :single_line ->
          # Text is centered at frame_height/2 + 2 with text_base: :middle
          # Cursor needs no extra adjustment
          frame_height / 2 - line_height / 2

        _ ->
          # Standard multi-line: position at line top + small offset
          (display_line - 1) * line_height + @multiline_row_y_offset
      end

    should_show_cursor = new_state.focused and new_state.cursor_visible

    graph
    |> Graph.modify(:cursor, fn primitive ->
      Primitives.update_opts(primitive,
        translate: {cursor_x, cursor_y},
        hidden: !should_show_cursor
      )
    end)
  end

  defp update_cursor_if_changed(graph, _old_state, _new_state), do: graph

  defp update_scrollbars_if_changed(
         graph,
         %State{scroll: old_scroll} = old_state,
         %State{scroll: new_scroll} = new_state
       ) do
    alias Widgex.Scroll.ScrollState

    # Check if scrollability changed (primitives may not exist)
    old_scrollable_x = ScrollState.scrollable_x?(old_scroll)
    new_scrollable_x = ScrollState.scrollable_x?(new_scroll)
    old_scrollable_y = ScrollState.scrollable_y?(old_scroll)
    new_scrollable_y = ScrollState.scrollable_y?(new_scroll)

    scrollability_changed =
      old_scrollable_x != new_scrollable_x or
        old_scrollable_y != new_scrollable_y

    if scrollability_changed do
      # Scrollability changed - need to rebuild content area to create/remove scrollbar primitives
      rebuild_content_area(graph, new_state)
    else
      # Update existing scrollbar thumb positions (keeping them at correct Y position)
      update_scrollbar_thumbs(graph, old_scroll, new_scroll, new_state)
    end
  end

  defp semantic_metadata(%State{
         id: id,
         editable: editable,
         mode: mode,
         cursor: cursor,
         selection: selection,
         scroll: scroll,
         frame: frame
       }) do
    %{
      type: if(mode == :multi_line, do: :text_buffer, else: :text_field),
      field_id: id,
      editable: editable,
      multiline: mode == :multi_line,
      role: if(mode == :multi_line, do: :textbox, else: :textfield),
      # The component's actual frame in parent coords. Tests must derive
      # click coordinates from THIS, not from the configured window size —
      # the WM may grant a smaller window and the layout reflows to match.
      frame: %{x: frame.pin.x, y: frame.pin.y, width: frame.size.width, height: frame.size.height}
    }
    |> maybe_put(:cursor_position, cursor)
    |> maybe_put(:selection, selection_to_map(selection))
    |> maybe_put(:scroll, scroll_to_map(scroll))
  end

  defp scroll_to_map(nil), do: nil

  defp scroll_to_map(%{
         offset_x: ox,
         offset_y: oy,
         viewport_width: vw,
         viewport_height: vh,
         content_width: cw,
         content_height: ch
       }) do
    %{
      offset_x: ox,
      offset_y: oy,
      viewport_width: vw,
      viewport_height: vh,
      content_width: cw,
      content_height: ch
    }
  end

  defp scroll_to_map(_), do: nil

  defp selection_to_map(nil), do: nil
  defp selection_to_map({{sl, sc}, {el, ec}}), do: %{start: {sl, sc}, end: {el, ec}}
  defp selection_to_map({start_pos, end_pos}), do: %{start: start_pos, end: end_pos}
  # Handle case where selection is already a map (from buffer state)
  defp selection_to_map(%{start: start_pos, end: end_pos}), do: %{start: start_pos, end: end_pos}

  defp maybe_put(metadata, _key, nil), do: metadata
  defp maybe_put(metadata, key, value), do: Map.put(metadata, key, value)

  # Update scrollbar thumb positions without moving them to wrong Y coordinate
  defp update_scrollbar_thumbs(graph, old_scroll, new_scroll, state) do
    alias Widgex.Scroll.ScrollState

    frame = state.frame
    show_ln = state.show_line_numbers
    ln_width = state.line_number_width
    scrollbar_width = 10
    scrollbar_padding = 2

    gutter_offset = if show_ln, do: ln_width, else: 0
    content_width = frame.size.width - gutter_offset
    frame_height = frame.size.height

    graph
    |> update_h_scrollbar_thumb(
      old_scroll,
      new_scroll,
      content_width,
      frame_height,
      scrollbar_width,
      scrollbar_padding
    )
    |> update_v_scrollbar_thumb(
      old_scroll,
      new_scroll,
      content_width,
      frame_height,
      scrollbar_width,
      scrollbar_padding
    )
  end

  defp update_h_scrollbar_thumb(
         graph,
         old_scroll,
         new_scroll,
         content_width,
         frame_height,
         scrollbar_width,
         scrollbar_padding
       ) do
    alias Widgex.Scroll.ScrollState

    if ScrollState.scrollable_x?(new_scroll) do
      track_x = scrollbar_padding
      track_y = frame_height - scrollbar_width - scrollbar_padding
      track_width = content_width - scrollbar_padding * 2

      track_width =
        if ScrollState.scrollable_y?(new_scroll) do
          track_width - scrollbar_width - scrollbar_padding
        else
          track_width
        end

      {new_thumb_x_ratio, _} = ScrollState.scrollbar_thumb(new_scroll, :x)
      scale = track_width / new_scroll.viewport_width
      new_thumb_x = new_thumb_x_ratio * scale

      try do
        Graph.modify(graph, :scrollbar_x_thumb, fn primitive ->
          Scenic.Primitive.put_style(primitive, :translate, {track_x + new_thumb_x, track_y})
        end)
      rescue
        _ -> graph
      end
    else
      graph
    end
  end

  defp update_v_scrollbar_thumb(
         graph,
         old_scroll,
         new_scroll,
         content_width,
         frame_height,
         scrollbar_width,
         scrollbar_padding
       ) do
    alias Widgex.Scroll.ScrollState

    if ScrollState.scrollable_y?(new_scroll) do
      track_x = content_width - scrollbar_width - scrollbar_padding
      track_height = frame_height - scrollbar_padding * 2

      track_height =
        if ScrollState.scrollable_x?(new_scroll) do
          track_height - scrollbar_width - scrollbar_padding
        else
          track_height
        end

      {new_thumb_y_ratio, _} = ScrollState.scrollbar_thumb(new_scroll, :y)
      scale = track_height / new_scroll.viewport_height
      new_thumb_y = new_thumb_y_ratio * scale

      try do
        Graph.modify(graph, :scrollbar_y_thumb, fn primitive ->
          Scenic.Primitive.put_style(
            primitive,
            :translate,
            {track_x, scrollbar_padding + new_thumb_y}
          )
        end)
      rescue
        _ -> graph
      end
    else
      graph
    end
  end

  # ===== LINE WRAPPING HELPERS =====

  defp wrap_lines(%State{} = state), do: state |> projection() |> elem(0)

  # Calculate the available width for text content
  # Note: scroll.viewport_width already excludes gutter (set from content_frame in State.new)
  # Subtract 40 for: text padding (20) + scrollbar (12) + buffer (8)
  # This must match the calculation in State.new and Reducer for consistent wrapping
  defp content_area_width(%State{scroll: scroll}) do
    scroll.viewport_width - 40
  end

  defp build_display_projection(%State{} = state) do
    {lines, mapping, _memo} = build_display_projection_with_memo(state)
    {lines, mapping}
  end

  # Wrapping is memoised per line TEXT under the current layout (mode, width,
  # font, tabs). An edit changes one line, but the projection is rebuilt whole;
  # without the memo every keystroke in a large wrapped document re-measured
  # every paragraph — twice, once for content size and once for the render.
  # The memo is rebuilt from what was just projected, so it never outgrows
  # the document.
  defp build_display_projection_with_memo(%State{} = state) do
    max_width = content_area_width(state)
    layout_key = {state.wrap_mode, max_width, state.font, state.tab_width}

    previous =
      case state.wrap_memo do
        {^layout_key, memo} -> memo
        _ -> %{}
      end

    {lines, mapping, memo, _seen} =
      Enum.reduce(visible_source_lines(state), {[], [], %{}, MapSet.new()}, fn
        {source_num, source_line}, {line_acc, mapping_acc, memo_acc, seen} ->
          wrapped =
            case previous do
              %{^source_line => wrapped} -> wrapped
              _ -> wrap_for_mode(source_line, max_width, state)
            end

          first_source_row? = not MapSet.member?(seen, source_num)

          entries =
            wrapped
            |> Enum.with_index()
            |> Enum.map(fn {_text, index} ->
              {source_num, first_source_row? and index == 0}
            end)

          {Enum.reverse(wrapped, line_acc), Enum.reverse(entries, mapping_acc),
           Map.put(memo_acc, source_line, wrapped), MapSet.put(seen, source_num)}
      end)

    {Enum.reverse(lines), Enum.reverse(mapping), {layout_key, memo}}
  end

  # Convert source cursor position to display cursor position
  # When lines wrap, we need to find which display line the cursor is on
  # and what column within that display line
  @doc """
  Map a cursor from SOURCE {line, col} to DISPLAY {line, col}.

  Public because scrolling needs it too: with word wrap on, a cursor's
  display line is further down than its source line, and anything computing
  a scroll target from the source line scrolls too little (the end of a
  wrapped document becomes unreachable).
  """
  def source_to_display_cursor(%State{} = state, {source_line, source_col}) do
    {display_lines, mapping} = projection(state)

    case first_display_row(mapping, source_line) do
      nil ->
        {1, source_col}

      first_row ->
        segments =
          display_lines
          |> Enum.drop(first_row - 1)
          |> Enum.zip(Enum.drop(mapping, first_row - 1))
          |> Enum.take_while(fn {_text, {source, _}} -> source == source_line end)
          |> Enum.map(&elem(&1, 0))

        source_text = Enum.at(state.lines, source_line - 1, "")
        {offset, display_col} = find_cursor_in_wrapped_lines(segments, source_col, source_text)
        {first_row + offset - 1, display_col}
    end
  end

  # 1-based display row of the first row projected from `source_line`, or nil
  # when the line is hidden inside a fold.
  defp first_display_row(mapping, source_line) do
    case Enum.find_index(mapping, fn {source, _} -> source == source_line end) do
      nil -> nil
      index -> index + 1
    end
  end

  @doc "Map a display row to its source line, accounting for folds and wrapping."
  def display_to_source_line(%State{} = state, display_line) do
    {_display_lines, mapping} = projection(state)

    case Enum.at(mapping, display_line - 1) || List.last(mapping) do
      {source, _first?} -> source
      nil -> 1
    end
  end

  defp visible_source_lines(%State{lines: lines, folds: folds} = state) do
    folds = folds || MapSet.new()

    ScenicWidgets.TextField.Folding.projection(lines, folds)
    |> Enum.flat_map(fn
      {line, text, 0} ->
        [{line, text}]

      {line, text, count} ->
        indent = fold_summary_indent(text, state.tab_width || 2)
        [{line, text}, {line, indent <> "… #{count} lines"}]
    end)
  end

  defp fold_summary_indent(text, tab_width) do
    leading =
      case Regex.run(~r/^[\t ]*/, text) do
        [indent] -> indent
        _ -> ""
      end

    leading <> String.duplicate(" ", tab_width)
  end

  # Find which wrapped line segment contains the cursor and what column within it
  # Note: Word wrap consumes spaces at wrap boundaries, so we need to track that
  defp find_cursor_in_wrapped_lines(wrapped_lines, source_col, source_text) do
    # Walk through wrapped lines, tracking cumulative SOURCE character position
    # When word wrapping, a space is consumed between wrapped lines
    find_cursor_in_wrapped_lines(
      wrapped_lines,
      source_col,
      String.graphemes(source_text),
      1,
      0,
      false
    )
  end

  defp find_cursor_in_wrapped_lines([], source_col, _source, line_num, chars_consumed, _) do
    # Cursor is past all content - place at end of last line
    {max(1, line_num - 1), max(1, source_col - chars_consumed)}
  end

  defp find_cursor_in_wrapped_lines(
         [line | rest],
         source_col,
         source,
         line_num,
         chars_consumed,
         had_previous_line
       ) do
    line_length = String.length(line)

    # Account for the space that was consumed at wrap boundary
    # (when transitioning from a previous line to this one via word wrap)
    space_adjustment =
      if had_previous_line do
        source
        |> Enum.drop(chars_consumed)
        |> Enum.take_while(&(&1 == " "))
        |> length()
      else
        0
      end

    # Total source characters consumed after this wrapped line
    source_chars_after = chars_consumed + space_adjustment + line_length

    # Source position where this display line starts
    source_start = chars_consumed + space_adjustment

    cond do
      # Cursor is within this line
      source_col >= source_start + 1 and source_col <= source_chars_after + 1 ->
        display_col = source_col - source_start
        {line_num, display_col}

      # Cursor is after this line - continue to next
      source_col > source_chars_after ->
        find_cursor_in_wrapped_lines(
          rest,
          source_col,
          source,
          line_num + 1,
          source_chars_after,
          true
        )

      # Cursor is before this line (shouldn't happen normally)
      true ->
        {line_num, 1}
    end
  end

  # Word-based line wrapping using FontMetrics when available
  defp wrap_line(line, max_width, %State{} = state) do
    Wrapping.word(line, max_width, &State.string_width(state, &1))
  end

  # Character-based line wrapping using FontMetrics when available
  defp wrap_line_by_chars(line, max_width, %State{} = state) do
    Wrapping.character(line, max_width, &State.string_width(state, &1))
  end

  defp wrap_for_mode(line, max_width, %State{wrap_mode: :char} = state),
    do: wrap_line_by_chars(line, max_width, state)

  defp wrap_for_mode(line, _max_width, %State{wrap_mode: :none}), do: [line]

  defp wrap_for_mode(line, max_width, state), do: wrap_line(line, max_width, state)
end
