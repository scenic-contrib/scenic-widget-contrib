# Semantic Click Implementation - Handover Document

## Problem Statement

Currently, clicking elements via scenic_mcp requires manual coordinate calculation, which is error-prone and non-deterministic. We need a system similar to Puppeteer's `page.click('selector')` that allows clicking elements by semantic identifier (like `:load_component_button`).

## Goal

Implement deterministic element clicking in scenic_mcp that:
1. Finds elements by their semantic ID or role
2. Calculates the center coordinates automatically
3. Sends click events to those coordinates
4. Works reliably across different screen sizes and layouts

## Current State

### What Works
- **Click visualization** (`scenic-widget-contrib/lib/widget_workbench/widget_wkb_scene.ex`):
  - Labeled clicks (A, B, C...) with coordinates
  - Smooth fade from 100% to 35% opacity over 10 seconds
  - Persists across graph re-renders
  - Uses `observe_input/3` callback (non-consuming observation)

- **scenic_mcp mouse clicking** (`scenic_mcp/lib/scenic_mcp/tools.ex:186-202`):
  - Fixed format: `{:cursor_button, {button, state, modifiers, coords}}`
  - State: 1 = press, 0 = release
  - Proper empty modifiers list: `[]`

- **Semantic inspection** (`scenic_mcp/lib/scenic_mcp/tools.ex:99-135`):
  - `inspect_viewport` reads semantic DOM from `:semantic_table`
  - Returns clickable elements, but **bounds/coordinates are not exposed yet**

### What Doesn't Work
- **Manual coordinate clicking is unreliable**:
  - Example: Clicking at (1135, 301) for "Load Component" button missed
  - No way to find element center programmatically
  - Coordinates are hardcoded and fragile

### Recent Win
- We can see click visualization now! This proves scenic_mcp clicks ARE reaching the app
- The miss was due to wrong coordinates, not a fundamental issue

## Technical Deep Dive

### Scenic's Semantic System

Scenic components can register themselves in the semantic DOM via the `:semantic_table` ETS table in the ViewPort:

```elixir
# From Button component (example)
Scenic.ViewPort.set_semantic(viewport, id, %{
  type: :button,
  clickable: true,
  bounds: %{left: x, top: y, width: w, height: h}
})
```

### Current semantic_mcp Implementation

Located in `scenic_mcp/lib/scenic_mcp/tools.ex`:

```elixir
def handle_viewport_inspect(_params) do
  with {:ok, vp_state} <- viewport_state() do
    # Gets semantic_table from viewport
    semantic_table = Map.get(vp_state, :semantic_table)
    elements = :ets.tab2list(semantic_table)

    # Problem: bounds are in the data but not extracted/returned!
    # Each element has structure: {key, %{bounds: %{...}, semantic: %{...}}}
  end
end
```

### Partially Implemented Solution

There's already a `find_clickable_elements/1` function stub in `scenic_mcp/lib/scenic_mcp/tools.ex:227-262` that:
- Filters for clickable elements
- **Has a `calculate_center/1` helper** (lines 264-275)
- Returns element data including bounds and center coordinates
- **But is not exposed through the MCP interface yet!**

## Implementation Plan

### Phase 1: Expose Element Finding (Backend - Elixir)

**File**: `scenic_mcp/lib/scenic_mcp/tools.ex`

1. ✅ **Already exists**: `find_clickable_elements/1` function (line 227)
2. ✅ **Already exists**: `calculate_center/1` helper (line 264)
3. ✅ **Already registered**: Handler in dispatcher (line 72)
4. ❓ **Need to verify**: Is it working? Test it!

### Phase 2: Expose to MCP Interface (TypeScript)

**File**: `scenic_mcp/src/index.ts`

Add new MCP tool definition:
```typescript
{
  name: "find_clickable_elements",
  description: "Find all clickable elements in the current viewport with their center coordinates",
  inputSchema: {
    type: "object",
    properties: {
      filter: {
        type: "string",
        description: "Optional filter by element ID or type"
      }
    }
  }
}
```

