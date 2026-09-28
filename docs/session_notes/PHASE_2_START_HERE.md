# TextField Phase 2 - Start Here

**Date**: 2025-11-02
**Status**: Phase 1 Complete ✅ | Phase 2 Ready to Begin
**Context**: Pick up TextField development for Phase 2 - Direct Input Mode

---

## Quick Context Load (Read These First)

**Essential Documents** (in order):
1. `@WIDGET_WKB_BASE_PROMPT.md` - Widget Workbench development guide
2. `@TEXT_FIELD_ARCHITECTURE.md` - Complete TextField architecture (2,557 lines)
3. `@PHASE_1_COMPLETE.md` - What was built in Phase 1
4. This document - Phase 2 plan

**Quick reference**:
- `@TEXT_FIELD_QUICK_REF.md` - One-page cheat sheet

---

## Phase 1 Status: COMPLETE ✅

### What Works Now

TextField component loads in Widget Workbench with:
- ✅ Multi-line text display
- ✅ Blinking cursor (500ms)
- ✅ Optional line numbers
- ✅ Configurable colors/fonts
- ✅ Transparent backgrounds

**Location**: `lib/components/text_field/`
```
text_field.ex  (104 lines) - Component lifecycle
state.ex       (169 lines) - State management
reducer.ex     (36 lines)  - Stub for Phase 2
renderer.ex    (145 lines) - Graph rendering
```

**Test**: `test/spex/text_field/01_basic_load_spex.exs`

**To verify**:
```bash
iex -S mix
# Click "Load Component" → "Text Field"
# You'll see demo text with blinking cursor
```

---

## Phase 2 Goal: Direct Input Mode

**Objective**: Make TextField accept keyboard input directly

**Current Issue**: TextField loads but doesn't respond to keyboard because:
1. We haven't implemented `handle_input/3` yet (commented out)
2. We haven't requested input types yet (commented out)
3. Widget Workbench doesn't forward input to loaded components yet

---

## Input Routing Strategy Decision

### The Question

**How should keyboard input reach the TextField?**

Three possible approaches:

#### Option A: Direct Component Input (Planned for Phase 2)
```elixir
# In text_field.ex init/3:
scene = if state.input_mode == :direct do
  request_input(scene, [:cursor_button, :key, :codepoint])
else
  scene
end

# TextField receives input directly
def handle_input({:codepoint, {char, _}}, _ctx, scene) do
  # Process character
end
```

**Pros**:
- Component is self-contained
- Works independently of Widget Workbench
- Standard Scenic pattern

**Cons**:
- Requires Widget Workbench to NOT consume keyboard events
- Need to ensure parent doesn't interfere

#### Option B: Widget Workbench Routes Input
```elixir
# In widget_wkb_scene.ex:
def handle_input({:codepoint, {char, _}} = input, _ctx, scene) do
  if scene.assigns.selected_component do
    # Forward to loaded component
    Scene.put_child(scene, :loaded_component, {:input, input})
  else
    {:noreply, scene}
  end
end

# In text_field.ex:
def handle_put({:input, input}, scene) do
  # Process input via reducer
end
```

**Pros**:
- Widget Workbench has full control
- Can intercept for debugging
- Can implement keyboard shortcuts (Ctrl+R to reset, etc.)

**Cons**:
- More complex Widget Workbench code
- Breaks component independence

#### Option C: Observe Pattern (Recommended for Widget Workbench)
```elixir
# In widget_wkb_scene.ex:
# Request input
request_input(scene, [:cursor_button, :key, :codepoint])

# Use observe_input (non-consuming)
def observe_input(input, context, scene) do
  # Log for debugging, but don't consume
  Logger.debug("Input observed: #{inspect(input)}")
  :noreply
end

# Let input pass through to component via normal Scenic routing
# Component requests input and receives it naturally
```

**Pros**:
- Component works independently
- Widget Workbench can observe without interfering
- Standard Scenic input flow
- TextField works same in Widget Workbench and production apps

**Cons**:
- Need to ensure Widget Workbench doesn't accidentally consume

---

## Recommended Approach: Option C + Option A

### Phase 2 Implementation Plan

**Step 1**: Make TextField request input (already architected)
```elixir
# In text_field.ex init/3 (uncomment):
scene = if state.input_mode == :direct do
  request_input(scene, [:cursor_button, :key, :codepoint])
else
  scene
end
```

