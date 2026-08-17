# defmodule ScenicWidgets.Widgex.FunBox do
#   use Widgex.Component

#   defstruct menu_map: nil,
#             color: :green

#   def render(%Scenic.Graph{} = graph, %__MODULE__{} = state, %Frame{} = f) do
#     graph |> fill_frame(f, color: state.color)
#   end

#   def radix_diff(%__MODULE__{} = old_state, _radix_state) do
#     {false, old_state}
#   end
# end
