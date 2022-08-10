defmodule ScenicWidgets.GraphState do
  @moduledoc """
  Facilitates the usage of a `%State{}` struct with a scene

  Note: the `%State{}` struct should have at least a `:graph` attribute.

  Example basic state module:

      defmodule State do
        @moduledoc false
        defstruct [:graph]
      end
  """

  @doc """
  Updates and pushes the graph
  """
  @spec update_graph(Scenic.Scene.t(), fun()) :: Scenic.Scene.t()
  def update_graph(%Scenic.Scene{} = scene, fun) when is_function(fun, 1) do
    graph = fun.(scene.assigns.state.graph)
    assign_and_push_graph(scene, scene.assigns.state, graph)
  end

  @spec update_state(Scenic.Scene.t(), fun()) :: Scenic.Scene.t()
  def update_state(%Scenic.Scene{} = scene, fun) when is_function(fun, 1) do
    state = fun.(scene.assigns.state)
    Scenic.Scene.assign(scene, :state, state)
  end

  def assign_and_push_graph(%Scenic.Scene{} = scene, state, graph) do
    state = %{state | graph: graph}

    scene
    |> Scenic.Scene.assign(:state, state)
    |> Scenic.Scene.push_graph(graph)
  end
end
