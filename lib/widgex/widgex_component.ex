defmodule Widgex.Component do
  # %__MODULE__{
  #   widgex: %Widgex.Component.Widget{
  #     id: :plaintext,
  #     # frame: %Frame{},
  #     theme: QuillEx.GUI.Themes.midnight_shadow()
  #     # layout: %Widgex.Layout{},

  #   },
  #   text: text,
  #   scroll: {0, 0}
  #   # file_bar: %{
  #   #   show?: true,
  #   #   filename: nil
  #   # }
  # }

  # defmodule Widget do
  #   defstruct id: nil,
  #             frame: nil,
  #             theme: nil

  #   # layout: nil
  # end

  # defstruct viewport: nil,
  # pid: nil,
  # module: nil,
  # theme: nil,
  # id: nil,
  # parent: nil,
  # children: nil,
  # child_supervisor: nil,
  # assigns: %{},
  # supervisor: nil,
  # stop_pid: nil

  # defstruct id: nil,
  #           state: nil
  #           frame: nil,
  #           theme: nil,
  #           layout: nil

  # TODO make a behaviour, widgex components must implement:
  # draw/1 - returns a new component state from incoming params
  # render/3 - renders the component state into a scenic graph

  defmacro __using__(macro_opts) do
    quote location: :keep, bind_quoted: [macro_opts: macro_opts] do
      # quote bind_quoted: [macro_opts: macro_opts] do
      use Scenic.Component
      use ScenicWidgets.ScenicEventsDefinitions
      require Logger
      # alias Widgex.Structs.{Coordinates, Dimensions}
      alias Widgex.Frame

      # maybe we shouldn't do this lol but it's the default left margin for text
      @left_margin 5

      # all Scenic components must implement this function, but for us it's always the same
      @impl Scenic.Component
      # TODO maybe there's some cool macros trick I can do to pattern matchy on a specific module struct here...
      # def validate({%Widget{} = _w, state, %Frame{} = frame, %Theme{} = _t}) when is_struct(state) do
      def validate({state, %Frame{} = frame}) when is_struct(state) do
        {:ok, {state, frame}}
      end

      def validate(%{frame: %Frame{}, state: _state} = data) do
        {:ok, data}
      end

      # all Scenic components must implement this function,
      # but for us it's always the same
      @impl Scenic.Component
      def init(scene, {state, %Frame{} = frame}, opts) when is_struct(state) do
        # TODO stuff like theme, frame etc all needs to be apart of the "higher level" struct for a component, abstracted away from the component state... probably Scenic can does this or at least should do it!
        # init_theme = ScenicWidgets.Utils.Theme.get_theme(opts)

        # TODO probably need to register the component somehow here...

        # If the component is properly registered we cuold check if it has already been rendered/spun-up and if it has, instead of rendering/spinning-up again, we could just push an update to it, sort of like a render_or_update function

        init_opts = Keyword.merge(opts, unquote(macro_opts))
        init_graph = render_group(state, frame, init_opts)

        init_scene =
          scene
          |> assign(graph: init_graph)
          |> assign(state: state)
          |> assign(frame: frame)
          # TODO bring opts into state eventually...
          |> assign(opts: init_opts)
          |> push_graph(init_graph)

        # if unquote(opts)[:handle_cursor_events?] do
        #   request_input(init_scene, [:cursor_pos, :cursor_button])
        # end

        # Quillex.Utils.PubSub.subscribe(topic: :radix_state_change)

        {:ok, init_scene}
      end

      # def handle_info(
      #       {:radix_state_change, new_radix_state},
      #       scene
      #     ) do
      #   # Note that we can't just directly compare old and new states because it may be more complicated, e.g. root scene only wants to change if the number of components changes, not the details of one component, even though these small changes cause a direct comparison to fail
      #   {scene_changed?, new_state} = radix_diff(scene.assigns.state, new_radix_state)

      #   if not scene_changed? do
      #     # any child components will get updates by being themselves subscribed to radix state changes...
      #     {:noreply, scene}
      #   else
      #     new_graph = render_group(new_state, scene.assigns.frame, scene.assigns.opts)

      #     # TODO this is an idea about looping through components in radix state & updating them using Graph.modify
      #     # it would be good here to just use Graph.modify, especially for scrolol events

      #     # new_graph =
      #     #   scene.assigns.graph
      #     #   |> Scenic.Graph.map({:widgex_component, __MODULE__}, fn component ->
      #     #     IO.puts("HIHIHIHI")
      #     #     # graph
      #     #     render_group(new_state, scene.assigns.frame, scene.assigns.opts)
      #     #   end)

      #     new_scene =
      #       scene
      #       |> assign(state: new_state)
      #       |> assign(graph: new_graph)
      #       |> push_graph(new_graph)

      #     {:noreply, new_scene}
      #   end
      # end

      defp render_group(state, %Frame{} = frame, opts) do
        Scenic.Graph.build(font: :ibm_plex_mono)
        |> Scenic.Primitives.group(
          fn graph ->
            graph
            # REMINDER: render/3 has to be implemented by the Widgex.Component implementing this behaviour
            |> render(state, frame)
            |> render_scrollbars(state, frame, opts)
          end,
          # trim outside the frame & move the frame to it's location
          id: {:widgex_component, state.widgex.id},
          # scissor: Dimensions.box(frame.size),
          scissor: frame.size.box,
          # translate: Coordinates.point(frame.pin)
          translate: frame.pin.point
        )
      end

      @doc """
      A simple helper function which fills the frame with a color.
      """
      def fill_frame(
            %Scenic.Graph{} = graph,
            %Frame{size: f_size},
            opts \\ []
          ) do
        graph |> Scenic.Primitives.rect(f_size.box, opts)
      end

      defp render_scrollbars(graph, state, frame, opts) do
        case Keyword.get(opts, :scrollable) do
          :all_axis ->
            graph
            |> render_scrollbar_x(state, frame, opts)
            |> render_scrollbar_y(state, frame, opts)

          _otherwise ->
            graph
        end
      end

      @scrollbar_size 20
      @scrollbar_bg_opacity @fifteen_percent_opaque
      @scroll_box_no_hover_opacity @thirty_percent_opaque
      @scroll_box_whilst_hovered_opacity @sixty_percent_opaque
      defp render_scrollbar_x(graph, state, frame, opts) do
        {left, top, right, bottom} = Scenic.Graph.bounds(graph)
        unscissored_width = right - left

        if unscissored_width > frame.size.width do
          # if we are going to render a vertical scrollbar we need to make room for it
          unscissored_height = bottom - top

          full_scrollbar_width =
            if unscissored_height > frame.size.height do
              frame.size.width - @scrollbar_size
            else
              frame.size.width
            end

          {scroll_x, _scroll_y} = state.scroll

          content_box_scroll_offset =
            frame.size.width * (-1 * scroll_x / (unscissored_width - frame.size.width))

          content_box_width = frame.size.width * (frame.size.width / unscissored_width)

          {r, g, b} = state.widgex.theme.accent2

          graph
          |> Scenic.Primitives.group(
            fn graph ->
              graph
              |> Scenic.Primitives.rect({full_scrollbar_width, @scrollbar_size},
                fill: {r, g, b, @scrollbar_bg_opacity}
              )
              |> Scenic.Primitives.rect({content_box_width, @scrollbar_size},
                id: {:widgex_component, state.widgex.id, :scrollbar_x_content_box},
                fill: {r, g, b, @scroll_box_no_hover_opacity},
                translate: {content_box_scroll_offset, 0},
                input: [:cursor_pos]
              )
            end,
            id: {:widgex_component, state.widgex.id, :scrollbar_x},
            translate: {0, frame.size.height - @scrollbar_size}
          )
        else
          # no need to render an x scrollbar...
          graph
        end
      end

      defp full_text_bounds(graph) do
        {left, top, right, bottom} = Scenic.Graph.bounds(graph)
        complete_height = bottom - top
        complete_width = right - left

        %{width: complete_width, height: complete_height}
      end

      defp vertical_scrollbar_box_height(
             _frame = %{size: %{height: frame_height}},
             _bounds = %{height: full_unbounded_height}
           ) do
        frame_height * (frame_height / full_unbounded_height)
      end

      defp horizontal_scrollbar_box_width(
             _frame = %{size: %{width: frame_width}},
             _bounds = %{width: full_unbounded_width}
           ) do
        frame_width * (frame_width / full_unbounded_width)
      end

      defp render_scrollbar_y(graph, state, frame, opts) do
        # {_left, top, _right, bottom} = Scenic.Graph.bounds(graph)
        # unscissored_height = bottom - top
        %{height: unscissored_height} = full_text_bounds(graph)

        if unscissored_height > frame.size.height do
          # to calculate the size of the "content box" on the scrollbar,
          # we need to know what % of the underlying content is visible
          # inside the current Frame - this is x% of the content, so
          # we need to make the content box x% of the scrollbar size
          {_scroll_x, scroll_y} = state.scroll

          content_box_scroll_offset =
            frame.size.height * (-1 * scroll_y / (unscissored_height - frame.size.height))

          content_box_height = frame.size.height * (frame.size.height / unscissored_height)

          {r, g, b} = state.widgex.theme.accent2

          graph
          |> Scenic.Primitives.group(
            fn graph ->
              graph
              |> Scenic.Primitives.rect({@scrollbar_size, frame.size.height},
                fill: {r, g, b, @scrollbar_bg_opacity}
              )
              |> Scenic.Primitives.rect({@scrollbar_size, content_box_height},
                id: {:widgex_component, state.widgex.id, :scrollbar_y_content_box},
                fill: {r, g, b, @scroll_box_no_hover_opacity},
                translate: {0, content_box_scroll_offset},
                input: [:cursor_pos]
              )
            end,
            id: {:widgex_component, state.widgex.id, :scrollbar_y},
            translate: {frame.size.width - @scrollbar_size, 0}
          )
        else
          # no need to render a y scrollbar...
          graph
        end
      end

      @scrollbar_content_boxes [
        {:widgex_component, __MODULE__, :scrollbar_x_content_box},
        {:widgex_component, __MODULE__, :scrollbar_y_content_box}
      ]
      def handle_input(
            {:cursor_pos, {_x, _y} = cursor_coords},
            scroll_box,
            %{assigns: %{scrollbar_clicked?: true}} = scene
          )
          when scroll_box in @scrollbar_content_boxes do
        # scroll_delta =
        #   {x_delta, y_delta} =
        #   Scenic.Math.Vector2.sub(scene.assigns.scrollbar_click_coords, cursor_coords)

        # Determine the difference between the initial click position and current cursor position
        # flip order of subtraction to account for backwards way coords works
        {x_delta, y_delta} =
          Scenic.Math.Vector2.sub(scene.assigns.scrollbar_click_coords, cursor_coords)

        # Calculate the scroll ratios
        full_bounds =
          %{width: complete_width, height: complete_height} =
          full_text_bounds(scene.assigns.graph)

        vertical_scroll_space =
          scene.assigns.frame.size.height -
            vertical_scrollbar_box_height(scene.assigns.frame, full_bounds)

        horizontal_scroll_space =
          scene.assigns.frame.size.width -
            horizontal_scrollbar_box_width(scene.assigns.frame, full_bounds)

        vertical_content_scroll_range = complete_height - scene.assigns.frame.size.height
        horizontal_content_scroll_range = complete_width - scene.assigns.frame.size.width

        vertical_scroll_ratio = vertical_content_scroll_range / vertical_scroll_space
        horizontal_scroll_ratio = horizontal_content_scroll_range / horizontal_scroll_space

        # Adjust deltas with scroll ratios
        adjusted_x_delta = x_delta * horizontal_scroll_ratio
        adjusted_y_delta = y_delta * vertical_scroll_ratio

        # # TODO need to figure out what % of movement through the textbox this delta scroll is & adjust
        # %{width: complete_width, height: complete_height} = full_text_bounds(scene.assigns.graph)

        # # Calculate the proportion of the content that is visible
        # proportion_visible = scene.assigns.frame.size.height / complete_height

        # # Determine the drag-able distance of the handle
        # drag_distance =
        #   scene.assigns.frame.size.height - scene.assigns.frame.size.height * proportion_visible

        # # Calculate the proportion of the handle's movement
        # handle_move_proportion = y_delta / drag_distance

        # # Calculate how much to scroll the content
        # # content_scroll =
        # #   handle_move_proportion * (complete_height - scene.assigns.frame.size.height)
        # # Given the handle's movement, how much should the content move?
        # content_move_ratio = (complete_height - scene.assigns.frame.size.height) / drag_distance

        # # Calculate how much to scroll the content based on cursor's y movement
        # content_scroll = y_delta * content_move_ratio

        # # Update the position of the content and the handle
        # # The y value of adjusted_delta should be the content_scroll, not just the delta
        # # adjusted_delta =
        # #   {x_delta / complete_width * scene.assigns.frame.size.width, content_scroll}

        # adjusted_delta =
        #   {x_delta / complete_width * scene.assigns.frame.size.width, content_scroll}

        # # what I need is the percentage of the total scrollbar - scrollbar height, * total height of the text
        # # adjusted_delta = {
        # #   x_delta / complete_width * scene.assigns.frame.size.width,
        # #   y_delta / complete_height * scene.assigns.frame.size.height
        # #   # y_delta / scene.assigns.frame.size.height * complete_height
        # # }

        # Introduce a factor to slow down the scroll relative to the cursor movement
        # Adjust this value to find the right speed
        factor = 1.75
        adjusted_scroll_delta = {x_delta * factor, y_delta * factor}

        ii = {:cursor_scroll, {adjusted_scroll_delta, cursor_coords}}

        # Forward the synthesized scroll input to the component's own
        # handle_input — the host app decides what scrolling means; this
        # library must not dispatch into any app's state layer.
        send(self(), {:widgex_input, ii})

        new_scene =
          scene
          |> assign(scrollbar_click_coords: cursor_coords)

        {:noreply, new_scene}
      end

      def handle_input(
            {:cursor_pos, {_x, _y} = coords},
            scroll_box,
            scene
          )
          when scroll_box in @scrollbar_content_boxes do
        # [
        #   %Scenic.Primitive{data: box_size}
        # ] = Scenic.Graph.get(scene.assigns.graph, scroll_box)

        # Graph.modify(graph, :rect, fn(p) ->
        #   update_opts(p, rotate: 0.5)
        # end)

        # we capture cursor pos so that all cursor_pos input gets routed
        # to this component, so that when we leave the bounds of this component,
        # we know that we've left (and thus to change the background color back to normal,
        # not to mention releasing the cursor_pos input)
        :ok = capture_input(scene, [:cursor_pos, :cursor_button])

        {r, g, b} = scene.assigns.state.widgex.theme.accent2

        new_graph =
          scene.assigns.graph
          |> Scenic.Graph.modify(
            scroll_box,
            &Scenic.Primitives.update_opts(&1, fill: {r, g, b, @scroll_box_whilst_hovered_opacity})
          )

        new_scene =
          scene
          # |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        {:noreply, new_scene}
      end

      def handle_input(
            {:cursor_pos, {_x, _y} = _coords},
            _any_other_component,
            scene
          ) do
        # if we get in here then we're capturing cursor_pos input but
        # we're not hovering over the scroll bar box, so we need to release it
        :ok = release_input(scene)

        {r, g, b} = scene.assigns.state.widgex.theme.accent2

        new_graph =
          Enum.reduce(
            @scrollbar_content_boxes,
            scene.assigns.graph,
            fn scroll_box, graph ->
              graph
              |> Scenic.Graph.modify(
                scroll_box,
                &Scenic.Primitives.update_opts(&1, fill: {r, g, b, @scroll_box_no_hover_opacity})
              )
            end
          )

        new_scene =
          scene
          # |> assign(state: new_state)
          |> assign(scrollbar_clicked?: false)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        {:noreply, new_scene}
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

      def handle_input(
            {:cursor_button, {:btn_left, @clicked, [], click_coords}},
            scroll_box,
            scene
          )
          when scroll_box in @scrollbar_content_boxes do
        # bounds = Scenic.Graph.bounds(scene.assigns.graph)

        # if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
        #   cast_parent(scene, {:click, scene.assigns.state.unique_id})
        # end

        new_scene =
          scene |> assign(scrollbar_clicked?: true, scrollbar_click_coords: click_coords)

        {:noreply, new_scene}
      end

      def handle_input(
            {:cursor_button, {:btn_left, @release_click, [], _click_coords}},
            scroll_box,
            scene
          )
          when scroll_box in @scrollbar_content_boxes do
        {:noreply, scene |> assign(scrollbar_clicked?: false)}
      end

      def handle_input(
            {:cursor_button, _click_details},
            scroll_box,
            scene
          )
          when scroll_box in @scrollbar_content_boxes do
        # bounds = Scenic.Graph.bounds(scene.assigns.graph)

        # if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
        #   cast_parent(scene, {:click, scene.assigns.state.unique_id})
        # end

        {:noreply, scene |> assign(scrollbar_clicked?: false)}
      end
    end
  end
end
