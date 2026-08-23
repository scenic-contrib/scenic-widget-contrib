# Spex Execution Model

## Synchronous Test Execution

All SexySpex tests run **synchronously** (one at a time), configured by:

```elixir
# In SexySpex framework (lib/sexy_spex.ex:159)
use ExUnit.Case, async: false
```

This is automatically applied when you `use SexySpex` in your test files.

## Why This Matters

### Viewport Sharing
All MenuBar spex share the same test viewport:
- **Viewport name**: `:test_viewport`
- **Driver name**: `:test_driver`
- **Port**: 9998

If tests ran in parallel (`async: true`), they would:
- ❌ Compete for the same viewport
- ❌ Interfere with each other's UI state
- ❌ Cause race conditions
- ❌ Produce flaky, unreliable tests

### Synchronous Execution Guarantees

✅ **One test at a time** - No viewport conflicts
✅ **Clean state** - Each test gets fresh viewport (via `setup_all`)
✅ **Predictable** - Tests execute in deterministic order
✅ **Reliable** - No race conditions or timing issues

## Execution Flow

When you run multiple spex files:

```bash
MIX_ENV=test mix spex test/spex/menu_bar/
```

Execution happens like this:

```
1. Run 01_basic_load_spex.exs
   ├─ setup_all: Start viewport
   ├─ Run all scenarios
   └─ on_exit: Stop viewport

2. Run 02_menu_interaction_spex.exs  (when created)
   ├─ setup_all: Start viewport
   ├─ Run all scenarios
   └─ on_exit: Stop viewport

3. Run 03_menu_item_click_spex.exs  (when created)
   ├─ setup_all: Start viewport
   ├─ Run all scenarios
   └─ on_exit: Stop viewport
```

**Each test file runs completely before the next one starts.**

## Performance Implications

### Pros
- ✅ No flakiness from race conditions
- ✅ Reliable, reproducible results
- ✅ Safe viewport/driver state management
- ✅ Easier to debug (sequential execution)

### Cons
- ⏱️ Tests take longer (can't parallelize)
- ⏱️ Each test pays viewport startup cost (~1.5s)

### Mitigation Strategies

1. **Group related tests in same file**
   ```elixir
   spex "MenuBar interactions" do
     scenario "Click File menu" do ... end
     scenario "Click Edit menu" do ... end
     scenario "Click View menu" do ... end
   end
   ```
   - Shares single viewport across scenarios
   - Faster than 3 separate files

2. **Use `mix spex.watch`** for development
   - Only runs tests that changed
   - Faster feedback loop

3. **Keep individual spex fast**
   - Minimize sleep/wait times
   - Use semantic helpers (they're optimized)
   - Focus each spex on one behavior

## Comparison with Standard ExUnit

| Feature | SexySpex | Standard ExUnit |
|---------|----------|-----------------|
| Async | `false` (sequential) | `true` (default, parallel) |
| Shared State | ✅ Safe | ❌ Risky |
| Performance | Slower | Faster |
| GUI Testing | ✅ Perfect | ❌ Problematic |
| Flakiness | Low | High (for GUI) |

## When Sequential Execution is Essential

Sequential execution (`async: false`) is **required** when:

1. **Shared Resources**
   - Viewport (our case)
   - Database connections
   - File system state
   - External services

2. **Order Dependencies**
   - Tests that build on each other
   - Setup that persists between tests

3. **State Mutation**
   - Tests that modify global state
   - GUI tests (screen state)

## Spex-Specific Behavior

Each spex file has its own lifecycle:

```elixir
defmodule MyWidgetSpex do
  use SexySpex  # Sets async: false

  setup_all do
    # Runs ONCE per file, before any scenarios
    start_viewport()
    on_exit(fn -> stop_viewport() end)
  end

  setup do
    # Runs BEFORE EACH scenario
    # Reset any per-scenario state
  end

  spex "Feature A" do
    scenario "A1" do ... end  # Uses viewport
    scenario "A2" do ... end  # Reuses same viewport
  end
end
```

**Key Point**: All scenarios in a file share the same viewport from `setup_all`.

## Best Practices

1. **One spex file per feature**
   - Group related scenarios together
   - Minimize viewport startup overhead

2. **Independent scenarios**
   - Each scenario should work alone
   - Don't rely on scenario execution order

3. **Clean state between scenarios**
   - Use `setup` callback if needed
   - Reset widget state explicitly

4. **Fast feedback**
   - Keep individual scenarios focused
   - Run specific files during development:
     ```bash
     MIX_ENV=test mix spex test/spex/menu_bar/01_basic_load_spex.exs
     ```

## Summary

- ✅ SexySpex runs tests **synchronously** by default
- ✅ This is **intentional** and **correct** for GUI testing
- ✅ No configuration needed - it just works
- ✅ All MenuBar spex can safely share `:test_viewport`
- ✅ No risk of parallel execution conflicts

The framework has us covered! 🎯
