defmodule ScenicWidgets.FrameBox do
  @moduledoc """
  FrameBox is a simple component, used during development to quickly
  see what exact space a %Frame{} occupies.
  """
  use Scenic.Component, has_children: false
  require Logger
  alias ScenicWidgets.Core.Structs.Frame

  @border_colors [
    :light_green,
    :red,
    :white,
    :black,
    :blue
  ]

  def validate(%{frame: %Frame{} = _f, color: color} = data) when is_atom(color) do
    {:ok, data}
  end

  def init(scene, args, _opts) do
    Logger.debug("#{__MODULE__} initializing...")

    init_graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.rect(args.frame.size, fill: args.color, translate: args.frame.pin)
      |> Scenic.Primitives.rect(args.frame.size,
        stroke: {10, Enum.random(@border_colors)},
        translate: args.frame.pin
      )

    init_scene =
      scene
      |> assign(graph: init_graph)
      |> assign(frame: args.frame)
      |> push_graph(init_graph)

    {:ok, init_scene}
  end
end
