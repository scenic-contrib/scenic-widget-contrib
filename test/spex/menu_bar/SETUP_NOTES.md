# MenuBar Spex Setup - Session Notes

This document captures the key learnings and decisions from setting up the MenuBar spex infrastructure.

## What We Accomplished

1. **Created First Organized Spex**: `test/spex/menu_bar/01_basic_load_spex.exs`
   - Clean, well-documented structure following SexySpex patterns
   - Tests basic MenuBar loading functionality
   - Serves as template for future widget spex

2. **Solved Viewport Naming Conflict**
   - **Problem**: Dev and test environments both tried to use `:main_viewport` and `:scenic_driver`
   - **Solution**: Made viewport/driver names configurable via `config/test.exs`
   - **Result**: Can now run dev viewport (port 9996) and test viewport (port 9998) simultaneously

3. **Updated Test Helpers** to use configured names:
   - `script_inspector.ex` - Reads from configured viewport
   - `semantic_ui.ex` - Interacts with configured driver/viewport
   - All helpers now environment-aware

4. **Comprehensive Documentation**
   - Created `test/spex/menu_bar/README.md` with patterns and examples
   - Updated `WIDGET_WKB_BASE_PROMPT.md` with framework clarifications
   - Documented all common pitfalls and solutions

## Key Technical Decisions

### Framework Naming
- Project uses **SexySpex** (not just "Spex")
- Package name: `sexy_spex`
- GitHub repo: https://github.com/JediLuke/spex
- Use `use SexySpex` in test files

### Viewport Configuration Strategy

**Before** (Hardcoded - caused conflicts):
```elixir
viewport_config = [
  name: :main_viewport,      # Hardcoded!
  drivers: [[name: :scenic_driver]]  # Hardcoded!
]
```

**After** (Configurable - allows simultaneous operation):
```elixir
# config/test.exs
config :scenic_mcp,
  port: 9998,
  viewport_name: :test_viewport,   # Different from dev
  driver_name: :test_driver         # Different from dev

# test file setup
viewport_name = Application.get_env(:scenic_mcp, :viewport_name)
driver_name = Application.get_env(:scenic_mcp, :driver_name)

viewport_config = [
  name: viewport_name,
  drivers: [[name: driver_name]]
]
```

**Benefits**:
- Dev and test can run simultaneously
- Each has its own MCP server on different port
- No process name conflicts
- Can develop widgets while tests run in background

### Test Helper Updates

All test helpers now pull configuration:
```elixir
# Instead of hardcoded :main_viewport
viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :main_viewport)
Scenic.ViewPort.info(viewport_name)
```

This makes helpers work in both dev and test environments seamlessly.

## Important Gotchas We Discovered

### 1. Local Display Required
- **Issue**: Scenic Driver Local requires a real graphical environment
- **Impact**: Spex tests must be run on local machine with display
- **Solution**: Always run tests locally, not remotely

### 2. Mix Environment is Critical
- **Always use** `MIX_ENV=test` when running spex
- Ensures correct config loaded (port 9998, test viewport names)
- Ensures test helpers are compiled
- Without it, tests may conflict with dev viewport

### 3. ScenicMCP Configuration
- ScenicMCP already supports configurable viewport/driver names via `ScenicMcp.Config`
- No changes needed to ScenicMCP codebase
- Just configure in `config/test.exs` and `config/dev.exs`

### 4. Process Cleanup is Essential
- Always kill existing viewport before starting new one
- Use `on_exit` callback to cleanup after tests
- Sleep after exit to allow full cleanup (100ms is good)

## Standard Spex Setup Pattern

This is the canonical pattern for all future widget spex:

```elixir
defmodule ScenicWidgets.MyWidget.SomeSpex do
  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}

  setup_all do
    # 1. Get environment-specific names (allows dev/test to coexist)
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)

    # 2. Kill any existing viewport with same name
    if viewport_pid = Process.whereis(viewport_name) do
      Process.exit(viewport_pid, :kill)
      Process.sleep(100)
    end

    # 3. Start application
    Application.ensure_all_started(:scenic_widget_contrib)

    # 4. Configure viewport with environment-specific names
    viewport_config = [
      name: viewport_name,
      size: {1200, 800},
      theme: :dark,
      default_scene: {WidgetWorkbench.Scene, []},
      drivers: [[
        module: Scenic.Driver.Local,
        name: driver_name,
        window: [title: "Test Window"],
        debug: false,
        cursor: true
      ]]
    ]

    # 5. Start viewport and wait for init
    {:ok, viewport_pid} = Scenic.ViewPort.start_link(viewport_config)
    Process.sleep(1500)

    # 6. Register cleanup
    on_exit(fn ->
      if pid = Process.whereis(viewport_name) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)

    {:ok, %{viewport_pid: viewport_pid}}
  end

  spex "My widget behavior" do
    scenario "Some interaction", context do
      given_ "initial state", context do
        # Use semantic helpers
        {:ok, context}
      end

      when_ "action occurs", context do
        # Perform actions
        {:ok, context}
      end

      then_ "expected outcome", context do
        # Assertions
        :ok
      end
    end
  end
end
```

## Future Improvements

1. **Create spex template generator**
   - `mix spex.new widget_name` to scaffold new spex
   - Auto-generates file with standard pattern

2. **Enhance semantic helpers**
   - Add more high-level interaction helpers
   - Screenshot comparison utilities
   - State inspection helpers

3. **CI Integration**
   - Add Xvfb setup to CI pipeline
   - Parallel spex execution
   - Screenshot artifact collection

4. **Documentation**
   - Video walkthrough of spex-driven development
   - More example spex for common patterns
   - Troubleshooting cookbook

## References

- SexySpex Framework: https://github.com/JediLuke/spex
- ScenicMCP Configuration: `../scenic_mcp_experimental/lib/scenic_mcp/config.ex`
- Widget Workbench Source: `lib/widget_workbench.ex`
- Base Prompt: `WIDGET_WKB_BASE_PROMPT.md`

## Testing This Setup

To verify everything works:

```bash
# Terminal 1: Run Widget Workbench in dev mode
iex -S mix
iex> WidgetWorkbench.start()
# Now using :main_viewport on port 9996

# Terminal 2: Run spex tests
MIX_ENV=test mix spex test/spex/menu_bar/01_basic_load_spex.exs
# Creates :test_viewport on port 9998

# Both should run simultaneously without conflicts!
```

## Conclusion

We now have a solid foundation for spex-driven MenuBar development:
- ✅ Proper viewport isolation between dev and test
- ✅ Configurable process names via environment
- ✅ Clean, documented spex template
- ✅ Updated test helpers
- ✅ Comprehensive documentation

Next steps:
1. Run the first spex locally to verify it works
2. Iterate on MenuBar functionality using failing spex
3. Add more spex for interaction, keyboard nav, etc.
4. Build up organized test suite incrementally
