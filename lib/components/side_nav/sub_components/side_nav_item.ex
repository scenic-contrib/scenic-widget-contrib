defmodule ScenicWidgets.SideNav.Item do
   @moduledoc """
   This module is really not that different from a normal Scenic Button,
   just customized a little bit.
   """
   use Scenic.Component
   alias alias ScenicWidgets.Core.Structs.Frame
   require Logger
  

   @item_height 50 # how tall each menu item is #TODO pass it in as a config
   @item_indent 32 # how far we indent sub-menus

  
   def validate(%{
      frame: %Frame{} = _frame,
      state: _state
   } = data) do
      # Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
      {:ok, data}
   end
  
   def init(scene, args, opts) do
      # Logger.debug "#{__MODULE__} initializing..."
  
      id = opts[:id] || raise "#{__MODULE__} must receive `id` via opts."

      theme =
         (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
         |> Scenic.Primitive.Style.Theme.normalize()
  
      init_graph = render(args.frame, args.state, theme)
  
      init_scene =
         scene
         |> assign(id: id)
         |> assign(graph: init_graph)
         |> assign(frame: args.frame)
         |> assign(state: args.state)
         |> assign(theme: theme)
         |> push_graph(init_graph)
  
      request_input(init_scene, [:cursor_pos, :cursor_button])
  
      {:ok, init_scene}
    end
  
    def bounds(%{frame: %{pin: {top_left_x, top_left_y}, size: {width, height}}}, _opts) do
      # NOTE: Because we use this bounds/2 function to calculate whether or
      # not the mouse is hovering over any particular button, we can't
      # translate entire groups of sub-menus around. We ned to explicitely
      # draw buttons in their correct order, and not translate them around,
      # because bounds/2 doesn't seem to work correctly with translated elements
      # TODO talk to Boyd and see if I'm wrong about this, or maybe we can improve Scenic to work with it
      left = top_left_x
      right = top_left_x + width
      top = top_left_y
      bottom = top_left_y + height
      {left, top, right, bottom}
    end

   def render(frame, %{item: {:leaf, label, index, click_fn}} = state, theme) do

      v_pos = ScenicWidgets.TextUtils.v_pos(state.font)

      Scenic.Graph.build()
      |> Scenic.Primitives.group(
         fn graph ->
            graph
            |> Scenic.Primitives.rect(
               {
                  frame.dimens.width-(state.offsets.x*@item_indent),
                  @item_height
               },
               id: :background,
               fill: theme.active
            )
            |> Scenic.Primitives.rect(frame.size,
               stroke: {1, :black}
            )
            |> Scenic.Primitives.text(label,
               fill: theme.text,
               font: state.font.name,
               font_size: state.font.size,
               translate: {@item_indent, (@item_height/2)+v_pos}
               # translate: {10, ScenicWidgets.TextUtils.v_pos(font)}
            )
         end,
         translate: {state.offsets.x*@item_indent, state.offsets.y*@item_height}
      )
   end

   def render(frame, %{item: {:open_node, label, index, sub_tree}} = state, theme) do
      
      v_pos = ScenicWidgets.TextUtils.v_pos(state.font)

      Scenic.Graph.build()
      |> Scenic.Primitives.group(
         fn graph ->
            graph
            |> Scenic.Primitives.rect(
               {
                  frame.dimens.width-(state.offsets.x*@item_indent),
                  @item_height
               },
               id: :background,
               # fill: theme.active
               fill: :red
            )
            |> Scenic.Primitives.rect(frame.size,
               stroke: {1, :black}
            )
            |> Scenic.Primitives.rect({32, 32}, fill: {:image, "ionicons/white_32_outline/chevron-forward.png"}, translate: {12, (@item_height-32)/2})
            |> Scenic.Primitives.text(label,
               fill: theme.text,
               font: state.font.name,
               font_size: state.font.size,
               translate: {2*@item_indent, (@item_height/2)+v_pos}
            )
         end,
         translate: {state.offsets.x*@item_indent, state.offsets.y*@item_height}
      )
   end

   def render(frame, %{item: {:closed_node, label, index, sub_tree}} = state, theme) do
      
      v_pos = ScenicWidgets.TextUtils.v_pos(state.font)

      Scenic.Graph.build()
      |> Scenic.Primitives.group(
         fn graph ->
            graph
            |> Scenic.Primitives.rect(
               {
                  frame.dimens.width-(state.offsets.x*@item_indent),
                  @item_height
               },
               id: :background,
               fill: theme.active
            )
            |> Scenic.Primitives.rect(frame.size,
               stroke: {1, :black}
            )
            |> Scenic.Primitives.rect({32, 32}, fill: {:image, "ionicons/white_32_outline/chevron-forward.png"}, translate: {12, (@item_height-32)/2})
            |> Scenic.Primitives.text(label,
               fill: theme.text,
               font: state.font.name,
               font_size: state.font.size,
               translate: {2*@item_indent, (@item_height/2)+v_pos}
               # translate: {10, ScenicWidgets.TextUtils.v_pos(font)}
            )
         end,
         translate: {state.offsets.x*@item_indent, state.offsets.y*@item_height}
      )
   end

   def handle_input({:cursor_pos, {_x, _y} = coords}, _context, scene) do
      bounds = Scenic.Graph.bounds(scene.assigns.graph)

      if coords |> ScenicWidgets.Utils.inside?(bounds) do

         new_graph = scene.assigns.graph
         |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: scene.assigns.theme.highlight))

         new_scene = scene
         |> assign(graph: new_graph)
         |> push_graph(new_graph)

         # cast_parent(scene, {:hover, scene.assigns.state.id})

         {:noreply, new_scene}
      else

         fill_color = 
            case scene.assigns.state.item do
               {:open_node, _, _, _sub_tree} ->
                  :red
               otherwise ->
                  IO.inspect otherwise
                  scene.assigns.theme.active
            end

         new_graph = scene.assigns.graph
         |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: fill_color))

         new_scene = scene
         |> assign(graph: new_graph)
         |> push_graph(new_graph)

         {:noreply, scene}
      end
   end
  
   def handle_input({:cursor_button, {:btn_left, 0, [], click_coords}}, _context, scene) do
      bounds = Scenic.Graph.bounds(scene.assigns.graph)

      if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
         case scene.assigns.state do
            %{item: {:leaf, _label, index, click_fn} = item} ->
               cast_parent(scene, {:click, item})
            %{item: {:closed_node, _label, index, _sub_tree} = item} ->
               cast_parent(scene, {:open_node, item})
            %{item: {:open_node, _label, index, _sub_tree} = item} ->
               cast_parent(scene, {:close_node, item})
         end
      end

      {:noreply, scene}
   end
  
   def handle_input(_input, _context, scene) do
      # Logger.debug "#{__MODULE__} ignoring input: #{inspect input}..."
      {:noreply, scene}
   end
  
