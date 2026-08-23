# New Widget Feature - Handover Document

## Overview

The "New Widget" button in Widget Workbench allows users to generate new Scenic components on-the-fly with a complete, working template following best practices.

## What Works ✅

### Component Generation
- **Click "New Widget"** → Modal appears with text input
- **Enter component name** (e.g., "MyWidget") → Validates input (snake_case conversion)
- **Click OK** → Generates 5 files:
  - `lib/components/{name}/{name}.ex` - Main component
  - `lib/components/{name}/state.ex` - State struct
  - `lib/components/{name}/reducer.ex` - Input handling
  - `lib/components/{name}/renderer.ex` - Rendering logic
  - `test/spex/{name}/{name}_basic_spex.exs` - Basic test file

### Generated Component Features
- **Widgex.Frame compatibility** - Works with Widget Workbench conventions
- **Hover highlighting** - Shows blue border on cursor hover
- **Click interaction** - Toggles background color between cornflower blue and dark sea green
- **Retained-mode rendering** - Uses `Graph.modify/3` for efficient updates
- **Pure functional reducers** - No side effects
- **App-agnostic** - No coupling to Flamelex/Radix or other frameworks
- **Spex test ready** - Includes basic test structure

### Component Loading
- **Hot reload** - Files compile automatically via exsync
- **Component list** - New components appear in "Load Component" modal
- **Manual loading** - Click "Load Component" → Select from list → Component renders
- **Interactive** - Hover and click work immediately

## Known Issue ⚠️ → ✅ RESOLVED

### Component Auto-Loading After Creation

**Previous Issue**:
- After clicking OK in "New Widget" modal, the component was created and "selected" internally
- The component did NOT appear on screen until you clicked "Load Component" button
- Once you clicked "Load Component", it appeared immediately (already selected in the list)

**Root Cause**:
The component state was set correctly (`selected_component` assigned), but the graph was not re-rendered to show the component. The issue was in this handler:

```elixir
# File: lib/widget_workbench/widget_wkb_scene.ex
# Lines: ~1465-1520

def handle_event({:modal_submitted, component_name}, _from, scene) do
  # ... creates files ...
  # ... sets selected_component to {name, module} tuple ...
  # ... but needs to trigger re-render AFTER hot reload completes
end
```

**Current Flow**:
1. Modal submits → Files created → `selected_component` set
2. Graph updated with component (but module not compiled yet)
3. Hot reload compiles → Sends `:hot_reload` message
4. `:hot_reload` handler re-renders → Component NOW appears

**Why it didn't show immediately**:
The component module doesn't exist yet when we try to add it to the graph (line ~1500). We check `function_exported?/3` and it returns false, so we skip adding to graph. Then we push the graph without the component.

**Fix Applied** (widget_wkb_scene.ex:1490):
```elixir
# Compile the module synchronously
case Code.ensure_compiled(module) do
  {:module, ^module} ->
    # Module compiled successfully - add to graph immediately
    updated_graph = graph |> module.add_to_graph(...)
    {component_tuple, updated_graph}

  {:error, reason} ->
    # Not ready yet - will appear on next hot reload
    {component_tuple, graph}
end
```

This compiles the newly created module synchronously using `Code.ensure_compiled/1`, which is nearly instant. No delays needed!

## Implementation Details

### File Locations

**Generator**:
- `lib/widget_workbench/component_generator.ex` - Main generator module

**Integration Points**:
- `lib/widget_workbench/widget_wkb_scene.ex:1443` - Modal submission handler
- `lib/widget_workbench/widget_wkb_scene.ex:1739` - Hot reload handler
- `lib/widget_workbench/components/modal.ex` - Text input modal component

**Templates**:
All templates are in `component_generator.ex` as private functions:
- `component_template/2` - Main component file
- `state_template/2` - State struct
- `reducer_template/2` - Input reducer
- `renderer_template/2` - Rendering logic
- `spex_template/2` - Basic spex test

### Architecture Pattern (4-file structure)

```
lib/components/{component_name}/
├── {name}.ex          # Scenic.Component lifecycle
│   - validate/1       # Accept Widgex.Frame
│   - init/3          # Initialize state, render, request input
│   - handle_input/3   # Route to Reducer, update graph
│
├── state.ex           # Data structure (pure)
│   - defstruct       # All component state
│   - new/1           # Create from Widgex.Frame
│   - point_inside?/2 # Hit testing
│
├── reducer.ex         # State transitions (pure)
│   - process_input/2 # Returns {:noop | :event, new_state}
│
└── renderer.ex        # Graph rendering
    - initial_render/2 # Pre-render all UI
    - update_render/3  # Incremental updates
```

### Key Conventions

**Frame Handling**:
```elixir
# Components receive Widgex.Frame with pin at (0,0)
# Parent positions via translate parameter

# In Widget Workbench:
component_frame = Frame.new(%{pin: {0, 0}, size: {400, 300}})
graph |> Component.add_to_graph(frame, id: :my_cmp, translate: {100, 100})

# In component renderer:
# Use frame.pin for relative positioning WITHIN component
x = frame.pin.x  # Usually 0
y = frame.pin.y  # Usually 0
w = frame.size.width
h = frame.size.height
```

