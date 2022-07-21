defmodule QuillEx.Components.NotePad.TextBoxMachv3 do
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

    new_graph = render(state, first_render?: true)

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(state: state)
      |> push_graph(new_graph)

    # QuillEx.Utils.PubSub.register()
    request_input(new_scene, [:cursor_button])

    {:ok, new_scene}
  end

  def render(state, first_render?: true) do
    {width, height} = state.frame.size

    font_size = 20
    text_left_margin = 20
    {:ok, metrics} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")
    text_width = FontMetrics.width(state.text, font_size, metrics)

    wrapped_text = FontMetrics.wrap(state.text, width - text_left_margin * 2, font_size, metrics)

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect(state.frame.size,
          scissor: state.frame.size,
          fill: :antique_white,
          stroke: {1, :ghost_white}
        )
        |> Scenic.Primitives.text(wrapped_text,
          font: :ibm_plex_mono,
          font_size: font_size,
          fill: :black,
          translate: {text_left_margin, 40}
        )
      end,
      translate: state.frame.pin
    )
  end
end
