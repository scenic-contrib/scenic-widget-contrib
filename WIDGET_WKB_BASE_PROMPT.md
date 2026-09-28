# Widget Workbench Base Prompt

This file provides guidance for AI assistants working on the Widget Workbench project.

## Project Overview

Widget Workbench is a visual development tool for designing and testing Scenic GUI components in real-time. It provides a live preview environment where developers can load, test, and iterate on Scenic widgets.

## Development Philosophy: Specification-First

Widget Workbench follows a **specification-first development** approach using Spex. Before implementing any widget or feature, write executable specifications that define expected behavior.

### Why Spex-First?
- **Clear requirements**: Specifications serve as living documentation
- **Test-driven**: Spex runs as executable tests, ensuring implementations meet specs
- **Regression prevention**: Specs catch breaking changes early
- **Better design**: Writing specs first forces you to think through the API

### Spex Workflow
1. **Write the spec** in `test/spex/` before any implementation
2. **Run the spec** - it should fail (red phase)
3. **Implement** the minimum code to pass the spec (green phase)
4. **Refactor** while keeping specs passing
5. **Document** any deviations or learnings in the spec comments

### Example Spex Structure
```elixir
defmodule ButtonWidgetSpex do
  use Spex

  spec "Button responds to clicks" do
    # Setup
    connect_scenic(port: 9996)
    
    # Action
    click_element(element_id: "my_button")
    
    # Assertion
    assert_state_changed(:button_clicked, true)
  end
end
```

## Quick Reference: Spex-First Widget Development

| Step | Command/Action | Purpose |
|------|---------------|---------|
| 1. Write spex | Create `test/spex/widgets/NAME_spex.exs` | Define behavior |
| 2. Run failing | `mix spex test/spex/widgets/NAME_spex.exs` | Verify red phase |
| 3. Implement | Create `lib/components/NAME.ex` | Make spex pass |
| 4. Iterate | `mix spex.watch` | Continuous feedback |
| 5. Verify | `iex -S mix` → test in workbench | Visual confirmation |
| 6. Document | Update this prompt with learnings | Knowledge capture |

## Key Information

### MCP Servers

**Scenic MCP Server**:
- **Port**: 9996 (Widget Workbench runs Scenic MCP on port 9996 in dev environment, port 9998 in test, so we can run spex or other tests without conflict)
- **Purpose**: Enables programmatic control and testing of the GUI via Model Context Protocol
- **Connection**: Use `mcp__scenic-mcp__connect_scenic(port: 9996)` to connect
- **Key Tools**:
  - `click_element(element_id)` - Click elements by semantic ID
  - `send_keys(text)` / `send_keys(key, modifiers)` - Send keyboard input
  - `take_screenshot()` - Capture current display
  - `inspect_viewport()` - Get text-based UI structure
  - `find_clickable_elements()` - Discover all clickable elements
- **Automatic Semantic Registration**: Any primitive with an `:id` is automatically registered and queryable via Scenic MCP (Phase 1 - no transform calculations yet)

**Tidewave MCP Server**:
- **Port**: 4067 (Elixir project evaluation and introspection)
- **Purpose**: Provides Elixir code evaluation, documentation lookup, and project introspection
- **Key Tools**:
  - `project_eval(code)` - Evaluate Elixir code in project context
  - `get_docs(reference)` - Get documentation for modules/functions
  - `get_source_location(reference)` - Find source file locations
  - `get_logs(tail, grep)` - Retrieve application logs

### Architecture

**GUI State Management**:
- All GUI state lives in `lib/widget_workbench/widget_wkb_scene.ex`
- Scene holds state in `assigns` map
- Components register callbacks for state updates
- Input flows: Scenic → Scene → Input Handler → Reducer → Components

**Component Selection Modal**:
- **Transform-based scrolling** (no re-rendering entire scene)
- **Nested group structure**:
  - Outer container: Fixed position with scissor box (ID: `:component_list_container`)
  - Inner scroll group: Translates for scrolling (ID: `:component_list_scroll_group`)
- Mouse wheel scrolling: `cursor_scroll` input handler
- Keyboard scrolling: Arrow up/down keys (physical keyboard only)
- Visual scrollbar with proportional thumb
- Scissor clipping keeps content inside modal boundaries
- All components registered with MCP semantic IDs (format: `component_#{name}`)
- Scroll updates via `Graph.modify()` - only updates transforms, preserves all other UI elements

