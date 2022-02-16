defmodule ScenicWidgets.MenuBar do
  use Scenic.Component
  require Logger
  alias ScenicWidgets.MenuBar.FloatButton
  use ScenicWidgets.ScenicEventsDefinitions

  # how far we indent the first menu item
  @left_margin 15

  def validate(
        %{
          # The %Frame{} struct describing the rectangular size of the component
          frame: %ScenicWidgets.Core.Structs.Frame{} = _f,
          # A list containing the contents of the Menu, and what functions to call if that item gets clicked on
          menu_opts: _map,
          # `{:fixed, x}` which means each menu item is a fixed width
          item_width: {:fixed, _w},
          font: %{
            # The font name
            name: _name,
            # A %FontMetrics{} struct for this font
            metrics: _fm,
            # The font-size of the main menubar options
            size: _s
          },
          sub_menu: %{
            # The height of the sub-menus (as opposed to the main menu bar)
            height: _h,
            # The size of the sub-menu font
            font: %{size: _font_s}
          }
        } = data
      ) do
    # NOTE: This is an example of a valid menu-map
    # [
    #     {"Buffer", [
    #         {"new", &QuillEx.API.Buffer.new/0},
    #         {"save", &QuillEx.API.Buffer.save/0},
    #         {"close", &QuillEx.API.Buffer.close/0}]},
    #     {"Help", [
    #         {"About QuillEx", &QuillEx.API.Misc.makers_mark/0}]},
    # ]
    # Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
    {:ok, data}
  end

  def init(scene, args, opts) do
    Logger.debug("#{__MODULE__} initializing...")
    Process.register(self(), __MODULE__)

    theme =
      (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
      |> Scenic.Primitive.Style.Theme.normalize()

    init_state = %{
      mode: :inactive,
      menu_opts: args.menu_opts,
      font: args.font,
      item_width: args.item_width,
      sub_menu: args.sub_menu
    }

    init_frame = args.frame

    init_graph = render(init_frame, init_state, theme)

    init_scene =
      scene
      |> assign(state: init_state)
      |> assign(graph: init_graph)
      |> assign(frame: init_frame)
      |> assign(theme: theme)
      |> push_graph(init_graph)

    request_input(init_scene, [:cursor_pos, :key])

    {:ok, init_scene}
  end

  def render(%{size: {width, height}}, %{mode: :inactive} = args, theme) do
    menu_items_list =
      args.menu_opts
      |> Enum.map(fn {label, _sub_menu} -> label end)
      |> Enum.with_index()

    {:fixed, menu_width} = args.item_width

    # NOTE: define a function which shall render the menu-item components,
    #      and we shall use if in the pipeline below to build the final graph
    render_menu_items = fn init_graph, menu_items_list ->
      {final_graph, _final_offset} =
        menu_items_list
        |> Enum.reduce({init_graph, _init_offset = 0}, fn {label, index}, {graph, offset} ->
          # TODO - either fixed width, or flex width (adapts to size of label)
          label_width = menu_width
          item_width = label_width + @left_margin

          carry_graph =
            graph
            |> FloatButton.add_to_graph(%{
              label: label,
              # NOTE: I hate indexes which start at zero...
              menu_index: {:top_index, index + 1},
              font: %{
                size: args.font.size,
                ascent: FontMetrics.ascent(args.font.size, args.font.metrics),
                descent: FontMetrics.descent(args.font.size, args.font.metrics),
                metrics: args.font.metrics
              },
              frame: %{
                # REMINDER: coords are like this, {x_coord, y_coord}
                pin: {offset, 0},
                size: {item_width, height}
              },
              margin: @left_margin
            })

          {carry_graph, offset + item_width}
        end)

      final_graph
    end

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect({width, height}, fill: theme.active, id: :menu_background)
        |> render_menu_items.(menu_items_list)
      end,
      id: :menu_bar
    )
  end

  def render_sub_menu(graph, %{state: state, index: top_index, frame: frame, theme: theme}) do
    {:fixed, menu_item_width} = state.item_width
    num_top_items = Enum.count(state.menu_opts)
    {_top_label, sub_menu} = state.menu_opts |> Enum.at(top_index - 1)
    num_sub_menu_items = Enum.count(sub_menu)
    sub_menu = sub_menu |> Enum.with_index()
    sub_menu_width = menu_item_width + num_top_items * @left_margin
    sub_menu_height = num_sub_menu_items * state.sub_menu.height

    render_sub_menu = fn init_graph ->
      {final_graph, _final_offset} =
        sub_menu
        |> Enum.reduce({init_graph, _init_offset = 0}, fn {{label, func}, sub_index},
                                                          {graph, offset} ->
          carry_graph =
            graph
            |> FloatButton.add_to_graph(%{
              label: label,
              # NOTE: I hate indexes which start at zero...
              menu_index: {:top_index, top_index, :sub_index, sub_index + 1},
              action: func,
              font: %{
                size: state.sub_menu.font.size,
                ascent: FontMetrics.ascent(state.sub_menu.font.size, state.font.metrics),
                descent: FontMetrics.descent(state.sub_menu.font.size, state.font.metrics),
                metrics: state.font.metrics
              },
              frame: %{
                # REMINDER: coords are like this, {x_coord, y_coord}
                pin: {0, offset},
                size: {sub_menu_width, state.sub_menu.height}
              },
              margin: @left_margin
            })

          {carry_graph, offset + state.sub_menu.height}
        end)

      final_graph
    end

    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # NOTE: We never see this rectangle beneath the sub_menu, but it
        #      gives this component a larger bounding box, which we
        #      need to detect when we've left the area with the mouse
        # |> Scenic.Primitives.rect({sub_menu_width, frame.dimensions.height + sub_menu_height}, translate: {0, -frame.dimensions.height})
        |> render_sub_menu.()
        |> Scenic.Primitives.rect({sub_menu_width, sub_menu_height}, stroke: {2, theme.border}) # draw border
        #NOTE: We can't set a negative x coordinate if it's the hard-left corner of the screen
        |> Scenic.Primitives.line({{(if top_index == 1, do: 0, else: -2),0},{sub_menu_width+2,0}}, stroke: {2, theme.active}) # draw a line over the top of the sub-menu border so it blends in better with the menu_bar itself (and overlap the edges a little bit)
      end,
      id: :sub_menu,
      translate: {menu_item_width * (top_index - 1), frame.dimensions.height}
    )
  end

  def handle_cast(new_mode, %{assigns: %{state: %{mode: current_mode}}} = scene)
      when new_mode == current_mode do
    # Logger.debug "#{__MODULE__} ignoring mode change request, as we are already in #{inspect new_mode}"
    {:noreply, scene}
  end

  def handle_cast({:hover, {:top_index, index}} = new_mode, scene) do
    # Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}, from: #{inspect scene.assigns.state.mode}"

    new_state =
      scene.assigns.state
      |> Map.put(:mode, new_mode)

    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:sub_menu)
      |> render_sub_menu(%{
        state: scene.assigns.state,
        index: index,
        frame: scene.assigns.frame,
        theme: scene.assigns.theme
      })

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast(
        {:click, {:top_index, top_ii, :sub_index, sub_ii}},
        %{assigns: %{state: %{menu_opts: menu_opts}}} = scene
      ) do
    # REMINDER: I use indexes which start at 1, Elixir does not :P 
    {_label, sub_menu} = menu_opts |> Enum.at(top_ii - 1)
    # REMINDER: I use indexes which start at 1, Elixir does not :P 
    {_label, action} = sub_menu |> Enum.at(sub_ii - 1)
    action.()
    GenServer.cast(__MODULE__, {:cancel, scene.assigns.state.mode})
    {:noreply, scene}
  end

  def handle_cast({:hover, {:top_index, _t, :sub_index, _s}} = new_mode, scene) do
    # Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}, from: #{inspect scene.assigns.state.mode}"

    # NOTE: Here we don't actually have to do anything except update
    #      the state - drawing the sub-menu was done when we transitioned
    #      into a `{:hover, x}` mode, and highlighting the float-buttons
    #      is done inside the FloatButton itself.

    new_state =
      scene.assigns.state
      |> Map.put(:mode, new_mode)

    new_scene =
      scene
      |> assign(state: new_state)

    {:noreply, new_scene}
  end

  def handle_cast({:cancel, :inactive}, scene) do
    # We just need to ignore these, the MenuBar keeps sending cancel
    # signals even when it's in :inactive mode... maybe that's a #TODO
    {:noreply, scene}
  end

  def handle_cast({:cancel, cancel_mode}, %{assigns: %{state: %{mode: current_mode}}} = scene)
      when cancel_mode == current_mode do
    new_mode = :inactive

    Logger.debug(
      "#{__MODULE__} changing state.mode to: #{inspect(new_mode)}, from: #{inspect(cancel_mode)}"
    )

    new_state =
      scene.assigns.state
      |> Map.put(:mode, new_mode)

    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:sub_menu)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast({:frame_reshape, new_frame}, scene) do
    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.modify(:menu_background, &Scenic.Primitives.rect(&1, new_frame.size))

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(frame: new_frame)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast({:cancel, _cancel_mode}, scene) do
    # Logger.debug "#{__MODULE__} ignoring mode cancellation request, as we are not in #{inspect cancel_mode}"
    {:noreply, scene}
  end

  # Here we use the cursor_pos to trigger resets when the user navigates
  # away from the MenuBar. Right now it only uses the y axis, this is a bug
  def handle_input({:cursor_pos, {_x, y}}, _context, scene) do
    # NOTE: `menu_bar_max_height` is the full height, including any
    #       currently rendered sub-menus. As new sub-menus of different
    #       lengths get rendered, this max-height will change.
    #
    #       menu_bar_max_height = @height + num_sub_menu*@sub_menu_height
    {0.0, 0.0, _viewport_width, menu_bar_max_height} = Scenic.Graph.bounds(scene.assigns.graph)

    if y > menu_bar_max_height do
      GenServer.cast(self(), {:cancel, scene.assigns.state.mode})
      {:noreply, scene}
    else
      # TODO here check if we veered of sideways in a sub-menu
      {:noreply, scene}
    end
  end

  def handle_input(@escape_key, _context, scene) do
    Logger.debug("#{__MODULE__} cancelling due to ESCAPE KEY !!")
    GenServer.cast(__MODULE__, {:cancel, scene.assigns.state.mode})
    {:noreply, scene}
  end

  def handle_input({:key, {key, _dont_care, _dont_care_either}}, _context, scene) do
    #Logger.debug("#{__MODULE__} ignoring key: #{inspect(key)}")
    {:noreply, scene}
  end
end
