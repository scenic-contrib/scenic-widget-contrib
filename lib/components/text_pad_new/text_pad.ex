defmodule ScenicWidgets.TextPad do
  use Scenic.Component
  require Logger

  def validate(data) do
    Logger.debug("#{__MODULE__} accepted params: #{inspect(data)}")
    {:ok, data}
  end

  def init(scene, args, opts) do
    Logger.debug("#{__MODULE__} initializing...")

    init_graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.group(fn graph ->
        graph
        |> Scenic.Primitives.rect({100, 100},
          id: :background,
          fill: :red,
          stroke: {2, :purple}
        )
      end)

    init_scene =
      scene
      |> assign(graph: init_graph)
      |> push_graph(init_graph)

    {:ok, init_scene}
  end
end
