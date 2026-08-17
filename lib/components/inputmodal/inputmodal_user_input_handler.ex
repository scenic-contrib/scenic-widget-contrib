# defmodule Flamelex.GUI.Component.Inputmodal.UserInputHandler do
#   @moduledoc """
#   Handles user input for the Inputmodal component.
#   """

#   require Logger
#   use ScenicWidgets.ScenicEventsDefinitions
#   alias Flamelex.GUI.Component.Inputmodal
#   alias Flamelex.GUI.Component.Inputmodal.Reducer

#   def handle(rdx, input) do
#     case input do
#       # Match on specific inputs and return actions
#       _ ->
#         Logger.warn("#{__MODULE__} received unhandled input: #{inspect(input)}")
#         :ignore
#     end
#   end
# end