end







   # def do_render_file_tree(graph, frame, [{:node, label, tree_branch}|rest], offsets) do
   #    # # here we have bottomed-out on a leaf-node, so we just render it

   #    # # the x_offset is how far we move this item to the right, it's a function
   #    # # of how deep we are in the menu tree, i.e. how many offsets we have
   #    # x_offset = length(offsets) - 1

   #    # # the y_offset is how far down we move this item, and it's a function
   #    # # of how many items are above this one in the menu
   #    # y_offset = Enum.sum(offsets)

   #    # new_graph = graph
   #    # |> Scenic.Primitives.rect(
   #    #     {
   #    #         frame.dimens.width-(x_offset*@item_indent),
   #    #         @item_height
   #    #     },
   #    #     fill: :gray,
   #    #     translate: {x_offset*@item_indent, y_offset*@item_height}
   #    # )
   #    # |> Scenic.Primitives.text(label,
   #    #     fill: :red,
   #    #     translate: {x_offset*@item_indent, y_offset*@item_height+ScenicWidgets.TextUtils.v_pos(font)}
   #    # )

   #    # # update the last item in the list by incrementing it
   #    # new_offsets = offsets

   #    # do_render_file_tree(new_graph, frame, rest, new_offsets)

   #    IO.puts "IGNORING NODE #{inspect label}"
   #    do_render_file_tree(graph, frame, rest, offsets)
   # end


   # def do_render_file_tree(graph, frame, [{:leaf, _label} = item|rest] = _tree, offsets) do


   #     {new_graph, new_offsets} =
   #         graph
   #         |> do_render_file_tree(frame, item, offsets)

   #     do_render_file_tree(new_graph, frame, rest, new_offsets)

   #     # graph
   #     # |> Scenic.Primitives.group(
   #     #     fn group_graph ->

   #     #         {final_graph, _final_offset} = 
   #     #             Enum.reduce(tree, {group_graph, 0}, fn item, {acc_graph, offset} ->

   #     #                 # {:leaf, label} = item

   #     #                 new_graph =
   #     #                     acc_graph
   #     #                     |> render_nav_tree_item(item, offset)

   #     #                 {new_graph, offset+1}
   #     #             end)

   #     #         final_graph
   #     # #     end,
   #     # #     id: {:tree_menu, offsets}
   #     # # )
   # end

   # def render_nav_tree_item(graph, {:node, item, _sub_items}, offset) when is_bitstring(item) do
      
   #     # font = 

   #     graph
   #     # |> Scenic.Primitives.group(
   #     #     fn graph ->
   #     #         graph
   #     |> Scenic.Primitives.rect({20*offset, 20},
   #         # id: :background,
   #         # fill: if(args.hover_highlight?, do: theme.highlight, else: theme.active)
   #         fill: :yellow,
   #         t: {200, 100}
   #     )
   #     |> Scenic.Primitives.text(item,
   #         # id: :label,
   #         # font: args.font.name,
   #         # font_size: args.font.size,
   #         translate: {150, (50*offset)+ScenicWidgets.TextUtils.v_pos(font())},
   #         fill: :red
   #         # fill: theme.text
   #     )
   #     #     end,
   #     #     # id: {:nav_tree_iterm, args.unique_id},
   #     #     translate: {72*offset, 0}
   #     # )
   # end

   # def render_leaf(graph, {:leaf, label}, offset) when is_bitstring(label) do
   #     graph
   #     |> Scenic.Primitives.rect({20*offset, 20},
   #         # id: :background,
   #         # fill: if(args.hover_highlight?, do: theme.highlight, else: theme.active)
   #         fill: :yellow,
   #         t: {200, 100}
   #     )
   #     |> Scenic.Primitives.text(label,
   #         translate: {150, (50*offset)+ScenicWidgets.TextUtils.v_pos(font)},
   #         fill: :white
   #     )
   # end
