defmodule ScenicWidgets.GraphTools do
  @moduledoc """
  Simple module to assist in drawing simple scenic components

  Think of it like an upsert on the graph
  """
  alias Scenic.Graph

  @doc """
  Insert or update a component/primitive in the graph

  Example:

      graph
      |> ScenicWidgets.GraphTools.upsert(:my_text, fn _g ->
        text = "This the some text to display"
        Scenic.Primitives.text(text, id: :my_text, t: {90, 150}, font_size: 10, text_align: :left)
      end)

  Note: the passed in function should be idempotent and side-effect free because it may be
  called multiple times

  Note: If the passed in function renders multiple primitives then it should
  ensure that the root primitive's id matches the passed in id so that the
  primitives can be updated

  To use this with a custom component you probably want to also use
  `ScenicWidgets.GraphTools.Upsertable`.
  """
  def upsert(graph, id, fun) when is_function(fun, 1) do
    case Graph.get(graph, id) do
      [] ->
        fun.(Graph.build())
        |> ensure_id_matches(graph, id, fun)

      # Work around not being able to modify a group primitive
      # Bug: https://github.com/boydm/scenic/issues/27
      [%{module: Scenic.Primitive.Group}] ->
        graph = Graph.delete(graph, id)
        fun.(graph)

      [_primitive] ->
        Graph.modify(graph, id, fn graph_or_primitive ->
          fun.(graph_or_primitive)
        end)
    end
  end

  defp ensure_id_matches(built_graph, actual_graph, id, fun) do
    case Graph.find(built_graph, fn p -> p != :_root_ end) do
      [primitive] ->
        # NOTE: There's a dialyzer issue here because of https://github.com/boydm/scenic/pull/279
        primitive = Scenic.Primitive.merge_opts(primitive, id: id)
        Graph.add(actual_graph, primitive)

      primitives ->
        if Enum.find(primitives, fn p -> p.id end) == nil do
          raise "If specifying multiple primitives, one of the primitive's id " <>
                  "needs to match the passed in id (passed in #{inspect(id)})"
        end

        fun.(actual_graph)
    end
  end
end