**Key State Fields** (in `lib/widget_workbench/widget_wkb_scene.ex`):
- `selected_component` - Currently loaded component module
- `component_modal_visible` - Boolean for component selection modal
- `modal_scroll_offset` - Current scroll position in modal (pixels)
- `click_visualization` - Click visualization state (for debugging)
- `frame` - Current viewport dimensions and layout

### Development Workflow

**Starting Widget Workbench**:
```bash
cd scenic-widget-contrib
mix deps.get
mix compile
iex -S mix  # Starts with MCP server on port 9996
```

**Testing with Scenic MCP**:
```elixir
# Connect to running app
connect_scenic(port: 9996)

# Interact with UI
click_element(element_id: "load_component_button")
inspect_viewport()
take_screenshot()
```

**Hot Reloading**:
- Code changes auto-reload via `exsync`
- Scene changes may require manual refresh
- NIFs (like Scenic.Math.Matrix) require full restart

## Spex Commands

**Running Specifications**:
```bash
# IMPORTANT: Always use MIX_ENV=test when running spex!
# This ensures test config is used (port 9998 instead of dev port 9996)

# Run all spex
MIX_ENV=test mix spex

# Run specific spex file
MIX_ENV=test mix spex test/spex/menu_bar/01_basic_load_spex.exs

# Run with verbose output
MIX_ENV=test mix spex --verbose

# Watch mode (auto-run on file changes)
MIX_ENV=test mix spex.watch

# Run only failing specs
MIX_ENV=test mix spex --failed
```

**Writing Effective Spex**:
- Keep specs focused on ONE behavior
- Use descriptive spec names that read like requirements
- Include both happy path and edge cases
- Test accessibility features (semantic IDs, keyboard nav)
- Verify visual states with screenshots when needed
- Use `use SexySpex` (not `use Spex`) - the framework is called SexySpex

## Common Tasks

**Adding a New Widget (Spex-First)**:
1. **Write the spex** in `test/spex/widgets/your_widget_spex.exs`:
   - Define expected initialization behavior
   - Specify render output requirements  
   - Document all input interactions
   - Define state transitions

2. **Run the failing spex**: `mix spex test/spex/widgets/your_widget_spex.exs`

3. **Create minimal implementation**:
   - Create component module in `lib/components/`
   - Implement only what's needed to pass the spex
   - Add to `available_components/0` in `widget_wkb_scene.ex`

4. **Iterate until green**: Run spex repeatedly, implementing incrementally

5. **Refactor and enhance**: Once spex passes, refactor for clarity

6. **Visual testing**: Load in Widget Workbench for manual verification

**Debugging Input Issues**:
- Use `observe_input/3` for non-consuming observation
- Parent scene should NOT consume events if children need them
- Check `request_input/2` calls - must request input types to receive them
- Hit-testing requires primitives in `input_lists` with correct transforms

**Common Gotchas**:
- Button components expect `id` parameter to match primitive ID (or `:btn` default)
- Components in parent's input_list have empty types `[]` - this is intentional
- Parent scenes requesting cursor input should not consume it in `handle_input`
- Coordinate systems: global coords → parent coords → local coords via transforms

## Spex Patterns for Widget Development

**Standard Setup Pattern** (viewport initialization):
```elixir
defmodule MyWidget.LoadSpex do
  use SexySpex  # Note: SexySpex, not Spex!

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}

  setup_all do
    # 1. Get environment-specific names (allows dev/test to coexist)
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)

    # 2. Kill any existing viewport (prevents naming conflicts)
    if viewport_pid = Process.whereis(viewport_name) do
      Process.exit(viewport_pid, :kill)
      Process.sleep(100)
    end

    # 3. Start application
    Application.ensure_all_started(:scenic_widget_contrib)

    # 4. Configure viewport with ALL required driver options
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
        layer: 0,           # Required by driver
        opacity: 255,       # Required by driver
        position: [         # Required by driver
          scaled: false,
          centered: false,
          orientation: :normal
        ]
      ]]
    ]

    # 5. Start viewport and wait for initialization
    {:ok, viewport_pid} = Scenic.ViewPort.start_link(viewport_config)
    Process.sleep(1500)

    # 6. Cleanup on exit
    on_exit(fn ->
      if pid = Process.whereis(viewport_name) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)

    {:ok, %{viewport_pid: viewport_pid}}
  end
end
```

