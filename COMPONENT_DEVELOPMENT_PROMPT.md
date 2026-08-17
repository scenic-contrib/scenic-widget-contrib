# Component Development Base Prompt

This file provides guidance for AI assistants working on individual Scenic widget components within the Widget Workbench project.

## Context: You Are Developing a Scenic Widget Component

You are helping develop a reusable, app-agnostic Scenic GUI component. This component:
- Lives in `lib/components/{component_name}/`
- Follows the **4-file architecture pattern** (component, state, reducer, renderer)
- Uses **Widgex.Frame** for positioning and sizing
- Implements **retained-mode rendering** with incremental updates
- Is **testable via Spex** (specification-first development)
- Can be loaded and tested in **Widget Workbench** (visual development tool)

## Component Architecture Pattern

### File Structure (4 files)
```
lib/components/{component_name}/
├── {component_name}.ex          # Main component (Scenic.Component lifecycle)
├── state.ex                     # State struct + query functions
├── reducer.ex                   # Pure state transitions (input → new state)
└── renderer.ex                  # Graph rendering (initial + incremental)
```

### Separation of Concerns

**`{component_name}.ex`** - Component Lifecycle
- `use Scenic.Component, has_children: false`
- `validate/1` - Accept `Widgex.Frame` or `%{frame: Frame}`
- `init/3` - Initialize state, render graph, request input
- `handle_input/3` - Route input through Reducer, update graph if state changed
- `handle_event/3` - Handle child component events (if applicable)

**`state.ex`** - Data Structure
- `defstruct` with all component state fields
- `new/1` - Create state from `Widgex.Frame` or map
- Query functions (pure): `point_inside?/2`, `get_bounds/1`, etc.
- **NO MUTATIONS** - all functions are pure

**`reducer.ex`** - State Transitions
- `process_input/2` - Pure function: `(state, input) -> {:noop | :event, new_state}`
- Returns `{:noop, new_state}` - internal state change, no parent notification
- Returns `{:event, event_data, new_state}` - send event to parent + update state
- **NO SIDE EFFECTS** - reducer is pure functional

**`renderer.ex`** - Graph Rendering
- `initial_render/2` - Pre-render ALL UI elements (even hidden ones)
- `update_render/3` - Incrementally update ONLY changed elements
- Use `Graph.modify/3` with descriptive IDs for targeted updates
- **Retained-mode pattern** - avoid full re-renders

## Key Conventions

### Widgex.Frame Usage
```elixir
# Frame structure
%Widgex.Frame{
  pin: %Widgex.Structs.Coordinates{x: 100, y: 100, point: {100, 100}},
  size: %Widgex.Structs.Dimensions{width: 400, height: 200, box: {400, 200}}
}

# Accessing frame fields
x = frame.pin.x
y = frame.pin.y
w = frame.size.width
h = frame.size.height
```

### Component Validation Pattern
```elixir
@impl Scenic.Component
def validate(%Widgex.Frame{} = frame) do
  # Widget Workbench passes bare frame
  {:ok, frame}
end

def validate(%{frame: %Widgex.Frame{}} = data) do
  # Standard pattern with :frame key
  {:ok, data}
end

def validate(_), do: {:error, "#{ModuleName} requires Widgex.Frame"}
```

### State Initialization Pattern
```elixir
def new(%Widgex.Frame{} = frame) do
  %__MODULE__{
    frame: frame,
    # ... other fields with defaults
  }
end

def new(%{frame: %Widgex.Frame{} = frame} = data) do
  %__MODULE__{
    frame: frame,
    # Extract other fields from data map
  }
end
```

### Retained-Mode Rendering Pattern
```elixir
# GOOD: Pre-render everything, toggle visibility
def initial_render(graph, state) do
  graph
  |> render_background(state)
  |> render_active_state_hidden(state)   # Pre-render, set :hidden style
  |> render_inactive_state_visible(state)
end

def update_render(graph, old_state, new_state) do
  graph
  |> update_if_changed(old_state.field, new_state.field, &update_fn/2)
end

defp update_if_changed(graph, old, new, _fun) when old == new, do: graph
defp update_if_changed(graph, _old, new, fun), do: fun.(graph, new)

# BAD: Don't re-render entire graph on state change
def update_render(graph, _old, new_state) do
  # Avoid this - rebuilds entire graph!
  initial_render(Graph.build(), new_state)
end
```

