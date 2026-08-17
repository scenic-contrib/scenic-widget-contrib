# Component Test Harness - Usage Guide

## Overview

The Component Test Harness provides automated, repeatable testing for Scenic components in the Widget Workbench via scenic_mcp automation. This enables:

- **Programmable component loading** - Load any component via API calls
- **Visual regression testing** - Automated screenshots for comparison
- **CI/CD integration** - Repeatable tests for continuous integration
- **Interactive debugging** - Step-by-step component testing

## Quick Start

### 1. Start Widget Workbench

```bash
cd scenic-widget-contrib
iex -S mix
```

The app will start on port 9996 with scenic_mcp server enabled.

### 2. Run the Test Harness

```bash
# Run all component loading tests
mix spex test/spex/component_loading_test_harness_spex.exs

# Run in manual mode (step-by-step)
mix spex test/spex/component_loading_test_harness_spex.exs --manual

# Run with verbose output
mix spex test/spex/component_loading_test_harness_spex.exs --verbose
```

## Programmatic Usage

### From IEx REPL

```elixir
# Start the helper module
alias ScenicWidgets.TestHelpers.ComponentTestHarness

# List all available components
components = ComponentTestHarness.list_available_components()
# => [{"Buttons", ScenicWidgets.Buttons}, {"MenuBar", ScenicWidgets.MenuBar}, ...]

# Load a specific component
{:ok, screenshot} = ComponentTestHarness.load_component("MenuBar")
# => {:ok, "/tmp/scenic_screenshot_2025-10-11_component_MenuBar.png"}

# Verify component loaded
ComponentTestHarness.component_loaded?(ScenicWidgets.MenuBar)
# => true

# Load and verify in one step
{:ok, screenshot} = ComponentTestHarness.load_and_verify_component(
  "MenuBar",
  ScenicWidgets.MenuBar
)

# Reset workbench to clean state
ComponentTestHarness.reset_workbench()

# List all clickable elements
{:ok, elements} = ComponentTestHarness.list_clickable_elements()
# => {:ok, [%{id: ":load_component_button", center: %{x: 100, y: 50}, ...}, ...]}
```

### From Test Code

```elixir
defmodule MyComponentTest do
  use ExUnit.Case
  alias ScenicWidgets.TestHelpers.ComponentTestHarness

  setup do
    # Ensure Widget Workbench is running
    unless WidgetWorkbench.running?() do
      {:ok, _pid} = WidgetWorkbench.start(size: {1200, 800})
    end

    on_exit(fn ->
      ComponentTestHarness.reset_workbench()
    end)

    :ok
  end

  test "MenuBar component loads successfully" do
    {:ok, screenshot} = ComponentTestHarness.load_component("MenuBar")

    assert ComponentTestHarness.component_loaded?(ScenicWidgets.MenuBar)
    assert File.exists?(screenshot)
  end

  test "all discovered components can load" do
    components = ComponentTestHarness.list_available_components()

    Enum.each(components, fn {name, module} ->
      assert {:ok, _screenshot} = ComponentTestHarness.load_component(name)
      assert ComponentTestHarness.component_loaded?(module)

      # Reset for next test
      ComponentTestHarness.reset_workbench()
    end)
  end
end
```

## Via scenic_mcp Tools (From Claude Code)

When Widget Workbench is running, you can control it directly from Claude Code:

```elixir
# Connect to the app
connect_scenic(port: 9996)

# Inspect what's currently displayed
inspect_viewport()

# Find clickable elements
find_clickable_elements()

# Click the load component button
click_element(element_id: "load_component_button")

# Wait a moment for modal
Process.sleep(300)

# Click a specific component (e.g., MenuBar)
click_element(element_id: "component_menu_bar")

# Take a screenshot
take_screenshot(filename: "my_test.png")
```

## Test Harness Architecture

```
Component Test Harness
├── Spex Tests (test/spex/component_loading_test_harness_spex.exs)
│   └── High-level test scenarios using Given-When-Then
│
├── Helper Module (lib/test_helpers/component_test_harness.ex)
│   ├── load_component/2 - Load component by name
│   ├── component_loaded?/1 - Verify component in viewport
│   ├── list_available_components/0 - Discover components
│   ├── reset_workbench/0 - Clean state
│   └── list_clickable_elements/0 - Query UI elements
│
└── scenic_mcp Integration (scenic_mcp/lib/scenic_mcp/tools.ex)
    ├── click_element/1 - Click by semantic ID
    ├── find_clickable_elements/0 - Discover elements
    ├── inspect_viewport/0 - Get UI structure
    └── take_screenshot/1 - Visual capture
```

## Component Semantic IDs

Components in the modal are registered with semantic IDs following this pattern:

```
component_#{Macro.underscore(component_name)}
```

Examples:
- `"MenuBar"` → `:component_menu_bar`
- `"IconButton"` → `:component_icon_button`
- `"SideNav"` → `:component_side_nav`

You can find the exact ID using:

```elixir
ComponentTestHarness.find_component_button("MenuBar")
# => {:ok, :component_menu_bar}
```

## Visual Regression Testing

Screenshots are automatically saved to `/tmp/` with timestamps:

```
/tmp/scenic_screenshot_2025-10-11_12-30-45_component_MenuBar.png
```

You can compare these screenshots across test runs to detect visual regressions:

