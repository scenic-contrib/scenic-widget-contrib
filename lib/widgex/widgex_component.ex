defmodule Widgex.Component do
  defmacro __using__(_opts) do
    quote do
      use Scenic.Component
      require Logger
      alias Widgex.Structs.{Coordinates, Dimensions, Frame}

      # all Scenic components must implement this function,
      # but for us it's always the same
      @impl Scenic.Component
      def validate({state, %Frame{} = frame}) when is_struct(state) do
        {:ok, {state, frame}}
      end

      # all Scenic components must implement this function,
      # but for us it's always the same
      @impl Scenic.Component
      def init(scene, {state, %Frame{} = frame}, opts) when is_struct(state) do
        init_graph = render_group(state, frame, opts)
        new_scene = scene |> assign(graph: init_graph) |> push_graph(init_graph)

        {:ok, new_scene}
      end

      defp render_group(state, %Frame{} = frame, opts) do
        Scenic.Graph.build(font: :ibm_plex_mono)
        |> Scenic.Primitives.group(
          fn graph ->
            # this function has to be implemented by the Widgex.Component being made
            graph |> render(state, frame)
          end,
          # trim outside the frame & move the frame to it's location
          scissor: Dimensions.box(frame.size),
          translate: Coordinates.point(frame.pin)
        )
      end

      @doc """
      A simple helper function which fills the frame with a color.
      """
      @opacity 0.5
      def fill_frame(
            %Scenic.Graph{} = graph,
            %Frame{size: f_size},
            color: c
          ) do
        graph
        |> Scenic.Primitives.rect(Dimensions.box(f_size),
          fill: c,
          opacity: @opacity
        )
      end
    end
  end
end
