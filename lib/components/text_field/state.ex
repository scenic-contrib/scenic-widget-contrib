defmodule ScenicWidgets.TextField.State do
  @moduledoc """
  State management for the TextField component.

  Supports both single-line and multi-line text editing with configurable
  wrapping, scrolling, line numbers, and interaction modes.
  """

  use Widgex.Scrollable
  require Logger
  alias ScenicWidgets.TextField.Wrapping

  defstruct [
    # Core
    # Widgex.Frame for positioning/sizing
    :frame,
    # List of strings: ["line 1", "line 2", ...]
    :lines,
    # {line, col} tuple (1-indexed)
    :cursor,
    # Component ID (for events)
    :id,

    # Display
    # Boolean, whether component has focus
    :focused,
    # System.monotonic_time when focus was gained (for debouncing)
    :focus_time,
    # Boolean, for blink animation
    :cursor_visible,
    # Erlang timer reference
    :cursor_timer,
    # :cursor (thin line) | :block (full char) | :hidden
    :cursor_mode,

    # Configuration
    # :single_line | :multi_line
    :mode,

    # Input Mode - CRITICAL for correct input routing!
    # :direct        - TextField requests and handles all keyboard input directly.
    #                  ⚠️ Will intercept global shortcuts! Use only when TextField
    #                  is the sole input handler (forms, simple editors).
    # :external      - TextField does NOT handle input. Parent app routes input
    #                  through its own system (Fluxus/Redux) and updates buffer.
    #                  Use for apps with global shortcuts (Flamelex, Vim-mode).
    # :store_backed - TextField handles input but syncs state with Buffer.Process.
    #                  Use when you want direct input but external state management.
    :input_mode,
    # Boolean
    :show_line_numbers,
    :show_matching_brace,
    :highlight_current_line,
    :highlight_current_column,
    # Pixels (default 40)
    :line_number_width,
    # Number of spaces per tab (default 4)
    :tab_width,
    # %{name: atom, size: int, metrics: FontMetrics | nil}
    :font,
    # %{text:, background:, cursor:, line_numbers:, border:, focused_border:}
    :colors,
    # Which edges get the 1px border line (default all four)
    :border_sides,
    # Host says an overlay (menu/dialog) owns the pointer — ignore clicks
    :overlay_open,

    # Buffer-backed mode (when input_mode == :store_backed)
    # Buffer store process: pid or via-tuple (GenServer.cast target)
    :dispatch,
    # Scenic.PubSub source atom publishing buffer state snapshots
    :source,
    # UUID of the document currently shown — used to detect buffer SWITCHES
    :buffer_id,

    # Interaction
    # Boolean (allow editing)
    :editable,
    # Boolean (allow text selection)
    :selectable,

    # Text Wrapping & Scrolling
    # :none | :word | :char
    :wrap_mode,
    # Widgex.Scroll.ScrollState (replaces manual scroll offsets)
    :scroll,
    # :auto | {:fixed_lines, n} | {:fixed_pixels, n}
    :height_mode,
    # Calculated from frame height and height_mode
    :max_visible_lines,
    # Number of lines to render outside viewport (default 96). A generous
    # retained window keeps wheel events on the translate-only fast path.
    :viewport_buffer_lines,
    # Buffered display-row window currently materialized in the graph.
    # It advances only when the viewport leaves it, not on every wheel tick.
    :render_window,
    # Derived folded/wrapped rows. Recomputed only when document/layout inputs
    # change; scrolling must never project the whole document again.
    :display_cache_key,
    :display_lines,
    :display_line_mapping,
    # {layout_key, %{line_text => wrapped_segments}} from the last projection,
    # so an edit re-wraps the lines it touched and looks the rest up.
    :wrap_memo,
    # MapSet of folded source-line headers (view state)
    :folds,
    # Fold header currently under the pointer in the line-number gutter.
    :fold_hover_line,

    # Legacy scroll fields (deprecated - use :scroll instead)
    # :none | :vertical | :horizontal | :both (for backwards compat)
    :scroll_mode,
    # Vertical scroll in pixels (for backwards compat)
    :vertical_scroll_offset,
    # Horizontal scroll in pixels (for backwards compat)
    :horizontal_scroll_offset,

    # Advanced (future)
    # {start, end} for text selection
    :selection,
    # Limit lines (nil = unlimited)
    :max_lines,
    # Milliseconds
    :cursor_blink_rate,
    # Boolean
    :show_scrollbars,
    # Pixels
    :scrollbar_width,

    # Scrollbar drag state
    # Which scrollbar is being dragged: :x | :y | nil
    :scrollbar_drag,
    # {x, y} mouse position when drag started
    :scrollbar_drag_start,
    # Starting scroll offset when drag started
    :scrollbar_drag_offset,

    # Text selection drag state (for click-and-drag selection)
    # true when dragging to select text, nil otherwise
    :text_drag,
    # {line, col} where text drag started
    :text_drag_start,

    # Double-click detection
    # System.monotonic_time(:millisecond) of last click
    :last_click_time,
    # {line, col} of last click for double-click detection
    :last_click_pos,

    # Syntax/structural highlighting. `highlights` is what a highlight source
    # last published for THIS document: %{line_no => {line_text, spans}} with
    # spans [{start_idx, end_idx, class}] in 0-based graphemes, end exclusive.
    # `highlight_styles` maps a class to how it is drawn:
    # %{font: face_atom | nil, underline: boolean, fill: color | nil}.
    # A row is styled only while its current text equals the published text,
    # so a lexer that lags typing can never colour the wrong characters.
    :highlight_source,
    :highlights,
    :highlight_styles,

    # Search state
    # Current search string (nil = not searching)
    :search_query,
    # List of {line, col, match_text} tuples
    :search_matches,
    # Index into search_matches (0-based)
    :search_current_index,

    # Undo/Redo state
    # List of {lines, cursor} snapshots (most recent first)
    :undo_stack,
    # List of {lines, cursor} snapshots (most recent first)
    :redo_stack,
    # Maximum undo stack size (default 100)
    :undo_max_size
  ]

  @type t :: %__MODULE__{}

  @doc """
  Create new state from Frame or config map.

  ## Examples

      # Minimal - just a frame
      State.new(%{frame: frame})

      # With configuration
      State.new(%{
        frame: frame,
        initial_text: "Hello\\nWorld",
        mode: :multi_line,
        show_line_numbers: true
      })
  """
  def new(%{frame: %Widgex.Frame{} = frame} = data) do
    alias Widgex.Structs.Dimensions

    data = normalize_legacy_store_params(data)

    font_config = Map.get(data, :font) || default_font()
    font = ensure_font_metrics(font_config)
    lines = parse_initial_text(data)
    wrap_mode = Map.get(data, :wrap_mode, :word)
    show_line_numbers = Map.get(data, :show_line_numbers, false)

    # Calculate dynamic gutter width based on line count
    line_number_width = gutter_width(show_line_numbers, lines, font)

    # Calculate the content frame (excluding line numbers if shown)
    # IMPORTANT: Must create a proper Dimensions struct so .box is correct
    content_frame =
      if show_line_numbers do
        content_width = frame.size.width - line_number_width
        %{frame | size: Dimensions.new({content_width, frame.size.height})}
      else
        frame
      end

    # Determine scroll direction based on wrap mode:
    # - :word or :char wrap → vertical only (content wraps horizontally)
    # - :none → both directions (no wrapping, need horizontal scroll)
    scroll_direction =
      case wrap_mode do
        :none -> :both
        # :word or :char
        _ -> :vertical
      end

    # Calculate initial content size
    # For wrapped modes, content_height depends on display line count, not source line count
    content_width = calculate_content_width(lines, font, content_frame, wrap_mode)
    content_height = calculate_content_height(lines, font, content_frame, wrap_mode)

    viewport_buffer_lines = Map.get(data, :viewport_buffer_lines, 96)
    max_visible_lines = calculate_max_lines(frame, font)

    %__MODULE__{
      frame: frame,
      lines: lines,
      cursor: Map.get(data, :initial_cursor, {1, 1}),
      id: Map.get(data, :id),

      # Display
      focused: Map.get(data, :focused, false),
      focus_time:
        if(Map.get(data, :focused, false), do: System.monotonic_time(:millisecond), else: nil),
      cursor_visible: true,
      cursor_timer: nil,
      cursor_mode: Map.get(data, :cursor_mode, :cursor),

      # Configuration
      mode: Map.get(data, :mode, :multi_line),
      input_mode: Map.get(data, :input_mode, :direct),
      show_line_numbers: show_line_numbers,
      show_matching_brace: Map.get(data, :show_matching_brace, true),
      highlight_current_line: Map.get(data, :highlight_current_line, false),
      highlight_current_column: Map.get(data, :highlight_current_column, false),
      line_number_width: line_number_width,
      tab_width: Map.get(data, :tab_width, 4),
      font: font,
      colors: Map.get(data, :colors) || default_colors(),
      border_sides: Map.get(data, :border_sides, [:top, :right, :bottom, :left]),
      overlay_open: Map.get(data, :overlay_open, false),

      # Buffer-backed mode
      dispatch: Map.get(data, :dispatch),
      source: Map.get(data, :source),
      buffer_id: Map.get(data, :buffer_id),

      # Interaction
      editable: Map.get(data, :editable, true),
      selectable: Map.get(data, :selectable, true),

      # Text Wrapping & Scrolling
      wrap_mode: wrap_mode,
      scroll:
        init_scroll(content_frame,
          direction: scroll_direction,
          content_height: content_height,
          content_width: content_width,
          initially_visible: Map.get(data, :show_scrollbars, true)
        ),
      height_mode: Map.get(data, :height_mode, :auto),
      max_visible_lines: max_visible_lines,
      viewport_buffer_lines: viewport_buffer_lines,
      render_window: {1, max_visible_lines + viewport_buffer_lines},
      display_cache_key: nil,
      display_lines: nil,
      display_line_mapping: nil,
      wrap_memo: nil,
      folds: Map.get(data, :folds, MapSet.new()) |> normalize_folds(),
      fold_hover_line: nil,

      # Legacy fields (for backwards compatibility during transition)
      scroll_mode: Map.get(data, :scroll_mode, :both),
      vertical_scroll_offset: 0,
      horizontal_scroll_offset: 0,

      # Advanced
      selection: nil,
      max_lines: Map.get(data, :max_lines),
      cursor_blink_rate: Map.get(data, :cursor_blink_rate, 500),
      show_scrollbars: Map.get(data, :show_scrollbars, true),
      scrollbar_width: Map.get(data, :scrollbar_width, 12),

      # Scrollbar drag state
      scrollbar_drag: nil,
      scrollbar_drag_start: nil,
      scrollbar_drag_offset: nil,

      # Highlighting
      highlight_source: Map.get(data, :highlight_source),
      highlights: nil,
      highlight_styles: Map.get(data, :highlight_styles, %{}),

      # Search state
      search_query: nil,
      search_matches: [],
      search_current_index: 0,

      # Undo/Redo state
      undo_stack: [],
      redo_stack: [],
      undo_max_size: Map.get(data, :undo_max_size, 100)
    }
    # If first_visible_line is provided, adjust scroll to show that line at the top
    |> maybe_restore_scroll_position(data, content_frame)
  end

  defp normalize_folds(%MapSet{} = folds), do: folds
  defp normalize_folds(folds) when is_list(folds), do: MapSet.new(folds)
  defp normalize_folds(_), do: MapSet.new()

  # Restore scroll position to show first_visible_line at the top of viewport
  defp maybe_restore_scroll_position(state, data, content_frame) do
    case Map.get(data, :first_visible_line) do
      nil ->
        state

      target_line when is_integer(target_line) and target_line >= 1 ->
        # Calculate the pixel offset for the target line
        # For wrapped text, we need to count display lines before the target
        target_offset_y = calculate_line_offset(state, target_line, content_frame)

        # Clamp the offset to valid range
        max_offset_y = max(0, state.scroll.content_height - state.scroll.viewport_height)
        clamped_offset_y = min(target_offset_y, max_offset_y) |> max(0)

        # Update scroll state with the new offset
        new_scroll = %{state.scroll | offset_y: clamped_offset_y}
        %{state | scroll: new_scroll}

      _ ->
        state
    end
  end

  # Calculate the pixel offset to show a given source line at the top
  defp calculate_line_offset(state, target_line, content_frame) do
    line_height = state.font.size

    case state.wrap_mode do
      :none ->
        # Simple: each source line is one display line
        (target_line - 1) * line_height

      _wrap ->
        # Wrapped: need to count display lines for all source lines before target
        max_width = content_frame.size.width - 40

        # Sum up display lines for lines 1 to (target_line - 1)
        display_lines_before =
          state.lines
          |> Enum.take(target_line - 1)
          |> Enum.map(fn line ->
            count_wrapped_lines_init(line, state.font, max_width, state.wrap_mode)
          end)
          |> Enum.sum()

        display_lines_before * line_height
    end
  end

  defp calculate_content_height(lines, font, frame, wrap_mode) do
    line_height = font.size
    # Add half line height of bottom padding so last line isn't jammed against frame edge
    bottom_padding = div(line_height, 2)

    display_line_count =
      case wrap_mode do
        :none ->
          # No wrapping: each source line is one display line
          length(lines)

        _wrap ->
          # Word/char wrapping: each source line may wrap into multiple display lines
          # Account for padding and scrollbar in available width
          max_width = frame.size.width - 40

          lines
          |> Enum.map(fn line -> count_wrapped_lines_init(line, font, max_width, wrap_mode) end)
          |> Enum.sum()
      end

    display_line_count * line_height + bottom_padding
  end

  # Count how many display lines a single source line will wrap into (used during init)
  # This is a simplified version that doesn't require the full State struct
  defp count_wrapped_lines_init(line, font, max_width, wrap_mode) do
    measure = &measure_string_width(&1, font)

    case wrap_mode do
      :char -> Wrapping.character(line, max_width, measure)
      :word -> Wrapping.word(line, max_width, measure)
    end
    |> length()
  end

  # Measure string width using FontMetrics if available, fallback to approximation
  defp measure_string_width(str, font) do
    case font do
      %{metrics: %FontMetrics{} = metrics, size: size} ->
        FontMetrics.width(str, size, metrics)

      %{size: size} ->
        # Fallback to monospace approximation
        String.length(str) * trunc(size * 0.6)
    end
  end

  defp calculate_content_width(lines, font, frame, wrap_mode) do
    case wrap_mode do
      :none ->
        # Measure actual longest line using FontMetrics if available
        {max_line_width, _longest_line_num, _longest_line_chars} =
          lines
          |> Enum.with_index(1)
          |> Enum.map(fn {line, idx} ->
            width =
              case font do
                %{metrics: %FontMetrics{} = metrics, size: size} ->
                  FontMetrics.width(line, size, metrics)

                %{size: size} ->
                  # Fallback to monospace approximation
                  String.length(line) * trunc(size * 0.6)
              end

            {width, idx, String.length(line)}
          end)
          |> Enum.max_by(fn {w, _, _} -> w end, fn -> {0, 0, 0} end)

        content_w = max(frame.size.width, max_line_width + 40)

        content_w

      _ ->
        # Wrapped content fits within frame
        frame.size.width
    end
  end

  defp parse_initial_text(%{initial_text: text}) when is_bitstring(text) do
    String.split(text, "\n")
  end

  defp parse_initial_text(_) do
    # Default to empty
    [""]
  end

  # Accept the pre-rename store params from older callers:
  # buffer_source -> source, buffer_controller -> dispatch,
  # input_mode: :buffer_backed -> :store_backed
  defp normalize_legacy_store_params(data) do
    data =
      case Map.get(data, :input_mode) do
        :buffer_backed -> Map.put(data, :input_mode, :store_backed)
        _ -> data
      end

    data
    |> rename_key(:buffer_source, :source)
    |> rename_key(:buffer_controller, :dispatch)
  end

  defp rename_key(data, old, new) do
    case Map.fetch(data, old) do
      {:ok, value} -> data |> Map.delete(old) |> Map.put_new(new, value)
      :error -> data
    end
  end

  defp default_font do
    %{name: :roboto_mono, size: 20, metrics: nil}
  end

  @doc """
  Ensure font has metrics loaded. If metrics are nil but a path is provided,
  load metrics from the TTF file using TruetypeMetrics.

  Font config can include:
  - `name` - Font name (atom)
  - `size` - Font size (integer)
  - `metrics` - Pre-loaded FontMetrics struct (optional)
  - `path` - Path to TTF file for loading metrics (optional)
  """
  def ensure_font_metrics(%{metrics: %FontMetrics{}} = font), do: font

  def ensure_font_metrics(%{path: path} = font) when is_binary(path) do
    case TruetypeMetrics.load(path) do
      {:ok, metrics} ->
        Map.put(font, :metrics, metrics)

      {:error, reason} ->
        raise "Failed to load font metrics from #{path}: #{inspect(reason)}"
    end
  end

  def ensure_font_metrics(%{name: name} = _font) do
    raise "FontMetrics not available for font #{inspect(name)}. Either provide pre-loaded metrics or a path to the TTF file."
  end

  defp default_colors do
    %{
      text: :white,
      background: {30, 30, 30},
      cursor: :white,
      line_numbers: {100, 100, 100},
      border: {60, 60, 60},
      focused_border: {100, 150, 200}
    }
  end

  defp calculate_max_lines(frame, font) do
    line_height = font.size
    trunc(frame.size.height / line_height)
  end

  # ===== QUERY FUNCTIONS (PURE) =====

  @doc """
  Check if point is inside TextField bounds.
  Coordinates are in component-local space (Scenic transforms them).
  """
  def point_inside?(%__MODULE__{frame: frame}, {x, y}) do
    # When component is added with translate, Scenic transforms input coords to local space
    # So we check against (0,0) origin, not frame.pin
    x >= 0 and x <= frame.size.width and
      y >= 0 and y <= frame.size.height
  end

  @doc """
  Get full text as single string with newlines.
  """
  def get_text(%__MODULE__{lines: lines}) do
    Enum.join(lines, "\n")
  end

  @doc """
  Get cursor position as {line, col} tuple (1-indexed).
  """
  def get_cursor(%__MODULE__{cursor: cursor}), do: cursor

  @doc """
  Get line at index (1-indexed). Returns empty string if out of bounds.
  """
  def get_line(%__MODULE__{lines: lines}, line_num) do
    Enum.at(lines, line_num - 1, "")
  end

  @doc """
  Count total lines in the text.
  """
  def line_count(%__MODULE__{lines: lines}), do: length(lines)

  @doc """
  Get the X offset where text starts (accounting for line numbers).
  """
  def text_x_offset(%__MODULE__{show_line_numbers: false}), do: 10

  def text_x_offset(%__MODULE__{show_line_numbers: true, line_number_width: width}),
    do: width + 10

  @doc """
  Calculate the required gutter width for the current number of lines.
  Returns width in pixels that fits the largest line number plus padding.
  """
  def calculate_gutter_width(%__MODULE__{show_line_numbers: false}), do: 0

  def calculate_gutter_width(%__MODULE__{show_line_numbers: true, lines: lines} = state) do
    line_count = length(lines)
    digit_count = if line_count == 0, do: 1, else: trunc(:math.log10(max(1, line_count))) + 1
    # Minimum 2 digits, plus padding on each side
    digits_to_show = max(2, digit_count)
    digit_width = char_width(state, "0")
    # Width = digits + padding (10px on left, 10px on right)
    trunc(digits_to_show * digit_width) + 20
  end

  @doc """
  Update the gutter width if needed based on line count.
  Returns updated state if width changed, original state otherwise.
  """
  def maybe_update_gutter_width(%__MODULE__{show_line_numbers: false} = state), do: state

  def maybe_update_gutter_width(%__MODULE__{show_line_numbers: true} = state) do
    required_width = calculate_gutter_width(state)

    if required_width != state.line_number_width do
      %{state | line_number_width: required_width}
    else
      state
    end
  end

  @doc """
  Calculate character width using FontMetrics.
  Raises if FontMetrics are not available - cursor positioning requires accurate metrics.
  """
  def char_width(%__MODULE__{font: %{metrics: %FontMetrics{} = metrics, size: size}}, char \\ "W") do
    FontMetrics.width(char, size, metrics)
  end

  def char_width(%__MODULE__{font: %{name: name}}, _char) do
    raise "FontMetrics not available for font #{inspect(name)}. TextField requires font metrics for accurate cursor positioning. Ensure the font has a corresponding .metrics file."
  end

  @doc """
  Calculate the width of a string using FontMetrics if available.
  Handles tab characters by expanding them based on tab_width.
  """
  def string_width(%__MODULE__{} = state, string) do
    # First expand tabs, then measure
    expanded = expand_tabs(state, string)
    string_width_raw(state, expanded)
  end

  # Raw string width without tab expansion (for internal use after tabs are expanded)
  defp string_width_raw(
         %__MODULE__{font: %{metrics: %FontMetrics{} = metrics, size: size}},
         string
       ) do
    FontMetrics.width(string, size, metrics)
  end

  defp string_width_raw(%__MODULE__{font: %{name: name}}, _string) do
    raise "FontMetrics not available for font #{inspect(name)}. TextField requires font metrics for accurate cursor positioning. Ensure the font has a corresponding .metrics file."
  end

  @doc """
  Expand tab characters to spaces based on tab_width setting.
  Uses proper tab stops (columns that are multiples of tab_width).
  """
  def expand_tabs(%__MODULE__{tab_width: tab_width}, string)
      when is_integer(tab_width) and tab_width > 0 do
    expand_tabs_at_column(string, 0, tab_width, [])
  end

  # Fallback if tab_width is nil or invalid - use default of 4
  def expand_tabs(%__MODULE__{}, string) do
    expand_tabs_at_column(string, 0, 4, [])
  end

  defp expand_tabs_at_column("", _col, _tab_width, acc) do
    acc |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp expand_tabs_at_column(<<"\t", rest::binary>>, col, tab_width, acc) do
    # Calculate spaces to next tab stop
    spaces_needed = tab_width - rem(col, tab_width)
    # Use regular spaces - the renderer will handle positioning
    spaces = String.duplicate(" ", spaces_needed)
    expand_tabs_at_column(rest, col + spaces_needed, tab_width, [spaces | acc])
  end

  defp expand_tabs_at_column(<<char::utf8, rest::binary>>, col, tab_width, acc) do
    expand_tabs_at_column(rest, col + 1, tab_width, [<<char::utf8>> | acc])
  end

  @doc """
  Expand tabs and return {leading_space_count, content} tuple.
  This is used by the renderer to position text with explicit x-offset
  since Scenic renders leading spaces as zero-width.
  """
  def expand_tabs_with_indent(%__MODULE__{} = state, string) do
    expanded = expand_tabs(state, string)
    # Count leading spaces and split
    {leading, content} = split_leading_spaces(expanded)
    indent_width = String.length(leading) * char_width(state)
    {indent_width, content}
  end

  defp split_leading_spaces(string) do
    case Regex.run(~r/^(\s*)(.*)$/s, string) do
      [_, leading, content] -> {leading, content}
      _ -> {"", string}
    end
  end

  @doc """
  Calculate line height from font size and metrics.
  """
  def line_height(%__MODULE__{font: %{size: size}}) do
    # Use font size as line height
    # Could be enhanced with FontMetrics.ascent + descent if needed
    size
  end

  @doc """
  Convert a click position (x, y) relative to the component frame to cursor position (line, col).
  Accounts for scroll offset, gutter, and text padding.
  Returns {line, col} tuple (1-indexed).
  """
  @doc """
  Gutter (line-number column) width for a given line count and font.
  Shared by `new/1` and `recalculate_line_number_width/1` so the two can
  never drift apart.
  """
  def gutter_width(false, _lines, _font), do: 0

  def gutter_width(true, lines, font) do
    line_count = length(lines)
    digit_count = if line_count == 0, do: 1, else: trunc(:math.log10(max(1, line_count))) + 1
    digits_to_show = max(2, digit_count)
    digit_width = trunc(font.size * 0.6)
    trunc(digits_to_show * digit_width) + 20
  end

  @doc """
  Recompute the scroll state's VIEWPORT dimensions from the current frame
  and gutter width, preserving the current offsets (clamped).

  Must be called after the frame changes when state is updated in place —
  `new/1` derives these from the content frame, and stale values make the
  visible-region maths wrong (text can vanish while the gutter still draws).
  """
  def recalculate_scroll_viewport(%__MODULE__{scroll: nil} = state), do: state

  def recalculate_scroll_viewport(%__MODULE__{frame: frame, scroll: scroll} = state) do
    content_width = max(frame.size.width - (state.line_number_width || 0), 1)
    content_height = max(frame.size.height, 1)

    scroll =
      scroll
      |> Map.put(:viewport_width, content_width)
      |> Map.put(:viewport_height, content_height)
      |> Widgex.Scroll.ScrollState.clamp()

    %{state | scroll: scroll}
  end

  @doc """
  Recompute the gutter width from current state (line count / font / whether
  line numbers are shown). Used when settings are applied in place.
  """
  def recalculate_line_number_width(%__MODULE__{} = state) do
    %{state | line_number_width: gutter_width(state.show_line_numbers, state.lines, state.font)}
  end

  def click_to_cursor(%__MODULE__{scroll: scroll, lines: lines} = state, {click_x, click_y}) do
    line_height = line_height(state)
    # Same as in renderer
    text_padding = 10
    gutter_width = if state.show_line_numbers, do: state.line_number_width, else: 0

    # Convert click to content coordinates (accounting for scroll and gutter).
    # Input coords arrive already transformed to this component's local space.
    content_x = click_x - gutter_width - text_padding + scroll.offset_x

    # The -4 aligns the click rows with the VISUAL rows: the renderer draws
    # line n's cursor block at (n-1)*line_height + 4 (see render_cursor) and
    # the text baseline at n*line_height, so glyphs sit ~4-6px lower than a
    # naive (n-1)*line_height row model. Without this, clicks in the bottom
    # few pixels of a visual line land one line down (QA A-known-failure #3).
    content_y = click_y + scroll.offset_y - 4

    # Calculate line number from Y coordinate
    display_line = max(1, div(max(trunc(content_y), 0), line_height) + 1)
    line = ScenicWidgets.TextField.Renderer.display_to_source_line(state, display_line)

    # Get the text of the clicked line
    line_text = Enum.at(lines, line - 1, "")

    # Calculate column from X coordinate using FontMetrics
    col = x_to_column(state, line_text, content_x)

    {line, col}
  end

  # Convert an X coordinate to a column position within a line of text
  # Uses binary search-like approach for efficiency with FontMetrics
  defp x_to_column(state, line_text, x) when x <= 0, do: 1
  defp x_to_column(state, "", _x), do: 1

  defp x_to_column(state, line_text, x) do
    # Walk through characters and find where the click falls
    chars = String.graphemes(line_text)
    find_column(state, chars, x, 0, 1)
  end

  defp find_column(_state, [], _x, _current_x, col), do: col

  defp find_column(state, [char | rest], x, current_x, col) do
    char_w = string_width(state, char)
    next_x = current_x + char_w

    # Click is within this character - check if closer to left or right edge
    if x < next_x do
      mid = current_x + char_w / 2
      if x < mid, do: col, else: col + 1
    else
      find_column(state, rest, x, next_x, col + 1)
    end
  end

  @doc """
  Get the word at or near the cursor position.
  Returns the word as a string, or nil if cursor is not on a word.
  """
  def word_at_cursor(%__MODULE__{lines: lines, cursor: cursor}), do: word_at(lines, cursor)

  @doc """
  The word at `{line, col}` in `lines`, or nil.

  Takes plain data rather than component state so a host can compute it from
  the document itself (e.g. a buffer store) instead of calling synchronously
  into the live component — which blocks on whatever that component is
  currently rendering.
  """
  def word_at(lines, {line_num, col}) when is_list(lines) do
    line = Enum.at(lines, line_num - 1, "")
    # Convert to 0-indexed
    extract_word_at(line, col - 1)
  end

  @doc """
  Get the word boundaries at a given position.
  Returns {start_col, end_col} (1-indexed, inclusive start, exclusive end for selection).
  Returns nil if position is not on a word.
  """
  def word_boundaries_at(%__MODULE__{lines: lines}, {line_num, col}) do
    line = Enum.at(lines, line_num - 1, "")
    # Convert to 0-indexed internally
    get_word_boundaries(line, col - 1)
  end

  # Get word boundaries at a given 0-indexed position in a string
  # Returns {start_col, end_col} (1-indexed) or nil
  defp get_word_boundaries("", _pos), do: nil

  defp get_word_boundaries(line, pos) do
    graphemes = String.graphemes(line)
    pos = max(0, min(pos, length(graphemes) - 1))

    # Check if position is on a word character
    char_at_pos = Enum.at(graphemes, pos, "")

    unless word_char?(char_at_pos) do
      # Try one position to the left (cursor might be after word)
      if pos > 0 do
        char_before = Enum.at(graphemes, pos - 1, "")
        if word_char?(char_before), do: get_word_boundaries(line, pos - 1), else: nil
      else
        nil
      end
    else
      # Find word boundaries (0-indexed)
      start_pos = find_word_start(graphemes, pos)
      end_pos = find_word_end(graphemes, pos)
      # Convert to 1-indexed, with end_col being position AFTER the word for selection
      {start_pos + 1, end_pos + 2}
    end
  end

  # Extract word at a given 0-indexed position in a string
  defp extract_word_at("", _pos), do: nil

  defp extract_word_at(line, pos) do
    graphemes = String.graphemes(line)
    pos = max(0, min(pos, length(graphemes) - 1))

    # Check if position is on a word character
    char_at_pos = Enum.at(graphemes, pos, "")

    unless word_char?(char_at_pos) do
      # Try one position to the left (cursor might be after word)
      if pos > 0 do
        char_before = Enum.at(graphemes, pos - 1, "")
        if word_char?(char_before), do: extract_word_at(line, pos - 1), else: nil
      else
        nil
      end
    else
      # Find word boundaries
      start_pos = find_word_start(graphemes, pos)
      end_pos = find_word_end(graphemes, pos)
      graphemes |> Enum.slice(start_pos..end_pos) |> Enum.join()
    end
  end

  defp find_word_start(graphemes, pos) when pos <= 0, do: 0

  defp find_word_start(graphemes, pos) do
    char = Enum.at(graphemes, pos - 1, "")
    if word_char?(char), do: find_word_start(graphemes, pos - 1), else: pos
  end

  defp find_word_end(graphemes, pos) when pos >= length(graphemes) - 1, do: length(graphemes) - 1

  defp find_word_end(graphemes, pos) do
    char = Enum.at(graphemes, pos + 1, "")
    if word_char?(char), do: find_word_end(graphemes, pos + 1), else: pos
  end

  defp word_char?(char), do: Regex.match?(~r/[\w]/, char)

  @doc """
  Get font ascent using FontMetrics if available.
  """
  def font_ascent(%__MODULE__{font: %{metrics: %FontMetrics{} = metrics, size: size}}) do
    FontMetrics.ascent(size, metrics)
  end

  def font_ascent(%__MODULE__{font: %{size: size}}) do
    # Approximation: ~80% of font size
    trunc(size * 0.8)
  end

  @doc """
  Which DISPLAY lines need rendering right now, as `{first, last}` (1-indexed,
  inclusive), given the live scroll offset and frame height.

  Rendering every line of the document builds one primitive per line, which
  on a large file costs seconds and blocks the component. Only lines within
  the viewport (plus `viewport_buffer_lines` either side, so small scrolls
  need no rebuild) are worth drawing — everything else is scissored away.

  Single-line mode always renders its one line.
  """
  def visible_display_range(%__MODULE__{mode: :single_line}, display_count),
    do: {1, display_count}

  def visible_display_range(%__MODULE__{render_window: {first, last}}, display_count) do
    first = min(max(first, 1), max(display_count, 1))
    {first, max(first, min(last, max(display_count, 1)))}
  end

  def visible_display_range(%__MODULE__{} = state, display_count) do
    line_height = line_height(state)
    offset_y = (state.scroll && state.scroll.offset_y) || 0
    height = state.frame.size.height
    buffer = state.viewport_buffer_lines || 5

    last = min(display_count, trunc((offset_y + height) / line_height) + 1 + buffer)

    # Clamp the START to the document as well. If the scroll offset outruns
    # the content (stale content_height, or wrap mode changing the display
    # line count under us), an unclamped start lands past the last line and
    # the range selects NOTHING — the view goes blank exactly when scrolled
    # to the end of the file.
    first =
      max(1, trunc(offset_y / line_height) + 1 - buffer)
      |> min(max(display_count, 1))

    {first, max(last, first)}
  end

  @doc false
  def advance_render_window(%__MODULE__{mode: :single_line} = state), do: state

  def advance_render_window(%__MODULE__{} = state) do
    line_height = line_height(state)
    offset_y = (state.scroll && state.scroll.offset_y) || 0
    buffer = state.viewport_buffer_lines || 96
    viewport_first = max(1, trunc(offset_y / line_height) + 1)
    viewport_last = trunc((offset_y + state.frame.size.height) / line_height) + 1

    case state.render_window do
      {first, last} when viewport_first >= first and viewport_last <= last ->
        state

      _ ->
        %{state | render_window: {max(1, viewport_first - buffer), viewport_last + buffer}}
    end
  end

  @doc false
  def reset_render_window(%__MODULE__{} = state) do
    state
    |> Map.put(:render_window, nil)
    |> advance_render_window()
  end

  @doc """
  Calculate which lines should be rendered based on viewport and scroll position.
  Returns {render_start, render_end} tuple (1-indexed, inclusive).
  """
  def visible_line_range(
        %__MODULE__{
          lines: lines,
          frame: frame,
          vertical_scroll_offset: scroll_y,
          viewport_buffer_lines: buffer_lines
        } = state
      ) do
    line_height = line_height(state)
    viewport_height = frame.size.height
    total_lines = length(lines)

    # Calculate visible range
    visible_start = max(1, div(-scroll_y, line_height) + 1)
    visible_end = min(total_lines, div(-scroll_y + viewport_height, line_height) + 2)

    # Add buffer for smooth scrolling
    render_start = max(1, visible_start - buffer_lines)
    render_end = min(total_lines, visible_end + buffer_lines)

    {render_start, render_end}
  end

  @doc """
  Check if a line number should be rendered based on viewport.
  """
  def should_render_line?(%__MODULE__{} = state, line_num) do
    {render_start, render_end} = visible_line_range(state)
    line_num >= render_start and line_num <= render_end
  end

  @doc """
  Ensure the cursor is visible within the viewport.
  Automatically adjusts scroll offsets if the cursor is outside the visible area.
  Returns updated state with adjusted scroll offsets.
  """
  def ensure_cursor_visible(
        %__MODULE__{
          cursor: {line, col},
          frame: frame,
          scroll: scroll
        } = state
      ) do
    line_height = line_height(state)
    viewport_height = frame.size.height
    viewport_width = frame.size.width

    # Use the cursor's DISPLAY line: with word wrap on it sits further down
    # than its source line, and scrolling by the source line scrolls too
    # little — the bottom of a wrapped document could not be reached.
    {display_line, _display_col} =
      ScenicWidgets.TextField.Renderer.source_to_display_cursor(state, {line, col})

    # Calculate cursor pixel position
    cursor_y = (display_line - 1) * line_height

    # Horizontal position. With wrapping on, every row fits the viewport and
    # the view never scrolls sideways — measuring the SOURCE column here used
    # to shove a wrapped document off-screen to the right whenever the cursor
    # landed on a continuation row (find-next made the text vanish).
    cursor_x =
      if state.wrap_mode == :none do
        current_line = get_line(state, line)
        string_width(state, String.slice(current_line, 0, col - 1))
      else
        0
      end

    # Use the scroll struct's offsets (these are positive values representing content offset)
    scroll_y = scroll.offset_y
    scroll_x = scroll.offset_x

    # Check vertical scrolling
    # scroll.offset_y is how much the content is scrolled DOWN (positive = scrolled down)
    new_scroll_y =
      cond do
        # Cursor is above viewport - scroll up to show it
        cursor_y < scroll_y ->
          cursor_y

        # Cursor is below viewport - scroll down to show it
        cursor_y + line_height > scroll_y + viewport_height ->
          cursor_y + line_height - viewport_height

        # Cursor is visible vertically
        true ->
          scroll_y
      end

    # Check horizontal scrolling
    text_offset = text_x_offset(state)

    new_scroll_x =
      cond do
        # Cursor is left of viewport - scroll left
        cursor_x < scroll_x ->
          cursor_x

        # Cursor is right of viewport - scroll right
        cursor_x + text_offset > scroll_x + viewport_width - 10 ->
          cursor_x + text_offset - viewport_width + 10

        # Cursor is visible horizontally
        true ->
          scroll_x
      end

    # Update both the scroll struct AND legacy fields for backward compatibility
    updated_scroll = %{scroll | offset_x: new_scroll_x, offset_y: new_scroll_y}

    %{
      state
      | scroll: updated_scroll,
        vertical_scroll_offset: -new_scroll_y,
        horizontal_scroll_offset: -new_scroll_x
    }
  end

  @doc """
  Like `ensure_cursor_visible/1`, but a cursor that is OFF-screen is brought
  to the vertical middle of the viewport rather than to its nearest edge.
  Used for jumps the user did not steer by hand — landing on a search match —
  where the surrounding lines are the point and an edge-clipped row is not.
  A cursor already on screen leaves the view where it is.
  """
  def reveal_cursor_centered(
        %__MODULE__{cursor: {line, col}, frame: frame, scroll: scroll} = state
      ) do
    line_height = line_height(state)
    viewport_height = frame.size.height

    {display_line, _display_col} =
      ScenicWidgets.TextField.Renderer.source_to_display_cursor(state, {line, col})

    cursor_y = (display_line - 1) * line_height

    on_screen? =
      cursor_y >= scroll.offset_y and cursor_y + line_height <= scroll.offset_y + viewport_height

    if on_screen? do
      ensure_cursor_visible(state)
    else
      max_offset = max(scroll.content_height - viewport_height, 0)
      centered = cursor_y - viewport_height / 2 + line_height / 2
      offset_y = centered |> max(0) |> min(max_offset)

      # Horizontal follow is unchanged: run the normal pass on top.
      ensure_cursor_visible(%{state | scroll: %{scroll | offset_y: offset_y}})
    end
  end

  @doc """
  Scroll the view by a delta amount.
  Positive values scroll down/right, negative values scroll up/left.
  """
  def scroll(
        %__MODULE__{
          vertical_scroll_offset: scroll_y,
          horizontal_scroll_offset: scroll_x
        } = state,
        {delta_x, delta_y}
      ) do
    %{
      state
      | vertical_scroll_offset: scroll_y + delta_y,
        horizontal_scroll_offset: scroll_x + delta_x
    }
  end

  @doc """
  Scroll vertically by a number of lines.
  Positive values scroll down, negative values scroll up.
  """
  def scroll_lines(%__MODULE__{} = state, line_count) do
    line_height = line_height(state)
    delta_y = line_count * line_height
    scroll(state, {0, delta_y})
  end

  @doc """
  Scroll horizontally by a number of characters.
  Positive values scroll right, negative values scroll left.
  """
  def scroll_chars(%__MODULE__{} = state, char_count) do
    char_width = char_width(state)
    delta_x = char_count * char_width
    scroll(state, {delta_x, 0})
  end

  # ===== SCROLLBAR HIT TESTING =====

  @scrollbar_width 10
  @scrollbar_padding 2

  @doc """
  Check if a point is on a scrollbar thumb.
  Returns :x, :y, or nil.
  Coordinates are in component-local space.
  """
  def scrollbar_hit_test(%__MODULE__{} = state, {x, y}) do
    alias Widgex.Scroll.ScrollState

    scroll = state.scroll
    frame = state.frame
    gutter_offset = if state.show_line_numbers, do: state.line_number_width, else: 0
    content_width = frame.size.width - gutter_offset
    frame_height = frame.size.height

    # Check horizontal scrollbar first (it's at the bottom)
    if ScrollState.scrollable_x?(scroll) do
      h_hit = check_h_scrollbar_hit(state, {x, y}, gutter_offset, content_width, frame_height)

      if h_hit,
        do: h_hit,
        else: check_v_scrollbar_hit(state, {x, y}, gutter_offset, content_width, frame_height)
    else
      check_v_scrollbar_hit(state, {x, y}, gutter_offset, content_width, frame_height)
    end
  end

  defp check_h_scrollbar_hit(state, {x, y}, gutter_offset, content_width, frame_height) do
    alias Widgex.Scroll.ScrollState

    scroll = state.scroll
    track_x = gutter_offset + @scrollbar_padding
    track_y = frame_height - @scrollbar_width - @scrollbar_padding
    track_width = content_width - @scrollbar_padding * 2

    # Account for vertical scrollbar
    track_width =
      if ScrollState.scrollable_y?(scroll) do
        track_width - @scrollbar_width - @scrollbar_padding
      else
        track_width
      end

    {thumb_x_ratio, thumb_width_ratio} = ScrollState.scrollbar_thumb(scroll, :x)
    scale = track_width / scroll.viewport_width
    thumb_width = max(thumb_width_ratio * scale, 20)
    thumb_x = track_x + thumb_x_ratio * scale

    # Check if click is on thumb
    if x >= thumb_x and x <= thumb_x + thumb_width and
         y >= track_y and y <= track_y + @scrollbar_width do
      :x
    else
      nil
    end
  end

  defp check_v_scrollbar_hit(state, {x, y}, gutter_offset, content_width, frame_height) do
    alias Widgex.Scroll.ScrollState

    scroll = state.scroll

    if ScrollState.scrollable_y?(scroll) do
      track_x = gutter_offset + content_width - @scrollbar_width - @scrollbar_padding
      track_y = @scrollbar_padding
      track_height = frame_height - @scrollbar_padding * 2

      # Account for horizontal scrollbar
      track_height =
        if ScrollState.scrollable_x?(scroll) do
          track_height - @scrollbar_width - @scrollbar_padding
        else
          track_height
        end

      {thumb_y_ratio, thumb_height_ratio} = ScrollState.scrollbar_thumb(scroll, :y)
      scale = track_height / scroll.viewport_height
      thumb_height = max(thumb_height_ratio * scale, 20)
      thumb_y = track_y + thumb_y_ratio * scale

      # Check if click is on thumb
      if x >= track_x and x <= track_x + @scrollbar_width and
           y >= thumb_y and y <= thumb_y + thumb_height do
        :y
      else
        nil
      end
    else
      nil
    end
  end

  @doc """
  Get scrollbar track dimensions for drag calculations.
  Returns {track_start, track_length, content_size, viewport_size}.
  """
  def scrollbar_track_info(%__MODULE__{} = state, :x) do
    alias Widgex.Scroll.ScrollState

    scroll = state.scroll
    gutter_offset = if state.show_line_numbers, do: state.line_number_width, else: 0
    content_width = state.frame.size.width - gutter_offset
    track_width = content_width - @scrollbar_padding * 2

    track_width =
      if ScrollState.scrollable_y?(scroll) do
        track_width - @scrollbar_width - @scrollbar_padding
      else
        track_width
      end

    {gutter_offset + @scrollbar_padding, track_width, scroll.content_width, scroll.viewport_width}
  end

  def scrollbar_track_info(%__MODULE__{} = state, :y) do
    alias Widgex.Scroll.ScrollState

    scroll = state.scroll
    frame_height = state.frame.size.height
    track_height = frame_height - @scrollbar_padding * 2

    track_height =
      if ScrollState.scrollable_x?(scroll) do
        track_height - @scrollbar_width - @scrollbar_padding
      else
        track_height
      end

    {@scrollbar_padding, track_height, scroll.content_height, scroll.viewport_height}
  end

  # ===========================================================================
  # Undo/Redo Operations
  # ===========================================================================

  @doc """
  Push current state onto undo stack before making a change.
  Call this BEFORE modifying lines/cursor, not after.
  Clears the redo stack (new changes invalidate redo history).
  """
  def push_undo(
        %__MODULE__{lines: lines, cursor: cursor, undo_stack: stack, undo_max_size: max_size} =
          state
      ) do
    snapshot = {lines, cursor}
    new_stack = [snapshot | stack] |> Enum.take(max_size)
    %{state | undo_stack: new_stack, redo_stack: []}
  end

  @doc """
  Undo the last change. Returns {:ok, new_state} or {:noop, state} if nothing to undo.
  """
  def undo(%__MODULE__{undo_stack: []} = state), do: {:noop, state}

  def undo(
        %__MODULE__{
          undo_stack: [{prev_lines, prev_cursor} | rest],
          lines: curr_lines,
          cursor: curr_cursor,
          redo_stack: redo
        } = state
      ) do
    # Push current state onto redo stack before restoring
    redo_snapshot = {curr_lines, curr_cursor}

    new_state = %{
      state
      | lines: prev_lines,
        cursor: prev_cursor,
        undo_stack: rest,
        redo_stack: [redo_snapshot | redo]
    }

    {:ok, ensure_cursor_visible(new_state)}
  end

  @doc """
  Redo the last undone change. Returns {:ok, new_state} or {:noop, state} if nothing to redo.
  """
  def redo(%__MODULE__{redo_stack: []} = state), do: {:noop, state}

  def redo(
        %__MODULE__{
          redo_stack: [{next_lines, next_cursor} | rest],
          lines: curr_lines,
          cursor: curr_cursor,
          undo_stack: undo
        } = state
      ) do
    # Push current state onto undo stack before restoring
    undo_snapshot = {curr_lines, curr_cursor}

    new_state = %{
      state
      | lines: next_lines,
        cursor: next_cursor,
        redo_stack: rest,
        undo_stack: [undo_snapshot | undo]
    }

    {:ok, ensure_cursor_visible(new_state)}
  end

  @doc """
  Check if undo is available.
  """
  def can_undo?(%__MODULE__{undo_stack: stack}), do: stack != []

  @doc """
  Check if redo is available.
  """
  def can_redo?(%__MODULE__{redo_stack: stack}), do: stack != []
end