### Input Handling Pattern
```elixir
# In main component file:
def handle_input(input, _context, scene) do
  state = scene.assigns.state

  case Reducer.process_input(state, input) do
    {:noop, ^state} ->
      # State unchanged, skip update
      {:noreply, scene}

    {:noop, new_state} ->
      # State changed, update graph
      update_scene(scene, state, new_state)

    {:event, event_data, new_state} ->
      # Send event to parent
      send_parent_event(scene, event_data)
      update_scene(scene, state, new_state)
  end
end

defp update_scene(scene, old_state, new_state) do
  graph = Renderer.update_render(scene.assigns.graph, old_state, new_state)
  scene = assign(scene, state: new_state, graph: graph) |> push_graph(graph)
  {:noreply, scene}
end

# In reducer.ex:
def process_input(%State{} = state, {:cursor_pos, coords}) do
  new_hover = State.point_inside?(state, coords)

  if state.hovered != new_hover do
    {:noop, %{state | hovered: new_hover}}
  else
    {:noop, state}
  end
end

def process_input(%State{} = state, {:cursor_button, {:btn_left, 1, [], coords}}) do
  if State.point_inside?(state, coords) do
    {:event, {:component_clicked, state.some_data}, update_state(state)}
  else
    {:noop, state}
  end
end
```

### Graph Update Helpers (Scenic API)
```elixir
# Update primitive options
graph
|> Graph.modify(:my_element, fn primitive ->
  Primitives.update_opts(primitive, fill: :red, stroke: {2, :black})
end)

# Update text content
graph
|> Graph.modify(:my_text, fn primitive ->
  Primitives.text(primitive, "New text content")
end)

# Show/hide elements
graph
|> Graph.modify(:my_element, fn primitive ->
  Primitives.update_opts(primitive, hidden: true)  # or false
end)

# Transform position
graph
|> Graph.modify(:my_group, fn primitive ->
  Primitives.update_opts(primitive, translate: {x, y})
end)
```

## Spex-First Development Workflow

### 1. Component Generated
When a new component is created via Widget Workbench, you get:
- 4 component files (working template)
- 1 basic spex file (load test only)

### 2. Expand Spex FIRST
Before implementing features, write spex for desired behavior:

```elixir
# test/spex/{component_name}/{component_name}_behavior_spex.exs
defmodule ScenicWidgets.MyComponent.BehaviorSpex do
  use SexySpex

  alias ScenicWidgets.TestHelpers.{SemanticUI, ScriptInspector}

  setup_all do
    # Standard viewport setup (see pattern below)
  end

  spex "Component behavior" do
    scenario "Feature works as expected", context do
      given_ "component is loaded", context do
        {:ok, Map.put(context, :component, load_component())}
      end

      when_ "user performs action", context do
        # Simulate user interaction
        {:ok, context}
      end

      then_ "component responds correctly", context do
        # Assert expected behavior
        assert expected_condition
        :ok
      end
    end
  end
end
```

### 3. Run Failing Spex
```bash
MIX_ENV=test mix spex test/spex/{component_name}/
# Should fail - red phase
```

### 4. Implement Incrementally
- Update `state.ex` with needed fields
- Update `reducer.ex` with input handling
- Update `renderer.ex` with visual changes
- Re-run spex after each change

### 5. Visual Testing in Widget Workbench
```bash
iex -S mix
# Load component, interact manually, verify behavior
```

## Standard Spex Setup Pattern

