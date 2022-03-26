defmodule QuillEx.Components.NotePad.TextBoxScrollable do
  use Scenic.Component
  require Logger

  # TODO just check it's a known component state
  def validate(%{text: _t, frame: _f} = data) do
    Logger.debug("#{__MODULE__} accepted params: #{inspect(data)}")
    {:ok, data}
  end

  def validate(_data) do
    {:error, "invalid input"}
  end

  def init(scene, state, opts) do
    Logger.debug("#{__MODULE__} initializing...")

    # TODO Process registration

    # this is also how much we translate the text, it's the buffer
    state = state |> Map.merge(%{scroll: {20, 30}})

    new_graph = render(state, first_render?: true)

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(state: state)
      |> push_graph(new_graph)

    # QuillEx.Utils.PubSub.register()
    request_input(new_scene, [:cursor_scroll])

    {:ok, new_scene}
  end

  def render(state, first_render?: true) do
    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect(state.frame.size,
          scissor: state.frame.size,
          fill: :antique_white,
          stroke: {1, :ghost_white}
        )
        |> Scenic.Primitives.text(state.text,
          font: :ibm_plex_mono,
          fill: :black,
          translate: {20, 30},
          id: :textblock
        )
      end,
      translate: state.frame.pin
    )
  end

  def handle_input(
        {:cursor_scroll, {{_x_scroll, _y_scroll} = delta_scroll, coords}},
        _context,
        scene
      ) do
    Logger.debug("Handling right scrolling - ")

    new_cumulative_scroll = Scenic.Math.Vector2.add(scene.assigns.state.scroll, delta_scroll)

    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.modify(
        :textblock,
        &Scenic.Primitives.update_opts(&1, translate: new_cumulative_scroll)
      )

    new_state =
      scene.assigns.state
      |> Map.merge(%{scroll: new_cumulative_scroll})

    # new_graph = render(state, first_render?: true)
    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(state: new_state)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_input(input, context, scene) do
    Logger.debug("#{__MODULE__} ignoring some input: #{inspect(input)}")
    {:noreply, scene}
  end
end
