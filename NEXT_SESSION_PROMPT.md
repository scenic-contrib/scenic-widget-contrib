# Widget Workbench - Next Session Tasks

## Current Status ✅

The Widget Workbench now has **fully functional scrolling** in the component selection modal:
- ✅ Transform-based scrolling (no re-rendering)
- ✅ Proper scissor clipping (nested group structure)
- ✅ Mouse wheel scrolling works
- ✅ Keyboard arrow key scrolling works
- ✅ Visual scrollbar with proportional thumb
- ✅ All buttons remain visible during scroll
- ✅ MCP semantic registration for automation

## Next Phase: Automated Component Loading & Consistent Origin

### Task 1: Programmable Component Loading Flow

**Goal**: Create a reliable, repeatable flow to programmatically load any component via MCP automation.

**Requirements**:
1. Open component modal
2. Find component by name (may require scrolling)
3. Click component to load it
4. Verify component loaded successfully
5. All via scenic_mcp tools for full automation

**Implementation Strategy**:
```elixir
# Example flow:
1. click_element("load_component_button")
2. find_clickable_elements() to get all component buttons
3. If target component not visible, scroll until found
4. click_element("component_#{component_name}")
5. Verify component loaded in workbench
```

**Challenges to solve**:
- Detecting if a component is currently visible in viewport
- Calculating scroll amount needed to reach a specific component
- Handling components at different scroll positions
- Semantic IDs for component buttons (already implemented: `component_buttons`, `component_menu_bar`, etc.)

### Task 2: Consistent Component Origin Point

**Problem**:
- Components currently render inconsistently
- First load: renders in middle of whitespace
- Second load: snaps to top-left corner
- No clear visual indicator of where components should anchor

**Goal**: Establish a consistent, visible origin point for component rendering.

**Requirements**:
1. **Define Origin**: Set a fixed origin point at approximately (50, 50) or similar
2. **Visual Marker**: Render a visible origin marker (small crosshair or dot with label)
3. **Consistent Positioning**: All components should render relative to this origin
4. **Persistent Across Reloads**: Origin stays the same even when loading different components
5. **Buffer Space**: Origin should have comfortable padding from edges

**Implementation Details**:

```elixir
# In widget_wkb_scene.ex:

# Define origin constant
@component_origin_x 100
@component_origin_y 100

# Render origin marker (always visible)
defp render_origin_marker(graph) do
  graph
  |> Primitives.circle(
    5,
    fill: {:color, {255, 0, 0}},  # Red dot
    translate: {@component_origin_x, @component_origin_y},
    id: :origin_marker
  )
  |> Primitives.line(
    {{@component_origin_x - 10, @component_origin_y}, {@component_origin_x + 10, @component_origin_y}},
    stroke: {2, {:color, {255, 0, 0}}},  # Horizontal line
    id: :origin_crosshair_h
  )
  |> Primitives.line(
    {{@component_origin_x, @component_origin_y - 10}, {@component_origin_x, @component_origin_y + 10}},
    stroke: {2, {:color, {255, 0, 0}}},  # Vertical line
    id: :origin_crosshair_v
  )
  |> Primitives.text(
    "Origin",
    font_size: 12,
    fill: {:color, {255, 0, 0}},
    translate: {@component_origin_x + 15, @component_origin_y + 5},
    id: :origin_label
  )
end

# Update component rendering to use origin
defp render_main_content(graph, frame, nil = _selected_component, _click_viz) do
  # Render origin marker when no component loaded
  graph
  |> render_origin_marker()
  |> Primitives.text(
    "No component loaded",
    translate: {@component_origin_x, @component_origin_y + 30}
  )
end

defp render_main_content(graph, frame, selected_component, _click_viz) do
  # Calculate component frame relative to origin
  component_frame = Frame.new(%{
    pin: {@component_origin_x, @component_origin_y},
    size: {frame.size.width - @component_origin_x - 100, frame.size.height - @component_origin_y - 100}
  })

  graph
  |> render_origin_marker()  # Always show origin
  |> render_loaded_component(selected_component, component_frame)
end
```

**Expected Result**:
- Clear red crosshair at (100, 100) marking the origin
- "Origin" label next to marker
- All components render with top-left at this origin point
- Origin visible at all times (behind or beside component)
- Consistent behavior across component loads/reloads

### Task 3: Component Frame Investigation

**Questions to Answer**:
1. Why does component positioning change between first and second load?
2. Where is the frame/translate being calculated for components?
3. How does `render_loaded_component` determine positioning?
4. Is there a frame recalculation happening on second load?

**Files to Investigate**:
- `lib/widget_workbench/widget_wkb_scene.ex` lines 180-240 (render_main_content)
- Component frame calculation logic
- Any transforms applied to loaded components

## Testing Checklist

After implementing:
- [ ] Origin marker visible at startup
- [ ] Origin marker visible when component loaded
- [ ] Components consistently render at origin across multiple loads
- [ ] Origin marker doesn't interfere with component interaction
- [ ] Can programmatically load any component via MCP
- [ ] Can scroll to find components not initially visible
- [ ] Component loading works reliably via automation

## Reference Information

**Key Files**:
- Main scene: `lib/widget_workbench/widget_wkb_scene.ex`
- Modal component: `lib/widget_workbench/components/modal.ex` (if needed)
- Base prompt: `WIDGET_WKB_BASE_PROMPT.md`

**MCP Port**: 9996 (Widget Workbench runs Scenic MCP on port 9996)

**Current Scrolling Implementation**:
- Nested group structure (lines 540-558)
- Outer container: Fixed position with scissor
- Inner scroll group: Translates for scrolling (ID: `:component_list_scroll_group`)
- Transform updates via `Graph.modify()` (no re-rendering)

**Component Discovery**:
```elixir
# Components are discovered from lib/components/
discover_components()  # Returns [{name, module}, ...]
```

## Success Criteria

1. ✅ Can write instructions like: "Load the Menu Bar component into workbench"
2. ✅ MCP automation can execute: open modal → scroll to component → click → verify
3. ✅ All components render at consistent origin point
4. ✅ Origin marker clearly visible and labeled
5. ✅ No positioning inconsistencies between loads
6. ✅ Origin persists across all scene changes
7. ✅ Buffer space around origin for comfortable development

## Notes for Next Session

- The scrolling infrastructure is solid and performant
- Focus on predictability and automation
- Origin marker should be subtle but clear
- Consider adding grid lines around origin for reference (optional)
- May want to make origin position configurable later
