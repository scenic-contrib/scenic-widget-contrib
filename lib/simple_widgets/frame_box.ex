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

   @fill_colors [:red, :blue, :green, :yellow]

   def validate(%{frame: %Frame{} = _f, color: color} = data) when is_atom(color) do
      {:ok, data}
   end

   def validate(%{frame: %Frame{} = _f} = data) do
      validate(data |> Map.merge(%{color: Enum.random(@fill_colors)}))
   end

   def init(scene, args, _opts) do
      Logger.debug("#{__MODULE__} initializing...")

      init_graph =
         Scenic.Graph.build()
         |> draw(args)

      init_scene =
         scene
         |> assign(graph: init_graph)
         |> assign(frame: args.frame)
         |> push_graph(init_graph)

      {:ok, init_scene}
   end

   @doc """
   This function is static, can be added to any normal graph
   """
   def draw(graph, %Frame{} = frame) do
      draw(graph, frame, %{fill: Enum.random(@fill_colors)})
   end

   def draw(graph, %Frame{} = frame, %{color: color}) do
      IO.puts "DEPRECATE - use FILL not COLOR"
      draw(graph, frame, %{fill: color})
   end

   def draw(graph, %Frame{} = frame, %{fill: color}) do
      # border_stroke = 10
      graph
      |> Scenic.Primitives.group(
         fn graph ->
            graph
            |> Scenic.Primitives.rect(frame.size,
               fill: color,
               translate: frame.pin
            )
            # |> Scenic.Primitives.rect(frame.size,
            #    # stroke: {border_stroke, color},
            #    translate: frame.pin
            # )
         end
      )
   end

   def draw(graph, %Frame{} = frame, %{border: color}) do
      border_stroke = 2
      graph
      |> Scenic.Primitives.group(
         fn graph ->
            graph
            |> Scenic.Primitives.rect(frame.size,
               stroke: {border_stroke, color},
               translate: frame.pin
            )
         end
      )
   end

   def draw(graph, %{frame: %Frame{} = frame, color: color}) do
      IO.puts "DEPRECTE THIS BAD DRAW FUNC"
      draw(graph, frame, %{color: color})
   end
end
