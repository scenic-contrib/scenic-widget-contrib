defmodule ScenicWidgets.PopupModal do
  @moduledoc """
  A centred modal panel over a dimmed overlay — for splash/About boxes and
  other informational popups that want more presence than a ConfirmDialog.

  ## Data

      %{
        frame: %Widgex.Frame{},          # the FULL area to dim (usually the viewport frame)
        title: "Quillex",                # large heading
        body: ["line", "", "line"],      # list of body lines ("" = spacer)
        button: {:ok, "OK"},             # single dismiss button (optional, default {:ok, "OK"})
        accent: color | nil              # title / button colour (optional)
      }

  ## Behaviour

  * Renders a semi-transparent overlay across `frame` and a centred panel.
  * The button click, Enter, or Escape all dismiss.
  * Sends `{:popup_modal_response, id, action}` to the parent scene, where
    `id` is the component's `:id` option and `action` the button id.
  * While open it consumes keyboard input (it is a modal) — the parent
    should blur any focused editor when showing it, and refocus on the
    response (same contract as ConfirmDialog).
  """
  use Scenic.Component, has_children: false
  require Logger

  alias Scenic.Graph
  import Scenic.Primitives

  @panel_width 560
  @line_height 24
  @title_height 44
  @button_h 34
  @button_w 96
  @pad 28

  @overlay {0, 0, 0, 160}
  @panel_bg {35, 38, 48}
  @panel_border {90, 95, 110}
  @text_color {210, 212, 220}
  @default_accent {255, 215, 0}

  @impl Scenic.Component
  def validate(%{frame: %{pin: _, size: _}, title: t, body: body} = data)
      when is_binary(t) and is_list(body) do
    {:ok, data}
  end

  def validate(data) do
    {:error,
     "PopupModal requires :frame, :title and :body (list of lines), got: #{inspect(data)}"}
  end

  @impl Scenic.Scene
  def init(scene, data, opts) do
    {btn_id, btn_label} = Map.get(data, :button, {:ok, "OK"})

    state = %{
      id: opts[:id],
      frame: data.frame,
      title: data.title,
      body: data.body,
      body_font: Map.get(data, :body_font),
      btn_id: btn_id,
      btn_label: btn_label,
      accent: Map.get(data, :accent) || @default_accent
    }

    graph = render(state)

    scene =
      scene
      |> assign(state: state, graph: graph)
      |> push_graph(graph)

    # Modal: consume the keyboard while open (Enter/Escape dismiss).
    request_input(scene, [:key])
    capture_input(scene, [:key, :codepoint])

    {:ok, scene}
  end

  @impl Scenic.Scene
  def handle_input({:key, {key, 1, _mods}}, _context, scene)
      when key in [:key_enter, :key_esc] do
    respond(scene)
  end

  def handle_input({:cursor_button, {:btn_left, 1, _, _coords}}, :popup_modal_button, scene) do
    respond(scene)
  end

  def handle_input(_input, _context, scene), do: {:noreply, scene}

  defp respond(scene) do
    %{id: id, btn_id: btn_id} = scene.assigns.state
    send_parent_event(scene, {:popup_modal_response, id, btn_id})
    {:noreply, scene}
  end

  # ==========================================================================

  @doc """
  Where the panel lands and how big it is: `%{x:, y:, width:, height:,
  columns:, per_column:}`.

  Public because the layout is the interesting part — a body longer than the
  window is exactly the case worth asserting on from outside, and recomputing
  it in a test would assert the test's arithmetic rather than the widget's.
  """
  def panel_bounds(state) do
    %{size: %{height: fh}} = state.frame

    # A body longer than the window has to go somewhere. Columns rather than a
    # taller panel: a reference nobody can read the bottom of is no reference,
    # and a keyboard-shortcut list is exactly the body that grows.
    per_column = lines_per_column(fh)
    columns = max(ceil(length(state.body) / per_column), 1)
    rows = min(length(state.body), per_column)

    panel_h = @pad * 2 + @title_height + rows * @line_height + @button_h + 16
    panel_w = @panel_width * columns

    state.frame
    |> ScenicWidgets.ModalShell.bounds({panel_w, panel_h})
    |> Map.merge(%{width: panel_w, height: panel_h, columns: columns, per_column: per_column})
  end

  defp render(state) do
    %{width: panel_w, height: panel_h, per_column: per_column} = bounds = panel_bounds(state)

    Graph.build()
    |> ScenicWidgets.ModalShell.overlay(state.frame, :popup_overlay, fill: @overlay)
    |> group(
      fn g ->
        g
        |> rrect({panel_w, panel_h, 8}, fill: @panel_bg, stroke: {1, @panel_border})
        |> text(state.title,
          translate: {panel_w / 2, @pad + 26},
          text_align: :center,
          font_size: 30,
          fill: state.accent
        )
        |> render_body_lines(state.body, per_column, state.body_font)
        |> render_button(state, panel_w, panel_h)
      end,
      translate: {bounds.x, bounds.y},
      id: :popup_panel
    )
  end

  defp lines_per_column(frame_height) do
    chrome = @pad * 2 + @title_height + @button_h + 16 + @pad
    max(trunc((frame_height * 0.9 - chrome) / @line_height), 4)
  end

  # One column keeps the original centred look, which is what every short body
  # (the About dialog) wants. More than one and centring stops meaning
  # anything, so each column is laid out from its own left edge.
  defp render_body_lines(g, lines, per_column, font) do
    single_column? = length(lines) <= per_column

    lines
    |> Enum.with_index()
    |> Enum.reduce(g, fn
      {"", _i}, acc ->
        acc

      {line, i}, acc ->
        column = div(i, per_column)
        row = rem(i, per_column)
        y = @pad + @title_height + 8 + row * @line_height

        opts = [font_size: 15, fill: @text_color] ++ font_opt(font)

        if single_column? do
          text(acc, line, [translate: {@panel_width / 2, y}, text_align: :center] ++ opts)
        else
          text(acc, line, [translate: {column * @panel_width + @pad * 2, y}] ++ opts)
        end
    end)
  end

  # A body whose columns are aligned with padding needs a monospaced face to
  # line up at all. Optional, so a prose body keeps the default.
  defp font_opt(nil), do: []
  defp font_opt(font), do: [font: font]

  defp render_button(g, state, panel_w, panel_h) do
    bx = (panel_w - @button_w) / 2
    by = panel_h - @pad - @button_h

    g
    |> group(
      fn gg ->
        gg
        |> rrect({@button_w, @button_h, 6},
          fill: {55, 60, 75},
          stroke: {1, state.accent},
          input: [:cursor_button],
          id: :popup_modal_button
        )
        |> text(state.btn_label,
          translate: {@button_w / 2, @button_h / 2 + 5},
          text_align: :center,
          font_size: 15,
          fill: @text_color
        )
      end,
      translate: {bx, by}
    )
  end
end
