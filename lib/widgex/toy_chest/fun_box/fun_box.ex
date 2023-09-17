defmodule ScenicWidgets.Widgex.FunBox do
  use Widgex.Component

  defstruct menu_map: nil,
            color: :green

  def render(%Scenic.Graph{} = graph, %__MODULE__{} = state, %Frame{} = f) do
    graph |> fill_frame(f, color: state.color)
  end
end