**Component Loading Spex**:
```elixir
spex "Widget loads successfully" do
  scenario "Load MyWidget component", context do
    given_ "Widget Workbench is running", context do
      case SemanticUI.verify_widget_workbench_loaded() do
        {:ok, state} -> {:ok, Map.put(context, :workbench, state)}
        {:error, reason} -> {:error, reason}
      end
    end

    when_ "we load MyWidget", context do
      case SemanticUI.load_component("My Widget") do
        {:ok, result} -> {:ok, Map.put(context, :result, result)}
        {:error, reason} -> {:error, reason}
      end
    end

    then_ "widget should be visible", context do
      assert context.result.loaded == true
      :ok
    end
  end
end
```

**Semantic UI Interaction**:
```elixir
# Use semantic helpers instead of manual coordinate calculations
when_ "we interact with the widget", context do
  # Good: Using semantic helpers
  SemanticUI.load_component("Menu Bar")
  SemanticUI.click_component_in_modal("Menu Bar")

  # Avoid: Manual coordinate calculations (brittle)
  # click_at_position(350, 425)  # Don't do this!

  {:ok, context}
end
```

## Testing Strategy

**Spex-First Development**:
- `test/spex/` - Executable specifications (write these FIRST)
- Spex defines the contract, implementation follows
- Each widget should have corresponding spex before implementation

**Test Hierarchy**:
1. **Spex** (highest level): User-facing behavior specifications
2. **Integration tests**: Component interaction tests
3. **Unit tests**: Internal function tests (only when needed)

**Coverage Goals**:
- 100% spex coverage for all user-facing features
- Focus on behavior, not implementation details
- Visual regression tests via screenshot comparisons

## Key Files

**Main Scene**:
- `lib/widget_workbench/widget_wkb_scene.ex` - Root scene, all GUI state and logic

**Component Library**:
- `lib/components/buttons/` - Button widgets
- `lib/components/menu_bar/` - Menu bar components
- `lib/components/side_nav/` - Navigation widgets
- `lib/layout_components/` - Layout helpers

**Testing**:
- `test/spex/` - Executable specifications for testing (WRITE THESE FIRST!)

## Dependencies

