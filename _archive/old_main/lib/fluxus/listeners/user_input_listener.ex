defmodule QuillEx.Fluxus.UserInputListener do
  @moduledoc """
  This process listens to events on the user_input_topic,
  """
  use GenServer
  require Logger

  @topic :quill_ex_user_input

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_args) do
    Logger.debug("#{__MODULE__} initializing...")
    EventBus.subscribe({__MODULE__, [to_string(@topic)]})
    {:ok, %{}}
  end

  def process({@topic, _id} = event_shadow) do
    event = EventBus.fetch_event(event_shadow)

    if not user_input?(event) do
      :ignore
    else
      %{data: {:user_input, radix_state, input}} = event
      # handle_input(input, event_shadow)
      raise "... you have died."
    end
  end

  def handle_input(input, event_shadow) do
    # radix_state = QuillEx.Fluxus.RadixStore.get()

    # action =

    # case QuillEx.Fluxus.UserInputHandler.process(input) do
    #   :ignore ->
    #     EventBus.mark_as_completed({__MODULE__, event_shadow})
    # end

    # case QuillEx.Fluxus.UserInputHandler.process(radix_state, input) do
    #   :ignore ->
    #     # try_custom_input_handler(radix_state, input, event_shadow)

    #     # Logger.debug "#{__MODULE__} ignoring... #{inspect(%{radix_state: radix_state, action: action})}"
    #     EventBus.mark_as_completed({__MODULE__, event_shadow})

    #   {:ok, ^radix_state} ->
    #     # Logger.debug "#{__MODULE__} ignoring (no state-change)..."
    #     EventBus.mark_as_completed({__MODULE__, event_shadow})

    #   {:ok, new_radix_state} ->
    #     # Logger.debug "#{__MODULE__} processed event, state changed..."
    #     QuillEx.Fluxus.RadixStore.put(new_radix_state)
    #     EventBus.mark_as_completed({__MODULE__, event_shadow})
    # end

    # QuillEx.Fluxus.RadixStore
  end

  # TODO need to add to memex to get refills for my ADHD meds, maybe need to change my insurance?
  # TODO add new button to jump between test memex & my real memex, so I can dev dev dev but also have quick access to my real memex for taking notes)

  def try_custom_input_handler(radix_state, input, event_shadow) do
    # TODO add a try/catch here???

    # TODO add an atom here to say we came from Flamelex, not Memelex or QuillEx, to make pattern matching easier when writing custom key bindings
    # This is the down-side of moving everything out of radix state... if it was all there then we really could just use pattern-matching here

    # TODO look for this module/file & see if it exists before attempting this
    case Memelex.My.Modz.CustomInputHandler.process(radix_state, input) do
      :ignore ->
        Logger.debug("Memelex.My.Modz.CustomInputHandler ignoring... #{inspect(%{input: input})}")
        EventBus.mark_as_completed({__MODULE__, event_shadow})

      {:ok, ^radix_state} ->
        # Logger.debug "#{Memelex.My.Modz.CustomInputHandler} ignoring (no state-change)..."
        EventBus.mark_as_completed({__MODULE__, event_shadow})

      {:ok, new_radix_state} ->
        # Logger.debug "#{Memelex.My.Modz.CustomInputHandler} processed event, state changed..."
        # NOTE - we only need to `put` user input into the store, dont call `update` because we dont need to broadcast this out to all components...
        Flamelex.Fluxus.RadixStore.put(new_radix_state)
        EventBus.mark_as_completed({__MODULE__, event_shadow})
    end
  end

  defp user_input?(%EventBus.Model.Event{topic: @topic, data: {:user_input, _radix_state, _ii}}),
    do: true

  defp user_input?(_otherwise), do: false
end
