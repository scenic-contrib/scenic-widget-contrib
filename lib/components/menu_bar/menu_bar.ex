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


  @doc """
  Return a list of all the zero-arity functions in a module, in
  the correctly formatted list of `{label, function}` tuples for
  injecting into a GUI.Component.MenuBar menu-map.
  """
  def zero_arity_functions("Elixir." <> module_name) when is_bitstring(module_name) do
    #NOTE: Because we automatically add Elixir. to the start of the module
    # (which we need to do in order to get `String.to_atom` to convert it
    # cleanly into a proper module name), we need to also strip it out
    # first if it already exists to cover all cases :facepalm:
    zero_arity_functions(module_name)
  end

  def zero_arity_functions(module_name) when is_bitstring(module_name) do
    "Elixir." <> module_name
    |> String.to_atom()
    |> zero_arity_functions()
  end

  def zero_arity_functions(module) when is_atom(module) do
    module.__info__(:functions)
    |> Enum.filter(fn {_exported_fn, arity} -> arity == 0 end)
    |> Enum.map(fn {exported_fn, _arity = 0} -> exported_fn end)
    |> Enum.map(fn exported_fn -> {Atom.to_string(exported_fn), fn ->
        #NOTE: When we execute one of these zero-arity functions,
        # it happens within the context/process of the MenuBar.
        # This means that any zero-arity function which is designed
        # to return an item (usually for use in the CLI) will return
        # that item, and it will get swallowed inside this context,
        # effectively achieving nothing. I put this IO.inspect here
        # so that we can at least see the results on the CLI even it
        # we can't use them.
        apply(module, exported_fn, [])
        |> IO.inspect(label: "#{Atom.to_string(exported_fn)}")
      end} end)
  end

  @doc """
  Construct a tree of zero-arity functions grouped by their modules,
  including constructing nested sub-menus based on a typical namespacing
  convention for Elixir modules. Returns a correctly formatted list of
  sub-menus (in the form `{:sub_menu, label, menu}`) and zero-arity
  functions (in the form `{label, function}`) for building sub-menu trees
  that can be injected into a GUI.Component.MenuBar menu-map.

  To filter from the list of all possible modules, we have to give it
  a string which is what all the modules in the sub-menu tree start with,
  e.g. "Elixir.Flamelex.API"

  Note that this function only works with Elixir modules, not Erlang ones.
  """
  def modules_and_zero_arity_functions(modules_start_with) when is_bitstring(modules_start_with) do

    split_base_module =
      Module.split(modules_start_with)
    base_depth =
      Enum.count(split_base_module)

    modules =
      :code.all_available()
      |> Enum.map(fn {module, _filename, _loaded?} -> module end)
      |> Enum.filter(fn module -> String.starts_with?("#{module}", modules_start_with) end)
      |> Enum.map(& to_string(&1))

    split_modules =
      modules
      |> Enum.map(& Module.split(&1))

    # get all the sub-menus in the level below this one
    {_module_depth, top_lvl_sub_menu} =
      split_modules
      |> Enum.group_by(& Enum.count(&1))
      |> Enum.find(fn {depth, _sub_menu} -> depth == base_depth+1 end)
    
    sub_menu_tree_result =
      top_lvl_sub_menu
      |> Enum.map(&calc_lower_sub_menu(&1, split_modules))
      |> Enum.reject(& &1 == :no_children)

    #NOTE: we check this cause we don't want to call `zero_arity_functions(modules_start_with)`
    # if the module doesn't exist, or it will crash!
    if Enum.member?(modules, modules_start_with) do
      sub_menu_tree_result ++ zero_arity_functions(modules_start_with)
    else
      # no need to get extra functions from the base module, just return the sub-menus
      sub_menu_tree_result
    end
  end

  def calc_lower_sub_menu(top_item, modules) do
    next_depth = Enum.count(top_item)+1
    module_name = Enum.reduce(top_item, fn x, acc -> acc <> "." <> x end) # convert a list like ["Module", "By", "Luke"] to a string, "Module.By.Luke"

    #NOTE: It's this step which causes the recusrion to bottom-out.
    # the increasing size of the sub-modules means we eventually
    # get an empty list when we filter on items which are a level deeper
    sub_modules =
      modules
      |> Enum.filter(&Enum.count(&1) == next_depth)
      |> Enum.filter(fn l -> List.starts_with?(l, top_item) end)

    this_sub_menu =
        Enum.map(sub_modules, fn sub_mod ->
          calc_lower_sub_menu(sub_mod, modules)
        end)
        |> Enum.reject(& &1 == :no_children)

    these_zero_arity_functions = zero_arity_functions(module_name)
    
    if this_sub_menu == [] and these_zero_arity_functions == [] do
      :no_children
    else
      label = List.last(top_item)
      {:sub_menu, label, this_sub_menu ++ these_zero_arity_functions}
    end
  end

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

  #NOTE: `hover_index` is a list, starting with the top-level items.
  # e.g. hovering over the first item in the menubar would be [1], then
  # hovering over the third sub-item beneath that menu would be [1, 3]
  def handle_cast({:hover, _hover_index} = new_mode, scene) do
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

  def handle_cast({:click, [_top_ii]}, scene) do
    {:noreply, scene} # just do nothing when we simply click on a top menu bar
  end

  def handle_cast({:click, [top_ii|rest_click_coords]}, %{assigns: %{state: state}} = scene) do

    {:sub_menu, _label, sub_menu} = state.menu_map |> Enum.at(top_ii - 1)
    
    {:ok, clicked_item, _y_offset} = sub_menu |> fetch_item_at(rest_click_coords)
    
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

  def handle_input({:key, {_key, _dont_care, _dont_care_either}}, _context, scene) do
    #Logger.debug("#{__MODULE__} ignoring key: #{inspect(key)}")
    {:noreply, scene}
  end

  def render(%{state: state} = args) do

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
    frame = %{size: {_width, height}},
    theme,
    [{label, item_num}|rest_menu_map]
  ) do

      do_hover_highlight? =
        case mode do
          :inactive ->
            false
          {:hover, [x]} ->
            x == item_num # test if the first item in the hover-chain is this top-level menu item
          {:hover, [_x|_rest]} ->
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

      # {_w, menu_bar_height} = args.frame.size
      
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
              args.frame.dimensions.height + (offsets.y*args.state.sub_menu.height)
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

  defp calc_sub_menu_dropdowns(%{state: %{mode: {:hover, hover_chain = [top_hover_index|_rest]}}} = args) do
    depth = Enum.count(hover_chain)

    # get the first menu in the chain by spoofing the call, as if we were simply hovering over one of the top menu-buttons
    [first_menu] = args
    |> put_in([:state, :mode], {:hover, [top_hover_index]})
    |> calc_sub_menu_dropdowns()

    # now call the recursive part, seeding the results (a lsit of lists/menus) with the one we've already calculated
    do_calc_sub_menu_dropdowns(args, [first_menu], hover_chain, {1, depth, _y_offset_carry = 0})
  end

  defp do_calc_sub_menu_dropdowns(_args, sub_menu_list, _hover_chain, {count, depth, _y_offset_carry}) when count >= depth do
    sub_menu_list # base case, we've finished calculating the menus
  end

  defp do_calc_sub_menu_dropdowns(args, sub_menu_list, hover_chain, {count, depth, y_offset_carry}) do
    
    sub_menu_id = Enum.take(hover_chain, count+1)
    Logger.debug "rendering a sub-sub menu... #{inspect sub_menu_id}"

    #NOTE: so the way y_offset_carry works is, we can get the
    # y_offset for each menu, but for sub-sub menus we need to keep
    # track of the y offset at _each_ level of the sub menus
    {:ok, hover_item, this_y_offset} = fetch_item_at(args.state.menu_map, sub_menu_id)
    new_y_offset = y_offset_carry+this_y_offset

    # check if we're hovering over a sub-menu...
    case hover_item do
      {_label, _func} ->
          # don't add any new sub-menus...
          do_calc_sub_menu_dropdowns(args, sub_menu_list, hover_chain, {count+1, depth, new_y_offset})
      # {:sub_menu, _label, _new_sub_menu = []} ->
          # # this sub-menu is empty, so don't add one here, else it draws a "border" around the empty menu
          # do_calc_sub_menu_dropdowns(args, sub_menu_list, hover_chain, {count+1, depth, new_y_offset})
      {:sub_menu, label, new_sub_menu} ->
          #NOTE: Although it looks buggy to draw the border around this empty menu,
          # it also looks buggy having a drop-down side arrow and then showing nothing...
          # I think it's actually better to render the empty menu, since this makes the bug
          # (which lies in whoever set up the menu-map, not in this rendering code) more obvious
          # If we want to change this, uncomment the case above this one
          if new_sub_menu == [] do
            Logger.warn "#{__MODULE__} menu `#{label}` is an empty sub-menu."
          end

          #NOTE: x_offset here tells us how many "menus" to the right to
          # render our first sub-menu, e.g. if we hover over the 3rd top
          # level menu item, move "2 menus over". `y_offset` tells us how
          # many levels "down" to move each menu
          next_menu = [{sub_menu_id, %{x: count, y: new_y_offset}, new_sub_menu}]
          do_calc_sub_menu_dropdowns(args, sub_menu_list ++ next_menu, hover_chain, {count+1, depth, new_y_offset})
    end
  end

  def fetch_item_at({:sub_menu, _label, sub_menu}, [x]) when is_list(sub_menu) and is_integer(x) do
    {:ok, Enum.at(sub_menu, x-1), x-1}
  end

  def fetch_item_at(sub_menu, [x]) when is_list(sub_menu) and is_integer(x) do
    {:ok, Enum.at(sub_menu, x-1), x-1}
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