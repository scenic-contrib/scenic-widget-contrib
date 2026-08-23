# Scenic Sidebar Component - Technical Implementation Report

## Overview

This report provides the complete implementation path for a hierarchical sidebar component using Spex-Driven Development. Each phase includes working code that builds upon the previous phase.

---

## Phase 1: Basic Structure & Rendering

### Goal
Create the foundational component that can render hierarchical items with proper indentation.

### Spex File: `phase1_basic_structure_spex.exs`

```elixir
defmodule Flamelex.GUI.Component.Sidebar.BasicStructureSpex do
  use SexySpex
  
  spex "Basic Sidebar Structure" do
    scenario "Component renders simple items", context do
      given_ "sidebar with flat items", context do
        items = [
          %{id: :file, label: "File", children: []},
          %{id: :edit, label: "Edit", children: []}
        ]
        # ... render sidebar
      end
      
      then_ "items are visible", context do
        assert ScriptInspector.rendered_text_contains?("File")
        assert ScriptInspector.rendered_text_contains?("Edit")
      end
    end
  end
end
```

### Implementation

#### 1. Main Component (`sidebar.ex`)

```elixir
defmodule Flamelex.GUI.Component.Sidebar do
  use Scenic.Component
  alias Scenic.{Graph, Primitives}
  
  @impl Scenic.Component
  def validate(%{frame: %Widgex.Frame{}, items: items} = data) 
      when is_list(items) do
    {:ok, data}
  end
  def validate(_), do: :invalid_input
  
  def add_to_graph(graph, data) do
    case validate(data) do
      {:ok, valid} -> 
        Primitives.component(graph, __MODULE__, valid, id: data[:id] || :sidebar)
      :invalid_input -> 
        raise ArgumentError, "Invalid sidebar data"
    end
  end
  
  @impl Scenic.Component
  def init(scene, %{frame: frame, items: items}, _opts) do
    state = %{
      frame: frame,
      items: items,
      indent_width: 20,
      item_height: 32
    }
    
    graph = render(state)
    
    scene
    |> assign(state: state)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end
  
  defp render(state) do
    Graph.build()
    |> Primitives.group(
      fn g ->
        g
        |> rect({state.frame.width, state.frame.height}, 
            fill: {30, 31, 41}, id: :sidebar_bg)
        |> render_items(state.items, state, 0, 0, [])
      end,
      id: :sidebar_container,
      translate: {state.frame.left, state.frame.top}
    )
  end
  
  defp render_items(graph, items, state, depth, y, path) do
    Enum.reduce(items, {graph, y}, fn item, {g, y_pos} ->
      current_path = path ++ [item.id]
      
      # Render item
      g = g
      |> Primitives.text(
        item.label,
        id: {:sidebar_item, current_path},
        translate: {depth * state.indent_width + 10, y_pos + 20},
        fill: {248, 248, 242}
      )
      
      # Render children
      if item[:children] && item.children != [] do
        render_items(g, item.children, state, depth + 1, 
                    y_pos + state.item_height, current_path)
      else
        {g, y_pos + state.item_height}
      end
    end)
    |> elem(0)
  end
end
```

---

## Phase 2: Expand/Collapse Functionality

### Goal
Add expand/collapse icons and functionality. Items with children start collapsed.

### Spex Focus
- Expand icons appear for items with children
- Clicking icon toggles visibility
- Children are hidden when parent collapsed

### Key Changes

```elixir
# Add to state
%{
  expanded_nodes: MapSet.new(),  # Track which nodes are expanded
}

# Update render_item to include expand icon
defp render_item(graph, item, state, depth, y, path) do
  has_children = item[:children] && item.children != []
  expanded = MapSet.member?(state.expanded_nodes, item.id)
  x = depth * state.indent_width
  
  graph
  |> Primitives.group(
    fn g ->
      g
      # Expand icon if has children
      |> then(fn g ->
        if has_children do
          triangle(g, {{x + 4, 12}, {x + 12, 16}, {x + 4, 20}},
            fill: {139, 141, 153},
            id: {:expand_icon, path},
            rotate: if(expanded, do: :math.pi/2, else: 0),
            pin: {x + 8, 16}
          )
        else
          g
        end
      end)
      # Item text
      |> text(item.label, 
          translate: {x + (if has_children, do: 20, else: 10), 20},
          fill: {248, 248, 242})
    end,
    id: {:sidebar_item, path},
    translate: {0, y},
    # KEY: Use input style for mouse events!
    input: [:cursor_button]
  )
end

# Add input handler
def handle_input({:cursor_button, {:btn_left, 0, _, _}}, ctx, scene) do
  %{state: state} = scene.assigns
  
  # Find what was clicked
  case ctx.id do
    {:expand_icon, path} ->
      item_id = List.last(path)
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
      
    _ -> {:noreply, scene}
  end
end
```

---

## Phase 3: Mouse Interaction & Hover

### Goal
Add hover highlighting and item selection without blocking other components.

### Key Implementation

```elixir
# Add to state
%{
  hover_path: nil,
  selected_path: nil
}

# Add hover handler (input style already set)
def handle_input({:cursor_pos, _}, ctx, scene) do
  case ctx.id do
    {:sidebar_item, path} ->
      update_hover(scene, path)
    _ ->
      clear_hover(scene)
  end
end

# Efficient hover update
defp update_hover(scene, path) do
  %{state: state, graph: graph} = scene.assigns
  
  if state.hover_path != path do
    # Only update the changed items
    new_graph = graph
    |> update_item_style(state.hover_path, :normal)
    |> update_item_style(path, :hover)
    
    scene
    |> assign(state: %{state | hover_path: path})
    |> push_graph(new_graph)
  end
  
  {:noreply, scene}
end

defp update_item_style(graph, nil, _), do: graph
defp update_item_style(graph, path, style) do
  color = case style do
    :hover -> {45, 47, 62}
    :selected -> {88, 91, 112}
    _ -> {30, 31, 41}
  end
  
  Graph.modify(graph, {:item_bg, path}, &fill(&1, color))
end
```

