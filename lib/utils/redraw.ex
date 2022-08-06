defmodule ScenicWidgets.Redraw do
  @moduledoc """
  Simple module to assist in redrawing a simple scenic component

  Drawback is that the id needs to be specified twice. Compare with `ScenicWidgets.Redraw2`

  Example:

      graph
      |> ScenicWidgets.Redraw.draw(:my_text, fn _g ->
        text = "This the some text to display"
        {Primitive.Text, text, id: :my_text, t: {90, 150}, font_size: 10, text_align: :left}
      end)
  """
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
        Graph.modify(graph, id, fn graph_or_primitive ->
          fun.(graph_or_primitive)
        end)
    end
  end
end
