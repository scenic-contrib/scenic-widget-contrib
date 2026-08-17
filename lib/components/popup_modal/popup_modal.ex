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

  defp render(state) do
    %{size: %{width: fw, height: fh}} = state.frame

    panel_h = @pad * 2 + @title_height + length(state.body) * @line_height + @button_h + 16
    panel_w = @panel_width
    bounds = ScenicWidgets.ModalShell.bounds(state.frame, {panel_w, panel_h})

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
        |> render_body_lines(state.body)
        |> render_button(state, panel_w, panel_h)
      end,
      translate: {bounds.x, bounds.y},
      id: :popup_panel
    )
  end

  defp render_body_lines(g, lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce(g, fn
      {"", _i}, acc ->
        acc

      {line, i}, acc ->
        text(acc, line,
          translate: {@panel_width / 2, @pad + @title_height + 8 + i * @line_height},
          text_align: :center,
          font_size: 15,
          fill: @text_color
        )
    end)
  end

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
