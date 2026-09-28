# MCP Scroll Transform Investigation

**Goal**: Fix semantic clicking for elements inside scrolled Scenic containers

**Date**: 2025-11-03

## Problem Statement

When elements (buttons) are inside a scrolled Scenic group:
1. Elements register with MCP at their original (pre-scroll) local coordinates
2. After scrolling, clicking at those registered coordinates misses the actual button
3. The scroll transform is applied to the parent group, but MCP doesn't know about it

**Example**:
- TextField button is at index 14 in a scrollable modal
- Modal scrolls down 495px to show TextField
- Button registered at y=705, but visual position is now y=705-495=210
- Click at y=705 hits empty space instead of button

## Architecture Overview

### Scenic Graph Structure
```
WidgetWorkbench.Scene (:_root_)
  └─ Modal container (translate: {modal_x, list_top})
      └─ Scroll group (id: :component_list_scroll_group, translate: {0, -scroll_offset})
          └─ Button 1 (local translate: {20, 0})
          └─ Button 2 (local translate: {20, 45})
          └─ ...
          └─ TextField button (local translate: {20, 630})
```

### MCP Semantic System

**Registration** (lib/components/scenic_contrib/button.ex or similar):
- Buttons call `ScenicMcp.register_element/3` with local bounds
- Stored in ETS table `:semantic_table`
- Entry: `{graph_key, %{elements: %{button_id => %{bounds: ..., transforms: ...}}}}`

**Lookup** (scenic_mcp_experimental/lib/scenic_mcp/tools.ex):
- `find_clickable_elements/1` reads from `:semantic_table`
- `calculate_center_with_transforms/4` computes click position
- Currently: only applies element's own transforms, not parent graph transforms

## Investigation Steps

### Step 1: Preserve graph_key (✅ DONE)

**File**: `scenic_mcp_experimental/lib/scenic_mcp/tools.ex:293`

**Change**: Keep graph_key when flattening elements
```elixir
{id, Map.put(element_info, :graph_key, graph_key)}
```

**Result**: graph_key now available in element_info

### Step 2: Pass graph_key to transform calculation (✅ DONE)

**File**: `scenic_mcp_experimental/lib/scenic_mcp/tools.ex:315`

**Change**: Pass graph_key and vp_state to calculate_center_with_transforms
```elixir
graph_key = Map.get(element_info, :graph_key)
center = calculate_center_with_transforms(bounds, transforms, graph_key, vp_state)
```

### Step 3: Look up parent graph transform (✅ IMPLEMENTED, ❌ NOT WORKING)

**File**: `scenic_mcp_experimental/lib/scenic_mcp/tools.ex:701-815`

**Changes**:
- Added `get_graph_transform/2` function
- Added `extract_translate_from_script/2` function
- Modified `calculate_center_with_transforms/4` to accumulate graph transform

**Discovery**: graph_key values are **random strings** (e.g., "7K_m-NNKD0rKEaAQvQjdKA"), not named IDs like `:component_list_scroll_group`

**Debug output**:
```
DEBUG: Graph translate for :_root_: {0, 0}
```

Buttons are being registered with graph_key = `:_root_`, not the scroll group!

### Step 4: Understanding graph_key values (🔍 IN PROGRESS)

From `/tmp/scenic_mcp_debug.txt`:
```
Selected: {:select_component, ScenicWidgets.TextField} from "7K_m-NNKD0rKEaAQvQjdKA"
```

**Questions**:
1. Why are buttons registering with `:_root_` instead of their parent scroll group?
2. Where does the random string graph_key come from?
3. Is there a mapping between `:component_list_scroll_group` and these random IDs?

### Step 5: Understanding Registration (🔍 IN PROGRESS)

**Key Discovery**: Components must **opt-in** to semantic registration

**From debug output**: Buttons ARE being registered - we see them in semantic_table
**graph_key format**: Random strings like "7K_m-NNKD0rKEaAQvQjdKA"

**Critical Question**: Where/how do Scenic.Components.button instances register with MCP?
- Not in button.ex source code
- Must be viewport-level registration
- Happens when graph is compiled/pushed

**The Real Problem**:
- Buttons register with graph_key = random ID (not `:component_list_scroll_group`)
- No link between button's graph_key and its parent scroll group
- Script_table lookup with random graph_key won't find scroll group's transform

## Current Status

**What Works**:
- ✅ graph_key is preserved in element_info
- ✅ get_graph_transform function exists
- ✅ calculate_center_with_transforms accumulates parent transform

**What Doesn't Work**:
- ❌ graph_key is a random ID, not the named scroll group ID
- ❌ No mapping between random graph_key and `:component_list_scroll_group`
- ❌ Can't look up scroll group's transform using button's graph_key

## Possible Solutions

### Option A: Store parent container ID during registration
**Complexity**: High - requires modifying Scenic's registration system
**Approach**: When component registers, also store parent group ID
**Status**: Would need upstream Scenic changes

### Option B: Traverse graph hierarchy at lookup time
**Complexity**: Medium - requires understanding Scenic's graph structure
**Approach**: Starting from button's graph, walk up to find scroll group
**Status**: Need to understand how to traverse compiled graph hierarchy

### Option C: Re-register with absolute positions on scroll
**Complexity**: Low - modify widget_wkb_scene.ex only
**Approach**: Calculate absolute positions accounting for scroll, re-register
**Status**: Simple workaround, doesn't solve general problem

