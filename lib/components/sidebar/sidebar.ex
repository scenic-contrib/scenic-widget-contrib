defmodule ScenicWidgets.Sidebar do
  use Scenic.Component
  require Logger
  alias Scenic.{Graph, Primitives}

  @impl Scenic.Component
  def validate(%{frame: frame, items: items} = data) 
      when is_list(items) do
    # Validate frame is either our test format or Widget Workbench format
    frame_valid = case frame do
      %Widgex.Frame{pin: %Widgex.Structs.Coordinates{}, size: %Widgex.Structs.Dimensions{}} -> true
      %{__struct__: Widgex.Frame} -> true  # Our test format
      _ -> false
    end
    
    if frame_valid do
      {:ok, data}
    else
      :invalid_input
    end
  end
  def validate(data), do: {:error, "Sidebar requires a map with :frame and :items. Got: #{inspect(data)}"}
  
  @impl Scenic.Scene
  def init(scene, %{frame: frame, items: items}, _opts) do
    state = %{
      frame: frame,
      items: items,
      indent_width: 20,
      item_height: 32,
      expanded_nodes: MapSet.new()  # Track which nodes are expanded
    }
    
    graph = render(state)
    
    # Fix: assign and push_graph in correct order, return scene properly
    scene = assign(scene, state: state)
    scene = push_graph(scene, graph)
    
    # Request input for mouse clicks - this returns :ok, not the scene
    request_input(scene, [:cursor_button, :cursor_pos])
    
    {:ok, scene}
  end
  
  defp render(state) do
    # Extract dimensions from Widgex.Frame
    # Don't use pin for translation - let parent handle positioning
    {width, height} = case state.frame.size do
      %Widgex.Structs.Dimensions{width: w, height: h} -> {w, h}
      {w, h} -> {w, h}
    end
    
    Graph.build()
    |> Primitives.group(
      fn g ->
        # First add the background
        base_graph = g
        |> Primitives.rect({width, height}, 
            fill: {30, 31, 41}, id: :sidebar_bg, input: [:cursor_button])
        
        # render_items returns {graph, final_y}, so we need to extract just the graph
        {items_graph, _final_y} = render_items(base_graph, state.items, state, 0, 0, [])
        
        items_graph
      end,
      id: :sidebar_container,
      # Don't translate here - parent will position us
      input: [:cursor_button]  # Enable input for the entire group
    )
  end
  
  defp render_items(graph, items, state, depth, y, path) do
    {final_graph, final_y} = Enum.reduce(items, {graph, y}, fn item, {g, y_pos} ->
      current_path = path ++ [item.id]
      has_children = item[:children] && item.children != []
      expanded = MapSet.member?(state.expanded_nodes, item.id)
      x = depth * state.indent_width
      
      # Render item group with expand icon and text
      updated_graph = g
      |> Primitives.group(
        fn item_g ->
          item_g
          # Add invisible clickable background
          |> Primitives.rect(
            {get_width(state.frame) - x, state.item_height},
            fill: :clear,
            id: {:item_bg, current_path},
            input: [:cursor_button]
          )
          # Expand icon if has children
          |> then(fn ig ->
            if has_children do
              # Triangle pointing right (collapsed) or down (expanded)
              triangle_points = if expanded do
                # Down-pointing triangle
                {{x + 6, y_pos + 10}, {x + 14, y_pos + 10}, {x + 10, y_pos + 18}}
              else
                # Right-pointing triangle  
                {{x + 6, y_pos + 8}, {x + 6, y_pos + 20}, {x + 14, y_pos + 14}}
              end
              
              Primitives.triangle(ig, triangle_points,
                fill: {139, 141, 153},
                id: {:expand_icon, current_path},
                input: [:cursor_button]
              )
            else
              ig
            end
          end)
          # Item text
          |> Primitives.text(
            item.label,
            id: {:sidebar_text, current_path},
            translate: {x + (if has_children, do: 20, else: 10), y_pos + 20},
            fill: {248, 248, 242}
          )
        end,
        id: {:sidebar_item, current_path},
        input: [:cursor_button]  # Enable mouse input on this group
      )
      
      # Render children only if expanded
      if has_children && expanded do
        {child_graph, final_y} = render_items(updated_graph, item.children, state, depth + 1, 
                    y_pos + state.item_height, current_path)
        {child_graph, final_y}
      else
        {updated_graph, y_pos + state.item_height}
      end
    end)
    
    {final_graph, final_y}
  end
  
  # Helper to get width from frame structure
  defp get_width(frame) do
    case frame.size do
      %Widgex.Structs.Dimensions{width: w} -> w
      {w, _h} -> w
      width when is_number(width) -> width
    end
  end
  
  @impl Scenic.Scene  
  def handle_input(event, context, scene) do
    handle_input_internal(event, context, scene)
  end
  
  # Handle mouse clicks on sidebar items
  defp handle_input_internal({:cursor_button, {:btn_left, 0, _, _coords}}, ctx, scene) do
    # Handle both direct IDs and wrapped in context map
    case ctx do
      # Direct ID patterns
      {:expand_icon, path} ->
        handle_expand_click(scene, path)
        
      {:sidebar_item, path} ->
        handle_item_click(scene, path)
        
      {:item_bg, path} ->
        handle_item_click(scene, path)
        
      :sidebar_bg ->
        {:noreply, scene}
        
      # Wrapped in map with :id key
      %{id: {:expand_icon, path}} ->
        handle_expand_click(scene, path)
        
      %{id: {:sidebar_item, path}} ->
        handle_item_click(scene, path)
        
      %{id: {:item_bg, path}} ->
        handle_item_click(scene, path)
        
      %{id: :sidebar_bg} ->
        {:noreply, scene}
        
      _ ->
        {:noreply, scene}
    end
  end
  
  defp handle_input_internal(input, ctx, scene) do
    {:noreply, scene}
  end
  
  defp handle_item_click(scene, path) do
    # For now, just handle expand/collapse if the item has children
    handle_expand_click(scene, path)
  end
  
  defp handle_expand_click(scene, path) do
    %{state: state} = scene.assigns
    item_id = List.last(path)
    
    # Find the item to check if it has children
    item = find_item_by_path(path, state.items)
    
    if item && item[:children] && item.children != [] do
      # Toggle expansion state
      new_expanded = if MapSet.member?(state.expanded_nodes, item_id) do
        MapSet.delete(state.expanded_nodes, item_id)
      else
        MapSet.put(state.expanded_nodes, item_id)
      end
      
      new_state = %{state | expanded_nodes: new_expanded}
      new_graph = render(new_state)
      
      scene
      |> assign(state: new_state)
      |> push_graph(new_graph)
      |> then(&{:noreply, &1})
    else
      {:noreply, scene}
    end
  end
  
  defp find_item_by_path([id], items) do
    Enum.find(items, fn item -> item.id == id end)
  end
  
  defp find_item_by_path([head | tail], items) do
    case Enum.find(items, fn item -> item.id == head end) do
      nil -> nil
      item -> 
        if item[:children] do
          find_item_by_path(tail, item.children)
        else
          nil
        end
    end
  end
end