**Step 2**: Implement handle_input in TextField
```elixir
# In text_field.ex (uncomment and implement):
def handle_input(input, _context, scene) do
  state = scene.assigns.state

  case Reducer.process_input(state, input) do
    {:noop, new_state} ->
      update_scene(scene, state, new_state)

    {:event, event_data, new_state} ->
      send_parent_event(scene, event_data)
      update_scene(scene, state, new_state)
  end
end
```

**Step 3**: Update Widget Workbench to observe (not consume)
```elixir
# In widget_wkb_scene.ex:
# Change handle_input to NOT consume keyboard events when component loaded
def handle_input({:key, _} = input, ctx, scene) do
  # Observe but don't consume - let it pass to component
  if scene.assigns.selected_component do
    Logger.debug("Keyboard input (passing to component): #{inspect(input)}")
  end
  {:noreply, scene}  # Don't consume!
end

def handle_input({:codepoint, _} = input, ctx, scene) do
  if scene.assigns.selected_component do
    Logger.debug("Codepoint input (passing to component): #{inspect(input)}")
  end
  {:noreply, scene}  # Don't consume!
end
```

**Step 4**: Implement Reducer input processing
```elixir
# In reducer.ex - implement process_input/2 (see architecture doc lines 628-718)
```

**Step 5**: Write spex for typing
```elixir
# test/spex/text_field/02_typing_spex.exs
```

---

## Phase 2 Tasks (Detailed)

### Task 1: Uncomment Input Handling in TextField

**File**: `lib/components/text_field/text_field.ex`

**Lines to uncomment**:
- Lines ~91-96: Request input in init/3
- Lines ~117-133: handle_input/3 implementation
- Lines ~180-186: update_scene/3 helper

**Test**: Component should request input, verify in logs

---

### Task 2: Implement Reducer Input Processing

**File**: `lib/components/text_field/reducer.ex`

**Functions to implement** (see architecture doc lines 628-718):

```elixir
# Character insertion
def process_input(%State{focused: true} = state, {:codepoint, {char, _}})
    when char >= 32 and char < 127 do
  new_state = insert_char(state, <<char::utf8>>)
  {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
end

# Cursor movement
def process_input(%State{focused: true} = state, {:key, {:key_left, 1, _}}) do
  {:noop, move_cursor(state, :left)}
end

# ... etc for all keys (see architecture doc)
```

**Helper functions** (lines 762-896):
- `move_cursor/2` - Arrow key movement
- `insert_char/2` - Character insertion
- `delete_before_cursor/1` - Backspace
- `delete_at_cursor/1` - Delete key
- `insert_newline/1` - Enter key

---

### Task 3: Update Widget Workbench Input Routing

**File**: `lib/widget_workbench/widget_wkb_scene.ex`

**Current behavior**: Widget Workbench requests cursor_button, key, codepoint

**Change needed**: Don't consume keyboard when component loaded

**Find**: Search for `def handle_input` handling `:key` and `:codepoint`

**Update to**: Use `observe_input/3` for logging, or make `handle_input` return `{:noreply, scene}` without consuming

**Example**:
```elixir
# Current (consumes input):
def handle_input({:key, _} = input, _ctx, scene) do
  # ... processes key ...
  {:cont, {:key, ...}, scene}  # or similar
end

# New (passes through):
def handle_input({:key, _} = input, _ctx, scene) do
  # Just log, don't process
  {:noreply, scene}
end
```

---

### Task 4: Implement Incremental Rendering

**File**: `lib/components/text_field/renderer.ex`

**Current**: `update_render/3` just calls `initial_render` (full re-render)

**Update to**: Only update changed lines

```elixir
def update_render(graph, old_state, new_state) do
  graph
  |> update_changed_lines(old_state, new_state)
  |> update_cursor_position(old_state, new_state)
  |> update_border_if_focused_changed(old_state, new_state)
end
```

---

### Task 5: Add Focus Management

**In reducer.ex**:
```elixir
# Click inside -> gain focus
def process_input(%State{focused: false} = state, {:cursor_button, {:left, 1, _, pos}}) do
  if State.point_inside?(state, pos) do
    {:event, {:focus_gained, state.id}, %{state | focused: true}}
  else
    {:noop, state}
  end
end

# Click outside -> lose focus
def process_input(%State{focused: true} = state, {:cursor_button, {:left, 1, _, pos}}) do
  if State.point_inside?(state, pos) do
    {:noop, state}  # Stay focused
  else
    {:event, {:focus_lost, state.id}, %{state | focused: false}}
  end
end
```