```elixir
setup_all do
  # Get environment-specific names
  viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)
  driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)

  # Kill any existing viewport
  if viewport_pid = Process.whereis(viewport_name) do
    Process.exit(viewport_pid, :kill)
    Process.sleep(100)
  end

  # Start application
  Application.ensure_all_started(:scenic_widget_contrib)

  # Configure viewport with ALL required driver options
  viewport_config = [
    name: viewport_name,
    size: {1200, 800},
    theme: :dark,
    default_scene: {WidgetWorkbench.Scene, []},
    drivers: [[
      module: Scenic.Driver.Local,
      name: driver_name,
      window: [resizeable: true, title: "Test Window"],
      on_close: :stop_viewport,
      debug: false,
      cursor: true,
      antialias: true,
      layer: 0,           # Required
      opacity: 255,       # Required
      position: [         # Required
        scaled: false,
        centered: false,
        orientation: :normal
      ]
    ]]
  ]

  # Start viewport and wait
  {:ok, viewport_pid} = Scenic.ViewPort.start_link(viewport_config)
  Process.sleep(1500)

  # Cleanup on exit
  on_exit(fn ->
    if pid = Process.whereis(viewport_name) do
      Process.exit(pid, :normal)
      Process.sleep(100)
    end
  end)

  {:ok, %{viewport_pid: viewport_pid}}
end
```

## Common Component Patterns

### Interactive Button/Clickable Area
```elixir
# State fields:
defstruct [:frame, :hovered, :pressed, :disabled]

# Reducer patterns:
def process_input(state, {:cursor_pos, coords}) do
  new_hover = !state.disabled and State.point_inside?(state, coords)
  if state.hovered != new_hover do
    {:noop, %{state | hovered: new_hover}}
  else
    {:noop, state}
  end
end

def process_input(state, {:cursor_button, {:btn_left, 1, [], coords}}) do
  # Press down
  if State.point_inside?(state, coords) and !state.disabled do
    {:noop, %{state | pressed: true}}
  else
    {:noop, state}
  end
end

def process_input(state, {:cursor_button, {:btn_left, 0, [], coords}}) do
  # Release - trigger click if still inside
  was_pressed = state.pressed
  inside = State.point_inside?(state, coords)

  if was_pressed and inside and !state.disabled do
    {:event, {:button_clicked, state.id}, %{state | pressed: false}}
  else
    {:noop, %{state | pressed: false}}
  end
end
```

### Text Input Field
```elixir
# State fields:
defstruct [:frame, :text, :cursor_pos, :focused, :selection]

# Reducer patterns:
def process_input(state, {:key, {:key_backspace, 1, _}}) do
  if state.focused and state.cursor_pos > 0 do
    {before, after_cursor} = String.split_at(state.text, state.cursor_pos)
    new_text = String.slice(before, 0..-2) <> after_cursor
    {:noop, %{state | text: new_text, cursor_pos: state.cursor_pos - 1}}
  else
    {:noop, state}
  end
end

def process_input(state, {:codepoint, {char, _}}) when char in ?a..?z or char in ?A..?Z do
  if state.focused do
    {before, after_cursor} = String.split_at(state.text, state.cursor_pos)
    new_text = before <> <<char::utf8>> <> after_cursor
    {:noop, %{state | text: new_text, cursor_pos: state.cursor_pos + 1}}
  else
    {:noop, state}
  end
end
```

### Scrollable Container
```elixir
# State fields:
defstruct [:frame, :scroll_offset, :content_height, :viewport_height]

# Reducer patterns:
def process_input(state, {:cursor_scroll, {_dx, dy}}) do
  max_scroll = max(0, state.content_height - state.viewport_height)
  new_offset = state.scroll_offset - dy * 20  # Scroll speed multiplier
  clamped = max(0, min(new_offset, max_scroll))

  if clamped != state.scroll_offset do
    {:noop, %{state | scroll_offset: clamped}}
  else
    {:noop, state}
  end
end

# Renderer pattern:
def initial_render(graph, state) do
  graph
  |> Primitives.group(fn g ->
    g
    |> render_content(state)
  end,
  id: :scroll_content,
  translate: {0, -state.scroll_offset},  # Scroll by translating group
  scissor: {frame.size.width, frame.size.height})  # Clip overflow
end

def update_render(graph, old_state, new_state) do
  if old_state.scroll_offset != new_state.scroll_offset do
    graph
    |> Graph.modify(:scroll_content, fn primitive ->
      Primitives.update_opts(primitive, translate: {0, -new_state.scroll_offset})
    end)
  else
    graph
  end
end
```

