# MenuBar Flicker Fix Plan - Spex-Driven Development

## Problem Analysis

The MenuBar flickering issue is caused by:
1. **Complete graph rebuilds** on every state change
2. **Lack of selective updates** - everything re-renders even for small changes
3. **No pre-rendering** - dropdowns are created/destroyed on open/close

## Solution: Optimized MenuBar Implementation

### Key Improvements

1. **Pre-render all dropdowns** (hidden by default)
   - All dropdowns exist in the graph from initialization
   - Toggle visibility instead of add/remove
   - Reduces render operations

2. **Selective graph updates**
   - Use `Graph.modify` instead of rebuilding
   - Update only changed elements
   - Track old vs new state to minimize updates

3. **Efficient state management**
   - Separate hover state for headers and dropdown items
   - Batch related updates
   - Avoid unnecessary state changes

## Implementation Status

### ✅ Completed
- Created `OptimizedRenderizer` module with selective update logic
- Created `OptimizedMenuBar` component using the new renderizer
- Pre-rendering of all dropdowns with visibility toggling
- Proper state tracking for hover and active states

### 🔄 Next Steps

1. **Fix the current MenuBar in Widget Workbench**
   ```elixir
   # Update WidgetWorkbench.Scene to use OptimizedMenuBar
   # In render_main_content/3, replace MenuBar with OptimizedMenuBar
   ```

2. **Create integration test**
   ```elixir
   # Test that loads MenuBar through Widget Workbench UI
   # Measures actual render performance
   ```

3. **Validate with spex tests**
   - Run flicker detection spex
   - Verify render counts are within limits
   - Test rapid interactions

## Spex-Driven Development Process

### 1. Write Failing Spex
```elixir
# Test that detects flickering
scenario "No flicker during rapid hover" do
  when_ "mouse moves rapidly between menus" do
    # Simulate rapid movements
  end
  
  then_ "render count is minimal" do
    assert render_count < threshold
  end
end
```

### 2. Implement Fix
- Use OptimizedMenuBar instead of regular MenuBar
- Ensure proper graph updates

### 3. Verify Spex Passes
```bash
mix spex test/spex/menubar_flicker_test_spex.exs
```

### 4. Refine and Iterate
- Add more edge case tests
- Optimize further if needed

## Manual Testing in Widget Workbench

1. Start Widget Workbench
2. Load MenuBar component
3. Rapidly move mouse between menu headers
4. Open/close dropdowns quickly
5. Observe for visual flickering

## Performance Metrics

Target performance:
- **Hover update**: < 2 renders
- **Dropdown open/close**: < 3 renders
- **Menu switch**: < 4 renders
- **No visual flickering**

## Integration Path

1. Test OptimizedMenuBar in isolation
2. Replace MenuBar with OptimizedMenuBar in Widget Workbench
3. Run comprehensive spex suite
4. Profile and optimize further if needed
5. Port improvements back to Flamelex