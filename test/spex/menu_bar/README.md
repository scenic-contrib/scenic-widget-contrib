# MenuBar Component Spex

This directory contains executable specifications (spex) for the MenuBar component, organized in development order.

## Spex Files

### 01_basic_load_spex.exs
**Purpose**: Foundation test - verifies MenuBar can boot and display basic structure
**Tests**:
- Widget Workbench boots successfully
- MenuBar component can be loaded
- Menu headers (File, Edit, View, Help) are visible

**Success Criteria**: At least 2 menu headers visible after loading

---

## Running Spex Tests

### Prerequisites
- **Local machine with display** (tests must be run locally, not remotely)
- **Scenic Driver Local compiled** (`cd deps/scenic_driver_local && make`)
- **All dependencies installed** (`mix deps.get`)
- **Test environment** (`MIX_ENV=test`)

### Running Tests

```bash
# Run all MenuBar spex (with test environment)
MIX_ENV=test mix spex test/spex/menu_bar/

# Run specific spex file
MIX_ENV=test mix spex test/spex/menu_bar/01_basic_load_spex.exs

# Run with verbose output
MIX_ENV=test mix spex test/spex/menu_bar/01_basic_load_spex.exs --verbose

# Watch mode (auto-run on file changes)
MIX_ENV=test mix spex.watch test/spex/menu_bar/
```

**Important**: Always use `MIX_ENV=test` when running spex! This ensures:
- MCP server runs on port 9998 (avoiding conflict with dev on 9996)
- Test-specific configuration is loaded
- Test helpers are compiled and available

### Troubleshooting

**Error: "GenServer :scenic_driver terminating"**
- **Cause**: Not running on a machine with a display
- **Solution**: Run tests on your local machine with graphical environment

**Error: "Widget Workbench not detected"**
- **Cause**: Scene didn't start properly or took too long to initialize
- **Solution**: Increase sleep time in setup_all, or check logs for startup errors

**Error: "Element not found" or "Modal didn't open"**
- **Cause**: UI element positions may have changed in scene layout
- **Solution**: Check `semantic_ui.ex` helper functions for correct coordinate calculations

---

## Development Workflow

When adding new spex for MenuBar:

1. **Identify the behavior to specify**
   - What user-facing feature are we testing?
   - What's the expected outcome?

2. **Write the spex FIRST** (before implementation)
   - Create new file: `NN_feature_name_spex.exs` (NN = next number)
   - Use Given-When-Then structure
   - Document why this spex exists

3. **Run failing spex** to verify red phase
   ```bash
   mix spex test/spex/menu_bar/NN_feature_name_spex.exs
   ```

4. **Implement** minimum code to pass

5. **Iterate** until green

6. **Update** this README with the new spex info

---

## Spex Framework Notes

- Uses **SexySpex** framework (from https://github.com/JediLuke/spex)
- `use SexySpex` in module definition
- Given-When-Then DSL for scenarios
- Built on ExUnit under the hood
- **Tests run synchronously** (`async: false`) - only one spex runs at a time
  - This is critical since all spex share the same viewport (`:test_viewport`)
  - No race conditions or viewport conflicts between tests

### Setup Pattern for Scenic Spex

The standard pattern for setting up Scenic GUI tests:

```elixir
setup_all do
  # 1. Kill any existing viewport (prevents naming conflicts)
  if viewport_pid = Process.whereis(:main_viewport) do
    Process.exit(viewport_pid, :kill)
    Process.sleep(100)
  end

  # 2. Start the application
  Application.ensure_all_started(:scenic_widget_contrib)

  # 3. Configure viewport (MUST use :main_viewport and :scenic_driver names)
  viewport_config = [
    name: :main_viewport,  # Required by ScenicMCP
    size: {1200, 800},
    theme: :dark,
    default_scene: {WidgetWorkbench.Scene, []},
    drivers: [
      [module: Scenic.Driver.Local, name: :scenic_driver, ...]
    ]
  ]

  # 4. Start viewport
  {:ok, viewport_pid} = Scenic.ViewPort.start_link(viewport_config)
  Process.sleep(1500)  # Wait for scene initialization

  # 5. Register cleanup
  on_exit(fn ->
    if pid = Process.whereis(:main_viewport) do
      Process.exit(pid, :normal)
      Process.sleep(100)
    end
  end)

  {:ok, %{viewport_pid: viewport_pid}}
end
```

**Key Points**:
- **Viewport and driver names are configurable** via `config :scenic_mcp`
- **Test environment uses different names** to allow simultaneous dev/test viewports:
  - Dev: `:main_viewport` and `:scenic_driver` on port 9996
  - Test: `:test_viewport` and `:test_driver` on port 9998
- This allows you to run Widget Workbench in dev mode WHILE running spex tests
- Pull names from config: `Application.get_env(:scenic_mcp, :viewport_name)`
- Always kill existing viewport first to avoid naming conflicts
- Wait after viewport startup for scene to initialize

### Helper Modules

**SemanticUI** (`test/test_helpers/semantic_ui.ex`):
- `verify_widget_workbench_loaded()` - Check if WW is running
- `load_component(name)` - Complete workflow to load a component
- `verify_component_loaded(name)` - Verify component is visible
- `click_load_component_button()` - Intelligently find and click button
- `click_component_in_modal(name)` - Select component from modal

**ScriptInspector** (`test/test_helpers/script_inspector.ex`):
- `get_rendered_text_string()` - Get all visible text from scene
- `rendered_text_contains?(text)` - Check if text is visible
- `get_render_stats()` - Get statistics about rendered content
- `get_script_table_directly()` - Access ETS script table

---

## Future Spex Ideas

Potential spex to add for MenuBar component:

- [ ] `02_menu_interaction_spex.exs` - Click menu headers, verify dropdowns open
- [ ] `03_menu_item_selection_spex.exs` - Click menu items, verify events fire
- [ ] `04_keyboard_navigation_spex.exs` - Arrow keys, Escape, Enter
- [ ] `05_hover_states_spex.exs` - Hover over menus/items, verify visual feedback
- [ ] `06_submenu_navigation_spex.exs` - Multi-level menu navigation
- [ ] `07_menu_close_behavior_spex.exs` - Escape key, outside click
- [ ] `08_accessibility_spex.exs` - Semantic IDs, keyboard-only navigation

---

## Notes for AI Assistants

When working on MenuBar spex:

1. **Always use SexySpex** (not plain Spex) - `use SexySpex`
2. **Leverage semantic helpers** - Don't calculate coordinates manually
3. **Document tradeoffs** - If a test is flaky, document why
4. **One behavior per spex file** - Keep tests focused
5. **Run tests locally** - Cannot run in headless/remote environments
6. **Update this README** - When adding new spex files, document them here