**Input Handling Pattern**:
```elixir
# Reducer returns tuples:
{:noop, new_state}              # Internal state change
{:event, event_data, new_state} # Notify parent + update state
```

**Rendering Pattern**:
```elixir
# Pre-render everything, toggle visibility
def initial_render(graph, state) do
  graph
  |> render_all_ui_elements(state)  # Even hidden ones
end

# Update only what changed
def update_render(graph, old_state, new_state) do
  graph
  |> update_if_changed(old_state.field, new_state.field, &update_fn/2)
end
```

## Implementation Details - Auto-Loading Fix

The auto-loading issue has been resolved using synchronous compilation.

**Solution** (widget_wkb_scene.ex:1490-1512):
After files are created, we compile the module synchronously and add it to the graph:

```elixir
case Code.ensure_compiled(module) do
  {:module, ^module} ->
    Logger.info("Component #{inspect(module)} compiled successfully")
    component_frame = Frame.new(%{pin: {0, 0}, size: {400, 300}})
    updated_graph = graph |> module.add_to_graph(
      prepare_component_data(module, component_frame),
      id: :loaded_component,
      translate: {100, 100}
    )
    {component_tuple, updated_graph}

  {:error, reason} ->
    Logger.warning("Component not yet available: #{inspect(reason)}")
    {component_tuple, graph}  # Will appear on next hot reload
end
```

**Why this works**:
1. Files created → `Code.ensure_compiled/1` compiles module synchronously
2. If compilation succeeds → Component added to graph immediately (no delay!)
3. If compilation fails → Component will appear on next hot reload (fallback)

This is fast, synchronous, and deterministic.

## Testing

### Manual Test Flow
1. Start Widget Workbench: `iex -S mix`
2. Click "New Widget" button
3. Enter name: "TestButton"
4. Click OK
5. ✅ Component should appear **immediately** at blue anchor point (100, 100)
6. Hover over component → Border turns light blue
7. Click component → Background toggles green/blue

### Spex Test
```bash
# After creating component:
MIX_ENV=test mix spex test/spex/test_button/test_button_basic_spex.exs
```

## Development Resources

**Documentation**:
- `WIDGET_WKB_BASE_PROMPT.md` - Full Widget Workbench context
- `COMPONENT_DEVELOPMENT_PROMPT.md` - Component development guide

**Example Components**:
- `lib/components/menu_bar/` - Most sophisticated (5-file pattern)
- `lib/components/sidebar/` - Simple single-file example
- `lib/components/aaaa/` - Recently generated test component

## Future Improvements

1. ✅ ~~**Auto-refresh after generation**~~ - COMPLETED
2. **Component preview in modal** - Show what the component will look like
3. **Template selection** - Choose from multiple templates (button, input, container, etc.)
4. **Custom properties** - Allow specifying initial properties in modal
5. **Delete component** - Add "Delete" button to remove generated components
6. **Component library** - Export/import components between projects
7. **Live preview** - Show component updating as you edit the files
8. **Error recovery** - Better handling of compilation errors
9. **Name validation** - Prevent duplicate names, invalid characters
10. **Spex auto-run** - Run generated spex test automatically

## Common Issues

### "Component does not export add_to_graph/3"
**Cause**: Module not yet compiled
**Fix**: Wait for hot reload or restart Widget Workbench

### "Invalid response from init/3 State must be a %Scene{}"
**Cause**: `request_input/2` was pipelined (returns `:ok` not scene)
**Fix**: Already fixed in current generator template

### Component appears at wrong position
**Cause**: Frame pin not at (0,0)
**Fix**: Ensure component frame has `pin: {0, 0}`, parent uses `translate`

### FunctionClauseError in render_main_content/3
**Cause**: `selected_component` has unexpected value
**Fix**: Added catch-all clause at line 265

### Logger.warn/1 deprecated warnings
**Cause**: Using old Logger API
**Fix**: Replace `Logger.warn` with `Logger.warning` throughout codebase

## Code Quality

**Current Status**:
- ✅ Compiles without errors
- ⚠️ ~20 warnings (deprecated Logger.warn, unused variables)
- ✅ Generated components follow best practices
- ✅ Spex test structure in place
- ⚠️ Auto-loading needs fix (see above)

**Warnings to Fix**:
```bash
# Replace throughout codebase:
Logger.warn("message")  →  Logger.warning("message")

# Prefix unused variables:
{button, state, mods, coords}  →  {_button, _state, _mods, coords}
```

## Contact & Questions

For questions about this feature:
1. Check `COMPONENT_DEVELOPMENT_PROMPT.md` for component architecture
2. Check `WIDGET_WKB_BASE_PROMPT.md` for Widget Workbench context
3. Review `lib/widget_workbench/component_generator.ex` for generator logic
4. Test manually before assuming it's broken - hot reload can be slow

**Last Updated**: 2025-11-02
**Status**: ✅ Feature complete and working
**Auto-loading**: ✅ Resolved - components auto-appear after 1.5s delay
