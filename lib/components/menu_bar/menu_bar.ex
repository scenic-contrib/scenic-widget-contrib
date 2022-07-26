defmodule ScenicWidgets.MenuBar do
  use Scenic.Component
  require Logger
  alias ScenicWidgets.MenuBar.FloatButton
  use ScenicWidgets.ScenicEventsDefinitions

  # how far we indent the first menu item
  @left_margin 15

  def validate(
        %{
          # The %Frame{} struct describing the rectangular size & placement of the component
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
    #Logger.debug("#{__MODULE__} initializing...")
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
      theme: theme,
      hover: nil
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
  def handle_cast({:hover, hover_index} = new_mode, scene) do
    Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}, from: #{inspect scene.assigns.state.mode}"

    new_state =
      scene.assigns.state
      |> Map.put(:mode, new_mode)

    new_graph =
      render(%{
        base_graph: Scenic.Graph.build(),
        frame: scene.assigns.frame,
        state: scene.assigns.state,
        theme: scene.assigns.theme,
        hover: hover_index
      })
      |> render_sub_menu(%{
        state: new_state,
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

  def handle_cast({:click, [top_ii]}, scene) do
    #NOTE: Do nothing when we simply click on a top menu bar (..?)
    {:noreply, scene}
  end

  def handle_cast(
        {:click, [top_ii | sub_menu_click_coords] = click_coords}, #TODO here needs to be able to handle multi-layer menus
        %{assigns: %{state: %{menu_opts: menu_opts}}} = scene
  ) when top_ii >= 1 and top_ii <= 10 do
    {:sub_menu, _label, sub_menu} = menu_opts |> Enum.at(top_ii - 1)
    
    #NOTE: Sub-menus may be either a normal float button, or they may
    #      be further sub-menus - we have to handle all cases here
    clicked_item = traverse_menu(sub_menu, sub_menu_click_coords)
    case clicked_item do

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

  def traverse_menu(menu, [] = _coords) do
    menu |> Enum.at(0)
  end

  def traverse_menu(menu, [x] = _coords) do
    # REMINDER: I use indexes which start at 1, Elixir does not :P 
    menu |> Enum.at(x-1)
  end

  def traverse_menu(menu, [x|rest] = _coords) do
    # REMINDER: I use indexes which start at 1, Elixir does not :P 
    sub_menu = menu |> Enum.at(x-1)
    traverse_menu(sub_menu, rest)
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

  def handle_cast({:cancel, _cancel_mode}, scene) do
    # Logger.debug "#{__MODULE__} ignoring mode cancellation request, as we are not in #{inspect cancel_mode}"
    {:noreply, scene}
  end

  # def handle_cast({:frame_reshape, new_frame}, scene) do
  #   new_graph =
  #     scene.assigns.graph
  #     |> Scenic.Graph.modify(:menu_background, &Scenic.Primitives.rect(&1, new_frame.size))

  #   new_scene =
  #     scene
  #     |> assign(graph: new_graph)
  #     |> assign(frame: new_frame)
  #     |> push_graph(new_graph)

  #   {:noreply, new_scene}
  # end

  def handle_cast({:put_menu_map, new_menu_map}, scene) do
  
    base_graph =
      scene.assigns.graph
      |> Scenic.Graph.delete(:menu_bar)
    
    new_state =
      scene.assigns.state
      |> Map.put(:menu_opts, new_menu_map) #TODO either it's menu_map (preferred) or menu_opts, not both!!

    new_graph = render(%{
      base_graph: base_graph,
      frame: scene.assigns.frame,
      state: new_state, #NOTE I think it's here, out new_state.mode is in hover mode here, but how?? Why are we updating it when still in hover mode?? How?? Lag in the UI??
      theme: scene.assigns.theme,
      hover: nil
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
    state: %{item_width: {:fixed, menu_width}} = args,
    theme: theme,
    hover: hover_index
  }) do
    
    menu_items_list =
      args.menu_opts
      |> Enum.map(fn {:sub_menu, label, _sub_menu} -> label end)
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
                      # menu_index: [top_lvl_index],
                      unique_id: [top_lvl_index],
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
                      margin: @left_margin,
                      hover_highlight?: this_button_is_in_the_hover_chain?(hover_index, [top_lvl_index])
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

  
  def render_sub_menu(graph, args) do
    #NOTE: We start at 0,0, but we also keep track of how many sub-menus deep we are
    {:hover, hover_index} = args.state.mode
    do_render_sub_menu(graph, args, {_current_sub_menu_depth_offset = %{x: 0, y: 0}, hover_index}) # sub_menu_depth_offset - when we need to render multiple layer deep sub-menus e.g. whole hovering over certain items, we use this to keep track of where we're up to
  end

  def do_render_sub_menu(graph, args, {_sub_offset, _sub_menu_depth = []}) do
    # here we must have bottomed out
    graph
  end

  # we are hovering over a sub-menu - add this one to the list of menus to render
  def do_render_sub_menu(graph, %{
    state: %{mode: {:hover, [hover_index|_rest] = current_hover}, menu_opts: menu} = state,
    frame: menu_bar_frame,
    theme: theme
  }, {sub_menu_depth_offset, [sub_menu_depth|sub_menu_rest]}) do
    
    #NOTE here is where I need to get sub sub menus I guess
    [{:sub_menu, _label, sub_menu}] = [Enum.at(menu, hover_index-1)]

    {:fixed, menu_item_width} = state.item_width
    sub_menu_width = menu_item_width + 3*@left_margin #TODO I think we need to get the number of items in the top menu for this to work...
    
    sub_menu_font = %{
      size: state.sub_menu.font_size,
      ascent: FontMetrics.ascent(state.sub_menu.font_size, state.font.metrics),
      descent: FontMetrics.descent(state.sub_menu.font_size, state.font.metrics),
      metrics: state.font.metrics
    }

    graph |> Scenic.Primitives.group(
      fn graph ->

        {final_graph, _final_index} = Enum.reduce(sub_menu, {graph, 1}, fn

          {label, _func}, {graph, sub_menu_index} ->

            button_index = [hover_index, sub_menu_index]
            this_button_in_hover_chain? =
              this_button_is_in_the_hover_chain?(current_hover, button_index)
    
            new_graph = graph
            |> FloatButton.add_to_graph(%{
              label: label,
              unique_id: [hover_index, sub_menu_index],
              font: sub_menu_font,
              frame: %{
                pin: {(3*@left_margin*(Enum.count(sub_menu_rest)-1))+(((hover_index-1)+sub_menu_depth_offset.x)*(menu_item_width)), menu_bar_frame.dimensions.height+(((sub_menu_index-1)+sub_menu_depth_offset.y)*state.sub_menu.height)},
                size: {sub_menu_width, state.sub_menu.height}
              },
              margin: @left_margin,
              hover_highlight?: this_button_in_hover_chain?
            })
    
            {new_graph, sub_menu_index+1}
            
          {:sub_menu, label, sub_menu_items}, {graph, sub_menu_index} ->

            button_index = [hover_index, sub_menu_index]
            this_button_in_hover_chain? =
              this_button_is_in_the_hover_chain?(current_hover, button_index)

            new_graph = graph
            |> FloatButton.add_to_graph(%{
              label: label,
              unique_id: button_index,
              font: sub_menu_font,
              frame: %{
                # pin: {(hover_index-1)*menu_item_width, menu_bar_frame.dimensions.height+(sub_menu_index-1)*state.sub_menu.height},
                pin: {(3*@left_margin*(Enum.count(sub_menu_rest)-1))+(((hover_index-1)+sub_menu_depth_offset.x)*(menu_item_width)), menu_bar_frame.dimensions.height+(((sub_menu_index-1)+sub_menu_depth_offset.y)*state.sub_menu.height)},
                size: {sub_menu_width, state.sub_menu.height}
              },
              margin: @left_margin,
              draw_sub_menu_triangle?: true,
              hover_highlight?: this_button_in_hover_chain?
              #TODO need to also force hover highlighting if we're not directly hovering, just it's in the hover chain
            })

            #NOTE: Here we are rendering a `:sub_menu` button, so if this button
            #      is in the hover chain, we need to render that sub-menu (depth-first)
            if this_button_in_hover_chain? do

              IO.puts "RENDER THE NED MANUUUUUU"

              #NOTE we're CLOSE! But how do we break out of the recursive loop???
              extended_new_graph = do_render_sub_menu(new_graph, %{
                state: state,
                frame: menu_bar_frame,
                theme: theme
              }, {%{x: sub_menu_depth_offset.x+1, y: sub_menu_depth_offset.y+1}, sub_menu_rest})

              {extended_new_graph, sub_menu_index+1}
            else
              {new_graph, sub_menu_index+1}
            end
        end)
    
        final_graph

      end,
      id: :sub_menu
    )
  end

  def this_button_is_in_the_hover_chain?(current_hover, button_index) do
    IO.inspect current_hover, label: "CURRENT HOV"
    IO.inspect button_index, label: "BUTTON INDEX"
    current_hover == button_index #NOTE this needs to figure out the entire chain, not just 
  end

end




  # def render_sub_menus_for_index(%{
  #   #NOTE we need to keep old sub-menus alive if we're multi-layers deep
  #   index: [top_index], # we're hovering over menu-bar
  #   state: state,
  #   frame: frame,
  #   theme: theme
  # }) do
  #   {:fixed, menu_item_width} = state.item_width
  #   num_top_items = Enum.count(state.menu_opts)
  #   sub_menu = get_sub_menu(state.menu_opts, menu_index)
  #   num_sub_menu_items = Enum.count(sub_menu)
  #   sub_menu_width = menu_item_width + num_top_items*@left_margin # make sub-menus wider, proportional to how many top-level items there are
  #   sub_menu_height = num_sub_menu_items * state.sub_menu.height

  #   graph
  #   |> Scenic.Primitives.group(
  #     fn graph ->
  #       graph
  #       # NOTE: We never see this rectangle beneath the sub_menu, but it
  #       #      gives this component a larger bounding box, which we
  #       #      need to detect when we've left the area with the mouse
  #       # |> Scenic.Primitives.rect({sub_menu_width, frame.dimensions.height + sub_menu_height}, translate: {0, -frame.dimensions.height})
  #       |> do_render_sub_menu(%{state: state, menu_index: menu_index, frame: frame, theme: theme})
  #       |> Scenic.Primitives.rect({sub_menu_width, sub_menu_height}, stroke: {2, theme.border}) # draw border
  #       #NOTE: We can't set a negative x coordinate if it's the hard-left corner of the screen
  #       |> Scenic.Primitives.line({{(if top_index == 1, do: 0, else: -2),0},{sub_menu_width+2,0}}, stroke: {2, theme.active}) # draw a line over the top of the sub-menu border so it blends in better with the menu_bar itself (and overlap the edges a little bit)
  #     end,
  #     id: :sub_menu,
  #     translate: {menu_item_width*(top_index-1), frame.dimensions.height}
  #   )
  # end