defmodule ScenicWidgets.MenuBar do
  use Scenic.Component
  require Logger
  alias ScenicWidgets.MenuBar.FloatButton
  use ScenicWidgets.ScenicEventsDefinitions
  # NOTE: This is an example of a valid menu-map
  # [
  #     {"Buffer", [
  #         {"new", &QuillEx.API.Buffer.new/0},
  #         {"save", &QuillEx.API.Buffer.save/0},
  #         {"close", &QuillEx.API.Buffer.close/0}]},
  #     {"Help", [
  #         {"About QuillEx", &QuillEx.API.Misc.makers_mark/0}]},
  # ]

  # how far we indent the first menu item
  @left_margin 15

  def validate(
        %{
          # The %Frame{} struct describing the rectangular size & placement of the component
          frame: %ScenicWidgets.Core.Structs.Frame{} = _f,
          # A list containing the contents of the Menu, and what functions to call if that item gets clicked on
          menu_map: _map,
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

    #Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
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
      font: calc_font_data(args.font),
      menu_map: args.menu_map,
      sub_menu: args.sub_menu,
      item_width: args.item_width,
    }

    init_frame = args.frame

    init_graph = render(%{
      state: init_state,
      frame: init_frame,
      theme: theme,
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
    {:noreply, scene} #NOTE: do nothing when we simply click on a top menu bar
  end

  def handle_cast({:click, [top_ii|rest_click_coords]}, %{assigns: %{state: state}} = scene) do

    {:sub_menu, _label, sub_menu} = state.menu_map |> Enum.at(top_ii - 1)
    
    {:ok, clicked_item} = sub_menu |> fetch_item_at(rest_click_coords)
    
    #NOTE: Sub-menus may be either a normal float button, or they may be further sub-menus - we have to handle all cases here
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

  def handle_cast({:cancel, :inactive}, scene) do
    # We just need to ignore these, the MenuBar keeps sending cancel
    # signals even when it's in :inactive mode... maybe that's a #TODO
    {:noreply, scene}
  end

  def handle_cast({:cancel, cancel_mode}, %{assigns: %{state: %{mode: current_mode}}} = scene)
      when cancel_mode == current_mode do
    #Logger.debug("#{__MODULE__} changing state.mode to: #{inspect(new_mode)}, from: #{inspect(cancel_mode)}")

    new_state =
      scene.assigns.state
      |> Map.put(:mode, :inactive)

    new_graph = render(%{
      state: new_state,
      frame: scene.assigns.frame,
      theme: scene.assigns.theme,
    })

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast({:cancel, _cancel_mode}, scene) do
    #Logger.debug "#{__MODULE__} ignoring mode cancellation request, as we are not in #{inspect cancel_mode}"
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

    new_state =
      scene.assigns.state
      # |> Map.put(:mode, :inactive) #TODO???
      |> Map.put(:menu_map, new_menu_map)

    new_graph = render(%{
      state: new_state,
      frame: scene.assigns.frame,
      theme: scene.assigns.theme,
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
    {_x, _y, _viewport_width, menu_bar_max_height} = Scenic.Graph.bounds(scene.assigns.graph)

    if y > menu_bar_max_height do
      GenServer.cast(self(), {:cancel, scene.assigns.state.mode})
      {:noreply, scene}
    else
      # TODO here check if we veered of sideways in a sub-menu
      {:noreply, scene}
    end
  end

  def handle_input(@escape_key, _context, scene) do
    #Logger.debug("#{__MODULE__} cancelling due to ESCAPE KEY !!")
    GenServer.cast(__MODULE__, {:cancel, scene.assigns.state.mode})
    {:noreply, scene}
  end

  def handle_input({:key, {key, _dont_care, _dont_care_either}}, _context, scene) do
    #Logger.debug("#{__MODULE__} ignoring key: #{inspect(key)}")
    {:noreply, scene}
  end

  def render(%{state: state, frame: frame, theme: theme} = args) do

    # this list contains all the sub-menu dropdowns we intend to recursively render
    sub_menu_dropdowns = calc_sub_menu_dropdowns(args)

    sub_menu_font = %{
      size: state.sub_menu.font_size,
      ascent: FontMetrics.ascent(state.sub_menu.font_size, state.font.metrics),
      descent: FontMetrics.descent(state.sub_menu.font_size, state.font.metrics),
      metrics: state.font.metrics
    }

    args = Map.merge(args, %{sub_menu_font: sub_menu_font})

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> render_main_menu_bar(args)
        |> render_sub_menu_dropdowns(args, sub_menu_dropdowns)
      end,
      id: :menu_bar
    )
  end

  defp render_main_menu_bar(graph, %{
    state: state,
    frame: frame = %{size: {width, height}},
    theme: theme
  }) do

    # strip out all the top-level menu item labels & give them a number
    pre_processed_menu_map = 
      state.menu_map
      |> Enum.map(fn
          # {label, _fn} ->
          #   label
          {:sub_menu, label, _sub_menu} ->
            label
        end)
      |> Enum.with_index(1)

    graph |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect({width, height}, fill: theme.active, id: :menu_background)
        |> do_render_main_menu_bar(state, frame, theme, pre_processed_menu_map)
      end,
      id: :main_menu_bar
    )
  end

  defp do_render_main_menu_bar(graph, _state, _frame, _theme, _pre_processed_menu_map = []) do
    graph
  end

  defp do_render_main_menu_bar(
    graph,
    state = %{mode: mode, item_width: {:fixed, menu_width}},
    frame = %{size: {width, height}},
    theme,
    [{label, item_num}|rest_menu_map]
  ) do

      do_hover_highlight? =
        case mode do
          :inactive ->
            false
          {:hover, [x]} ->
            x == item_num # test if the first item in the hover-chain is this top-level menu item
          {:hover, [x|_rest]} ->
            # if we want to highlight the top menu item when we hover over a sub-menu,
            # we would set this to true
            false
        end

      graph
      |> FloatButton.add_to_graph(%{
        label: label,
        unique_id: [item_num], #NOTE: Buttons don't start at zero, they start at 1... no sane person ever says "click on button zero" - sorry Tom.
        font: state.font,
        frame: %{
          pin: {(item_num-1)*(menu_width+@left_margin), 0}, #NOTE: Coordinates still start at zero though... #REMINDER: coords are like this, {x_coord, y_coord}
          size: {menu_width+@left_margin, height}
        },
        margin: @left_margin,
        hover_highlight?: do_hover_highlight?
      })
      |> do_render_main_menu_bar(state, frame, theme, rest_menu_map)
  end

  defp render_sub_menu_dropdowns(graph, _args, _sub_menu_dropdown_list = []) do
    graph # don't render any sub-menus if there's none to render
  end

  defp render_sub_menu_dropdowns(graph, args, sub_menu_dropdowns)
    when is_list(sub_menu_dropdowns) and length(sub_menu_dropdowns) >= 1 do

      {_w, menu_bar_height} = args.frame.size
      
      num_top_items = Enum.count(args.state.menu_map) # count how many top-level menu items
      {:fixed, menu_item_width} = args.state.item_width
      sub_menu_width = menu_item_width + num_top_items*@left_margin # make sub-menus wider, proportional to how many top-level items there are

      args = Map.merge(args, %{sub_menu_width: sub_menu_width})
    
      #NOTE: We can't translate entire sub-menus around, because we use the bounds/2
      # function to compute whether or not we're hovering over a button, and that
      # doesn't seem to support translating buttons around #TODO talk to Boyd about it
      graph |> Scenic.Primitives.group(
        fn graph ->
          graph
          |> do_render_sub_menu_dropdowns(args, sub_menu_dropdowns)
        end,
        id: :sub_menu_collection
      )
  end

  defp do_render_sub_menu_dropdowns(graph, _args, _sub_menu_dropdown_list = []) do
    graph # base case
  end
  
  defp do_render_sub_menu_dropdowns(graph, args, [{sub_menu_index, offsets, sub_menu_to_render}|rest_sub_menus]) do

    {:hover, [top_hover_index|_rest]} = args.state.mode
    num_menu_items = Enum.count(sub_menu_to_render)
    {:fixed, menu_item_width} = args.state.item_width

    carry_graph = graph
    |> Scenic.Primitives.group(
      fn graph ->
        {final_acc_graph, _final_index} =

          sub_menu_to_render
          |> Enum.reduce({graph, 1}, fn item, {graph, menu_item_index} ->

            # items which are in turn access to further sub-menus need a little triangle drawn on them
            {label, do_draw_sub_menu_triangle?} = case item do
              {label, _func} ->
                {label, false}
              {:sub_menu, label, _sub_menu_items} ->
                {label, true}
            end 

            new_graph = render_sub_menu_item(graph, args |> Map.merge(%{
              label: label,
              sub_menu_index: sub_menu_index,
              item_index: menu_item_index,
              offsets: offsets,
              draw_sub_menu_triangle?: do_draw_sub_menu_triangle?
            }))

            {new_graph, menu_item_index+1}
          end)

        # draw border around the sub-menu
        final_acc_graph
        |> Scenic.Primitives.rect(
          {args.sub_menu_width, num_menu_items*args.state.sub_menu.height}, # draw the border-box
            stroke: {2, args.theme.border},
            translate: {
              (top_hover_index-1)*menu_item_width + (offsets.x*args.sub_menu_width),
              args.frame.dimensions.height
        }) 
        #NOTE: This next line draw a "black" (or whatever color our menu bar background is)
        # over the top of the sub-menu border-box drawn above, so that instead of a completely
        # square border, we cover up the top-line of the border so that it blends in better
        # with the menu_bar itself (and overlap the edges a little bit)
        #NOTE: We can't set a negative x coordinate if it's the hard-left corner of the screen,
        # so we have this cute little hack to set the first item's line to zero - the others all
        # have a 2 pixel overlap on either side, this ensures the top-line of the border-box is completely invisible
        #TODO figure out whether or not this is a sub-menu sitting on the very top (offsets.y = 0) or if it's a sub menu hanging of the bottom
        |> Scenic.Primitives.line({{(if top_hover_index == 1, do: 0, else: -2),0},{args.sub_menu_width+2,0}}, stroke: {2, args.theme.active}, translate: {menu_item_width*(top_hover_index-1), args.frame.dimensions.height})

      end,
      id: {:dropdown, sub_menu_index}
    )

    do_render_sub_menu_dropdowns(carry_graph, args, rest_sub_menus)
  end

  defp render_sub_menu_item(graph, args) do

    {:hover, hover_index = [top_hover_index|_rest]} = args.state.mode

    {:fixed, menu_item_width} = args.state.item_width

    menu_item_frame = %{
      pin: {
        (top_hover_index-1)*menu_item_width + (args.offsets.x*args.sub_menu_width),
        args.frame.dimensions.height+(((args.item_index-1)+args.offsets.y)*args.state.sub_menu.height)
      },
      size: {args.sub_menu_width, args.state.sub_menu.height}
    }

          
    item_unique_id = args.sub_menu_index ++ [args.item_index]

    graph
    |> FloatButton.add_to_graph(%{
      label: args.label,
      unique_id: item_unique_id,
      font: args.sub_menu_font,
      frame: menu_item_frame,
      margin: @left_margin,
      draw_sub_menu_triangle?: args.draw_sub_menu_triangle?,
      hover_highlight?: item_unique_id == hover_index #TODO this_button_in_hover_chain?
    })    

  end

  defp calc_font_data(%{size: size, metrics: metrics}) do
    %{
      size: size,
      ascent: FontMetrics.ascent(size, metrics),
      descent: FontMetrics.descent(size, metrics),
      metrics: metrics
    }
  end

  defp calc_sub_menu_dropdowns(%{state: %{mode: :inactive}}) do
    [] # don't render any sub-menus if we're in :inactive mode
  end

  defp calc_sub_menu_dropdowns(%{state: %{mode: {:hover, [top_hover_index]}, menu_map: menu_map}}) do
    # this is the case of just rendering a single, first-level sub menu
    [{:sub_menu, _label, top_lvl_sub_menu}] = [Enum.at(menu_map, top_hover_index-1)]
    #NOTE: No offsets for a single menu, offsets only apply for sub-sub menus...
    [{_sub_menu_id = [top_hover_index], _offsets = %{x: 0, y: 0}, top_lvl_sub_menu}]
  end

  defp calc_sub_menu_dropdowns(%{state: %{mode: {:hover, hover_chain = [top_hover_index|_rest]}, menu_map: menu_map}} = args) do
    depth = Enum.count(hover_chain)

    # get the first menu in the chain by spoofing the call, as if we were simply hovering over one of the top menu-buttons
    [first_menu] = args
    |> put_in([:state, :mode], {:hover, [top_hover_index]})
    |> calc_sub_menu_dropdowns()

    # now call the recursive part, seeding the results (a lsit of lists/menus) with the one we've already calculated
    do_calc_sub_menu_dropdowns(args, [first_menu], hover_chain, {1, depth})
    # |> IO.inspect(label: "DROPDOWNSSS")
  end

  defp do_calc_sub_menu_dropdowns(_args, sub_menu_list, _hover_chain, {count, depth}) when count >= depth do
    sub_menu_list # base case, we've finished calculating the menus
  end

  defp do_calc_sub_menu_dropdowns(args, sub_menu_list, hover_chain, {count, depth}) do
    
    sub_menu_id = Enum.take(hover_chain, depth)
    Logger.debug "rendering a sub-sub menu... #{inspect sub_menu_id}"

    {:ok, hover_item} = fetch_item_at(args.state.menu_map, sub_menu_id)

    # check if we're hovering over a sub-menu...
    case hover_item do
      {_label, _func} ->
        # don't add any new sub-menus...
        do_calc_sub_menu_dropdowns(args, sub_menu_list, hover_chain, {count+1, depth})
      {:sub_menu, _label, new_sub_menu} ->
          next_menu = 
          #TODO calc real offsets somehow!!
          #NOTE: x_offset here tells us how many "menus" to the right to render our first sub-menu, e.g. if we hover over the 3rd top level menu item, move "2 menus over"
            [{sub_menu_id, %{x: 1, y: 0}, [{"new", &QuillEx.API.Buffer.new/0},{"new", &QuillEx.API.Buffer.new/0},{"new", &QuillEx.API.Buffer.new/0}]}]

          do_calc_sub_menu_dropdowns(args, sub_menu_list ++ next_menu, hover_chain, {count+1, depth})
    end
  end

  def fetch_item_at({:sub_menu, _label, sub_menu}, [x]) when is_list(sub_menu) and is_integer(x) do
    {:ok, Enum.at(sub_menu, x-1)}
  end

  def fetch_item_at(sub_menu, [x]) when is_list(sub_menu) and is_integer(x) do
    {:ok, Enum.at(sub_menu, x-1)}
  end

  def fetch_item_at(sub_menu, [x|rest]) when is_list(sub_menu) and is_integer(x) do
    next_menu = Enum.at(sub_menu, x-1)
    fetch_item_at(next_menu, rest)
  end

  def fetch_item_at({:sub_menu, _label, sub_menu}, [x|rest]) when is_list(sub_menu) and is_integer(x) do
    next_menu = Enum.at(sub_menu, x-1)
    fetch_item_at(next_menu, rest)
  end

end