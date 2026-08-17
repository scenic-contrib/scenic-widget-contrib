# defmodule Flamelex.GUI.Component.Inputmodal.Render do
#   @moduledoc """
#   Functions to render the %Scenic.Graph{} for Inputmodal component.
#   """

#   alias Flamelex.GUI.Component.Inputmodal.State
#   alias Flamelex.Fluxus.RadixState
#   alias Flamelex.GUI.Utils.Draw

#   def go(%Widgex.Frame{} = f, %State{} = _state) do
#     Scenic.Graph.build()
#     |> Scenic.Primitives.group(
#       fn graph ->
#         graph
#         |> Draw.background(f, :medium_slate_blue)
#         |> Widgex.Frame.draw_guidewires(f)
#         |> Scenic.Primitives.text("Flamelex.GUI.Component.Inputmodal",
#           font_size: 24,
#           translate: {f.size.width / 2, f.size.height / 2}
#         )
#       end,
#       translate: f.pin.point
#     )
#   end
# end