---

## Phase 4: Keyboard Navigation

### Goal
Enable full keyboard control: arrows to navigate, left/right to collapse/expand.

### Implementation

```elixir
# In init - keyboard needs global capture
request_input(scene, [:key])

# Keyboard handler
def handle_input({:key, {key, :press, _}}, _ctx, scene) do
  case key do
    "down" -> navigate_next(scene)
    "up" -> navigate_previous(scene)
    "right" -> expand_current(scene)
    "left" -> collapse_current(scene)
    "return" -> activate_current(scene)
    _ -> {:noreply, scene}
  end
end

defp get_visible_items(state) do
  flatten_visible(state.items, [], state.expanded_nodes)
end

defp flatten_visible(items, path, expanded) do
  Enum.flat_map(items, fn item ->
    current = path ++ [item.id]
    base = [{current, item}]
    
    if item[:children] && MapSet.member?(expanded, item.id) do
      base ++ flatten_visible(item.children, current, expanded)
    else
      base
    end
  end)
end
```

---

## Phase 5: Scrolling & Performance

### Goal
Handle large datasets efficiently with viewport culling and smooth scrolling.

### Critical Implementation

```elixir
# Request scroll input
request_input(scene, [:cursor_scroll, :key])

# Viewport culling
defp render_content(graph, state) do
  visible_items = get_visible_items(state)
  viewport_height = state.frame.height
  
  # Calculate visible range
  first_visible = div(state.scroll_offset, state.item_height)
  last_visible = div(state.scroll_offset + viewport_height, state.item_height) + 2
  
  graph
  |> scissor({state.frame.width, viewport_height})
  |> group(
    fn g ->
      visible_items
      |> Enum.with_index()
      |> Enum.filter(fn {_, idx} -> 
        idx >= first_visible && idx <= last_visible 
      end)
      |> Enum.reduce(g, fn {{path, item}, idx}, acc ->
        render_visible_item(acc, item, path, idx, state)
      end)
    end,
    translate: {0, -state.scroll_offset}
  )
end

# Scroll handler
def handle_input({:cursor_scroll, {_, dy}}, _ctx, scene) do
  %{state: state} = scene.assigns
  
  total_height = length(get_visible_items(state)) * state.item_height
  max_scroll = max(0, total_height - state.frame.height)
  
  new_offset = state.scroll_offset - dy * 20
  |> max(0)
  |> min(max_scroll)
  
  if new_offset != state.scroll_offset do
    # Only update the scroll transform
    new_graph = Graph.modify(
      scene.assigns.graph,
      :sidebar_content,
      &translate(&1, {0, -new_offset})
    )
    
    scene
    |> assign(state: %{state | scroll_offset: new_offset})
    |> push_graph(new_graph)
  end
  
  {:noreply, scene}
end
```

---

## Phase 6: Actions & Communication

### Goal
Execute actions and notify parent components of selections.

### Implementation

```elixir
defp handle_item_click(scene, path) do
  item = find_item_by_path(path, scene.assigns.state.items)
  
  # Update selection
  scene = update_selection(scene, path)
  
  # Execute action if present
  if item[:action] do
    if Code.ensure_loaded?(Flamelex.Fluxus) do
      Flamelex.Fluxus.action(item.action)
    else
      send(self(), {:action_triggered, item.action})
    end
  end
  
  # Notify parent
  cast_parent(scene, {:sidebar_selection, path})
  
  {:noreply, scene}
end
```

---

## Phase 7: Search Integration

### Goal
Filter items by search query with auto-expansion to show results.

### Implementation Outline

```elixir
# Search UI in header
defp render_search_box(graph, state) do
  if state.search_enabled do
    graph
    |> rect({state.frame.width - 16, 32}, 
        fill: {40, 42, 54},
        stroke: {2, {68, 71, 90}})
    |> text(state.search_query || "Search...",
        translate: {8, 22},
        fill: {139, 141, 153})
  else
    graph
  end
end

# Filter logic
defp filter_items(items, query) do
  # Recursive filter that preserves parents of matches
end

# Auto-expand to show results
defp expand_for_search(state, results) do
  # Add all parent IDs to expanded_nodes
end
```

---

## Phase 8: Polish & Production

### Goal
Handle edge cases, add accessibility, ensure stability.

### Checklist
- [ ] Empty state handling
- [ ] Max depth enforcement (5 levels)
- [ ] Rapid click handling
- [ ] Memory leak prevention
- [ ] Semantic markup for testing
- [ ] Theme customization
- [ ] Touch gesture support

---

## Architecture Summary

```
sidebar.ex           - Main component, initialization, input routing
├── state.ex        - State management, data normalization
├── renderer.ex     - All rendering logic, viewport culling
├── input_handler.ex- Input processing, action dispatch
└── search.ex       - Search filtering, auto-expansion
```

## Performance Targets

- Initial render: <50ms for 1000 items
- Scroll frame: <16ms (60fps)
- Expand/collapse: <10ms
- Search filter: <100ms for 1000 items
- Memory: O(n) where n = visible items

## Critical Reminders

1. **NEVER** use `request_input` for mouse events
2. **ALWAYS** use `input:` style on primitives for scoped input
3. **Pre-render** everything possible, toggle visibility
4. **Use Graph.modify** for updates, not full re-renders
5. **Test with MenuBar** active to ensure no blocking

---

Each phase builds on the previous one. Run spex → See failure → Implement → Verify → Continue.