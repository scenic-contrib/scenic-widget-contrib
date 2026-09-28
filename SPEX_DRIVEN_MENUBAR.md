# Spex-Driven MenuBar Development

## Overview

This document outlines the spex-driven development approach for creating a rock-solid MenuBar component. By using executable specifications (spex) as our primary development driver, we ensure that every aspect of the MenuBar is thoroughly tested and validated.

## The Spex-Driven Development Loop

```
1. Write Spex → 2. Run Spex → 3. See Failures → 4. Implement/Fix → 5. Run Spex → 6. Refactor
     ↑                                                                              ↓
     └──────────────────────────────────────────────────────────────────────────┘
```

## MenuBar Spex Suite Structure

### 1. **Visual Rendering Specs** (`menubar_spec_suite.exs`)
- Basic rendering with correct dimensions
- Menu item alignment and spacing
- Theme application and consistency
- Responsive layout behavior

### 2. **Interaction Specs**
- Hover behavior and highlighting
- Click to open/close dropdowns
- Mouse movement between menus
- Focus management

### 3. **Performance Specs** (`menubar_flicker_test_spex.exs`)
- Render efficiency during rapid interactions
- Flicker detection and prevention
- State update optimization
- Memory usage patterns

### 4. **State Management Specs**
- Single dropdown constraint
- State consistency across interactions
- Proper cleanup on close
- Event handler efficiency

### 5. **Keyboard Navigation Specs**
- Arrow key navigation
- Enter/Space to open menus
- Escape to close
- Tab navigation support

### 6. **Edge Case Specs**
- Empty menus
- Very long menu labels
- Deeply nested menus
- Rapid state changes

## Running the Spex Suite

### Single Run
```bash
# Run all MenuBar specs
mix spex test/spex/menubar*.exs

# Run specific spec
mix spex test/spex/menubar_flicker_test_spex.exs

# Run with verbose output
mix spex test/spex/menubar_spec_suite.exs --verbose
```

### Watch Mode (Continuous Development)
```bash
# Watch all MenuBar specs
mix spex_watch test/spex/menubar*.exs

# Focus on flicker tests
mix spex_watch --focus flicker

# Verbose watch mode
mix spex_watch --verbose
```

## Fixing the Flickering Issue

The flickering in MenuBar is likely caused by:

1. **Complete re-renders on state changes** - The current `update_graph` function rebuilds the entire graph
2. **Inefficient dropdown toggling** - Dropdowns might be destroyed and recreated
3. **Excessive state updates** - Every mouse movement might trigger a full update

### Spex-Driven Fix Process

1. **Run the flicker test spex**:
   ```bash
   mix spex test/spex/menubar_flicker_test_spex.exs
   ```

2. **Identify the failure points**:
   - How many renders per interaction?
   - Where are the render spikes?
   - What triggers excessive updates?

3. **Implement targeted fixes**:
   - **Option A**: Implement proper graph diffing in `Renderizer.update_graph/2`
   - **Option B**: Use visibility toggling instead of add/remove for dropdowns
   - **Option C**: Debounce hover events to reduce state updates

4. **Verify with spex**:
   - Run the test again
   - Ensure render count is within acceptable limits
   - Check that visual behavior is still correct

## Example Fix Implementation

Here's a potential fix for the renderizer pattern:

```elixir
defmodule WidgetWorkbench.Components.MenuBar.Renderizer do
  # ... existing code ...
  
  def update_graph(existing_graph, %State{} = state) do
    # Instead of rebuilding, update only what changed
    existing_graph
    |> update_hover_states(state)
    |> update_dropdown_visibility(state)
  end
  
  defp update_hover_states(graph, %State{} = state) do
    # Update only the hover highlights
    state.menu_map
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {{menu_id, _}, index}, g ->
      is_hovered = state.hovered_item == menu_id
      
      # Update just the header background
      Graph.modify(g, {:menu_header_bg, menu_id}, fn primitive ->
        Primitive.put_style(primitive, :fill, 
          if(is_hovered, do: state.theme.hover, else: state.theme.background)
        )
      end)
    end)
  end
  
  defp update_dropdown_visibility(graph, %State{active_menu: active_menu} = state) do
    # Toggle visibility instead of adding/removing
    state.menu_map
    |> Enum.reduce(graph, fn {menu_id, _}, g ->
      Graph.modify(g, {:dropdown_group, menu_id}, fn primitive ->
        Primitive.put_style(primitive, :hidden, menu_id != active_menu)
      end)
    end)
  end
end
```

## Continuous Improvement

As you work through the spex suite:

1. **Add new specs** when you discover edge cases
2. **Refactor specs** to be more precise and maintainable
3. **Extract common patterns** into helper functions
4. **Document findings** in code comments

## Success Metrics

The MenuBar component is considered "rock solid" when:

- ✅ All specs pass consistently
- ✅ Render count per interaction < 3
- ✅ No visual flickering detected
- ✅ Smooth transitions between states
- ✅ Keyboard navigation fully functional
- ✅ Memory usage stable over time
- ✅ Works across different screen sizes

## Next Steps

1. Run the comprehensive spex suite
2. Fix all failing specs using the iterative approach
3. Add additional specs for any discovered edge cases
4. Profile and optimize based on performance specs
5. Document the final implementation patterns