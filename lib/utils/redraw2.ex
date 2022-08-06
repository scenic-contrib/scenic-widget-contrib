defmodule ScenicWidgets.Redraw2 do
  @moduledoc """
  Version of `ScenicWidgets.Redraw` that makes it easier to update a component in place

  But the drawback is that the code becomes less legible

  Example:

      graph
      |> ScenicWidgets.Redraw2.draw(:some_text, fn _g ->
        text = "This the some text to display"
        {Primitive.Text, text, t: {90, 150}, font_size: 10, text_align: :left}
      end)
  """
  alias Scenic.Graph
  alias Scenic.Primitive

  def rectangle(%Graph{} = g, data, opts) do
    add_to_graph(g, Primitive.Rectangle, data, opts)
  end

  def rectangle(%Primitive{module: Primitive.Rectangle} = p, data, opts) do
    modify(p, data, opts)
  end

  def draw(graph, id, fun) do
    case Graph.get(graph, id) do
      [] ->
        {mod, params, opts} = fun.(graph)
        opts = Keyword.put_new(opts, :id, id)
        add_to_graph(graph, mod, params, opts)

      # Work around not being able to modify a group primitive
      # Bug: https://github.com/boydm/scenic/issues/27
      [%{module: Scenic.Primitive.Group}] ->
        graph = Graph.delete(graph, id)
        {mod, params, opts} = fun.(graph)
        add_to_graph(graph, mod, params, opts)

      [_primitive] ->
        Graph.modify(graph, id, fn primitive ->
          {_mod, params, opts} = fun.(primitive)
          modify(primitive, params, opts)
        end)
    end
  end

  # Copied from Scenic:
  # https://github.com/boydm/scenic/blob/94679b1ab50834e20b94ca11bc0c5645bf0c909e/lib/scenic/components.ex#L696
  defp modify(%Primitive{module: Primitive.Component, data: {mod, _, id}} = p, data, options) do
    data =
      case mod.validate(data) do
        {:ok, data} -> data
        {:error, msg} -> raise msg
      end

    Primitive.put(p, {mod, data, id}, options)
  end

  # Copied from Scenic:
  # https://github.com/boydm/scenic/blob/9314020b2962e38bea871e8e1f59cd273dfe0af0/lib/scenic/primitives.ex#L1467
  defp modify(%Primitive{module: mod} = p, data, opts) do
    data =
      case mod.validate(data) do
        {:ok, data} -> data
        {:error, error} -> raise Exception.message(error)
      end

    Primitive.put(p, data, opts)
  end

  defp add_to_graph(%Graph{} = g, mod, data, opts) do
    data =
      case mod.validate(data) do
        {:ok, data} -> data
        {:error, error} -> raise Exception.message(error)
      end

    mod.add_to_graph(g, data, opts)
  end
end