### Dropdown/Collapsible Section
```elixir
# State fields:
defstruct [:frame, :expanded, :items, :selected_index]

# Pre-render pattern (efficient for dropdowns):
def initial_render(graph, state) do
  graph
  |> render_header(state)
  |> render_dropdown_content(state)  # Always render, control visibility
end

defp render_dropdown_content(graph, state) do
  # Pre-render all items, hide when collapsed
  items_graph = Enum.reduce(state.items, graph, fn item, g ->
    render_item(g, item, state)
  end)

  # Wrap in group that can be hidden
  Graph.modify(items_graph, :dropdown_group, fn primitive ->
    Primitives.update_opts(primitive, hidden: !state.expanded)
  end)
end

def update_render(graph, old_state, new_state) do
  if old_state.expanded != new_state.expanded do
    graph
    |> Graph.modify(:dropdown_group, fn primitive ->
      Primitives.update_opts(primitive, hidden: !new_state.expanded)
    end)
  else
    graph
  end
end
```

## Performance Optimization Patterns

### When to Optimize
- Many elements (>50 primitives)
- Frequent updates (animation, live data)
- Scroll performance issues
- Noticeable lag in UI responsiveness

### Optimization Techniques

**1. Incremental Updates (Always)**
```elixir
# GOOD: Only update what changed
def update_render(graph, old, new) do
  graph
  |> update_field_a_if_changed(old.a, new.a)
  |> update_field_b_if_changed(old.b, new.b)
end

# BAD: Rebuild entire graph
def update_render(_graph, _old, new) do
  initial_render(Graph.build(), new)
end
```

**2. Group Related Elements**
```elixir
# Move groups instead of individual elements
graph
|> Primitives.group(fn g ->
  g
  |> element_1()
  |> element_2()
  |> element_3()
end,
id: :my_group,
translate: {x, y})  # Move entire group at once
```

**3. Virtualization for Long Lists**
```elixir
# Only render visible items (for lists > 100 items)
def render_visible_items(graph, state) do
  visible_start = div(state.scroll_offset, item_height)
  visible_end = visible_start + div(state.viewport_height, item_height) + 2

  state.items
  |> Enum.slice(visible_start, visible_end - visible_start)
  |> Enum.reduce(graph, &render_item/2)
end
```

**4. Batch Graph Operations**
```elixir
# GOOD: Pipeline multiple Graph.modify calls
graph
|> Graph.modify(:item1, &update_fn/1)
|> Graph.modify(:item2, &update_fn/1)
|> Graph.modify(:item3, &update_fn/1)

# BAD: Multiple push_graph calls
push_graph(scene, Graph.modify(graph, :item1, &update_fn/1))
push_graph(scene, Graph.modify(graph, :item2, &update_fn/1))
```

**5. Cache Computed Values in State**
```elixir
defstruct [
  :items,
  :computed_layout,  # Cache expensive layout calculations
  :visible_bounds    # Cache hit-test bounds
]

def new(data) do
  items = Map.get(data, :items, [])

  %__MODULE__{
    items: items,
    computed_layout: compute_layout(items),  # Compute once
    visible_bounds: compute_bounds(items)
  }
end
```

## Debugging Tips

### Visual Debugging
```elixir
# Add debug layer to see frame bounds
def render_debug_layer(graph, frame) do
  graph
  |> Primitives.rect(
    {frame.size.width, frame.size.height},
    stroke: {2, :red},
    fill: :clear,
    translate: {frame.pin.x, frame.pin.y},
    id: :debug_bounds
  )
end
```