---

### Task 6: Write Typing Spex

**File**: `test/spex/text_field/02_typing_spex.exs`

**Test scenarios**:
1. Load TextField
2. Click to focus
3. Type characters → verify they appear
4. Backspace → verify deletion
5. Arrow keys → verify cursor movement
6. Enter → verify newline (multi-line) or event (single-line)

**Reference**: `test/spex/menu_bar/` for patterns

---

## Testing Strategy

### Unit Tests (Optional for Phase 2)
```bash
# Test reducer logic directly
mix test test/components/text_field/reducer_test.exs
```

### Spex Tests (Primary)
```bash
# Phase 1: Loading
MIX_ENV=test mix spex test/spex/text_field/01_basic_load_spex.exs

# Phase 2: Typing (to be written)
MIX_ENV=test mix spex test/spex/text_field/02_typing_spex.exs

# Watch mode
MIX_ENV=test mix spex.watch test/spex/text_field/
```

### Manual Testing
```bash
iex -S mix
# Load TextField
# Try typing - should see characters appear
# Try backspace, arrows, etc.
```

---

## Current Input Routing in Widget Workbench

**Check this first**:
```bash
grep -n "def handle_input" lib/widget_workbench/widget_wkb_scene.ex
grep -n "request_input" lib/widget_workbench/widget_wkb_scene.ex
```

**Current state** (from WIDGET_WKB_BASE_PROMPT.md line 79):
```elixir
request_input(scene, [:cursor_pos, :cursor_button, :cursor_scroll, :key, :viewport])
```

**Note**: `:codepoint` is NOT in the list! Need to add it.

**Also check**: Does `handle_input` consume `:key` events? If yes, TextField won't receive them.

---

## Key Architecture Decisions (Recap)

From TEXT_FIELD_ARCHITECTURE.md:

### Input Modes (lines 95-121)

