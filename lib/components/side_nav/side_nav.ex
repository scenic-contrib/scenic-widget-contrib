defmodule ScenicWidgets.SideNav do
   use Scenic.Component
   require Logger
   # alias ScenicWidgets.MenuBar.FloatButton
   alias ScenicWidgets.Core.Structs.Frame
   # use ScenicWidgets.ScenicEventsDefinitions


   @item_height 50 # how tall each menu item is #TODO pass it in as a config
   @item_indent 25 # how far we indent sub-menus


   def validate(%{
      frame: %Frame{} = _f,      # The %Frame{} struct describing the rectangular size & placement of the component
      state: _nav_tree           # A list containing the contents of the Menu, and what functions to call if that item gets clicked on
   } = data) do
      {:ok, data}
   end
  
   def init(scene, args, opts) do
      # Logger.debug("#{__MODULE__} initializing...")

      id = opts[:id] || raise "#{__MODULE__} must receive `id` via opts."

      theme =
         (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
         |> Scenic.Primitive.Style.Theme.normalize()

      init_graph = render(args.frame, args.state)

      init_scene =
         scene
         |> assign(id: id)
         |> assign(state: args.state)
         |> assign(graph: init_graph)
         |> assign(frame: args.frame)
         |> assign(theme: theme)
         |> push_graph(init_graph)

      {:ok, init_scene}
   end

   def handle_cast({:state_change, new_state}, scene) do

      new_graph = render(scene.assigns.frame, new_state)

      new_scene = scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)
   
      {:noreply, new_scene}
   end

   def handle_cast({:click, {:leaf, label, index, click_fn}}, scene) do
      click_fn.()
      {:noreply, scene}
   end

   def handle_cast({:open_node, node}, scene) do
      # IO.inspect(node, label: "OPENING NODE")
      new_state = scene.assigns.state |> open_node(node)
      GenServer.cast(self(), {:state_change, new_state})
      {:noreply, scene}
   end

   def handle_cast({:close_node, index}, scene) do
      IO.puts "CLOSING NODE #{inspect index}"
      new_state = scene.assigns.state |> close_node(index)
      GenServer.cast(self(), {:state_change, new_state})
      {:noreply, scene}
   end

   def render(%Frame{} = frame, state) do
      Scenic.Graph.build()
      |> Scenic.Primitives.group(
         fn graph ->
            graph
            |> Scenic.Primitives.rect(frame.size, fill: :gold)
            |> render_file_tree(frame, state)
         end,
         translate: frame.pin
      )
   end

   def render_file_tree(graph, frame, tree) when is_list(tree) do
      {final_graph, _final_offsets} = do_render_file_tree(graph, frame, tree, {0, 0}) # Start at level 0, as this is the top level item, we increment it on the first iteration so the first index is 1
      final_graph
   end

   def do_render_file_tree(graph, _frame, [], offsets) do
      {graph, offsets} # base case
   end

   def do_render_file_tree(graph, outer_frame, [{:open_node, label, index, sub_tree} = item|rest], {x_offset, y_offset}) do
      # the x_offset is how far we move this item to the right, it's a function
      # of how deep we are in the menu tree, i.e. how many offsets we have
      # x_offset = length(offsets) - 1

      # the y_offset is how far down we move this item, and it's a function
      # of how many items are above this one in the menu
      # y_offset = Enum.sum(offsets)

      new_graph = graph
      |> ScenicWidgets.SideNav.Item.add_to_graph(%{
         frame: calc_item_frame(outer_frame, y_offset),
         state: %{
            item: item,
            offsets: %{
               x: x_offset,
               y: y_offset
            },
            font: font() 
         }
      }, id: {label, index})

      # because this is an open node, we need to recursively render the sub-menu
      # we need to keep track of the y-offset to push down further menu items, but we can discard the x offset for lower levels
      {opened_node_graph, {_sub_x_offset, new_y_offset}} = 
         do_render_file_tree(new_graph, outer_frame, sub_tree, {x_offset+1, y_offset+1}) # add another level of offsets, because we just went down a level
      
      # update the last item in the list by incrementing it
      # [last_offset|other_reversed_offsets] = Enum.reverse(offsets)
      # new_offsets = Enum.reverse([last_offset+1|other_reversed_offsets])

      do_render_file_tree(opened_node_graph, outer_frame, rest, {x_offset, new_y_offset})
   end

   def do_render_file_tree(graph, outer_frame, [item|rest], {x_offset, y_offset}) do

      # extract label & index for use in the SideNav.Item `:id`
      {_node_type, label, index, _other_stuff} = item

      # the x_offset is how far we move this item to the right, it's a function
      # of how deep we are in the menu tree, i.e. how many offsets we have
      # x_offset = length(offsets) - 1

      # the y_offset is how far down we move this item, and it's a function
      # of how many items are above this one in the menu
      # y_offset = Enum.sum(offsets)

      new_graph = graph
      |> ScenicWidgets.SideNav.Item.add_to_graph(%{
         frame: calc_item_frame(outer_frame, y_offset),
         state: %{
            item: item,
            offsets: %{
               x: x_offset,
               y: y_offset
            },
            font: font() 
         }
      }, id: {label, index})
      
      # update the last item in the list by incrementing it
      # [last_offset|other_reversed_offsets] = Enum.reverse(offsets)
      # new_offsets = Enum.reverse([last_offset+1|other_reversed_offsets])

      do_render_file_tree(new_graph, outer_frame, rest, {x_offset, y_offset+1})
   end

   def calc_item_frame(%{dimens: %{width: frame_w}}, y_offset) do
      # {x_offset*@item_indent, y_offset*@item_height}
      Frame.new(pin: {0, y_offset}, size: {frame_w, @item_height})
   end

   def open_node(nav_tree, {:closed_node, label, index, sub_tree}) do
      # node_to_open = {:closed_node, ^label, ^index} = do_extract_node_from_tree(nav_tree, index)
      do_put_node(nav_tree, {:open_node, label, index, sub_tree}, index)
      |> IO.inspect(label: "NEW TREE AFTER OPEN")
   end

   def close_node(nav_tree, {:open_node, label, index, sub_tree}) do
      # node_to_open = {:closed_node, ^label, ^index} = do_extract_node_from_tree(nav_tree, index)
      do_put_node(nav_tree, {:closed_node, label, index, sub_tree}, index)
   end

   def do_extract_node_from_tree(nav_tree, [ii]) do
      Enum.at(nav_tree, ii-1)
   end

   def do_extract_node_from_tree(nav_tree, [ii|rest]) do
      do_extract_node_from_tree(Enum.at(nav_tree, ii-1), rest)
   end

   def do_put_node(nav_tree, item, [ii]) when is_list(nav_tree) do
      List.update_at(nav_tree, ii-1, fn(_old_item) -> item end)
   end

   def do_put_node(nav_tree, item, [ii|rest] = _index) when is_list(nav_tree) do
      # dbg()
      List.update_at(nav_tree, ii-1, fn
         {node, label, index, sub_tree} ->
            new_sub_tree = do_put_node(sub_tree, item, rest)
            {node, label, index, new_sub_tree}
      end)
   end

   defp font do
      {:ok, ibm_plex_mono_metrics} =
         TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

      font = %{
         name: :ibm_plex_mono,
         size: 24,
         metrics: ibm_plex_mono_metrics
      }
   end
end
