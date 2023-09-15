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
      def init(scene, {state, %Frame{} = frame}, _opts) when is_struct(state) do
        init_graph = render(state, frame)
        new_scene = scene |> assign(graph: init_graph) |> push_graph(init_graph)

        {:ok, new_scene}
      end
    end
  end
end
