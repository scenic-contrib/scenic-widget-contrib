defmodule ScenicWidgets.Redraw do
  alias Scenic.Graph

  def draw(graph, id, fun) do
    case Graph.get(graph, id) do
      [] ->
        fun.(graph)

      # Work around not being able to modify a group primitive
      # Bug: https://github.com/boydm/scenic/issues/27
      [%{module: Scenic.Primitive.Group}] ->
        graph = Graph.delete(graph, id)
        fun.(graph)

      [_] ->
        Graph.modify(graph, id, fn graph ->
          fun.(graph)
        end)
    end
  end
end
