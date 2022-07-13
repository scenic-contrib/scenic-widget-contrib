defmodule ScenicWidgets.GraphState do
  def update_graph(scene, fun) when is_function(fun, 1) do
    graph = fun.(scene.assigns.state.graph)
    assign_and_push_graph(scene, scene.assigns.state, graph)
  end

  def assign_and_push_graph(scene, state, graph) do
    state = %{state | graph: graph}

    scene
    |> Scenic.Scene.assign(:state, state)
    |> Scenic.Scene.push_graph(graph)
  end
end
