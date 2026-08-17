defmodule ScenicWidgets.GraphTools.Upsertable do
  @moduledoc """
  Makes it easy to upsert a custom component

  Add `use ScenicWidgets.GraphTools.Upsertable` to your custom component to get
  `upsert/3` added as a callback to the component. Use `upsert/3` the same way
  you would `add_to_graph/3` but it also works if the component is already added
  to the graph (i.e. when you actually have a instance of the component from
  `Scenic.Graph.modify/3`).

  Switch from:

      Dash.CalendarComponent.add_to_graph(
        graph,
        %{
          today: Date.utc_today(),
        },
        t: {616, 350}
      )

  to:

      ScenicWidgets.GraphTools.upsert(graph, :calendar, fn g ->
        Dash.CalendarComponent.upsert(
          g,
          %{
            today: Date.utc_today(),
          },
          id: :calendar,
          t: {616, 350}
        )
      end)

  Note: The params you pass in need to be different for an upsert to have any
  effect. If the params are the same as the previous render then there will be
  no change in the graph.
  """

  @type graph_or_primitive :: Scenic.Graph.t() | Scenic.Primitive.t()

  defmacro __using__(_opts) do
    quote do
      def upsert(graph_or_primitive, data, opts) do
        case graph_or_primitive do
          %Scenic.Graph{} = graph -> add_to_graph(graph, data, opts)
          %Scenic.Primitive{} = primitive -> modify(primitive, data, opts)
        end
      end

      # Copied from Scenic:
      # https://github.com/boydm/scenic/blob/94679b1ab50834e20b94ca11bc0c5645bf0c909e/lib/scenic/components.ex#L696
      defp modify(
             %Scenic.Primitive{module: Scenic.Primitive.Component, data: {mod, _, id}} = p,
             data,
             options
           ) do
        data =
          case mod.validate(data) do
            {:ok, data} -> data
            {:error, msg} -> raise msg
          end

        Scenic.Primitive.put(p, {mod, data, id}, options)
      end

      # Copied from Scenic:
      # https://github.com/boydm/scenic/blob/9314020b2962e38bea871e8e1f59cd273dfe0af0/lib/scenic/primitives.ex#L1467
      # TODO: Check that `mod` matches this module
      defp modify(%Scenic.Primitive{module: mod} = p, data, opts) do
        data =
          case mod.validate(data) do
            {:ok, data} -> data
            {:error, error} -> raise Exception.message(error)
          end

        Scenic.Primitive.put(p, data, opts)
      end
    end
  end

  @doc """
  Either insert or update a component into a `Scenic.Graph`

  Meant to be used both when creating the initial graph and with
  `Scenic.Graph.modify/3`. When creating the initial graph the graph should be
  passed and the component will be inserted, otherwise the graph will TODO FIXME
  """
  @callback upsert(graph_or_primitive(), data :: any(), opts :: keyword()) :: graph_or_primitive()
end