**Direct Mode** (what we're building):
- TextField requests input
- TextField handles events in `handle_input/3`
- Good for: forms, simple apps, Widget Workbench

**External Mode** (Phase 3):
- Parent controls all input
- Parent sends actions via `put_child`
- Good for: Flamelex, vim editors

### State Structure (lines 456-580)

**Key fields for Phase 2**:
- `focused: boolean` - Is TextField focused?
- `cursor: {line, col}` - Cursor position (1-indexed)
- `lines: [string]` - Text content
- `cursor_visible: boolean` - For blink

### Events Emitted (lines 217-224)

TextField sends to parent:
- `{:text_changed, id, full_text}` - When text changes
- `{:focus_gained, id}` - When clicked
- `{:focus_lost, id}` - When clicked outside
- `{:cursor_moved, id, {line, col}}` - When cursor moves
- `{:enter_pressed, id, text}` - In single-line mode

---

## Potential Issues & Solutions

### Issue 1: Widget Workbench consumes keyboard events

**Symptom**: TextField doesn't receive `:key` or `:codepoint` events

**Solution**: Update Widget Workbench to not consume these events when a component is loaded

**Check**:
```elixir
# In widget_wkb_scene.ex handle_input:
def handle_input({:key, _}, _ctx, scene) do
  # If this returns {:cont, ...} or processes the key, it's consuming
  # Should return {:noreply, scene} to pass through
end
```

### Issue 2: Codepoint not requested

**Symptom**: Can't type characters, only special keys work

**Solution**: Add `:codepoint` to Widget Workbench's `request_input`:
```elixir
request_input(scene, [:cursor_pos, :cursor_button, :cursor_scroll, :key, :codepoint, :viewport])
```

### Issue 3: Multiple components requesting input

**Symptom**: Both TextField and Widget Workbench receive input

**Solution**: This is fine! Scenic delivers input to all components that request it. Use `observe_input` in Widget Workbench for non-consuming observation.

### Issue 4: Focus not working

**Symptom**: Can't click to focus TextField

**Solution**: Ensure TextField is in Widget Workbench's `input_lists` so it receives cursor_button events

---

## Success Criteria for Phase 2

When Phase 2 is complete:

- [ ] TextField requests input in direct mode
- [ ] Clicking TextField sets focus (border changes color)
- [ ] Typing characters inserts them at cursor
- [ ] Cursor moves when typing
- [ ] Backspace deletes character before cursor
- [ ] Delete key deletes character at cursor
- [ ] Arrow keys move cursor
- [ ] Home/End keys work
- [ ] Enter creates newline (multi-line) or emits event (single-line)
- [ ] Text changes emit `{:text_changed, id, text}` events
- [ ] Clicking outside loses focus
- [ ] Spex tests pass for typing scenarios
- [ ] Manual testing works in Widget Workbench

---

## File Checklist for Phase 2

**Files to modify**:
- [ ] `lib/components/text_field/text_field.ex` - Uncomment input handling
- [ ] `lib/components/text_field/reducer.ex` - Implement process_input/2
- [ ] `lib/components/text_field/renderer.ex` - Implement incremental updates
- [ ] `lib/widget_workbench/widget_wkb_scene.ex` - Add :codepoint, don't consume keyboard
- [ ] `test/spex/text_field/02_typing_spex.exs` - New spex for typing

**Files to reference**:
- `TEXT_FIELD_ARCHITECTURE.md` lines 628-896 (reducer implementation)
- `WIDGET_WKB_BASE_PROMPT.md` lines 369-371 (input routing)
- `test/spex/menu_bar/02_dropdown_spex.exs` (spex patterns)

---

## Quick Start Commands (Next Session)

```bash
cd /home/luke/workbench/flx/scenic-widget-contrib

# 1. Read context
cat PHASE_2_START_HERE.md
cat PHASE_1_COMPLETE.md

# 2. Check current input routing
grep -A 10 "request_input" lib/widget_workbench/widget_wkb_scene.ex
grep -A 20 "def handle_input.*:key" lib/widget_workbench/widget_wkb_scene.ex

# 3. Verify Phase 1 works
iex -S mix
# Click Load Component → Text Field → Should see demo text

# 4. Start implementing Phase 2
# Edit lib/components/text_field/text_field.ex
# Uncomment lines ~91-96 (request_input)
# Uncomment lines ~117-133 (handle_input)

# 5. Implement reducer
# Edit lib/components/text_field/reducer.ex
# Implement process_input/2 for each key type

# 6. Test
MIX_ENV=test mix spex test/spex/text_field/
```

---

## Estimated Effort

**Phase 2 tasks**:
- Uncomment TextField input handling: 10 minutes
- Implement reducer input processing: 1-2 hours (many keys to handle)
- Update Widget Workbench routing: 30 minutes
- Implement incremental rendering: 1 hour
- Write typing spex: 1 hour
- Manual testing and fixes: 1 hour

**Total**: 4-6 hours

---

## Context for AI Assistant

When starting the next session, say:

```
@PHASE_2_START_HERE.md @TEXT_FIELD_ARCHITECTURE.md @PHASE_1_COMPLETE.md

I want to continue implementing TextField. We've completed Phase 1 (display and cursor).
Now let's implement Phase 2 (direct input mode) so TextField can accept keyboard input.

Please:
1. Check current Widget Workbench input routing
2. Uncomment input handling in text_field.ex
3. Implement reducer.ex process_input/2 for keyboard events
4. Update Widget Workbench to pass through keyboard input
5. Write spex to test typing

Start by checking what input events Widget Workbench currently requests and handles.
```

---

## Links to Key Files

**TextField Implementation**:
- `/home/luke/workbench/flx/scenic-widget-contrib/lib/components/text_field/text_field.ex`
- `/home/luke/workbench/flx/scenic-widget-contrib/lib/components/text_field/state.ex`
- `/home/luke/workbench/flx/scenic-widget-contrib/lib/components/text_field/reducer.ex`
- `/home/luke/workbench/flx/scenic-widget-contrib/lib/components/text_field/renderer.ex`

**Widget Workbench**:
- `/home/luke/workbench/flx/scenic-widget-contrib/lib/widget_workbench/widget_wkb_scene.ex`

**Tests**:
- `/home/luke/workbench/flx/scenic-widget-contrib/test/spex/text_field/01_basic_load_spex.exs`

**Architecture**:
- `/home/luke/workbench/flx/scenic-widget-contrib/TEXT_FIELD_ARCHITECTURE.md`
- `/home/luke/workbench/flx/scenic-widget-contrib/WIDGET_WKB_BASE_PROMPT.md`

---

**Ready to begin Phase 2!** 🚀
