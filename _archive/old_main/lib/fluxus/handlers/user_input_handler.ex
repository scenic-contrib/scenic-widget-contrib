defmodule QuillEx.Fluxus.UserInputHandler do
  use ScenicWidgets.ScenicEventsDefinitions
  require Logger

  # def handle(radix_state, input) when input in [@left_shift, @right_shift] do
  def handle(%{lateral: false} = _radix_state, @left_shift) do
    # def handle(radix_state, {:key, {:key_leftshift, 1, []}}) do
    # def handle(radix_state, {:key, {:key_leftshift, 10, []}}) do
    IO.puts("GO LATERSL")
    {:action, {:minor_mode, :lateral}}
  end

  # def handle(%{lateral: true} = _radix_state, @left_shift_release) do
  # def handle(%{lateral: true} = _radix_state, {:key, {:key_leftshift, @key_released, []}}) do
  # def handle(%{lateral: true} = _radix_state, {:key, {:key_leftshift, 1, []}}) do
  def handle(%{lateral: true} = _radix_state, {:key, {:key_leftshift, 0, [:shift]}}) do
    IO.puts("WATER AS COLDX AS IC")
    # def handle(radix_state, {:key, {:key_leftshift, 1, []}}) do
    # def handle(radix_state, {:key, {:key_leftshift, 10, []}}) do
    {:action, {:minor_mode, nil}}
  end

  def handle(radix_state, input) do
    Logger.warn("UserInputHandler.handle, ignoring: #{inspect(input)}")
    :ignored
  end
end

# defmodule QuillEx.UserInputHandler do
#   use ScenicWidgets.ScenicEventsDefinitions
#   require Logger

#   # treat key repeats as a press
#   def process({:key, {key, @key_held, mods}}) do
#     process({:key, {key, @key_pressed, mods}})
#   end

#   # ignore key-release inputs
#   def process({:key, {_key, @key_released, _mods}}) do
#     :ignore
#   end

#   def process({:key, {k, @key_released, _mods}}) when k in [@left_shift, @right_shift] do
#     :ignore
#   end

#   # all input not handled above, can be handled as editor input
#   def process(key) do
#     try do
#       QuillEx.UserInputHandler.Editor.process(key)
#     rescue
#       FunctionClauseError ->
#         Logger.warn("Input: #{inspect(key)} not handled by #{__MODULE__}...")
#         :ignore
#     end
#   end
# end