```elixir
# Baseline screenshot
{:ok, baseline} = ComponentTestHarness.load_component("MenuBar",
  screenshot_name: "menubar_baseline")

# Make code changes, restart app

# New screenshot
{:ok, current} = ComponentTestHarness.load_component("MenuBar",
  screenshot_name: "menubar_current")

# Compare with image diff tool (e.g., ImageMagick)
System.cmd("compare", [baseline, current, "/tmp/diff.png"])
```

## Troubleshooting

### Component button not found

If `load_component/1` returns `{:error, "Component button not found"}`:

1. **Check modal is open**:
   ```elixir
   inspect_viewport()  # Should show modal content
   ```

2. **List available elements**:
   ```elixir
   {:ok, elements} = ComponentTestHarness.list_clickable_elements()
   IO.inspect(elements)
   ```

3. **Verify component name matches**:
   ```elixir
   components = ComponentTestHarness.list_available_components()
   IO.inspect(components)
   ```

### scenic_mcp connection timeout

If MCP calls timeout:

1. **Check server is running**:
   ```elixir
   Process.whereis(ScenicMcp.Server)
   # Should return a PID
   ```

2. **Restart Widget Workbench**:
   ```bash
   # Kill existing iex
   # Restart
   cd scenic-widget-contrib && iex -S mix
   ```

3. **Check port availability**:
   ```bash
   lsof -i :9996
   ```

### Component loads but verification fails

If `component_loaded?/1` returns `false`:

1. **Check script table**:
   ```elixir
   alias ScenicWidgets.TestHelpers.ScriptInspector
   ScriptInspector.debug_script_table()
   ```

2. **Wait longer for render**:
   ```elixir
   ComponentTestHarness.load_component("MenuBar", wait_ms: 2000)
   ```

3. **Verify module name**:
   ```elixir
   # Make sure you're checking the right module
   components = ComponentTestHarness.list_available_components()
   {_name, correct_module} = Enum.find(components, fn {name, _mod} ->
     name == "MenuBar"
   end)
   ComponentTestHarness.component_loaded?(correct_module)
   ```

## Examples

### Example 1: Load and Test All Components

```elixir
alias ScenicWidgets.TestHelpers.ComponentTestHarness

components = ComponentTestHarness.list_available_components()

results = Enum.map(components, fn {name, module} ->
  IO.puts("Testing #{name}...")

  case ComponentTestHarness.load_and_verify_component(name, module) do
    {:ok, screenshot} ->
      IO.puts("  ✅ #{name} loaded successfully")
      {:ok, name, screenshot}

    {:error, reason} ->
      IO.puts("  ❌ #{name} failed: #{reason}")
      {:error, name, reason}
  end

  ComponentTestHarness.reset_workbench()
  Process.sleep(500)
end)

# Print summary
successes = Enum.count(results, &match?({:ok, _, _}, &1))
failures = Enum.count(results, &match?({:error, _, _}, &1))

IO.puts("\n📊 Results: #{successes} passed, #{failures} failed")
```

### Example 2: Interactive Component Exploration

```elixir
alias ScenicWidgets.TestHelpers.ComponentTestHarness

# Start interactive session
defmodule ComponentExplorer do
  def explore do
    components = ComponentTestHarness.list_available_components()

    IO.puts("\n📦 Available Components:")
    components
    |> Enum.with_index(1)
    |> Enum.each(fn {{name, _module}, idx} ->
      IO.puts("  #{idx}. #{name}")
    end)

    IO.puts("\nEnter component number to load (or 'q' to quit):")

    case IO.gets("> ") |> String.trim() do
      "q" -> :ok
      num_str ->
        case Integer.parse(num_str) do
          {num, _} when num > 0 and num <= length(components) ->
            {name, module} = Enum.at(components, num - 1)
            IO.puts("\nLoading #{name}...")

            case ComponentTestHarness.load_and_verify_component(name, module) do
              {:ok, screenshot} ->
                IO.puts("✅ Loaded! Screenshot: #{screenshot}")
                IO.puts("Press Enter to reset and continue...")
                IO.gets("")
                ComponentTestHarness.reset_workbench()
                explore()

              {:error, reason} ->
                IO.puts("❌ Failed: #{reason}")
                explore()
            end

          _ ->
            IO.puts("Invalid number")
            explore()
        end
    end
  end
end

ComponentExplorer.explore()
```

## CI/CD Integration

Add to your GitHub Actions workflow:

```yaml
- name: Run Component Test Harness
  run: |
    cd scenic-widget-contrib
    mix deps.get
    mix compile
    # Start Widget Workbench in background
    iex -S mix &
    WB_PID=$!
    sleep 5  # Wait for startup
    # Run tests
    mix spex test/spex/component_loading_test_harness_spex.exs
    # Cleanup
    kill $WB_PID
```

## Next Steps

1. **Add more spex scenarios** - Test specific component interactions
2. **Implement visual diffing** - Automated screenshot comparison
3. **Add performance metrics** - Track component load times
4. **Create component-specific tests** - Deep testing for each widget

## Related Files

- **Spex test**: `test/spex/component_loading_test_harness_spex.exs`
- **Helper module**: `lib/test_helpers/component_test_harness.ex`
- **scenic_mcp tools**: `../scenic_mcp/lib/scenic_mcp/tools.ex`
- **Widget Workbench scene**: `lib/widget_workbench/widget_wkb_scene.ex`
- **Script inspector**: `lib/test_helpers/script_inspector.ex`

## Support

For issues or questions:
- Check the session notes in `NEXT_SESSION_PROMPT.md`
- Review `WIDGET_WKB_BASE_PROMPT.md` for architecture details
- See `SESSION_SUMMARY_2025-10-11.md` for recent changes