Map to Elixir action in message handler:
```typescript
case "find_clickable_elements":
  return { action: "find_clickable", ...args };
```

### Phase 3: High-Level Click Helper

**Option A**: Add Elixir helper in `scenic_mcp/lib/scenic_mcp/tools.ex`
```elixir
def click_element(element_id) do
  with {:ok, result} <- find_clickable_elements(%{}),
       element <- Enum.find(result.elements, fn e ->
         e.id == element_id || e.data.id == element_id
       end),
       %{x: x, y: y} <- element.center do
    handle_mouse_click(%{"x" => x, "y" => y})
  end
end
```

**Option B**: Let Claude Code handle it (simpler!)
```
1. Call find_clickable_elements()
2. Parse response, find element by ID
3. Extract center coordinates
4. Call send_mouse_click(x, y)
```

## Testing Plan

### Step 1: Verify find_clickable_elements Works
```elixir
# In IEx or via MCP
ScenicMcp.Tools.find_clickable_elements(%{})
# Should return: {:ok, %{status: "ok", count: N, elements: [...]}}
```

### Step 2: Test with WidgetWorkbench
```
1. Start WidgetWorkbench with MCP server
2. Connect scenic_mcp
3. Call find_clickable_elements
4. Verify "Load Component" button is in results
5. Check center coordinates are correct
6. Click using those coordinates
7. Observe click visualization - should hit dead center!
```

### Step 3: Make it Repeatable
Create test script that:
- Finds button by ID `:load_component_button`
- Extracts center coordinates
- Clicks
- Verifies modal opened (via screenshot or viewport inspection)

## Key Files

### Elixir (scenic_mcp)
- `lib/scenic_mcp/tools.ex` - Tool implementations
  - Line 227: `find_clickable_elements/1`
  - Line 264: `calculate_center/1`
  - Line 186: `handle_mouse_click/1`
- `lib/scenic_mcp/server.ex` - TCP server and dispatcher
  - Line 72: Action dispatcher

### TypeScript (scenic_mcp MCP interface)
- `src/index.ts` - MCP tool definitions and bridge

### Scenic Components (for testing)
- `scenic-widget-contrib/lib/widget_workbench/widget_wkb_scene.ex`
  - Line 141: Button with id `:load_component_button`

## Success Criteria

✅ Can query: "Find all clickable elements"
✅ Can filter: "Find element with id :load_component_button"
✅ Returns: Bounds and center coordinates
✅ Can click: Deterministically opens modal
✅ Visual proof: Click visualization hits dead center of button

## Debug Tools Available

1. **Click Visualization** - See exactly where clicks land
   - Labeled (A, B, C...)
   - Shows coordinates
   - Fades over 10 seconds
   - Persists across re-renders

2. **Viewport Inspection** - See semantic DOM structure
   - Currently: Element types and counts
   - Soon: Full bounds and coordinates

3. **Screenshots** - Visual verification
   - `take_screenshot()` via scenic_mcp
   - Compare before/after clicks

## Next Steps

1. **Test existing `find_clickable_elements`** - It might already work!
2. **Expose to TypeScript MCP interface** - Add tool definition
3. **Test end-to-end** - Find button, click it, verify modal
4. **Document usage** - Add examples to scenic_mcp README
5. **Add filtering** - By ID, type, or text content
6. **Add error handling** - What if element not found?

## Context Notes

- This work builds on the successful click visualization implementation
- The `observe_input/3` callback proved non-consuming observation works perfectly
- `Graph.modify(&Primitives.update_opts(&1, ...))` is the correct way to update primitives
- Scenic's semantic system is already in place, we just need to expose it properly

## Questions for Next Session

1. Does `find_clickable_elements/1` already work as-is?
2. Do Scenic components actually populate bounds in semantic_table?
3. Should we add filtering by element type (button, text_field, etc.)?
4. Should we validate coordinates are within viewport bounds?
5. Should we add "hover" capability (move mouse without clicking)?

---

**Status**: Ready for implementation
**Estimated Effort**: 2-3 hours
**Risk**: Low - Foundation is already in place
**Impact**: High - Makes scenic_mcp testing deterministic and reliable
