defmodule ScenicWidgets.SearchPane.Renderizer do
  @moduledoc """
  Draws `ScenicWidgets.SearchPane`.

  ## Why this is incremental

  It used to rebuild the whole graph on every change, on the grounds that a
  sidebar's worth of content is small enough not to be worth the bookkeeping.
  That is true right up until the pane wants to contain a **component** — a
  TextField for its query, say — because a graph built from scratch takes the
  component with it, and a child that is destroyed and recreated on every
  keystroke loses its cursor, its selection and its input registration.

  So the pane is drawn as four independent pieces, and a change replaces only
  the pieces it actually affects:

      :search_pane_background   the pane's own rect            (theme/frame)
      :search_pane_chrome       header backdrop, title, close  (theme/frame)
      :search_pane_widgets      fields, toggles, status        (typing, results)
      :search_pane_body         result rows and scrollbars     (results, hover)

  None of the four overlap another, so replacing one and letting it land at
  the end of the graph cannot put it over the top of something it should be
  under. Anything that does not fit that — a change of theme or frame —
  rebuilds the lot, which is rare enough to be free.
  """

  use Widgex.Scrollable, direction: :vertical

  alias Scenic.Graph
  alias Scenic.Primitives
  alias ScenicWidgets.SearchPane.State

  # Where a match's highlight rectangle sits relative to the text baseline.
  @highlight_top 5

  # IconMenu's dropdown corner, and the slightly tighter one it gives the rows
  # inside it.
  @panel_radius 4
  @panel_row_radius 3

  @doc "The whole pane, from nothing. Used on init and nowhere else."
  def render(%State{} = state) do
    Graph.build()
    |> render_backdrop(state)
    # FIELDS FIRST, then the widgets that sit on top of them. The option
    # toggles live inside the query field's right-hand end, and a field is a
    # component with its own opaque background — drawn after them, it buries
    # them completely.
    |> render_fields(state)
    |> render_widgets(state)
    |> render_body(state)
    |> render_settings(state)
    |> render_action_tooltip(state)
  end

  # Everything the live widgets sit ON TOP of. Each piece carries an id and is
  # modified in place rather than replaced, because a replacement lands at the
  # END of the graph — and a backdrop drawn last is a backdrop drawn over the
  # things it is supposed to be behind.
  defp render_backdrop(graph, %State{theme: theme} = state) do
    height = State.header_height(state)
    width = state.frame.size.width

    graph
    |> Primitives.rect(state.frame.size.box,
      id: :search_pane_background,
      fill: theme.background,
      stroke: {1, theme.border},
      input: [:cursor_button, :cursor_pos]
    )
    |> Primitives.rect({width, height}, id: :search_pane_header_bg, fill: theme.header_background)
    |> Primitives.line({{0, height}, {width, height}},
      id: :search_pane_header_rule,
      stroke: {1, theme.border}
    )
    # And a rule above the status line: it is the boundary between the
    # controls and the results, and crowded against the settings it read as
    # one more option rather than as the end of them.
    |> Primitives.line(
      {{theme.padding, State.status_rule_y(state)},
       {width - theme.padding, State.status_rule_y(state)}},
      id: :search_pane_status_rule,
      stroke: {1, theme.border}
    )
    # The pane says what it is, and says it properly: it was set in the same
    # small dim type as a row label, which made the top of the pane read as
    # another result rather than as a title.
    |> Primitives.text("SEARCH",
      id: :search_pane_title,
      translate: {theme.padding, theme.padding + theme.row_height - 4},
      fill: theme.text,
      font: theme.font,
      font_size: theme.font_size
    )
  end

  defp update_backdrop(graph, %State{theme: theme} = state) do
    height = State.header_height(state)
    width = state.frame.size.width
    close = Enum.find(State.header_widgets(state), &(&1.id == :close))

    graph
    |> Graph.modify(:search_pane_background, fn p ->
      Primitives.rect(p, state.frame.size.box, fill: theme.background, stroke: {1, theme.border})
    end)
    |> Graph.modify(:search_pane_header_bg, fn p ->
      Primitives.rect(p, {width, height}, fill: theme.header_background)
    end)
    |> Graph.modify(:search_pane_status_rule, fn p ->
      Primitives.line(
        p,
        {{theme.padding, State.status_rule_y(state)},
         {width - theme.padding, State.status_rule_y(state)}},
        stroke: {1, theme.border}
      )
    end)
    |> Graph.modify(:search_pane_header_rule, fn p ->
      Primitives.line(p, {{0, height}, {width, height}}, stroke: {1, theme.border})
    end)
    |> Graph.modify(:search_pane_title, fn p ->
      Primitives.text(p, "SEARCH",
        translate: {theme.padding, theme.padding + theme.row_height - 6},
        fill: theme.heading,
        font_size: theme.small_font_size
      )
    end)
    |> Graph.modify(:search_pane_close_glyph, fn p ->
      Primitives.text(p, "×",
        translate: {close.x + 4, close.y + close.h - 6},
        fill: theme.dim_text,
        font_size: theme.font_size
      )
    end)
  end

  @doc """
  Redraw only what changed between two states.

  The pane is drawn as four sibling pieces (see the moduledoc); this replaces
  the ones the change touched and leaves the rest — and anything living
  alongside them — alone.
  """
  def update_render(graph, %State{} = old_state, %State{} = new_state) do
    moved? = geometry_changed?(old_state, new_state)

    body_replaced? = moved? or body_changed?(old_state, new_state)

    graph
    |> then(fn g -> if moved?, do: update_backdrop(g, new_state), else: g end)
    |> maybe_replace(
      :search_pane_widgets,
      moved? or widgets_changed?(old_state, new_state),
      &render_widgets(&1, new_state)
    )
    |> maybe_replace(:search_pane_body, body_replaced?, &render_body(&1, new_state))
    |> update_hover(old_state, new_state)
    # LAST, and re-rendered whenever anything under it was.
    #
    # A replaced piece lands at the END of the graph, which is what puts it on
    # top. Every other piece is disjoint, so that never mattered; this one
    # deliberately overlaps the results, so a body rebuilt after it is drawn
    # OVER it. That is what happened when a settings option was toggled: the
    # panel redrew for the option, and then the search it started came back a
    # moment later, rebuilt the body, and buried the panel under its own
    # results.
    |> maybe_replace(
      :search_pane_settings,
      new_state.domain_open? and
        (moved? or body_replaced? or settings_changed?(old_state, new_state)),
      &render_settings(&1, new_state)
    )
    |> then(fn g ->
      # And when it is not open there is nothing to draw, but there may still
      # be a panel in the graph from a moment ago.
      if not new_state.domain_open? and old_state.domain_open?,
        do: Graph.delete(g, :search_pane_settings),
        else: g
    end)
    |> then(fn g -> if moved?, do: move_fields(g, new_state), else: g end)
    |> Graph.delete(:search_pane_action_tooltip)
    |> render_action_tooltip(new_state)
  end

  defp render_action_tooltip(graph, %State{} = state) do
    tooltip =
      State.visible_rows(state)
      |> Enum.flat_map(&State.action_bounds(state, &1))
      |> Enum.find(&(&1.action == state.hovered))
      |> case do
        nil ->
          nil

        b ->
          text = action_tooltip(b.action, state)

          %{
            text: text,
            at: tooltip_at(b, text, state)
          }
      end

    ScenicWidgets.Tooltip.add(graph, tooltip, state.theme, state.frame.size.width,
      id: :search_pane_action_tooltip
    )
  end

  defp tooltip_at(%{x: x, y: y, w: w, h: h}, text, state) do
    font_size = Map.get(state.theme, :tooltip_font_size, 12)
    tooltip_width = ScenicWidgets.Tooltip.width(text, state.theme.font, font_size)
    tooltip_height = font_size + 14
    button_top = State.header_height(state) + y - state.scroll.offset_y
    button_bottom = button_top + h

    anchor_y =
      if button_bottom + tooltip_height + 4 <= state.frame.size.height,
        do: button_bottom,
        else: button_top - tooltip_height - 8

    # Tooltip.add/5 applies its own ten-pixel pointer offset. Subtract it here
    # so the resulting box, rather than that historical pointer offset, is
    # centred on the action button.
    {max(x + w / 2 - tooltip_width / 2 - 10, -6), anchor_y}
  end

  defp action_tooltip({:dismiss_file, _}, _state), do: "Remove file from search scope"
  defp action_tooltip({:replace_file, _}, _state), do: "Replace all matches in this file"

  defp action_tooltip({:dismiss_match, path, line, col}, state) do
    if MapSet.member?(state.model.skipped, {path, line, col}),
      do: "Add back to bulk replace",
      else: "Skip this occurrence during replacement"
  end

  defp action_tooltip({:replace_match, _, _, _}, _state), do: "Replace this occurrence"

  defp settings_changed?(old_state, new_state) do
    settings_signature(old_state) != settings_signature(new_state)
  end

  # The scope rows are compared by their LABEL, not just their id and whether
  # they are open — the tick is IN the label ("[x] lib"), and it is the thing
  # most likely to change. Comparing ids alone, unticking a directory changed
  # nothing the panel could see, and it went on drawing the old ticks until
  # something else happened to redraw it.
  #
  # This used to work by accident: the scope tree was drawn by the header,
  # whose signature includes model.status, and unticking anything starts a
  # search — so the status changed, and the header redrew for that instead.
  defp settings_signature(%State{model: model} = state) do
    {state.domain_open?, state.scope_open?, state.settings_scroll, state.results_view,
     settings_hover(state), model.open_buffers_only, model.show_ignored_files,
     model.apply_custom_excludes,
     Enum.map(State.scope_rows(state), &{&1.id, &1.label, Map.get(&1, :expanded?)})}
  end

  defp maybe_replace(graph, _id, false, _render), do: graph

  defp maybe_replace(graph, id, true, render) do
    graph |> Graph.delete(id) |> render.()
  end

  # A different theme or a different frame moves or recolours everything. It
  # arrives on every mouse move while the sidebar divider is being dragged, so
  # it has to be as cheap as it can be — and in particular must not disturb
  # anything living in the graph alongside these pieces.
  defp geometry_changed?(old_state, new_state) do
    old_state.theme != new_state.theme or old_state.frame != new_state.frame or
      layout_signature(old_state) != layout_signature(new_state)
  end

  # Only a hover over a HEADER control redraws the header. Hovering a result
  # is the body's business, and rebuilding the controls for it was half of
  # why the highlight lagged the pointer.
  # By the SHAPE of the id, not by searching the header for it: this runs on
  # every mouse move, and building the header widgets to answer it meant
  # walking the scope tree each time the pointer twitched.
  @header_ids [
    :close,
    :replace_caret,
    :replace_all,
    :replace_one,
    :clear,
    :edit_excludes,
    :domain_header,
    :status
  ]

  defp header_hover(%State{hovered: hovered}) when hovered in @header_ids, do: hovered
  defp header_hover(%State{hovered: {:domain, _} = hovered}), do: hovered
  defp header_hover(%State{hovered: {:scope_row, _} = hovered}), do: hovered
  defp header_hover(%State{hovered: {:scope_expand, _} = hovered}), do: hovered
  defp header_hover(%State{hovered: {:toggle, _} = hovered}), do: hovered
  defp header_hover(%State{}), do: nil

  # Everything that changes the SHAPE of the header — where the rows sit, how
  # tall the backdrop is, where the rule under the controls goes.
  #
  # Opening the settings was in neither this nor the widget signature, and the
  # symptoms were an exact map of that: the backdrop kept its old height and
  # left a band of bare pane between it and the results, the disclosure
  # triangle never turned, and the status line stayed where it had been —
  # above the options that had appeared beneath it. Only the body noticed,
  # because the rows really had changed, so the scope tree appeared on its own
  # under a header that had not moved. Typing a character then changed the
  # status text, which finally tripped the widget check and set it all right.
  # Including the scope rows THEMSELVES, not just whether the section is open.
  # Expanding a folder adds rows to the header, which moves the status line
  # and everything under it — and with only the open/shut flags here, that
  # change was invisible to the header while the body moved anyway (its
  # scroll resync tripped its own check). The tree appeared to do nothing but
  # shove the results down.
  defp layout_signature(%State{} = state) do
    {state.domain_open?, state.replace_open?, state.results_view,
     Enum.map(State.scope_rows(state), &{&1.id, Map.get(&1, :expanded?)})}
  end

  # Everything the header's live widgets are drawn from. A search changes the
  # status line, a click changes a toggle. Typing is NOT here: the fields draw
  # themselves, so a keystroke costs this module nothing at all.
  defp widgets_changed?(old_state, new_state) do
    widget_signature(old_state) != widget_signature(new_state)
  end

  defp widget_signature(%State{model: model} = state) do
    {state.focused, state.focused_field, header_hover(state), model.status, model.error,
     model.case_sensitive, model.regex, model.open_buffers_only, model.show_ignored_files,
     model.apply_custom_excludes, model.active_match, model.total_matches,
     layout_signature(state)}
  end

  # The rows are derived from a good deal of state — results, dismissals, which
  # scope nodes are open, which file groups are collapsed — so they are
  # compared directly rather than by guessing at their inputs. Building the
  # list is cheap; building its primitives is not, and that is what this
  # avoids.
  # Compared by their INPUTS, not by building them. A project search can
  # return five hundred rows, and this ran on every update — twice, once for
  # each state — so a mouse crossing a row boundary cost a thousand row
  # constructions before anything was drawn. That is the whole of the freeze.
  defp body_changed?(old_state, new_state) do
    old_state.scroll != new_state.scroll or
      body_signature(old_state) != body_signature(new_state)
  end

  # Including whether the results are STALE: the fade is a property of the
  # body, so a body that does not notice the status changing goes on drawing
  # the previous query's results at full strength.
  defp body_signature(%State{model: model} = state),
    do: {model.files, state.collapsed_files, state.results_view, State.stale?(state)}

  # Hover used to rebuild the entire body — every result row, every scope row,
  # on every crossing of a row boundary. With a few hundred matches on screen
  # the highlight visibly trailed the pointer. Only two rows can change, so
  # only two rectangles are touched.
  defp update_hover(graph, %State{hovered: same}, %State{hovered: same}), do: graph

  defp update_hover(graph, old_state, new_state) do
    graph
    |> paint_row(old_state.hovered, false, new_state)
    |> paint_row(new_state.hovered, true, new_state)
    |> show_row_actions(old_state.hovered, false, new_state)
    |> show_row_actions(new_state.hovered, true, new_state)
  end

  defp paint_row(graph, nil, _hovered?, _state), do: graph

  # Only the FILL changes, so only the fill is set — no need to know the row's
  # size, and therefore no need to build the rows to find it. Everything in
  # the body is a result now (the scope tree moved to the header), so an
  # unhovered row is the pane's own colour.
  defp paint_row(graph, hovered, hovered?, %State{theme: theme} = state) do
    fill = if hovered?, do: theme.row_hover, else: theme.background
    id = hover_row_id(state, hovered) || hovered

    Graph.modify(graph, {:row_bg, id}, &Primitives.update_opts(&1, fill: fill))
  end

  defp show_row_actions(graph, nil, _visible?, _state), do: graph

  defp show_row_actions(graph, hovered, visible?, state) do
    row_id = hover_row_id(state, hovered)

    if row_id do
      Graph.modify(
        graph,
        {:row_actions, row_id},
        &Primitives.update_opts(&1, hidden: not visible?)
      )
    else
      graph
    end
  end

  defp hover_row_id(state, hovered) do
    state
    |> State.visible_rows()
    |> Enum.find_value(fn row ->
      if hovered == row.id or hovered in row.actions, do: row.id
    end)
  end

  @doc """
  Move the already-rendered body to a new scroll offset.

  The body only holds the rows around the viewport, so far enough and there
  are no rows left to move: past the overscan the window is rebuilt at the new
  offset, which draws the forty rows now under the viewport rather than the
  five hundred that are not. Inside it — which is most wheel notches — this
  stays what it always was, one transform.
  """
  def scroll_to(graph, %State{} = old_state, %State{} = new_state) do
    if State.visible_window(old_state) == State.visible_window(new_state) do
      graph
      |> update_scroll_transform(:search_pane_scroll, old_state.scroll, new_state.scroll)
      |> update_scrollbars(
        old_state.scroll,
        new_state.scroll,
        State.body_frame(new_state),
        color: new_state.theme.scrollbar_color,
        group_id: :search_pane
      )
    else
      # render_body draws the scrollbars too, and at the new offset, so this
      # needs no separate scrollbar update.
      graph |> Graph.delete(:search_pane_body) |> render_body(new_state)
    end
  end

  # ── Header ────────────────────────────────────────────────────────────────

  # The parts that change while the pane is being used, and that this module
  # draws itself. The two editable fields are NOT among them: they are
  # TextField components (see render_fields/2), created once and updated by
  # message, never redrawn from here.
  defp render_widgets(graph, %State{} = state) do
    live =
      State.header_widgets(state)
      |> Enum.reject(&match?(%{id: {:field, _}}, &1))
      # The settings live in a panel of their own, drawn over the results.
      |> Enum.reject(&State.settings_widget?/1)

    Primitives.group(
      graph,
      fn g -> Enum.reduce(live, g, &render_header_widget(&2, &1, state)) end,
      id: :search_pane_widgets,
      translate: {0, 0}
    )
  end

  @doc """
  The settings panel — a menu dropping out of the cog, drawn OVER the results.

  Its own piece of the graph, and the only one that deliberately overlaps
  another, so it is rendered last and replaced whole. Everything else in this
  module is arranged so that the four pieces never overlap; this is the
  exception, and it is the exception on purpose.
  """
  def render_settings(graph, %State{domain_open?: false}), do: graph

  def render_settings(graph, %State{} = state) do
    ScenicWidgets.Menu.Dropdown.render(
      graph,
      State.settings_rows(state),
      State.settings_layout(state),
      theme: State.dropdown_theme(state),
      hovered: elem(settings_hover(state), 0),
      hovered_node: elem(settings_hover(state), 1),
      show_shortcuts: false,
      # This pane takes its pointer input from its own primitives, and the
      # panel hangs out past the pane's edge — so the panel has to claim the
      # pointer over itself, or everything it overhangs is unclickable.
      input: true,
      id: :search_pane_settings
    )
  end

  # What the panel should light: the row under the pointer, and the node
  # inside it when that row is the scope tree.
  defp settings_hover(%State{hovered: {:settings, row_id, node_id}}), do: {row_id, node_id}
  defp settings_hover(%State{}), do: {nil, nil}

  @doc """
  The editable fields, as real TextFields.

  Called once, from `render/1`. Everything a one-line input should do —
  selection, the clipboard, word-wise movement, Ctrl+Backspace — is behaviour
  this pane used to reimplement, badly and partially, and now simply gets. The
  cost is that they are processes: they have to survive every redraw, which is
  why the rest of this module is written the way it is.
  """
  def render_fields(graph, %State{} = state) do
    State.header_widgets(state)
    |> Enum.filter(&match?(%{id: {:field, _}}, &1))
    |> Enum.reduce(graph, fn %{id: {:field, field}} = w, g ->
      # TRANSLATE, not a pinned frame. A TextField draws from its own origin
      # and hit-tests against 0..width (State.point_inside?/2), so a frame
      # pinned where the field belongs draws it in the right place by accident
      # while testing every click in the wrong space — clicks near its right
      # edge fall outside and blur it.
      ScenicWidgets.TextField.add_to_graph(g, field_data(w, field, state),
        id: field_id(field),
        translate: {w.x, w.y}
      )
    end)
  end

  @doc """
  Where a field is and how it looks — everything it takes from the pane.

  `nil` when that field is not on screen: the replacement row lives behind a
  disclosure, and asking after it while it is shut used to hand a nil
  rectangle to Frame.new and take the pane down with it.
  """
  def field_settings(%State{theme: theme} = state, field) do
    case Enum.find(State.header_widgets(state), &(&1.id == {:field, field})) do
      nil ->
        nil

      w ->
        %{
          frame: Widgex.Frame.new(%{pin: {0, 0}, size: {w.w, w.h}}),
          colors: field_colors(theme),
          font: field_font(theme),
          placeholder: placeholder(field)
        }
    end
  end

  @doc "Move the field components after a resize."
  def move_fields(graph, %State{} = state) do
    Enum.reduce(State.fields(), graph, fn field, g ->
      w = Enum.find(State.header_widgets(state), &(&1.id == {:field, field}))

      case Graph.get(g, field_id(field)) do
        [] ->
          g

        _ ->
          Graph.modify(
            g,
            field_id(field),
            &Scenic.Primitive.put_transform(&1, :translate, {w.x, w.y})
          )
      end
    end)
  end

  @doc "The component id a field's TextField is registered under."
  def field_id(:query), do: :search_pane_query_field
  def field_id(:replace), do: :search_pane_replace_field

  defp field_data(w, field, %State{theme: theme} = state) do
    %{
      id: field_id(field),
      frame: Widgex.Frame.new(%{pin: {0, 0}, size: {w.w, w.h}}),
      initial_text: State.field_value(state, field),
      # A pane opened on a seeded query shows it selected. The seed arrives as
      # part of the pane's own construction, before there is a field to send
      # it to, so it has to be part of how the field starts.
      initial_selection: if(field == :query and state.query != "", do: :all, else: nil),
      mode: :single_line,
      input_mode: :direct,
      show_line_numbers: false,
      placeholder: placeholder(field),
      focused: state.focused and state.focused_field == field,
      editable: true,
      colors: field_colors(theme),
      font: field_font(theme)
    }
  end

  # A TextField measures text, so it needs real metrics rather than a font
  # name. The theme names a font the host has registered as a static asset,
  # which is where the metrics live; if it has not, that is a mistake worth
  # hearing about rather than a reason to draw with the wrong widths.
  defp field_font(theme) do
    {:ok, {Scenic.Assets.Static.Font, metrics}} = Scenic.Assets.Static.meta(theme.font)
    %{name: theme.font, size: theme.font_size, metrics: metrics}
  end

  # The field draws its own backdrop and border now. The pane used to draw a
  # rect underneath it and repaint the border on every focus change.
  defp field_colors(theme) do
    %{
      text: theme.text,
      placeholder: theme.dim_text,
      background: theme.field_background,
      border: theme.field_border,
      focused_border: theme.field_focus_border,
      cursor: theme.field_focus_border,
      # Selection is drawn OVER the text, so it has to be translucent — and
      # Scenic wants that said explicitly: a three-part colour here is not a
      # colour it will accept.
      selection: with_alpha(theme.match_highlight, 160)
    }
  end

  defp with_alpha({r, g, b}, a), do: {r, g, b, a}
  defp with_alpha({r, g, b, _a}, a), do: {r, g, b, a}

  defp render_header_widget(graph, %{id: {:toggle, option}} = w, %State{theme: theme} = state) do
    on? = Map.fetch!(state.model, option)
    label = if option == :case_sensitive, do: "Aa", else: ".*"

    # Rounded, and lit the way the find bar lights its own: the two widgets
    # ask the same question and had grown two different answers.
    graph
    |> hover_row(w, state)
    |> Primitives.rounded_rectangle({w.w, w.h, 3},
      fill: if(on?, do: theme.button_active, else: theme.button_background),
      stroke: {1, if(on?, do: theme.field_focus_border, else: theme.field_border)},
      translate: {w.x, w.y}
    )
    |> Primitives.text(label,
      translate: {w.x + w.w / 2, w.y + w.h - 6},
      text_align: :center,
      fill: if(on?, do: theme.text, else: theme.dim_text),
      font: theme.font,
      font_size: theme.small_font_size
    )
  end

  # The disclosure for the replacement row — a triangle pointing at what it
  # opens, the same idiom as the find bar's.
  defp render_header_widget(graph, %{id: :replace_caret} = w, %State{theme: theme} = state) do
    graph
    |> hover_row(w, state)
    |> caret(w.x + w.w / 2, w.y + theme.field_height / 2, state.replace_open?, theme.dim_text)
  end

  # Replace this one, and replace all of them — an arrow going into one line
  # or into a stack of them. The same pair of glyphs the find bar uses: two
  # spellings of one action in one editor is one too many.
  defp render_header_widget(graph, %{id: :replace_one} = w, %State{} = state),
    do: replace_button(graph, w, 1, state)

  defp render_header_widget(graph, %{id: :replace_all} = w, %State{} = state),
    do: replace_button(graph, w, 3, state)

  defp render_header_widget(graph, %{id: direction} = w, %State{theme: theme} = state)
       when direction in [:previous_match, :next_match] do
    cx = w.x + w.w / 2
    cy = w.y + w.h / 2
    tip_x = if direction == :previous_match, do: cx - 3, else: cx + 3
    tail_x = if direction == :previous_match, do: cx + 2, else: cx - 2

    graph
    |> hover_row(w, state)
    |> Primitives.line({{tail_x, cy - 5}, {tip_x, cy}},
      stroke: {1.7, theme.dim_text},
      cap: :round
    )
    |> Primitives.line({{tip_x, cy}, {tail_x, cy + 5}},
      stroke: {1.7, theme.dim_text},
      cap: :round
    )
  end

  defp replace_button(graph, w, lines, %State{theme: theme} = state) do
    cx = w.x + w.w / 2
    cy = w.y + w.h / 2
    arrow_y = cy - 5

    graph
    |> hover_row(w, state)
    |> Primitives.rounded_rectangle({w.w, w.h, 3},
      fill: theme.button_background,
      stroke: {1, theme.field_border},
      translate: {w.x, w.y}
    )
    |> Primitives.line({{cx - 6, arrow_y}, {cx + 3, arrow_y}},
      stroke: {1.5, theme.button_text},
      cap: :round
    )
    |> Primitives.line({{cx, arrow_y - 3}, {cx + 3, arrow_y}},
      stroke: {1.5, theme.button_text},
      cap: :round
    )
    |> Primitives.line({{cx, arrow_y + 3}, {cx + 3, arrow_y}},
      stroke: {1.5, theme.button_text},
      cap: :round
    )
    |> then(fn g ->
      Enum.reduce(0..(lines - 1), g, fn i, acc ->
        y = cy + 2 + i * 3

        Primitives.line(acc, {{cx - 6, y}, {cx + 6, y}},
          stroke: {1.3, theme.button_text},
          cap: :round
        )
      end)
    end)
  end

  # The close, drawn rather than typed — a text "×" cannot be made to line up
  # in a box, and this one needs to be the size of the closes on the tabs.
  defp render_header_widget(graph, %{id: :close} = w, %State{theme: theme} = state) do
    cx = w.x + w.w / 2
    cy = w.y + w.h / 2
    r = 5

    graph
    |> hover_row(w, state)
    |> Primitives.line({{cx - r, cy - r}, {cx + r, cy + r}},
      stroke: {1.8, theme.text},
      cap: :round
    )
    |> Primitives.line({{cx + r, cy - r}, {cx - r, cy + r}},
      stroke: {1.8, theme.text},
      cap: :round
    )
  end

  # A scope row, drawn in the header now. Same shape as a body row — a
  # caret, a tick and a name — but it belongs to the settings section, so it
  # sits on that background rather than the pane's.
  # The triangle is its own control (it expands; the row it sits on ticks),
  # but it is DRAWN by the row, so there is nothing to add here — only the
  # hit area and the semantic entry, which State and SearchPane provide.
  defp render_header_widget(graph, %{id: {:scope_expand, _id}}, %State{}), do: graph

  defp render_header_widget(graph, %{id: {:scope_row, _id}} = w, %State{theme: theme} = state) do
    row = w.row
    # Including when the pointer is on the triangle at its left-hand end:
    # that is one row to look at, whatever it is made of.
    hovered? = state.hovered in [w.id, {:scope_expand, row.id}]
    x = w.x + row.depth * theme.indent
    text_x = if disclosing?(row), do: x + 12, else: x

    graph
    # Inside the panel, and only inside it. This used to be drawn wider than
    # the row and pinned to x = 0, so that the settings read as a full-width
    # band of the header — which is what they were. In a floating panel that
    # band runs straight out through the border on both sides.
    #
    # Rounded and CLEAR until hovered, the way IconMenu draws its rows: a row
    # painted in the panel's own colour is a rectangle you can see the edges
    # of, tiling the panel with seams.
    |> Primitives.rrect({w.w, w.h, @panel_row_radius},
      fill: if(hovered?, do: theme.row_hover, else: :clear),
      translate: {w.x, w.y}
    )
    |> then(fn g ->
      if disclosing?(row),
        do: caret(g, x + 4, w.y + w.h / 2, row_open?(row), theme.dim_text),
        else: g
    end)
    |> Primitives.text(clip(row.label, w.w - 24, theme.font_size),
      translate: {text_x, w.y + w.h - 6},
      fill: row_colour(row, theme),
      font: theme.font,
      font_size: row_font_size(row, theme)
    )
  end

  defp render_header_widget(graph, %{id: :clear} = w, %State{theme: theme} = state) do
    cx = w.x + w.w / 2
    cy = w.y + w.h / 2
    r = 6
    # The bar lies along the ring's own diagonal, so it meets the circle
    # rather than crossing it at a tangent.
    d = r * :math.sqrt(2) / 2

    graph
    |> hover_row(w, state)
    |> Primitives.circle(r, stroke: {1.6, theme.dim_text}, translate: {cx, cy})
    |> Primitives.line({{cx - d, cy + d}, {cx + d, cy - d}},
      stroke: {1.6, theme.dim_text},
      cap: :round
    )
  end

  # The disclosure for the search settings: a caret and a word, not three dots.
  # A control that hides something should say what it is hiding.
  # The settings, as a cog on the status bar. DRAWN, not typed: IBM Plex Mono
  # has no U+2699, and Scenic draws a missing glyph as an empty box — the same
  # reason the disclosure triangles are drawn and the shortcuts are spelled
  # "Cmd" rather than "⌘".
  #
  # A ring with spokes standing out of it, which is what a gear is at this
  # size; teeth as rotated rectangles at 24px come out as mush.
  defp render_header_widget(graph, %{id: :domain_header} = w, %State{theme: theme} = state) do
    cx = w.x + w.w / 2
    cy = w.y + w.h / 2
    colour = if state.domain_open?, do: theme.text, else: theme.dim_text

    graph
    |> then(fn g ->
      # Lit for as long as the panel is open, not just while the pointer is on
      # it. A menubar does this, and it is what stops an open dropdown looking
      # orphaned from the button that opened it.
      # Active and hovered are DIFFERENT, as they are in IconMenu: the button
      # of an open menu is lit more strongly than one merely under the
      # pointer, so you can tell which of the two is happening.
      cond do
        state.domain_open? ->
          Primitives.rrect(g, {w.w, w.h, @panel_row_radius},
            fill: theme.button_background,
            translate: {w.x, w.y}
          )

        true ->
          hover_row(g, w, state)
      end
    end)
    |> Primitives.circle(5, stroke: {1.6, colour}, translate: {cx, cy})
    |> cog_teeth(cx, cy, colour)
    |> Primitives.circle(1.6, fill: colour, translate: {cx, cy})
  end

  @cog_teeth 8
  defp cog_teeth(graph, cx, cy, colour) do
    Enum.reduce(0..(@cog_teeth - 1), graph, fn i, g ->
      angle = i * 2 * :math.pi() / @cog_teeth
      {dx, dy} = {:math.cos(angle), :math.sin(angle)}

      Primitives.line(
        g,
        {{cx + dx * 5.5, cy + dy * 5.5}, {cx + dx * 8.5, cy + dy * 8.5}},
        stroke: {1.6, colour},
        cap: :round
      )
    end)
  end

  # A disclosure triangle, DRAWN. Typed as a character it is a character the
  # font may not have, and an empty box where the triangle should be is worse
  # than no triangle at all.
  defp caret(graph, cx, cy, open?, colour) do
    r = 3.5

    points =
      if open?,
        do: {{cx - r, cy - r / 2}, {cx + r, cy - r / 2}, {cx, cy + r}},
        else: {{cx - r / 2, cy - r}, {cx + r, cy}, {cx - r / 2, cy + r}}

    Primitives.triangle(graph, points, fill: colour)
  end

  # A domain option, drawn as a tick box and a sentence — these are choices
  # about where to look, and a two-letter glyph could not say which is which.
  defp render_header_widget(graph, %{id: {:domain, option}} = w, %State{theme: theme} = state) do
    on? = Map.fetch!(state.model, option)
    mark = if on?, do: "[x]", else: "[ ]"

    Primitives.text(graph, mark <> "  " <> domain_label(option),
      translate: {w.x + 2, w.y + w.h - 6},
      fill: if(on?, do: theme.text, else: theme.dim_text),
      font: theme.font,
      font_size: theme.small_font_size
    )
  end

  defp domain_label(:open_buffers_only), do: "Search only open buffers"
  defp domain_label(:show_ignored_files), do: "Show .gitignore files in search"
  defp domain_label(:apply_custom_excludes), do: "Apply custom search excludes"

  # A plain action among the switches, so it reads as "and here is the list
  # those settings are talking about".
  defp render_header_widget(graph, %{id: :edit_excludes} = w, %State{theme: theme} = state) do
    graph
    |> hover_row(w, state)
    |> Primitives.text("     Edit the exclude list…",
      translate: {w.x + 2, w.y + w.h - 6},
      fill: theme.dim_text,
      font: theme.font,
      font_size: theme.small_font_size
    )
  end

  # Header controls light up under the pointer, like the rows do.
  defp hover_row(graph, %{id: id} = w, %State{hovered: id, theme: theme}) do
    Primitives.rrect(graph, {w.w, w.h, @panel_row_radius},
      fill: theme.row_hover,
      translate: {w.x, w.y}
    )
  end

  defp hover_row(graph, _w, _state), do: graph

  defp render_header_widget(graph, %{id: :status} = w, %State{theme: theme} = state) do
    {text, colour} = status_line(state)

    Primitives.text(graph, text,
      translate: {w.x, w.y + w.h - 6},
      fill: colour,
      font: theme.font,
      font_size: theme.small_font_size
    )
  end

  defp placeholder(:query), do: "Search project"
  defp placeholder(:replace), do: "Replace with"

  defp status_line(%State{model: %{error: error}, theme: theme}) when is_binary(error),
    do: {error, theme.error_text}

  defp status_line(%State{model: model, theme: theme} = state) do
    text =
      case model.status do
        :idle -> idle_line(model.root, state)
        # Two different things, and worth telling apart: nothing has started
        # yet, versus something is running. A pane that says "searching…"
        # during the debounce is claiming work it has not begun.
        :debouncing -> "typing…"
        :searching -> "searching…"
        {:done, 0, 0, _ms} -> "no matches"
        {:done, _n, _files, _ms} -> navigation_status(model)
        {:error, reason} -> "search failed: #{inspect(reason)}"
      end

    colour = if match?({:error, _}, model.status), do: theme.error_text, else: theme.dim_text
    {text, colour}
  end

  defp navigation_status(%{total_matches: 0}), do: "no matches"

  defp navigation_status(%{active_match: active, files: files, total_matches: total}) do
    flat = for file <- files, match <- file.matches, do: {file.path, match.line, match.col}
    current = (Enum.find_index(flat, &(&1 == active)) || 0) + 1
    "#{current} of #{total}"
  end

  # An empty pane should say WHAT it is about to search, not describe itself.
  # "Type to search the project" is true of every project there has ever
  # been; the name of the one in front of you is the useful half.
  defp idle_line(nil, _state), do: "Type to search the project"

  defp idle_line(root, %State{theme: theme} = state) do
    room = status_room(state)

    "Search " <>
      clip_left(
        pretty_path(root),
        room - 7 * char_width(theme.small_font_size),
        theme.small_font_size
      )
  end

  defp status_room(%State{} = state) do
    case Enum.find(State.header_widgets(state), &(&1.id == :status)) do
      %{w: w} -> w
      nil -> state.frame.size.width
    end
  end

  # Home is where most projects are, and "~" is both shorter and how a person
  # says it.
  defp pretty_path(path) do
    case System.user_home() do
      nil ->
        path

      home ->
        if String.starts_with?(path, home),
          do: "~" <> String.slice(path, String.length(home)..-1//1),
          else: path
    end
  end

  # Clipped from the FRONT: the end of a path is the part that says which
  # project this is, and the beginning is the part every project shares.
  defp clip_left(text, width, font_size) do
    limit = max_chars(width, font_size)

    if String.length(text) <= limit do
      text
    else
      "…" <> String.slice(text, (String.length(text) - max(limit - 1, 0))..-1//1)
    end
  end

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  # ── Body ──────────────────────────────────────────────────────────────────

  # Only the rows the viewport can show (plus the overscan) are built and
  # drawn. The rest of the result set exists as a content height and nothing
  # else: a row that is scrolled a thousand pixels out of sight is not a
  # cheaper primitive, it is no primitive.
  defp render_body(graph, %State{theme: theme} = state) do
    body = State.body_frame(state)
    rows = State.visible_rows(state)

    Primitives.group(
      graph,
      fn g ->
        g
        |> scrollable_group(
          state.scroll,
          body,
          fn sg -> Enum.reduce(rows, sg, &render_row(&2, &1, state)) end,
          id: :search_pane_scroll,
          overlay_scrollbars: true
        )
        |> render_scrollbars(state.scroll, body,
          color: theme.scrollbar_color,
          group_id: :search_pane
        )
        |> searching_line(rows, state)
      end,
      id: :search_pane_body,
      translate: {0, State.header_height(state)}
    )
  end

  # The first search of a session has no previous results to fade, and an
  # empty pane is what "no matches" looks like — so it says which it is.
  defp searching_line(graph, [], %State{theme: theme} = state) do
    if State.stale?(state) do
      Primitives.text(graph, "Searching…",
        translate: {theme.padding, theme.row_height + 2},
        fill: theme.dim_text,
        font: theme.font,
        font_size: theme.font_size
      )
    else
      graph
    end
  end

  defp searching_line(graph, _rows, %State{}), do: graph

  defp render_row(graph, row, %State{theme: theme} = state) do
    hovered? = state.hovered == row.id
    actions_visible? = hovered? or state.hovered in row.actions
    x = theme.padding + row.depth * theme.indent
    # A row that opens something leaves room for its triangle.
    text_x = if disclosing?(row), do: x + 12, else: x

    action_left =
      state
      |> State.action_bounds(row)
      |> Enum.map(& &1.x)
      |> Enum.min(fn -> state.frame.size.width end)

    room = action_left - text_x - 4
    label = clip(row.label, room, theme.font_size)

    Primitives.group(
      graph,
      fn g ->
        g
        |> row_background(row, hovered?, state)
        |> maybe_row_caret(row, x, theme)
        |> maybe_match_highlight(row, text_x, String.length(label), theme, state)
        |> Primitives.text(label,
          translate: {text_x, row.height - 6},
          fill: row_colour(row, theme) |> fade_if_stale(state),
          font: theme.font,
          font_size: row_font_size(row, theme)
        )
        |> maybe_skipped_strike(row, text_x, label, theme)
        |> render_actions(row, actions_visible?, state)
      end,
      translate: {0, row.y}
    )
  end

  # Every row gets a background rectangle, always, with a stable id — even
  # when it is drawn in the pane's own colour. That is what lets a hover be a
  # repaint of one rectangle instead of a rebuild of every row.
  defp row_background(graph, row, hovered?, %State{theme: theme, frame: frame}) do
    Primitives.rect(graph, {frame.size.width, row.height},
      fill: row_fill(row, hovered?, theme),
      id: {:row_bg, row.id}
    )
  end

  # Scope rows share the settings background: without it the tree reads as a
  # strange first result — a list of directories among a list of matches.
  defp row_fill(%{current?: true}, _hovered, theme), do: theme.button_active
  defp row_fill(_row, true, theme), do: theme.row_hover

  defp row_fill(%{kind: kind}, false, theme) when kind in [:scope, :scope_header],
    do: theme.header_background

  defp row_fill(_row, false, theme), do: theme.background

  # The whole point of drawing matches in a pane of their own: the matched text
  # is marked inside the line, so a result reads as a hit rather than as a line
  # that happens to be listed.
  defp maybe_match_highlight(graph, %{kind: :match} = row, x, drawn_chars, theme, state) do
    # The row's text is clipped to the pane's width, so the highlight has to be
    # clipped with it. Drawing the full match regardless left a stray block
    # floating past the end of a truncated line, marking nothing.
    visible = min(row.match_len, drawn_chars - row.match_start)

    if visible > 0 do
      cw = char_width(theme.font_size)

      Primitives.rect(graph, {visible * cw, theme.font_size + 2},
        fill: fade_if_stale(theme.match_highlight, state),
        translate: {x + row.match_start * cw, @highlight_top}
      )
    else
      graph
    end
  end

  defp maybe_match_highlight(graph, _row, _x, _drawn_chars, _theme, _state), do: graph

  # Half way to the pane's own colour, which reads as "not yet" in a light
  # theme and a dark one alike — the results are still legible, still
  # scrollable, still clickable, and visibly not the answer to what is in the
  # box.
  defp fade_if_stale(colour, %State{} = state) do
    if State.stale?(state), do: blend(colour, state.theme.background), else: colour
  end

  defp blend({r, g, b}, {br, bg, bb}), do: {div(r + br, 2), div(g + bg, 2), div(b + bb, 2)}

  # Which rows have a triangle: the scope header, and any scope node with
  # children. Files in the results have their own collapse marker already.
  defp disclosing?(%{kind: :scope_header}), do: true
  defp disclosing?(%{kind: :scope, expandable?: true}), do: true
  # A directory and a file both open and shut, and a triangle is how a person
  # can tell before clicking. A file used to have no marker at all — the only
  # sign it was collapsed was its matches not being there.
  defp disclosing?(%{kind: :dir}), do: true
  defp disclosing?(%{kind: :file}), do: true
  defp disclosing?(_row), do: false

  defp maybe_row_caret(graph, row, x, theme) do
    if disclosing?(row) do
      caret(graph, x + 4, row.height / 2, row_open?(row), theme.dim_text)
    else
      graph
    end
  end

  defp row_open?(%{kind: :scope_header, expanded?: open?}), do: open?
  defp row_open?(%{expanded?: open?}), do: open?
  defp row_open?(_row), do: false

  defp row_colour(%{current?: true}, theme), do: theme.button_text
  defp row_colour(%{kind: :dir}, theme), do: theme.heading
  defp row_colour(%{kind: :file}, theme), do: theme.text
  defp row_colour(%{kind: :scope_header}, theme), do: theme.heading
  defp row_colour(%{kind: :scope}, theme), do: theme.dim_text
  defp row_colour(_row, theme), do: theme.dim_text

  defp row_font_size(%{kind: :scope_header}, theme), do: theme.small_font_size
  defp row_font_size(_row, theme), do: theme.font_size

  defp maybe_skipped_strike(graph, %{kind: :match, skipped?: true}, x, label, theme) do
    width = min(String.length(label) * char_width(theme.font_size), 240)

    Primitives.line(graph, {{x, theme.row_height / 2}, {x + width, theme.row_height / 2}},
      stroke: {1, theme.dim_text}
    )
  end

  defp maybe_skipped_strike(graph, _row, _x, _label, _theme), do: graph

  defp render_actions(graph, row, visible?, %State{theme: theme} = state) do
    Primitives.group(
      graph,
      fn group ->
        Enum.reduce(State.action_bounds(state, row), group, fn b, g ->
          g
          |> Primitives.rrect({b.w, b.h, 3},
            id: {:action_bg, b.action},
            fill: theme.button_background,
            stroke: {1, theme.field_border},
            translate: {b.x, b.y - row.y}
          )
          |> Primitives.text(action_label(b.action, row),
            id: {:action_glyph, b.action},
            translate: {b.x + b.w / 2, b.y - row.y + b.h / 2},
            text_align: :center,
            text_base: :middle,
            fill: theme.button_text,
            font: theme.font,
            font_size: theme.small_font_size
          )
        end)
      end,
      id: {:row_actions, row.id},
      hidden: not visible?
    )
  end

  defp action_label({:replace_file, _}, _row), do: "Replace all"
  defp action_label({:replace_match, _, _, _}, _row), do: "Replace"
  defp action_label({:dismiss_file, _}, _row), do: "×"
  defp action_label({:dismiss_match, _, _, _}, %{skipped?: true}), do: "Add back"
  defp action_label({:dismiss_match, _, _, _}, _row), do: "Skip"

  # ── Text metrics ──────────────────────────────────────────────────────────
  #
  # The pane is monospaced, so a ratio beats a metrics lookup — the same
  # approximation TabBar uses for its labels.

  defp char_width(font_size), do: font_size * 0.6

  defp max_chars(width, font_size), do: max(trunc(width / char_width(font_size)), 0)

  defp clip(text, width, font_size) do
    limit = max_chars(width, font_size)

    if String.length(text) <= limit,
      do: text,
      else: String.slice(text, 0, max(limit - 1, 0)) <> "…"
  end
end
