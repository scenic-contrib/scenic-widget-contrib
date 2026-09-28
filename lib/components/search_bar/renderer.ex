defmodule ScenicWidgets.SearchBar.Renderer do
  @moduledoc """
  Draws `ScenicWidgets.SearchBar`.

  The arrangement is the one every editor has settled on, and for reasons
  worth writing down:

      [⌄] [ Find……………………………… Aa .* ] [‹] [3/10] [›]              [×]
          [ Replace………………………………… ]                     [→] [⇉]

  * The **disclosure caret** is on the far left, where something that opens
    another row belongs — it points at what it opens.
  * The **close** is on the far right. It used to be on the left, in the
    caret's place, which put the most destructive control in the bar under
    the pointer's resting position.
  * The **option toggles** sit inside the right-hand end of the field they
    apply to, so it reads that they modify the query rather than the search.
  * Every button has a tooltip. These are drawn glyphs rather than words, and
    an icon that cannot say what it does has to be guessed at.

  Every rectangle here comes from `State.widgets/1` — the same list the hit
  test uses, so a button cannot draw in one place and respond in another.
  """

  alias ScenicWidgets.SearchBar.State
  alias ScenicWidgets.{FloatingPanel, Tooltip}
  alias Scenic.Graph
  alias Scenic.Primitives

  @doc "Layout constants shared with the component's hit-testing."
  defdelegate button_width(), to: State
  defdelegate match_count_width(), to: State

  @doc """
  The complete search bar, from nothing. Used on init, and whenever the
  replace row appears or disappears — that changes which fields exist.
  """
  def render(%State{} = state) do
    Graph.build()
    |> render_backdrop(state)
    |> render_fields(state)
    |> render_chrome(state)
  end

  @doc """
  Redraw only what changed.

  The bar holds child components now — its two fields are TextFields — and a
  graph rebuilt from scratch takes its children with it, losing their cursor
  and their selection on every keystroke. So the backdrop is modified in
  place (it is UNDER everything, and a replacement lands at the END of the
  graph), the chrome is replaced wholesale (it is ON TOP of everything, which
  is where a replacement lands anyway), and the fields are left alone.
  """
  def update_render(graph, %State{} = old_state, %State{} = new_state) do
    graph
    |> then(fn g ->
      if geometry_changed?(old_state, new_state), do: update_backdrop(g, new_state), else: g
    end)
    |> Graph.delete(:search_bar_chrome)
    |> render_chrome(new_state)
    |> move_fields(new_state)
  end

  @doc "Has anything moved or been recoloured?"
  def geometry_changed?(old_state, new_state),
    do: old_state.theme != new_state.theme or old_state.frame != new_state.frame

  @doc "Do the FIELDS themselves have to be rebuilt? Only the replace row does that."
  def fields_changed?(old_state, new_state),
    do: old_state.replace_mode != new_state.replace_mode

  defp render_backdrop(graph, %State{} = state) do
    FloatingPanel.add_card(graph, {State.frame_width(state), State.height(state)},
      id: :search_bar_bg,
      fill: state.theme.background,
      border: state.theme.border
    )
  end

  defp update_backdrop(graph, %State{} = state) do
    Graph.modify(graph, :search_bar_bg, fn p ->
      Primitives.rounded_rectangle(p, {State.frame_width(state), State.height(state), 7},
        fill: state.theme.background,
        stroke: {1, state.theme.border}
      )
    end)
  end

  # Everything this module draws itself, in one group so it can be replaced in
  # one go. It sits ON TOP of the fields deliberately: the option toggles are
  # drawn inside the search field's right-hand end.
  defp render_chrome(graph, %State{} = state) do
    widgets = State.widgets(state)
    drawn = Enum.reject(widgets, &(&1.id in [:search_field, :replace_field]))

    Primitives.group(
      graph,
      fn g ->
        g
        |> render_widgets(drawn, state)
        |> Tooltip.add(
          tooltip_for(state.hovered, widgets, state),
          state.theme,
          State.frame_width(state)
        )
      end,
      id: :search_bar_chrome,
      translate: {0, 0}
    )
  end

  @doc """
  The editable fields, as real TextFields.

  Selection, the clipboard, word-wise movement, Ctrl+Backspace, undo — all of
  it behaviour this bar used to reimplement one key at a time, and mostly did
  not. Ctrl+A did nothing here until now.
  """
  def render_fields(graph, %State{} = state) do
    State.widgets(state)
    |> Enum.filter(&(&1.id in [:search_field, :replace_field]))
    |> Enum.reduce(graph, fn w, g ->
      field = field_of(w.id)

      # TRANSLATE, not a pinned frame. A TextField draws from its own origin
      # and hit-tests against 0..width — see State.point_inside?/2 — so a
      # frame pinned where the field belongs draws it in the right place by
      # accident and tests clicks in the wrong space. The component is moved
      # by the graph; its frame only says how big it is.
      ScenicWidgets.TextField.add_to_graph(g, field_data(w, field, state),
        id: field_id(field),
        translate: {w.x, w.y}
      )
    end)
  end

  @doc """
  Where a field is and how it looks — everything it takes from the bar.

  `nil` when that field is not on screen: the replacement row only exists in
  replace mode, and asking after it otherwise used to hand a nil rectangle to
  Frame.new and take the bar down with it.
  """
  def field_settings(%State{} = state, field) do
    case Enum.find(State.widgets(state), &(&1.id == widget_id(field))) do
      nil ->
        nil

      w ->
        %{
          frame: Widgex.Frame.new(%{pin: {0, 0}, size: {w.w, w.h}}),
          colors: field_colors(state.theme),
          font: field_font(state)
        }
    end
  end

  @doc "Where a field's component sits in the bar's graph, if it is there at all."
  def field_translate(%State{} = state, field) do
    case Enum.find(State.widgets(state), &(&1.id == widget_id(field))) do
      nil -> nil
      w -> {w.x, w.y}
    end
  end

  @doc "Move the field components after a resize."
  def move_fields(graph, %State{} = state) do
    Enum.reduce([:search, :replace], graph, fn field, g ->
      case {Graph.get(g, field_id(field)), field_translate(state, field)} do
        {[], _} ->
          g

        {_, nil} ->
          g

        {_, translate} ->
          Graph.modify(g, field_id(field), fn p ->
            Scenic.Primitive.put_transform(p, :translate, translate)
          end)
      end
    end)
  end

  @doc "The component id a field's TextField is registered under."
  def field_id(:search), do: :search_bar_query_field
  def field_id(:replace), do: :search_bar_replace_field

  defp widget_id(:search), do: :search_field
  defp widget_id(:replace), do: :replace_field

  defp field_of(:search_field), do: :search
  defp field_of(:replace_field), do: :replace

  defp field_data(w, field, %State{} = state) do
    text = if field == :search, do: state.query, else: state.replace_query

    %{
      id: field_id(field),
      frame: Widgex.Frame.new(%{pin: {0, 0}, size: {w.w, w.h}}),
      initial_text: text,
      # A bar opened on the word under the cursor shows it selected, so the
      # first thing typed replaces the guess instead of being appended to it.
      initial_selection: if(field == :search and text != "", do: :all, else: nil),
      mode: :single_line,
      input_mode: :direct,
      show_line_numbers: false,
      placeholder: if(field == :search, do: "Find", else: "Replace"),
      focused: state.focused and state.focused_field == field,
      editable: true,
      colors: field_colors(state.theme),
      font: field_font(state)
    }
  end

  defp field_colors(theme) do
    %{
      text: theme.text,
      placeholder: theme.placeholder,
      background: theme.input_background,
      border: theme.border,
      focused_border: theme.focus_border,
      cursor: theme.text,
      selection: with_alpha(theme.match_highlight, 110)
    }
  end

  defp with_alpha({r, g, b}, a), do: {r, g, b, a}
  defp with_alpha({r, g, b, _a}, a), do: {r, g, b, a}

  # A TextField measures text, so it needs metrics rather than a font name.
  defp field_font(%State{font: font}) do
    case font do
      %{metrics: metrics} when not is_nil(metrics) ->
        font

      %{name: name} = f ->
        {:ok, {Scenic.Assets.Static.Font, metrics}} = Scenic.Assets.Static.meta(name)
        Map.put(f, :metrics, metrics)
    end
  end

  defp tooltip_for(nil, _widgets, _state), do: nil

  defp tooltip_for(id, widgets, state) do
    case Enum.find(widgets, &(&1.id == id and &1.tooltip != nil)) do
      nil -> nil
      w -> %{text: w.tooltip, at: {w.x, tooltip_y(w, state)}}
    end
  end

  # A tooltip hangs from the bottom of the ROW its control is on, not from the
  # bottom of the control itself — the option toggles are inset inside the
  # query field, so hanging them from their own edge put them a dozen pixels
  # above the labels beside them.
  #
  # The caret is the exception: it spans every row, so it hangs from the
  # bottom of the whole bar, level with the replace buttons it sits beside
  # when the second row is open.
  defp tooltip_y(%{id: :toggle_replace}, state), do: State.height(state)

  defp tooltip_y(%{y: y}, state) when y >= 0 do
    if y >= State.bar_height(), do: State.height(state), else: State.bar_height()
  end

  defp render_widgets(graph, widgets, state) do
    Enum.reduce(widgets, graph, &render_widget(&2, &1, state))
  end

  # ── The widgets ───────────────────────────────────────────────────────────

  defp render_widget(graph, %{id: :toggle_replace} = w, %State{} = state) do
    graph
    |> hover_backdrop(w, state)
    |> caret(w, state.replace_mode, state.theme.text)
  end


  defp render_widget(graph, %{id: {:toggle, option}} = w, %State{} = state) do
    on? = Map.fetch!(state, option)
    label = if option == :case_sensitive, do: "Aa", else: ".*"

    graph
    |> Primitives.rounded_rectangle({w.w, w.h, 3},
      id: {:option, option},
      # Grey when off rather than transparent: an unlit toggle still has to
      # look like a button you could press. Lit, it keeps the find bar's own
      # colours, which the pane has now adopted too.
      fill: if(on?, do: state.theme.option_on, else: state.theme.button_bg),
      stroke: {1, if(on?, do: state.theme.option_on_border, else: state.theme.border)},
      translate: {w.x, w.y}
    )
    |> Primitives.text(label,
      font: :roboto_mono,
      font_size: 11,
      fill: if(on?, do: state.theme.text, else: state.theme.placeholder),
      text_align: :center,
      translate: {w.x + w.w / 2, w.y + w.h / 2 + 4}
    )
  end

  defp render_widget(graph, %{id: :prev} = w, %State{} = state) do
    graph |> hover_backdrop(w, state) |> arrow(w, :left, state.theme.text)
  end

  defp render_widget(graph, %{id: :next} = w, %State{} = state) do
    graph |> hover_backdrop(w, state) |> arrow(w, :right, state.theme.text)
  end

  defp render_widget(graph, %{id: :count} = w, %State{} = state) do
    text =
      if state.total_matches > 0,
        do: "#{state.current_match}/#{state.total_matches}",
        else: "0/0"

    colour =
      if state.total_matches > 0, do: state.theme.match_highlight, else: state.theme.placeholder

    Primitives.text(graph, text,
      id: :match_count,
      font: :roboto_mono,
      font_size: 13,
      fill: colour,
      text_align: :center,
      translate: {w.x + w.w / 2, w.y + w.h / 2 + 4.5}
    )
  end

  defp render_widget(graph, %{id: :close} = w, %State{} = state) do
    graph |> hover_backdrop(w, state) |> cross(w, state.theme.text)
  end

  defp render_widget(graph, %{id: :replace_one} = w, %State{} = state) do
    graph |> hover_backdrop(w, state) |> replace_icon(w, 1, state.theme.text)
  end

  defp render_widget(graph, %{id: :replace_all} = w, %State{} = state) do
    graph |> hover_backdrop(w, state) |> replace_icon(w, 3, state.theme.text)
  end

  # ── Pieces ────────────────────────────────────────────────────────────────

  # Buttons are transparent until the pointer is on them. A row of filled
  # rectangles reads as a toolbar of its own, and competes with the field —
  # which is the thing the bar is actually about.
  defp hover_backdrop(graph, %{id: id} = w, %State{hovered: id, theme: theme}) do
    inset_x = 2
    inset_y = 6

    Primitives.rounded_rectangle(graph, {w.w - inset_x * 2, w.h - inset_y * 2, 4},
      fill: theme.button_hover,
      translate: {w.x + inset_x, w.y + inset_y}
    )
  end

  defp hover_backdrop(graph, _w, _state), do: graph

  # A disclosure triangle: pointing right when the replace row is hidden, down
  # when it is showing. It points AT what it opens.
  # The glyph sits on the FIRST row even though the button spans them all: a
  # triangle floating between two rows would not read as belonging to either.
  defp caret(graph, w, open?, colour) do
    cx = w.x + w.w / 2
    cy = w.y + State.bar_height() / 2
    r = 4

    points =
      if open?,
        do: {{cx - r, cy - r / 2}, {cx + r, cy - r / 2}, {cx, cy + r}},
        else: {{cx - r / 2, cy - r}, {cx + r, cy}, {cx - r / 2, cy + r}}

    Primitives.triangle(graph, points, fill: colour, id: :replace_caret)
  end

  # A real arrow — a shaft with a head on it — rather than an angle bracket.
  # A chevron says "there is more this way"; an arrow says "go". These
  # buttons GO to the next match, so they get arrows.
  defp arrow(graph, w, direction, colour) do
    cx = w.x + w.w / 2
    cy = w.y + w.h / 2
    len = 5.5
    head = 3.5

    # tip is the end the head sits on; tail is the other
    {tip, tail} =
      if direction == :left,
        do: {cx - len, cx + len},
        else: {cx + len, cx - len}

    barb = if direction == :left, do: head, else: -head

    graph
    |> Primitives.line({{tail, cy}, {tip, cy}}, stroke: {1.7, colour}, cap: :round)
    |> Primitives.line({{tip + barb, cy - head}, {tip, cy}}, stroke: {1.7, colour}, cap: :round)
    |> Primitives.line({{tip + barb, cy + head}, {tip, cy}}, stroke: {1.7, colour}, cap: :round)
  end

  defp cross(graph, w, colour) do
    cx = w.x + w.w / 2
    cy = w.y + w.h / 2
    r = 5

    graph
    |> Primitives.line({{cx - r, cy - r}, {cx + r, cy + r}}, stroke: {2, colour}, cap: :round)
    |> Primitives.line({{cx + r, cy - r}, {cx - r, cy + r}}, stroke: {2, colour}, cap: :round)
  end

  # An arrow going INTO lines: one line for "replace this one", a stack of
  # them for "replace all of them". The count is the whole difference between
  # the two buttons, so it is the whole difference between the two icons.
  defp replace_icon(graph, w, lines, colour) do
    cx = w.x + w.w / 2
    cy = w.y + w.h / 2
    arrow_y = cy - 5

    graph
    |> Primitives.line({{cx - 7, arrow_y}, {cx + 4, arrow_y}}, stroke: {1.6, colour}, cap: :round)
    |> Primitives.line({{cx + 1, arrow_y - 3}, {cx + 4, arrow_y}}, stroke: {1.6, colour}, cap: :round)
    |> Primitives.line({{cx + 1, arrow_y + 3}, {cx + 4, arrow_y}}, stroke: {1.6, colour}, cap: :round)
    |> then(fn g ->
      Enum.reduce(0..(lines - 1), g, fn i, acc ->
        y = cy + 2 + i * 3.5

        Primitives.line(acc, {{cx - 7, y}, {cx + 7, y}}, stroke: {1.4, colour}, cap: :round)
      end)
    end)
  end

  @doc "Updates the match count display."
  def update_match_count(graph, %State{current_match: current, total_matches: total, theme: theme}) do
    text = if total > 0, do: "#{current}/#{total}", else: "0/0"
    colour = if total > 0, do: theme.match_highlight, else: theme.placeholder

    Graph.modify(graph, :match_count, fn primitive ->
      Primitives.text(primitive, text, fill: colour)
    end)
  end
end