**Key Elixir Packages**:
- `scenic` - GUI framework (local modified version in `../scenic_local`)
- `scenic_driver_local` - Graphics driver
- `scenic_live_reload` - Hot reloading support
- `tidewave` - MCP tools for Elixir evaluation
- `sexy_spex` - Specification framework (https://github.com/JediLuke/spex)
  - Note: Package name is `sexy_spex` but GitHub repo is called "spex"
  - Use `use SexySpex` in test files (not `use Spex`)
  - Provides `SexySpex.Helpers.start_scenic_app/2` for application startup
  - **Runs tests synchronously** (`async: false`) - safe for shared viewport usage

**Scenic MCP** (for AI control):
- Lives in `../scenic_mcp_experimental` (sibling project)
- TypeScript MCP server → TCP bridge → Elixir GenServer → ViewPort
- Enables Puppeteer-like automation for Scenic apps
- Configurable via `config :scenic_mcp, port: 9999, viewport_name: :main_viewport, driver_name: :scenic_driver`
- Default names `:main_viewport` and `:scenic_driver` are expected for auto-discovery

## Development Tips

**When Adding Features**:
1. **FIRST**: Write spex specifications in `test/spex/`
2. Run failing spex to confirm red phase
3. Update scene state in `widget_wkb_scene.ex` assigns
4. Add reducer function to handle state changes
5. Update render functions to reflect new state
6. Add input handlers if needed
7. Iterate until spex passes
8. Test with Scenic MCP automation
9. Visual verification in Widget Workbench

**Input Routing Order**:
1. Driver sends input to ViewPort
2. ViewPort checks if input type in `requested_inputs`
3. `do_listed_input` (hit-testing) runs FIRST
4. `do_requested_input` (delivers to requesting scenes) runs SECOND
5. Scenes call `observe_input` then `handle_input`

**Semantic Element Registration** (Phase 1 - Automatic):
```elixir
# Elements with IDs are automatically registered!
graph
|> rectangle({100, 50}, id: :my_button, translate: {x, y})
|> text("Click Me", id: :button_label, translate: {x + 10, y + 25})

# Query registered elements
{:ok, viewport} = Scenic.ViewPort.info(:main_viewport)
{:ok, button} = Scenic.ViewPort.Semantic.find_element(viewport, :my_button)

# Click by ID (no coordinates needed!)
{:ok, coords} = Scenic.ViewPort.Semantic.click_element(viewport, :my_button)

# Find all clickable elements
{:ok, elements} = Scenic.ViewPort.Semantic.find_clickable_elements(viewport)

# For advanced control, use explicit semantic metadata:
graph
|> rectangle(
  {100, 50},
  semantic: %{
    id: :custom_button,
    type: :button,
    clickable: true,
    label: "Save",
    role: :primary_action
  }
)
```

See `scenic_local/guides/testing_and_automation.md` for complete documentation.

## Troubleshooting

**Spex tests fail with "GenServer :scenic_driver terminating"**:
- **Error**: `(MatchError) no match of right hand side value: :error` at driver.ex:221
- **Cause**: Missing required driver options in viewport config (`layer`, `opacity`, `position`)
- **Solution**: Use complete driver config from Standard Setup Pattern above
- **Required options**: `layer: 0`, `opacity: 255`, `position: [scaled: false, centered: false, orientation: :normal]`

**Viewport naming conflicts**:
- **Cause**: Trying to start viewport when one already exists with name `:main_viewport`
- **Solution**: Kill existing viewport before starting new one (see setup pattern above)
- ScenicMCP requires specific names: `:main_viewport` and `:scenic_driver`

**App won't start**:
- Check port isn't in use: `lsof -i :9996` (dev) or `lsof -i :9998` (test)
- Ensure scenic_driver_local compiled: `cd deps/scenic_driver_local && make`
- Check Elixir version: `elixir --version` (needs 1.12+)

**Clicks not working**:
- Verify element registered with MCP: `find_clickable_elements()`
- Check input_lists in ViewPort state
- Ensure parent scene doesn't consume events
- Verify button ID matches primitive ID

**Hot reload issues**:
- Full restart needed for NIF changes (scenic_local)
- Scene state persists across reloads
- Use `mix compile --force` if changes not picked up

## Common Spex Failures and Solutions

**"Element not found"**:
- Ensure semantic ID registered: `register_semantic/4`
- Check timing - add `wait_for_element/1` if needed
- Verify element is in current viewport

**"State mismatch"**:
- Check reducer actually updates state
- Ensure state key names match between spex and implementation
- Add logging in reducer to debug state transitions

**"Click not registered"**:
- Verify element in input_lists
- Check parent isn't consuming the click
- Ensure clickable bounds are correct

**"Spex timing out"**:
- Add appropriate wait conditions
- Check MCP server is running on correct port
- Verify scenic_driver_local is compiled

## Performance Considerations

**When to Optimize**:
- Scroll performance issues → Use transform-based scrolling (like component modal)
- Many elements → Consider virtualization for lists > 100 items
- Frequent updates → Batch Graph.modify calls
- Complex scenes → Profile with `:observer.start()`

**Optimization Patterns**:
- Prefer `Graph.modify` over full re-renders
- Use groups to batch transform updates
- Minimize primitive count in input_lists
- Cache computed values in assigns

## Resources

- **Scenic Docs**: https://hexdocs.pm/scenic/
- **Scenic GitHub**: https://github.com/boydm/scenic
- **Spex GitHub**: https://github.com/JediLuke/spex
- **Widget Contrib Fork**: https://github.com/JediLuke/scenic-widget-contrib/tree/text_pad_wip
- **Project Root**: `/Users/luke/workbench/flx/`

## Development Principles

1. **Spex First**: Always write specifications before implementation
2. **Behavior Over Implementation**: Test what the user experiences, not how it works
3. **Fail Fast**: Run spex early and often during development
4. **Document Deviations**: If implementation differs from spex, document why
5. **Visual Verification**: Always manually test in Widget Workbench after spex passes