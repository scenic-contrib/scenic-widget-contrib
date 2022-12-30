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
      # state: %{
      #    label: _label,
      #    level: _level,
      #    is_node?: _is_node?,
      #    open?: _open?, 
      #    font: _font
      # }
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

   def render(frame, %{item: {:leaf, label}} = state, theme) do

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

   def render(frame, %{item: {:node, label, _sub_menu}} = state, theme) do
      
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

         new_graph = scene.assigns.graph
         |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: scene.assigns.theme.active))

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
            %{item: {:leaf, _label}} ->
               cast_parent(scene, {:click, scene.assigns.id, scene.assigns.state.func})
            %{item: {:node, _label, _sub_menu}} ->
               cast_parent(scene, {:open_node, scene.assigns.id})
         end
      end

      {:noreply, scene}
   end
  
   def handle_input(_input, _context, scene) do
      # Logger.debug "#{__MODULE__} ignoring input: #{inspect input}..."
      {:noreply, scene}
   end
  
end
  