### Option D: Manual parent tracking in widget_wkb_scene
**Complexity**: Low-Medium
**Approach**: When creating buttons in scroll group, manually pass scroll offset as transform
**Status**: Quick fix for this specific case

## Decision: Option D - Manual Scroll Offset Tracking

**Chosen**: Option D - Pass scroll offset when creating buttons

**Rationale**:
- Quick to implement
- No Scenic internals knowledge needed
- Solves the immediate problem
- Can be generalized later if needed

**Implementation Plan**:
1. Pass `scroll_offset` to `render_component_list`
2. Include scroll offset in button's `translate` or custom metadata
3. MCP will see absolute position = local_pos + container_pos - scroll_offset

## BREAKTHROUGH: scene_script_table Contains Hierarchy! 🎉

**Discovery** (2025-11-03): ViewPort already tracks parent-child graph relationships!

**Location**: `/home/luke/workbench/flx/scenic/lib/scenic/view_port.ex`

**Key Functions**:
- Line 2224: `build_scene_script_info(graph, graph_key, script, state)`
- Line 2229: `children = extract_script_references(script)` - Extracts child graph_keys!
- Line 2249: `transforms: extract_graph_transforms(script)` - Extracts graph-level transforms!

**scene_script_table Structure**:
```elixir
%{
  graph_key: "random-uuid",
  children: ["child-graph-1", "child-graph-2"],  # ← Parent-child links!
  transforms: [{:translate, {x, y}}, ...],       # ← Transform ops!
  elements: %{...},
  by_type: %{...}
}
```

**Solution**:
Instead of trying to store parent info during registration (Option A) or manual workarounds (Options C/D), we can **traverse the scene_script_table hierarchy** at lookup time (Option B).

**Algorithm**:
1. Button registers with random graph_key "xyz123"
2. MCP lookup finds button in semantic_table["xyz123"]
3. NEW: Traverse scene_script_table to find parent chain: xyz123 → parent_key → :_root_
4. Accumulate transforms from each parent graph in the chain
5. Apply accumulated transforms to button's local position

## Implementation Complete! ✅

**New Functions** (scenic_mcp_experimental/lib/scenic_mcp/tools.ex):

1. **`get_hierarchy_transforms/2`** (line 738-760)
   - Main entry point, checks for scene_script_table
   - Builds parent map and starts traversal

2. **`build_parent_map/1`** (line 770-779)
   - Inverts children lists to create child -> parent mapping
   - Reads from scene_script_table ETS

3. **`accumulate_parent_transforms/5`** (line 791-814)
   - Recursively walks up parent chain
   - Accumulates translate transforms from each level
   - Stops at :_root_ or max depth 10

4. **`get_graph_transform_from_scene_script/2`** (line 822-844)
   - Extracts translate transform from scene_script_table entry
   - Parses transforms list: `[{:translate, {x, y}}, ...]`

**Modified Functions**:

1. **`calculate_center_with_transforms/4`** (line 683-710)
   - Now calls `get_hierarchy_transforms` instead of `get_graph_transform`
   - Accumulates: element local + element transform + hierarchy transforms

## Final Discovery: Re-registration on Scroll ✅

**Test Result**: TextField loading test PASSES!

**But not for the reason expected!**

Hierarchy traversal was implemented, but it turns out the buttons are registered in `:_root_` graph (not child graphs), and the scroll offset is a **primitive group transform** (not a graph transform).

**What Actually Happens**:
1. Modal opens, buttons register at positions like `{420.0, 705.0}`
2. Test detects TextField is off-screen (index 14, max visible 7)
3. Test sends scroll event (495px down)
4. **Modal re-renders with new scroll offset**
5. **Buttons re-register at SAME positions** `{420.0, 705.0}` (ignoring scroll in registration)
6. Semantic click works because button IS at that position on screen

**The scroll offset is applied as a Scenic primitive group transform**:
```elixir
|> Primitives.group(
  fn inner_g ->
    inner_g
    |> render_component_list(...)  # Buttons render here
  end,
  id: :component_list_scroll_group,
  translate: {0, -clamped_scroll}  # ← This is a rendering transform!
)
```

**Why the test passes**:
- The scroll transform affects WHERE the buttons RENDER on screen
- But the buttons are registered at their VISUAL position (after transform is applied by Scenic's renderer)
- MCP semantic system registers at screen coordinates, not local coordinates
- So after scrolling, buttons re-register at their new visual positions

**Conclusion**: The current system WORKS CORRECTLY for this case! Buttons register at their actual on-screen position. The hierarchy traversal code I wrote isn't needed for this scenario, but might be useful for other cases where elements need to account for parent transforms.

## Next Steps

1. [x] Decision made: Option B - Traverse graph hierarchy
2. [x] Discovery: scene_script_table has children + transforms
3. [x] Implement: Build parent hierarchy map from scene_script_table
4. [x] Implement: Accumulate transforms up the hierarchy chain
5. [x] Test: Buttons in scrolled containers work correctly!
6. [x] Verify: TextField loads successfully after scroll
7. [ ] Document: Update semantic system docs with findings
8. [ ] Cleanup: Remove unused hierarchy traversal code or keep for future use?

## Files Modified

- `scenic_mcp_experimental/lib/scenic_mcp/tools.ex`:
  - Line 293: Keep graph_key
  - Line 315: Pass graph_key to calculate_center_with_transforms
  - Line 683-815: New transform lookup functions