### Logging State Transitions
```elixir
def process_input(state, input) do
  result = handle_input(state, input)

  case result do
    {:event, event, new_state} ->
      Logger.debug("Event: #{inspect(event)}, State: #{inspect(state)} -> #{inspect(new_state)}")
    {:noop, ^state} ->
      # No change, no log
      :ok
    {:noop, new_state} ->
      Logger.debug("State change: #{inspect(state)} -> #{inspect(new_state)}")
  end

  result
end
```

### Input Event Tracing
```elixir
def handle_input(input, _ctx, scene) do
  Logger.debug("#{__MODULE__} received input: #{inspect(input)}")
  # ... rest of handler
end
```

## Common Gotchas

### ❌ Don't Request Input You Don't Handle
```elixir
# BAD: Requesting all input types
request_input(scene, [:cursor_pos, :cursor_button, :cursor_scroll, :key, :codepoint])

# GOOD: Only request what you use
request_input(scene, [:cursor_button])  # If only handling clicks
```

### ❌ Don't Consume Input That Children Need
```elixir
# BAD: Parent consuming all clicks
def handle_input({:cursor_button, _} = input, _ctx, scene) do
  # Do something
  {:noreply, scene}  # Input stops here!
end

# GOOD: Let input propagate to children
def handle_input({:cursor_button, _} = input, _ctx, scene) do
  # Only handle if it's for this component specifically
  {:cont, scene}  # Or let hit-testing handle it
end
```

### ❌ Don't Modify State Directly
```elixir
# BAD: Side effects in reducer
def process_input(state, input) do
  # This mutates state!
  state.items = Enum.reverse(state.items)
  {:noop, state}
end

# GOOD: Return new state
def process_input(state, input) do
  new_items = Enum.reverse(state.items)
  {:noop, %{state | items: new_items}}
end
```

### ❌ Don't Use Tuple Coordinates with Widgex.Frame
```elixir
# BAD: Mixing tuple and struct patterns
x = elem(frame.pin, 0)  # Don't treat as tuple

# GOOD: Use struct accessors
x = frame.pin.x
y = frame.pin.y
```

## Testing Checklist

Before considering a component complete:

- [ ] **Spex tests pass**: `MIX_ENV=test mix spex test/spex/{component_name}/`
- [ ] **Visual testing**: Component loads in Widget Workbench
- [ ] **Hover states work**: Cursor movement triggers visual feedback
- [ ] **Click handling works**: Clicks trigger expected behavior
- [ ] **Keyboard input works** (if applicable): Keys update component
- [ ] **Edge cases handled**: Empty state, null values, extreme sizes
- [ ] **Performance acceptable**: No lag with normal usage patterns
- [ ] **Code is clean**: No warnings, good names, documented

## Resources

- **Scenic Docs**: https://hexdocs.pm/scenic/
- **Scenic GitHub**: https://github.com/boydm/scenic
- **Spex Framework**: https://github.com/JediLuke/spex
- **Widget Workbench**: `/lib/widget_workbench/widget_wkb_scene.ex`
- **Example Components**: `/lib/components/menu_bar/` (most sophisticated)
- **Base Prompt**: `WIDGET_WKB_BASE_PROMPT.md` (full project context)

## Quick Command Reference

```bash
# Generate new component
# (In Widget Workbench GUI: Click "New Widget" button)

# Run spex tests
MIX_ENV=test mix spex test/spex/{component_name}/

# Watch mode (auto-run on file changes)
MIX_ENV=test mix spex.watch

# Start Widget Workbench
iex -S mix

# Compile and check for errors
mix compile

# Format code
mix format lib/components/{component_name}/**/*.ex
```

## Development Workflow Summary

1. **Generate component** → Widget Workbench "New Widget" button
2. **Write spex** → Define behavior in `test/spex/{name}/`
3. **Run failing spex** → Confirm red phase
4. **Implement feature** → Update state/reducer/renderer
5. **Re-run spex** → Iterate until green
6. **Visual test** → Load in Widget Workbench, verify manually
7. **Refactor** → Clean up code while keeping spex green
8. **Document** → Add docstrings, update comments

Remember: **Spex first, implementation second, visual verification third!**
