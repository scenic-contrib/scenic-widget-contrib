defmodule Widgex.Component do
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use Scenic.Component
      use ScenicWidgets.ScenicEventsDefinitions
      require Logger
      alias Widgex.Structs.{Coordinates, Dimensions, Frame}

      # all Scenic components must implement this function,
      # but for us it's always the same
      @impl Scenic.Component
      def validate({state, %Frame{} = frame}) when is_struct(state) do
        {:ok, {state, frame}}
      end

      # all Scenic components must implement this function,
      # but for us it's always the same
      @impl Scenic.Component
      def init(scene, {state, %Frame{} = frame}, opts) when is_struct(state) do
        # TODO stuff like theme, frame etc all needs to be apart of the "higher level" struct for a component, abstracted away from the component state... probably Scenic can does this or at least should do it!
        # init_theme = ScenicWidgets.Utils.Theme.get_theme(opts)

        init_graph = render_group(state, frame, opts)

        init_scene =
          scene
          |> assign(graph: init_graph)
          |> assign(state: state)
          |> push_graph(init_graph)

        if unquote(opts)[:handle_cursor_events?] do
          request_input(init_scene, [:cursor_pos, :cursor_button])
        end

        {:ok, init_scene}
      end

      defp render_group(state, %Frame{} = frame, _opts) do
        Scenic.Graph.build(font: :ibm_plex_mono)
        |> Scenic.Primitives.group(
          fn graph ->
            # this function has to be implemented by the Widgex.Component being made
            graph |> render(state, frame)
          end,
          # trim outside the frame & move the frame to it's location
          scissor: Dimensions.box(frame.size),
          translate: Coordinates.point(frame.pin)
        )
      end

      @doc """
      A simple helper function which fills the frame with a color.
      """
      @opacity 0.5
      def fill_frame(
            %Scenic.Graph{} = graph,
            %Frame{size: f_size},
            color: c
          ) do
        graph
        |> Scenic.Primitives.rect(Dimensions.box(f_size),
          fill: c,
          opacity: @opacity
        )
      end

      # def handle_input({:cursor_pos, {_x, _y} = coords}, _context, scene) do
      #   IO.puts("HOVER COORDS: #{inspect(coords)}")
      #   # NOTE: `menu_bar_max_height` is the full height, including any
      #   #       currently rendered sub-menus. As new sub-menus of different
      #   #       lengths get rendered, this max-height will change.
      #   #
      #   #       menu_bar_max_height = @height + num_sub_menu*@sub_menu_height
      #   # {_x, _y, _viewport_width, menu_bar_max_height} = Scenic.Graph.bounds(scene.assigns.graph)

      #   # if y > menu_bar_max_height do
      #   #   GenServer.cast(self(), {:cancel, scene.assigns.state.mode})
      #   #   {:noreply, scene}
      #   # else
      #   #   # TODO here check if we veered of sideways in a sub-menu
      #   #   {:noreply, scene}
      #   # end

      #   {:noreply, scene}
      # end

      # def handle_input({:cursor_button, {:btn_left, 0, [], click_coords}}, _context, scene) do
      #   bounds = Scenic.Graph.bounds(scene.assigns.graph)

      #   if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
      #     cast_parent(scene, {:click, scene.assigns.state.unique_id})
      #   end

      #   {:noreply, scene}
      # end
    end
  end
end
