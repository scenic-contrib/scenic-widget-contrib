defmodule Widgex.NeoComponent do
  # This is an optional callback.
  # """
  # @callback custom_init_logic(map()) :: map()

  # @doc """
  # This function (which implemented) takes in a map of args and returns
  # the rego tag for this component. This is useful when trying to find
  # a component's pid.
  # """
  # @callback rego_tag(any()) :: any()

  defmacro __using__(macro_opts) do
    quote location: :keep, bind_quoted: [macro_opts: macro_opts] do
      use Scenic.Component
      use ScenicWidgets.ScenicEventsDefinitions
      require Logger
      alias Widgex.Structs.{Coordinates, Dimensions, Frame}

      # @impl Scenic.Component
      # def validate(%{frame: %Frame{}, state: _s} = data) do
      #   {:ok, data}
      # end

      @impl Scenic.Component
      def init(scene, state, _opts) do
        # TODO stuff like theme, frame etc all needs to be apart of the "higher level" struct for a component, abstracted away from the component state... probably Scenic can does this or at least should do it!
        # init_theme = ScenicWidgets.Utils.Theme.get_theme(opts)

        # TODO probably need to register the component somehow here...

        # If the component is properly registered we cuold check if it has already been rendered/spun-up and if it has, instead of rendering/spinning-up again, we could just push an update to it, sort of like a render_or_update function

        # init_opts = Keyword.merge(opts, unquote(macro_opts))
        init_graph = render(state)

        init_scene =
          scene
          |> assign(graph: init_graph)
          |> assign(state: state)
          # |> assign(frame: args.frame)
          # # TODO bring opts into state eventually...
          # |> assign(opts: init_opts)
          |> push_graph(init_graph)

        # if unquote(opts)[:handle_cursor_events?] do
        #   request_input(init_scene, [:cursor_pos, :cursor_button])
        # end

        # Quillex.Utils.PubSub.subscribe(topic: :radix_state_change)

        {:ok, init_scene}
      end

      # defp render_component(%{id: id, frame: frame, state: state}) do
      #   Scenic.Graph.build()
      #   |> Scenic.Primitives.group(
      #     fn graph ->
      #       graph
      #       # REMINDER: render/3 has to be implemented by the Widgex.Component implementing this behaviour
      #       |> render(frame, state)

      #       # |> render_scrollbars(state, frame, opts)
      #     end,
      #     # trim outside the frame & move the frame to it's location
      #     id: {:widgex_component, id},
      #     scissor: frame.size.box,
      #     translate: frame.pin.point
      #   )
      # end
    end
  end
end
