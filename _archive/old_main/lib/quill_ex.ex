defmodule QuillEx do
  # @doc """
  # Publish an action to the internal event-bus.
  # """
  # def action({reducer, action}) when is_atom(reducer) do
  #   # https://www.etatvasoft.com/insights/react-design-patterns-and-structures-of-redux-and-flux/
  #   # `Flux Architecture`: A design pattern that implements a single mediator
  #   # (either a reducer or store, depending on implementation) for all actions,
  #   # through which the app state is processed and returned to the view.

  #   # 1) ACTION: Here
  #   # 2) DISPATCHER: We use EventBus. "Receives actions and broadcasts payloads to registered callbacks"
  #   # 3) STORE: This is the likes of BufferManager, in combination with RadixState. "Containers for application state & logic that have callbacks registered to the dispatcher." - BufferManager gets triggered by what it sees on EventBus, but all it can do is update the global `RadixState` - this will automatically get broadcast out (also on EventBus)
  #   # 4) VIEW: This is where it is imporant to write components which are pure functions rendered from state
  #   # 5) ACTION2: UI interaction achieves interaction by calling further actions in turn (often via the API, developing which not only gives us a nice dev experience, it improves the quality of the GUI code)
  #   EventBus.notify(%EventBus.Model.Event{
  #     id: UUID.uuid4(),
  #     topic: :general,
  #     data: {reducer, {:action, action}}
  #   })
  # end
end
