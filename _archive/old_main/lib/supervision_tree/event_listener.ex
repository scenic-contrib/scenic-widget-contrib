# defmodule QuillEx.EventListener do
#   use GenServer
#   require Logger

#   def start_link(_args) do
#     GenServer.start_link(__MODULE__, %{})
#   end

#   def init(_args) do
#     # Logger.debug("#{__MODULE__} initializing...")
#     Process.register(self(), __MODULE__)
#     EventBus.subscribe({__MODULE__, ["quill_ex"]})
#     {:ok, %{}}
#   end

#   def process({:quill_ex = _topic, _id} = event_shadow) do
#     event = EventBus.fetch_event(event_shadow)
#     radix_state = QuillEx.Fluxus.RadixStore.get()

#     case do_process(radix_state, event.data) do
#       x when x in [:ok, :ignore] ->
#         EventBus.mark_as_completed({__MODULE__, event_shadow})

#       {:ok, ^radix_state} ->
#         # Logger.debug "ignoring action, no change to radix_state..."
#         EventBus.mark_as_completed({__MODULE__, event_shadow})

#       {:ok, new_radix_state} ->
#         QuillEx.Fluxus.RadixStore.put(new_radix_state)
#         EventBus.mark_as_completed({__MODULE__, event_shadow})

#       {:error, reason} ->
#         Logger.error(reason)
#         :ignore
#     end
#   end

#   ## --------------------------------------------------------

#   def do_process(radix_state, {reducer, {:action, action}}) when is_atom(reducer) do
#     try do
#       reducer.process(radix_state, action)
#     rescue
#       FunctionClauseError ->
#         {:error,
#          "#{__MODULE__} -- reducer `#{inspect(reducer)}` could not match action: #{inspect(action)}"}
#     end
#   end

#   def do_process(radix_state, action) do
#     # details = %{radix_state: radix_state, action: action}
#     # Logger.debug "#{__MODULE__} ignoring action... #{inspect(details)}"
#     :ignore
#   end
# end
