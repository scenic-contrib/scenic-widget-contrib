defmodule ScenicWidgets.TestPattern do
  use Scenic.Component
  require Logger

  def validate(data) do
    Logger.debug("#{__MODULE__} accepted params: #{inspect(data)}")
    {:ok, data}
  end

  def init(scene, _args, _opts) do
    Logger.debug("#{__MODULE__} initializing...")

    rect_size = {80, 80}

    init_graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.group(
        fn graph ->
          graph
          # 1st column
          |> Scenic.Primitives.rect(rect_size, fill: :white, translate: {100, 100})
          |> Scenic.Primitives.rect(rect_size, fill: :green, translate: {100, 180})
          |> Scenic.Primitives.rect(rect_size, fill: :red, translate: {100, 260})
          # 2nd column
          |> Scenic.Primitives.rect(rect_size, fill: :blue, translate: {180, 100})
          |> Scenic.Primitives.rect(rect_size, fill: :black, translate: {180, 180})
          |> Scenic.Primitives.rect(rect_size, fill: :yellow, translate: {180, 260})
          # 3rd column
          |> Scenic.Primitives.rect(rect_size, fill: :pink, translate: {260, 100})
          |> Scenic.Primitives.rect(rect_size, fill: :purple, translate: {260, 180})
          |> Scenic.Primitives.rect(rect_size, fill: :brown, translate: {260, 260})
        end,
        id: :test_pattern
      )

    init_scene =
      scene
      |> assign(graph: init_graph)
      |> push_graph(init_graph)

    {:ok, init_scene}
  end
end
