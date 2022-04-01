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
            # A %FontMetrics{} struct for this font
            metrics: _fm,
            # The font-size of the main menubar options
            size: _size
          },
          sub_menu: %{
            # The height of the sub-menus (as opposed to the main menu bar)
            height: _h,
            # The size of the sub-menu font
            font_size: _sub_menu_font_size
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

    init_graph = render(%{
      base_graph: Scenic.Graph.build(),
      frame: init_frame,
      state: init_state,
      theme: theme
    })

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

  

  def handle_cast(new_mode, %{assigns: %{state: %{mode: current_mode}}} = scene)
      when new_mode == current_mode do
    # Logger.debug "#{__MODULE__} ignoring mode change request, as we are already in #{inspect new_mode}"
    {:noreply, scene}
  end

  #NOTE: Put a hard-limit on menu size for now, just for safety - I doubt we will ever want/need more than 20 top menu items anyway
  #NOTE: A list of length 1 mean's we're hoving over a top-level menu item - one within the menu bar itself
  def handle_cast({:hover, [top_index|_rest]} = new_mode, scene) when top_index >= 1 and top_index <= 20 do
    # Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}, from: #{inspect scene.assigns.state.mode}"

    new_state =
      scene.assigns.state
      |> Map.put(:mode, new_mode)

    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:sub_menu)
      |> render_sub_menu(%{
        state: scene.assigns.state,
        index: [top_index],
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

  # # def handle_cast({:hover, [_top_ii, _sub_ii]} = new_mode, scene) do
  # def handle_cast({:hover, menu_index} = new_mode, scene) do
  #   # Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}, from: #{inspect scene.assigns.state.mode}"

  #   # NOTE: Here we don't actually have to do anything except update
  #   #      the state - drawing the sub-menu was done when we transitioned
  #   #      into a `{:hover, x}` mode, and highlighting the float-buttons
  #   #      is done inside the FloatButton itself.

  #   IO.inspect menu_index, label: "ii capn"

  #   new_state =
  #     scene.assigns.state
  #     |> Map.put(:mode, new_mode)

  #   new_scene =
  #     scene
  #     |> assign(state: new_state)

  #   {:noreply, new_scene}
  # end

  def handle_cast(
        {:click, [top_ii, sub_ii]},
        %{assigns: %{state: %{menu_opts: menu_opts}}} = scene
  ) when top_ii >= 1 and top_ii <= 20 and sub_ii >= 1 and sub_ii <= 20 do
    # REMINDER: I use indexes which start at 1, Elixir does not :P 
    {_label, sub_menu} = menu_opts |> Enum.at(top_ii - 1)
    # REMINDER: I use indexes which start at 1, Elixir does not :P 

    case sub_menu |> Enum.at(sub_ii - 1) do
      #NOTE: Sub-menus may be either a normal float button, or they may
      #      be further sub-menus - we have to handle all cases here

      # normal float button
      {_label, action} ->
        action.()
        GenServer.cast(__MODULE__, {:cancel, scene.assigns.state.mode})
        {:noreply, scene}

      {:sub_menu, _label, _menu_contents} ->
        # if we click on a sub-menu, just do nothing...
        {:noreply, scene}
    end
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

  #TODO either it's menu_map (preferred) or menu_opts, not both!!
  def handle_cast({:put_menu_map, new_menu_map}, scene) do

    new_state = scene.assigns.state |> Map.put(:menu_opts, new_menu_map)
    # new_state = state
    # |> put_in([:assigns, :frame, :menu_map], new_menu_map)
    # new_state = scene.assigns.state |> Map.put(:menu_map, new_menu_map)
    # new_graph = render(scene.assigns.frame, new_state, scene.assigns.theme)

    base_graph = scene.assigns.graph
    |> Scenic.Graph.delete(:menu_bar)

    new_graph = render(%{
      base_graph: base_graph,
      frame: scene.assigns.frame,
      state: new_state,
      theme: scene.assigns.theme
    })

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
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


  #NOTE: This function renders the actual MenuBar, as it looks when it is inactive.
  #      Hovering over an item will cause sub-menus to render, but this happens elsewhere in the code
  def render(%{
    base_graph: base_graph,
    frame: %{size: {width, height}} = _frame,
    state: %{mode: :inactive, item_width: {:fixed, menu_width}} = args,
    theme: theme
  }) do
    
    menu_items_list =
      args.menu_opts
      |> Enum.map(fn {label, _sub_menu} -> label end)
      |> Enum.with_index(1)

    # NOTE: define a function which shall render the menu-item components,
    #      and we shall use if in the pipeline below to build the final graph
    render_menu_items = fn init_graph, menu_items_list ->
      {final_graph, _final_offset} =
        menu_items_list
        |> Enum.reduce(_init_acc = {init_graph, _init_item_num = 1}, fn
              _menu_item = {label, top_lvl_index}, _acc = {graph, menu_item_num} ->
                  #TODO - either fixed width, or flex width (adapts to size of label)
                  label_width = menu_width
                  item_width = label_width + @left_margin

                  carry_graph =
                    graph
                    |> FloatButton.add_to_graph(%{
                      label: label,
                      # NOTE: Buttons don't start at zero, they start at 1... no sane person ever says "click on button zero" - sorry Tom.
                      menu_index: [top_lvl_index],
                      font: %{
                        size: args.font.size,
                        ascent: FontMetrics.ascent(args.font.size, args.font.metrics),
                        descent: FontMetrics.descent(args.font.size, args.font.metrics),
                        metrics: args.font.metrics
                      },
                      frame: %{
                        # REMINDER: coords are like this, {x_coord, y_coord}
                        pin: {(top_lvl_index-1)*item_width, 0},
                        size: {item_width, height}
                      },
                      margin: @left_margin
                    })

                  {carry_graph, menu_item_num+1}
        end)

      final_graph
    end

    base_graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect({width, height}, fill: theme.active, id: :menu_background)
        |> render_menu_items.(menu_items_list)
      end,
      id: :menu_bar
    )
  end

  # def render_sub_menu(graph, %{state: state, index: %{top_index: top_index, sub_index: _sub_index}, frame: frame, theme: theme}) do
  def render_sub_menu(graph, %{state: state, index: [top_index|_rest] = menu_index, frame: frame, theme: theme}) do
    {:fixed, menu_item_width} = state.item_width
    num_top_items = Enum.count(state.menu_opts)
    # [top_index|_rest] = menu_index

    sub_menu = get_sub_menu(state.menu_opts, menu_index)
    num_sub_menu_items = Enum.count(sub_menu)
    sub_menu_width = menu_item_width + num_top_items*@left_margin
    sub_menu_height = num_sub_menu_items * state.sub_menu.height

    # sub_menu_font = %{
    #     size: state.sub_menu.font_size,
    #     ascent: FontMetrics.ascent(state.sub_menu.font_size, state.font.metrics),
    #     descent: FontMetrics.descent(state.sub_menu.font_size, state.font.metrics),
    #     metrics: state.font.metrics
    #   }

    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # NOTE: We never see this rectangle beneath the sub_menu, but it
        #      gives this component a larger bounding box, which we
        #      need to detect when we've left the area with the mouse
        # |> Scenic.Primitives.rect({sub_menu_width, frame.dimensions.height + sub_menu_height}, translate: {0, -frame.dimensions.height})
        |> do_render_sub_menu(%{state: state, menu_index: menu_index, frame: frame, theme: theme})
        |> Scenic.Primitives.rect({sub_menu_width, sub_menu_height}, stroke: {2, theme.border}) # draw border
        #NOTE: We can't set a negative x coordinate if it's the hard-left corner of the screen
        |> Scenic.Primitives.line({{(if top_index == 1, do: 0, else: -2),0},{sub_menu_width+2,0}}, stroke: {2, theme.active}) # draw a line over the top of the sub-menu border so it blends in better with the menu_bar itself (and overlap the edges a little bit)
      end,
      id: :sub_menu,
      translate: {menu_item_width * (top_index-1), frame.dimensions.height}
    )
  end

  # def get_sub_menu(menu_opts, menu_index) do
  #   IO.inspect menu_opts

  #   menu_index |> Enum.map_reduce(menu_index, fn {index, acc_menu} ->
  #     {label, _sub_menu} = Enum.at(acc_menu, index-1, :error)
  #   end)
  # end

  # def do_get_sub_menu(menu_opts, [ii]) do
  #   {_label, sub_menu} = Enum.at(menu_opts, ii-1, :error)
  # end

   

  # def get_sub_menu(menu_opts, menu_index) do
  #   {menu_address, _last_index} = Enum.split(menu_index, -1) # ditch last index
  #   do_get_sub_menu(menu_opts, menu_address)
  # end

  def get_sub_menu(menu_opts, index = [ii|rest]) do
    #NOTE: This function has 2 handle clauses here. In hindsight, either
    #      I should have used a `{:menu, blah}` tuple for everything, even
    #      the top layer, or gone with just the default {:name, action}
    #      tuple & used type checking (to see whether or not action was
    #      a function, meaning this is a button, or a list, meaning this
    #      is another sub-menu). Instead... this function has 2 handle clauses here.
    IO.inspect index, label: "IIIII"
    IO.inspect menu_opts, label: "BIG M"
    case Enum.at(menu_opts, ii-1, :error) do
      {_label, sub_menu} ->
          get_sub_menu(sub_menu, rest)
      {:sub_menu, _sub_label, sub_menu} ->
          get_sub_menu(sub_menu, rest)
      other_clause ->
        raise other_clause
    end
  end

  # def get_sub_menu(menu_opts, label = [ii|rest]) do
  #   IO.inspect label
  #   IO.inspect menu_opts, label: "BIG M"
  #   {_label, sub_menu} = Enum.at(menu_opts, ii-1, :error)
  #   get_sub_menu(sub_menu, rest)
  # end

  def get_sub_menu(item, []) do
    item
  end

  defp do_render_sub_menu(graph, %{state: state, menu_index: menu_index, frame: frame, theme: theme}) do
    {:fixed, menu_item_width} = state.item_width
    num_top_items = Enum.count(state.menu_opts)
    [top_index|sub_indices] = menu_index
    {:fixed, top_index_menu_width} = state.item_width
    top_index_menu_width = top_index_menu_width + @left_margin
    sub_menu = get_sub_menu(state.menu_opts, menu_index)
    # {_top_label, sub_menu} = state.menu_opts |> Enum.at(top_index - 1)
    num_sub_menu_items = Enum.count(sub_menu)
    sub_menu = sub_menu |> Enum.with_index(1)
    sub_menu_width = menu_item_width + num_top_items * @left_margin
    sub_menu_height = num_sub_menu_items * state.sub_menu.height
    sub_menu_font = %{
        size: state.sub_menu.font_size,
        ascent: FontMetrics.ascent(state.sub_menu.font_size, state.font.metrics),
        descent: FontMetrics.descent(state.sub_menu.font_size, state.font.metrics),
        metrics: state.font.metrics
      }


    sub_menu |> Enum.reduce(graph, fn
        
        {{label, _func}, sub_index}, graph ->
          graph |> render_float_button(%{
            label: label,
            menu_pos: IO.inspect(menu_index ++ [sub_index], label: "Subren77"),
            top_index_menu_width: top_index_menu_width,
            font: sub_menu_font,
            size: {sub_menu_width, state.sub_menu.height}
          })

          {{:sub_menu, label, sub_menu_items}, sub_index}, graph ->

            pop_out_icon_height = 0.6*state.sub_menu.height
            pop_out_icon_coords = %{x: 0.84*sub_menu_width, y: (state.sub_menu.height-pop_out_icon_height)/2}

            graph
            |> render_float_button(%{
                label: label,
                menu_pos: menu_index ++ [sub_index],
                top_index_menu_width: top_index_menu_width,
                font: sub_menu_font,
                size: {sub_menu_width, state.sub_menu.height}
            })
            # draw the sub-menu & sigils over the top of the carry_graph
            |> ScenicWidgets.Utils.Shapes.right_pointing_triangle(%{
                top_left: pop_out_icon_coords,
                height: pop_out_icon_height,
                color: theme.border
            })
            #now, lol let's just try it, call render sub-menu with a different offset
            |> do_render_sub_menu(%{
                state: state,
            #     menu_pos: state.menu_pos ++ [top_index, sub_index], #TODO
                menu_index: menu_index ++ [sub_index], #TODO
            #     # index: top_index, #TODO this needs to be updated to 
                frame: frame, #TODO need to move the frame over 1 offset
                theme: theme
            })


    end)
  end

  #   {final_graph, _final_offset} =
  #     sub_menu
  #     |> Enum.reduce({graph, _init_offset = 0}, fn

  #           # normal FloatButton
  #           {{label, _func}, sub_index}, {graph, offset} ->
  #               carry_graph = render_float_button(graph, %{
  #                 label: label,
  #                 menu_pos: [top_index, sub_index],
  #                 font: sub_menu_font,
  #                 size: {sub_menu_width, state.sub_menu.height}
  #               })
  #               {carry_graph, offset + state.sub_menu.height}

  #           # sub-menu
  #           {{:sub_menu, label, sub_menu_items}, sub_index}, {graph, offset} ->
  #               pop_out_icon_height = 0.6*state.sub_menu.height
  #               pop_out_icon_coords = %{x: 0.84*sub_menu_width, y: (state.sub_menu.height-pop_out_icon_height)/2}
  #               IO.inspect theme

  #               carry_graph = render_float_button(graph, %{
  #                 label: label,
  #                 menu_pos: [top_index, sub_index],
  #                 # offset: offset,
  #                 # top_index: top_index,
  #                 # sub_index: sub_index,
  #                 font: sub_menu_font,
  #                 size: {sub_menu_width, state.sub_menu.height}
  #               })
  #               # draw the sub-menu & sigils over the top of the carry_graph
  #               |> ScenicWidgets.Utils.Shapes.right_pointing_triangle(%{
  #                 top_left: pop_out_icon_coords,
  #                 height: pop_out_icon_height,
  #                 color: theme.border
  #               })
  #               #now, lol let's just try it, call render sub-menu with a different offset
  #               |> do_render_sub_menu(%{
  #                   state: sub_menu_items,
  #                   menu_pos: state.menu_pos ++ [top_index, sub_index], #TODO
  #                   # index: top_index, #TODO this needs to be updated to 
  #                   frame: frame, #TODO need to move the frame over 1 offset
  #                   theme: theme
  #                 })

  #               {carry_graph, offset + state.sub_menu.height}

  #     end)

  #   final_graph
  # end

  defp render_float_button(graph, %{
    label: label,
    menu_pos: menu_pos,
    top_index_menu_width: top_index_menu_width,
    font: font,
    size: {sub_menu_width, sub_menu_height} = button_size
  }) do
    IO.puts "RENDER FLOAT #{inspect menu_pos}"

    [top_index|sub_indices] = menu_pos
    IO.inspect sub_indices, label: "SUB2"
    depth_of_sub_menu_tree = Enum.count(sub_indices)

    #NOTE: Take this example, menu_pos = [2,4,6,1]. The first element is
    #      `top_index`, and it tells us that we were initially hovering
    #      over the second menu item, so we already need to move this
    #      sub_menu at least 2*sub_menu_width. What's left is [4,6,1] -
    #      this means we are going to be rendering 3 more sub-menus, so
    #      we need to move this one over 3 more sub_menu_width. Finally,
    #      to calculate how far down the screen we need to render this
    #      float button, we can add up the depth of the menu entries, because
    #      buttons render linearly down the screen.
    sub_button_vertical_render_offset = Enum.sum(sub_indices)

    IO.inspect top_index, label: "OPOPOPOPOP"
    top_left = {
      #NOTE the top-level offset is already taken into account, it's in the pin of the sub-menu frame!!
      (depth_of_sub_menu_tree-1)*sub_menu_width,
      # ((top_index-1) + (depth_of_sub_menu_tree))*sub_menu_width,
      # (top_index-1)*top_index_menu_width,
      # 0, 
      (sub_button_vertical_render_offset-1)*sub_menu_height #NOTE depth of sub tree should be the offset
    }

    graph
    |> FloatButton.add_to_graph(%{
      label: label,
      menu_index: menu_pos,
      font: font,
      frame: %{
        # REMINDER: coords are like this, {x_coord, y_coord}
        pin: top_left,
        size: button_size
      },
      margin: @left_margin
    })
  end

end
