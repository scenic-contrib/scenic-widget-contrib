# TextField Component - Architecture & Implementation Plan

**Created**: 2025-11-02
**Status**: Design Complete, Ready for Implementation
**Component**: `ScenicWidgets.TextField`

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Research & Investigation](#research--investigation)
3. [Architecture Design](#architecture-design)
4. [Communication Patterns](#communication-patterns)
5. [State Management](#state-management)
6. [Implementation Plan](#implementation-plan)
7. [Usage Examples](#usage-examples)
8. [Testing Strategy](#testing-strategy)

---

## Executive Summary

This document defines the architecture for migrating Quillex's `BufferPane` component into a reusable `TextField` widget for scenic-widget-contrib, following the established 4-file pattern while supporting both simple and complex usage patterns.

### Key Design Decisions

1. **Dual Input Modes**: Support both direct input (simple apps) and external control (complex apps like Flamelex)
2. **Multi-line First**: Build multi-line by default, single-line as configuration option
3. **Inline Cursor**: Render cursor directly in component (no child component)
4. **Configurable Features**: Line numbers, fonts, colors all configurable
5. **Event-Driven**: Always emit events to parent for state changes
6. **Scenic Patterns**: Use `handle_put/2` for external control, `handle_input/3` for direct control

---

## Research & Investigation

### Source Material: Quillex BufferPane

**Location**: `/home/luke/workbench/flx/quillex/lib/gui/components/buffer_pane/`

**Architecture** (differs from scenic-widget-contrib pattern):
```
buffer_pane/
├── buffer_pane.ex              # Component lifecycle
├── buffer_pane_state.ex        # State struct (minimal)
├── buffer_pane_user_input_handler.ex  # Input routing
└── buffer_pane_renderizer.ex   # Rendering logic

cursor_caret/
└── cursor_caret.ex             # Separate animated cursor component
```

**Key Features Discovered**:

1. **Multi-line Text Rendering**
   - Lines stored as list of strings: `["line 1", "line 2", ...]`
   - Incremental updates - only re-renders changed lines
   - Line numbers in 40px left margin
   - Uses `TruetypeMetrics` for accurate character positioning

2. **External State Management**
   - Text content lives in external `Quillex.Buffer.Process` GenServer
   - BufferPane subscribes to buffer changes via PubSub
   - Receives updates via `handle_info({:buf_state_changes, new_buf})`

3. **Mode-Based Input Handling**
   - Routes input to mode-specific handlers (Vim, Notepad, etc.)
   - Handlers return action tuples: `{:insert, "text", :at_cursor}`
   - Actions processed by external buffer, results broadcast back

4. **Cursor Component**
   - Separate `CursorCaret` component with independent state
   - Three modes: `:cursor` (2px line), `:block` (char width), `:hidden`
   - Blinking animation (500ms interval via `:timer.send_interval`)
   - Positioned using FontMetrics for character-accurate placement

5. **Keyboard Input Handling** (Notepad mode)
   ```elixir
   # From buffer_pane/vim_key_mappings/gedit_notepad_map.ex

   {:key, {:key_return, 1, _}} → {:newline, :at_cursor}
   {:key, {:key_backspace, 1, _}} → {:delete, :before_cursor}
   {:key, {:key_delete, 1, _}} → {:delete, :at_cursor}
   {:key, {:key_left, 1, _}} → {:move_cursor, :left, 1}
   {:key, {:key_right, 1, _}} → {:move_cursor, :right, 1}
   {:key, {:key_up, 1, _}} → {:move_cursor, :up, 1}
   {:key, {:key_down, 1, _}} → {:move_cursor, :down, 1}
   {:key, {:key_home, 1, _}} → {:move_cursor, :line_start}
   {:key, {:key_end, 1, _}} → {:move_cursor, :line_end}
   {:codepoint, {char, _}} → {:insert, char_string, :at_cursor}
   ```

### Source Material: Scenic Built-in TextField

**Location**: `/home/luke/workbench/flx/scenic/lib/scenic/component/input/text_field.ex`

**Key Learnings**:

1. **Input Capture**
   ```elixir
   @input_capture [:cursor_button, :codepoint, :key]
   request_input(scene, @input_capture)
   ```

2. **Parent Communication Patterns**
   ```elixir
   # Child → Parent events
   send_parent_event(scene, {:value_changed, id, value})
   send_parent_event(scene, {:focus, id})
   send_parent_event(scene, {:blur, id})
   ```

3. **External Updates via `handle_put/2`**
   ```elixir
   def handle_put(new_value, scene) when is_bitstring(new_value) do
     send_parent_event(scene, {:value_changed, id, new_value})
     # Update display, move caret, push graph
     {:noreply, updated_scene}
   end
   ```

4. **Query Interface via `handle_get/2` and `handle_fetch/2`**
   ```elixir
   def handle_get(_, scene) do
     {:reply, scene.assigns.value, scene}
   end

   def handle_fetch(_, scene) do
     {:reply, {:ok, scene.assigns.value}, scene}
   end
   ```

5. **Focus Management**
   ```elixir
   # On focus: capture input, show caret, change border color
   capture_input(scene, @input_capture)

   # On blur: release input, hide caret, restore border
   release_input(scene)
   ```

6. **Caret as Child Component**
   - Uses `Scenic.Component.Input.Caret` child component
   - Controls via `cast_children(scene, :start_caret)`
   - Resets blink on movement: `cast_children(scene, :reset_caret)`

### Scenic Communication Mechanisms

**1. Parent → Child: `Scene.put_child/3` + `handle_put/2`**

How it works:
```elixir
# In scenic/lib/scenic/scene.ex:517
def put_child(%Scene{} = scene, id, value) do
  case child(scene, id) do
    {:ok, pids} ->
      Enum.each(pids, &send(&1, {:_put_, value}))
      :ok
  end
end

# Component receives :_put_ message, Scenic routes to handle_put/2
def handle_put(value, scene) do
  # Update component state
  {:noreply, updated_scene}
end
```

**Use case**: External state management - parent controls child's value

**2. Child → Parent: `send_parent_event/2`**

```elixir
# Child emits event
send_parent_event(scene, {:value_changed, id, new_text})

# Parent receives via handle_event/3
def handle_event({:value_changed, :my_textfield, text}, _from, scene) do
  # Process at application level
  {:noreply, scene}
end
```

**Use case**: Notify parent of changes for app-level logic

**3. Direct Communication: `cast_parent/2`, `cast_children/2`**

```elixir
# More flexible GenServer-style casts
cast_parent(scene, {:custom_message, data})
cast_children(scene, {:update_mode, :vim_normal})
```

**Use case**: Custom messages between components

---

## Architecture Design

### File Structure (4-File Pattern)

Following scenic-widget-contrib conventions:

```
lib/components/text_field/
├── text_field.ex        # Component lifecycle (Scenic.Component)
├── state.ex             # State struct + query functions
├── reducer.ex           # Pure state transitions
└── renderer.ex          # Graph rendering (initial + incremental)
```

### Component Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    TextField Component                       │
│                                                              │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────┐  │
│  │  text_field.ex │  │    state.ex    │  │ reducer.ex   │  │
│  │  ────────────  │  │  ────────────  │  │ ──────────── │  │
│  │  • validate/1  │  │  • defstruct   │  │ • process_   │  │
│  │  • init/3      │  │  • new/1       │  │   input/2    │  │
│  │  • handle_     │  │  • point_      │  │ • process_   │  │
│  │    input/3     │  │    inside?/2   │  │   action/2   │  │
│  │  • handle_     │  │  • get_text/1  │  │              │  │
│  │    put/2       │  │  • get_cursor  │  │ Returns:     │  │
│  │  • handle_     │  │    _pos/1      │  │ {:noop, s}   │  │
│  │    info/2      │  │                │  │ {:event,     │  │
│  │    (blink)     │  │  Pure queries  │  │  e, s}       │  │
│  └────────────────┘  └────────────────┘  └──────────────┘  │
│         │                    │                    │          │
│         └────────────────────┴────────────────────┘          │
│                              │                               │
│                    ┌─────────▼──────────┐                   │
│                    │   renderer.ex      │                   │
│                    │   ────────────     │                   │
│                    │   • initial_       │                   │
│                    │     render/2       │                   │
│                    │   • update_        │                   │
│                    │     render/3       │                   │
│                    │   • render_lines/2 │                   │
│                    │   • render_cursor  │                   │
│                    │     /2             │                   │
│                    └────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘

External Interactions:

INPUT MODE: DIRECT                    INPUT MODE: EXTERNAL
━━━━━━━━━━━━━━━━━                    ━━━━━━━━━━━━━━━━━━━━

Scenic Input                          Parent Scene
     │                                     │
     ▼                                     │
handle_input/3                             │
     │                                     │
     ▼                                     ▼
 Reducer                              handle_put/2
     │                                     │
     ▼                                     ▼
 Renderer                              Reducer
     │                                     │
     ▼                                     ▼
send_parent_event                      Renderer
({:text_changed, ...})                    │
                                          ▼
                                  send_parent_event
                                  ({:text_changed, ...})
```

---

## Communication Patterns

### Pattern 1: Direct Input Mode (Simple Apps)

**Use Case**: Widget Workbench, simple forms, chat boxes

**Configuration**:
```elixir
%{
  frame: frame,
  initial_text: "",
  mode: :multi_line,
  input_mode: :direct,  # TextField handles keyboard directly
  show_line_numbers: false
}
```

**Flow**:
```
User presses 'a'
    ↓
Scenic routes input to TextField (because it called request_input)
    ↓
TextField.handle_input({:codepoint, {?a, _}}, _ctx, scene)
    ↓
Reducer.process_input(state, {:codepoint, {?a, _}})
    ↓
Returns: {:event, {:text_changed, "a"}, new_state}
    ↓
TextField updates graph, emits event to parent
    ↓
Parent receives: handle_event({:text_changed, :field_id, "a"}, ...)
```

**Implementation**:
```elixir
# text_field.ex
def init(scene, data, _opts) do
  state = State.new(data)

  # Only request input in direct mode
  scene = if state.input_mode == :direct do
    request_input(scene, [:cursor_button, :key, :codepoint])
  else
    scene
  end

  graph = Renderer.initial_render(Graph.build(), state)

  {:ok, scene
    |> assign(state: state, graph: graph)
    |> push_graph(graph)}
end

def handle_input(input, _context, scene) do
  state = scene.assigns.state

  case Reducer.process_input(state, input) do
    {:noop, ^state} ->
      {:noreply, scene}

    {:noop, new_state} ->
      update_scene(scene, state, new_state)

    {:event, event_data, new_state} ->
      send_parent_event(scene, event_data)
      update_scene(scene, state, new_state)
  end
end

defp update_scene(scene, old_state, new_state) do
  graph = Renderer.update_render(scene.assigns.graph, old_state, new_state)
  scene = assign(scene, state: new_state, graph: graph)
  {:noreply, push_graph(scene, graph)}
end
```

### Pattern 2: External Control Mode (Complex Apps)

**Use Case**: Flamelex, Quillex, Vim emulators, modal editors

**Configuration**:
```elixir
%{
  frame: frame,
  initial_text: buffer_content,
  mode: :multi_line,
  input_mode: :external,  # Parent will control via put_child
  show_line_numbers: true,
  buffer_uuid: "abc-123"  # Optional external reference
}
```

**Flow**:
```
User presses 'i' (insert mode key)
    ↓
Parent Scene.handle_input({:key, {:key_i, 1, _}}, ...)
    ↓
Parent determines this means "enter insert mode"
    ↓
Parent updates own state, maybe switches mode
    ↓
Later, user presses 'x' in insert mode
    ↓
Parent Scene.handle_input({:codepoint, {?x, _}}, ...)
    ↓
Parent decides: "in insert mode, send to buffer"
    ↓
Scene.put_child(parent, :buffer_pane, {:action, :insert_text, "x"})
    ↓
TextField.handle_put({:action, :insert_text, "x"}, scene)
    ↓
Reducer.process_action(state, {:insert_text, "x"})
    ↓
Returns: {:event, {:text_changed, "x"}, new_state}
    ↓
TextField updates graph, emits event
    ↓
Parent receives: handle_event({:text_changed, :buffer_pane, "x"}, ...)
    ↓
Parent can sync to external buffer, log for undo, etc.
```

**Implementation**:
```elixir
# text_field.ex
def handle_put({:action, action_type, data}, scene) do
  state = scene.assigns.state

  case Reducer.process_action(state, {action_type, data}) do
    {:noop, new_state} ->
      update_scene(scene, state, new_state)

    {:event, event_data, new_state} ->
      send_parent_event(scene, event_data)
      update_scene(scene, state, new_state)
  end
end

def handle_put(text, scene) when is_bitstring(text) do
  # Simple text replacement (like Scenic's TextField)
  state = %{scene.assigns.state | lines: String.split(text, "\n")}
  send_parent_event(scene, {:text_changed, scene.assigns.id, text})
  update_scene(scene, scene.assigns.state, state)
end
```

**Example: Flamelex Integration**
```elixir
defmodule Flamelex.RootScene do
  def handle_input({:key, {:key_i, 1, _}}, _ctx, %{assigns: %{mode: :vim_normal}} = scene) do
    # Switch to insert mode
    scene = assign(scene, mode: :vim_insert)
    {:noreply, scene}
  end

  def handle_input({:codepoint, {char, _}}, _ctx, %{assigns: %{mode: :vim_insert}} = scene) do
    # In insert mode, forward to buffer
    char_string = <<char::utf8>>
    Scene.put_child(scene, :buffer_pane, {:action, :insert_text, char_string})
    {:noreply, scene}
  end

  def handle_input({:key, {:key_escape, 1, _}}, _ctx, %{assigns: %{mode: :vim_insert}} = scene) do
    # Exit insert mode
    scene = assign(scene, mode: :vim_normal)
    {:noreply, scene}
  end

  def handle_event({:text_changed, :buffer_pane, new_text}, _from, scene) do
    # Optionally sync to external buffer process
    BufferManager.update_buffer(scene.assigns.buffer_uuid, new_text)
    {:noreply, scene}
  end
end
```

---

## State Management

### State Structure

```elixir
defmodule ScenicWidgets.TextField.State do
  @moduledoc """
  State for TextField component.

  ## Fields

  ### Core
  - `frame` - Widgex.Frame for positioning/sizing
  - `lines` - List of strings (["line 1", "line 2", ...])
  - `cursor` - {line, col} tuple (1-indexed)
  - `id` - Component ID (for events)

  ### Display
  - `focused` - Boolean, whether component has focus
  - `cursor_visible` - Boolean, for blink animation
  - `cursor_timer` - Erlang timer reference

  ### Configuration
  - `mode` - :single_line | :multi_line
  - `input_mode` - :direct | :external
  - `show_line_numbers` - Boolean
  - `line_number_width` - Pixels (default 40)
  - `font` - %{name: atom, size: int, metrics: FontMetrics}
  - `colors` - %{text:, background:, cursor:, line_numbers:, border:, focused_border:}

  ### Text Wrapping & Scrolling
  - `wrap_mode` - :none | :char | :word (text wrapping behavior)
  - `scroll_mode` - :none | :vertical | :horizontal | :both
  - `vertical_scroll_offset` - Vertical scroll in pixels
  - `horizontal_scroll_offset` - Horizontal scroll in pixels
  - `height_mode` - :auto | {:fixed_lines, n} | {:fixed_pixels, n}
  - `max_visible_lines` - Calculated from frame height and height_mode

  ### Advanced (future)
  - `selection` - {start, end} for text selection
  - `max_lines` - Limit lines (nil = unlimited)
  - `read_only` - Boolean
  """

  defstruct [
    # Core
    frame: nil,
    lines: [""],
    cursor: {1, 1},
    id: nil,

    # Display
    focused: false,
    cursor_visible: true,
    cursor_timer: nil,

    # Configuration
    mode: :multi_line,
    input_mode: :direct,
    show_line_numbers: false,
    line_number_width: 40,
    font: nil,
    colors: nil,

    # Interaction
    editable: true,
    selectable: true,

    # Text Wrapping & Scrolling
    wrap_mode: :none,
    scroll_mode: :both,
    vertical_scroll_offset: 0,
    horizontal_scroll_offset: 0,
    height_mode: :auto,
    max_visible_lines: nil,

    # Advanced
    selection: nil,
    max_lines: nil,
    cursor_blink_rate: 500,
    show_scrollbars: true,
    scrollbar_width: 12
  ]

  @type t :: %__MODULE__{}

  @doc "Create new state from Frame or config map"
  def new(%Widgex.Frame{} = frame) do
    new(%{frame: frame})
  end

  def new(%{frame: %Widgex.Frame{} = frame} = data) do
    %__MODULE__{
      frame: frame,
      lines: parse_initial_text(data),
      mode: Map.get(data, :mode, :multi_line),
      input_mode: Map.get(data, :input_mode, :direct),
      show_line_numbers: Map.get(data, :show_line_numbers, false),
      font: Map.get(data, :font) || default_font(),
      colors: Map.get(data, :colors) || default_colors(),
      id: Map.get(data, :id),
      max_visible_lines: calculate_max_lines(frame, Map.get(data, :font))
    }
  end

  defp parse_initial_text(%{initial_text: text}) when is_bitstring(text) do
    String.split(text, "\n")
  end
  defp parse_initial_text(_), do: [""]

  defp default_font do
    # TODO: Load metrics from Scenic cache
    %{name: :roboto_mono, size: 20, metrics: nil}
  end

  defp default_colors do
    %{
      text: :white,
      background: {30, 30, 30},
      cursor: :white,
      line_numbers: {100, 100, 100},
      border: {60, 60, 60},
      focused_border: {100, 150, 200}
    }
  end

  defp calculate_max_lines(frame, font) do
    line_height = (font || default_font()).size
    trunc(frame.size.height / line_height)
  end

  # Query functions (pure)

  @doc "Check if point is inside TextField bounds"
  def point_inside?(%__MODULE__{frame: frame}, {x, y}) do
    x >= frame.pin.x and x <= frame.pin.x + frame.size.width and
    y >= frame.pin.y and y <= frame.pin.y + frame.size.height
  end

  @doc "Get full text as single string"
  def get_text(%__MODULE__{lines: lines}) do
    Enum.join(lines, "\n")
  end

  @doc "Get cursor position"
  def get_cursor(%__MODULE__{cursor: cursor}), do: cursor

  @doc "Get line at index (1-indexed)"
  def get_line(%__MODULE__{lines: lines}, line_num) do
    Enum.at(lines, line_num - 1, "")
  end

  @doc "Count total lines"
  def line_count(%__MODULE__{lines: lines}), do: length(lines)
end
```

### Reducer Actions

```elixir
defmodule ScenicWidgets.TextField.Reducer do
  alias ScenicWidgets.TextField.State

  @moduledoc """
  Pure state transition functions for TextField.

  Handles both:
  - Raw input events (for direct mode)
  - High-level actions (for external mode)

  Returns:
  - {:noop, state} - State changed, no parent notification needed
  - {:event, event_data, state} - State changed, notify parent
  """

  # ===== DIRECT INPUT PROCESSING =====

  @doc "Process raw Scenic input events"
  def process_input(state, input)

  # Mouse click - gain focus
  def process_input(%State{focused: false} = state, {:cursor_button, {:left, 1, _, pos}}) do
    if State.point_inside?(state, pos) do
      {:event, {:focus_gained, state.id}, %{state | focused: true}}
    else
      {:noop, state}
    end
  end

  # Lose focus on outside click
  def process_input(%State{focused: true} = state, {:cursor_button, {:left, 1, _, pos}}) do
    if State.point_inside?(state, pos) do
      # TODO: Move cursor to click position
      {:noop, state}
    else
      {:event, {:focus_lost, state.id}, %{state | focused: false}}
    end
  end

  # Arrow keys - move cursor
  def process_input(%State{focused: true} = state, {:key, {:key_left, 1, _}}) do
    {:noop, move_cursor(state, :left)}
  end

  def process_input(%State{focused: true} = state, {:key, {:key_right, 1, _}}) do
    {:noop, move_cursor(state, :right)}
  end

  def process_input(%State{focused: true} = state, {:key, {:key_up, 1, _}}) do
    {:noop, move_cursor(state, :up)}
  end

  def process_input(%State{focused: true} = state, {:key, {:key_down, 1, _}}) do
    {:noop, move_cursor(state, :down)}
  end

  # Home/End
  def process_input(%State{focused: true} = state, {:key, {:key_home, 1, _}}) do
    {:noop, move_cursor(state, :line_start)}
  end

  def process_input(%State{focused: true} = state, {:key, {:key_end, 1, _}}) do
    {:noop, move_cursor(state, :line_end)}
  end

  # Enter - newline
  def process_input(%State{focused: true, mode: :multi_line} = state,
                    {:key, {:key_return, 1, _}}) do
    new_state = insert_newline(state)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  def process_input(%State{focused: true, mode: :single_line} = state,
                    {:key, {:key_return, 1, _}}) do
    # Single-line: emit enter event
    {:event, {:enter_pressed, state.id, State.get_text(state)}, state}
  end

  # Backspace
  def process_input(%State{focused: true} = state, {:key, {:key_backspace, 1, _}}) do
    new_state = delete_before_cursor(state)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # Delete
  def process_input(%State{focused: true} = state, {:key, {:key_delete, 1, _}}) do
    new_state = delete_at_cursor(state)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # Character input
  def process_input(%State{focused: true} = state, {:codepoint, {char, _}})
      when char >= 32 and char < 127 do
    # Printable ASCII only (for now)
    new_state = insert_char(state, <<char::utf8>>)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # Ignore unfocused input
  def process_input(%State{focused: false} = state, _input) do
    {:noop, state}
  end

  # Catch-all
  def process_input(state, _input) do
    {:noop, state}
  end

  # ===== EXTERNAL ACTION PROCESSING =====

  @doc "Process high-level actions (for external control mode)"
  def process_action(state, action)

  def process_action(state, {:insert_text, text}) do
    new_state = insert_text_at_cursor(state, text)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  def process_action(state, {:delete_char, :before}) do
    new_state = delete_before_cursor(state)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  def process_action(state, {:delete_char, :at}) do
    new_state = delete_at_cursor(state)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  def process_action(state, {:move_cursor, direction}) do
    {:noop, move_cursor(state, direction)}
  end

  def process_action(state, {:set_cursor, {line, col}}) do
    {:noop, %{state | cursor: {line, col}}}
  end

  def process_action(state, {:set_text, text}) do
    lines = String.split(text, "\n")
    new_state = %{state | lines: lines, cursor: {1, 1}}
    {:event, {:text_changed, state.id, text}, new_state}
  end

  def process_action(state, {:delete_line, line_num}) do
    new_lines = List.delete_at(state.lines, line_num - 1)
    new_state = %{state | lines: new_lines}
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # ===== HELPER FUNCTIONS (PRIVATE) =====

  defp move_cursor(%State{cursor: {line, col}} = state, :left) do
    cond do
      col > 1 ->
        %{state | cursor: {line, col - 1}}
      line > 1 ->
        # Move to end of previous line
        prev_line = State.get_line(state, line - 1)
        %{state | cursor: {line - 1, String.length(prev_line) + 1}}
      true ->
        state
    end
  end

  defp move_cursor(%State{cursor: {line, col}} = state, :right) do
    current_line = State.get_line(state, line)
    line_length = String.length(current_line)

    cond do
      col <= line_length ->
        %{state | cursor: {line, col + 1}}
      line < State.line_count(state) ->
        # Move to start of next line
        %{state | cursor: {line + 1, 1}}
      true ->
        state
    end
  end

  defp move_cursor(%State{cursor: {line, col}} = state, :up) do
    if line > 1 do
      %{state | cursor: {line - 1, col}}
    else
      state
    end
  end

  defp move_cursor(%State{cursor: {line, col}} = state, :down) do
    if line < State.line_count(state) do
      %{state | cursor: {line + 1, col}}
    else
      state
    end
  end

  defp move_cursor(%State{cursor: {line, _col}} = state, :line_start) do
    %{state | cursor: {line, 1}}
  end

  defp move_cursor(%State{cursor: {line, _col}} = state, :line_end) do
    current_line = State.get_line(state, line)
    %{state | cursor: {line, String.length(current_line) + 1}}
  end

  defp insert_char(%State{cursor: {line, col}, lines: lines} = state, char) do
    current_line = Enum.at(lines, line - 1, "")
    {before, after_cursor} = String.split_at(current_line, col - 1)
    new_line = before <> char <> after_cursor
    new_lines = List.replace_at(lines, line - 1, new_line)

    %{state | lines: new_lines, cursor: {line, col + 1}}
  end

  defp insert_text_at_cursor(%State{cursor: {line, col}, lines: lines} = state, text) do
    # TODO: Handle multi-line inserts
    current_line = Enum.at(lines, line - 1, "")
    {before, after_cursor} = String.split_at(current_line, col - 1)
    new_line = before <> text <> after_cursor
    new_lines = List.replace_at(lines, line - 1, new_line)

    %{state | lines: new_lines, cursor: {line, col + String.length(text)}}
  end

  defp insert_newline(%State{cursor: {line, col}, lines: lines} = state) do
    current_line = Enum.at(lines, line - 1, "")
    {before, after_cursor} = String.split_at(current_line, col - 1)

    new_lines =
      lines
      |> List.replace_at(line - 1, before)
      |> List.insert_at(line, after_cursor)

    %{state | lines: new_lines, cursor: {line + 1, 1}}
  end

  defp delete_before_cursor(%State{cursor: {line, 1}} = state) when line > 1 do
    # At start of line - join with previous line
    prev_line = State.get_line(state, line - 1)
    current_line = State.get_line(state, line)
    new_line = prev_line <> current_line

    new_lines =
      state.lines
      |> List.replace_at(line - 2, new_line)
      |> List.delete_at(line - 1)

    %{state | lines: new_lines, cursor: {line - 1, String.length(prev_line) + 1}}
  end

  defp delete_before_cursor(%State{cursor: {line, col}} = state) when col > 1 do
    current_line = State.get_line(state, line)
    {before, after_cursor} = String.split_at(current_line, col - 1)
    new_line = String.slice(before, 0..-2) <> after_cursor
    new_lines = List.replace_at(state.lines, line - 1, new_line)

    %{state | lines: new_lines, cursor: {line, col - 1}}
  end

  defp delete_before_cursor(state), do: state

  defp delete_at_cursor(%State{cursor: {line, col}} = state) do
    current_line = State.get_line(state, line)
    line_length = String.length(current_line)

    cond do
      col <= line_length ->
        # Delete character at cursor
        {before, after_cursor} = String.split_at(current_line, col - 1)
        new_line = before <> String.slice(after_cursor, 1..-1)
        new_lines = List.replace_at(state.lines, line - 1, new_line)
        %{state | lines: new_lines}

      line < State.line_count(state) ->
        # At end of line - join with next line
        next_line = State.get_line(state, line + 1)
        new_line = current_line <> next_line
        new_lines =
          state.lines
          |> List.replace_at(line - 1, new_line)
          |> List.delete_at(line)
        %{state | lines: new_lines}

      true ->
        state
    end
  end
end
```

---

## Text Wrapping & Scrolling Behavior

### Overview

TextField supports multiple strategies for handling text that exceeds the visible area:

| Strategy | Horizontal | Vertical | Use Case |
|----------|-----------|----------|----------|
| **No wrap, scroll both** | Scroll | Scroll | Code editor, wide logs |
| **Wrap words, scroll vertical** | Wrap | Scroll | Text editor, documentation |
| **Wrap chars, scroll vertical** | Wrap | Scroll | Chat, constrained width |
| **No wrap, fixed height** | Scroll | Scroll (limited) | Single-line input with overflow |
| **Auto-expand** | No scroll | Expand frame | Dynamic text areas |

### Configuration Options

```elixir
# Example 1: Code editor (wide lines, many lines)
%{
  frame: frame,
  wrap_mode: :none,           # Don't wrap - allow horizontal scroll
  scroll_mode: :both,         # Enable both horizontal and vertical scroll
  height_mode: {:fixed_lines, 40},  # Show exactly 40 lines
  show_line_numbers: true
}

# Example 2: Text editor (word wrap, vertical scroll)
%{
  frame: frame,
  wrap_mode: :word,           # Wrap on word boundaries
  scroll_mode: :vertical,     # Only vertical scroll (no horizontal)
  height_mode: :auto,         # Use full frame height
  show_line_numbers: false
}

# Example 3: Chat message input (constrained width)
%{
  frame: frame,
  wrap_mode: :char,           # Wrap at any character (no overflow)
  scroll_mode: :vertical,     # Vertical scroll only
  height_mode: {:fixed_lines, 3},  # Max 3 visible lines
  mode: :multi_line
}

# Example 4: Single-line input with overflow
%{
  frame: frame,
  mode: :single_line,
  wrap_mode: :none,           # Don't wrap (single line anyway)
  scroll_mode: :horizontal,   # Scroll long lines horizontally
  height_mode: {:fixed_lines, 1}
}

# Example 5: Auto-expanding text area
%{
  frame: frame,
  wrap_mode: :word,
  scroll_mode: :none,         # No scroll - frame expands instead
  height_mode: :auto          # Grows with content (up to max_lines)
}
```

### Wrapping Modes

#### `:none` - No Wrapping (Horizontal Scroll)
```
Visible Area (400px wide):
┌─────────────────────┐
│This is a very long l│→ (scroll right to see "ine of text")
│Another line         │
└─────────────────────┘
```

**Behavior**:
- Lines extend beyond visible width
- Horizontal scrollbar appears (if `scroll_mode` includes `:horizontal`)
- Cursor can move past right edge, triggering auto-scroll
- Good for: code, logs, tabular data

**Implementation**:
- Render full line width (use FontMetrics to calculate)
- Apply horizontal `translate` transform for scroll offset
- Use `scissor` to clip overflow

#### `:word` - Word Wrap
```
Visible Area (400px wide):
┌─────────────────────┐
│This is a very long  │
│line of text         │
│Another line         │
└─────────────────────┘
```

**Behavior**:
- Text wraps at word boundaries
- Single words longer than width wrap at character boundary
- No horizontal scroll
- Cursor movement wraps to next visual line
- Good for: prose, documentation, multi-paragraph text

**Implementation**:
- Calculate wrapped lines before rendering: `calculate_wrapped_lines/2`
- Store both logical lines (user input) and display lines (wrapped)
- Map cursor between logical and display coordinates

#### `:char` - Character Wrap
```
Visible Area (400px wide):
┌─────────────────────┐
│This is a very long l│
│ine of text          │
│Another line         │
└─────────────────────┘
```

**Behavior**:
- Wraps at any character position
- Maximizes use of horizontal space
- Good for: constrained UIs, mobile, chat

**Implementation**:
- Similar to word wrap but simpler (no word boundary detection)
- Break at frame width

### Scrolling Modes

#### `:none` - No Scroll (Frame Expansion)
```elixir
scroll_mode: :none,
height_mode: :auto
```

**Behavior**:
- TextField frame expands vertically to fit all content
- Useful for dynamic forms where TextField grows
- Parent scene must handle layout changes
- Can set `max_lines` to prevent infinite growth

**Event emitted**:
```elixir
{:height_changed, id, new_height_pixels}
```

#### `:vertical` - Vertical Scroll Only
```elixir
scroll_mode: :vertical,
wrap_mode: :word  # Usually paired with wrapping
```

**Behavior**:
- Fixed width (no horizontal scroll)
- Vertical scrollbar appears when content exceeds frame height
- Mouse wheel scrolls vertically
- Cursor at bottom of screen triggers auto-scroll down

**Implementation**:
- Apply vertical `translate: {0, -vertical_scroll_offset}`
- Render scrollbar (optional, can be hidden)
- Handle `:cursor_scroll` input events

#### `:horizontal` - Horizontal Scroll Only
```elixir
scroll_mode: :horizontal,
wrap_mode: :none  # Must be :none for horizontal scroll
```

**Behavior**:
- Fixed height
- Horizontal scrollbar for wide lines
- Cursor moving past right edge auto-scrolls

**Implementation**:
- Apply horizontal `translate: {-horizontal_scroll_offset, 0}`
- Calculate max line width for scrollbar size

#### `:both` - Bi-directional Scroll
```elixir
scroll_mode: :both,
wrap_mode: :none  # No wrapping when scrolling both directions
```

**Behavior**:
- Content scrolls in both dimensions
- Typical for code editors, spreadsheets
- Scrollbars in both directions

**Implementation**:
- Apply both transforms: `translate: {-h_offset, -v_offset}`
- Render both scrollbars

### Height Modes

#### `:auto` - Use Full Frame Height
```elixir
height_mode: :auto
```

- Uses entire `frame.size.height`
- Calculates `max_visible_lines` from frame height and font size
- Most common mode

#### `{:fixed_lines, n}` - Fixed Line Count
```elixir
height_mode: {:fixed_lines, 10}  # Always show exactly 10 lines
```

- Shows exactly N lines, regardless of frame size
- Useful for consistent UI layouts
- Remaining frame space can be used for scrollbar, padding, etc.

#### `{:fixed_pixels, n}` - Fixed Pixel Height
```elixir
height_mode: {:fixed_pixels, 240}  # 240px of content area
```

- Content area is exactly N pixels tall
- Useful when frame is larger than needed

### Scrollbar Rendering

TextField can render optional scrollbars:

```elixir
# State configuration
show_scrollbars: true,  # or false to hide
scrollbar_width: 12,    # pixels
scrollbar_style: :modern  # :modern | :classic | :minimal
```

**Scrollbar elements**:
- Track (background)
- Thumb (draggable indicator showing position and visible proportion)
- Auto-hide when content fits

### Dynamic Font & Configuration Updates

All visual properties can be updated dynamically via `handle_put/2`:

```elixir
# Change font size
Scene.put_child(scene, :editor, {:config, :font_size, 24})

# Change font family
Scene.put_child(scene, :editor, {:config, :font, %{name: :ibm_plex_mono, size: 20}})

# Change colors
Scene.put_child(scene, :editor, {:config, :colors, %{text: :green, background: :black}})

# Toggle line numbers
Scene.put_child(scene, :editor, {:config, :show_line_numbers, true})

# Change wrap mode
Scene.put_child(scene, :editor, {:config, :wrap_mode, :word})

# Change scroll mode
Scene.put_child(scene, :editor, {:config, :scroll_mode, :vertical})
```

**Implementation**:
```elixir
def handle_put({:config, key, value}, scene) do
  state = scene.assigns.state
  new_state = apply_config_change(state, key, value)

  # Some changes require full re-render
  graph = case key do
    :font -> Renderer.initial_render(Graph.build(), new_state)  # Full re-render
    :wrap_mode -> Renderer.initial_render(Graph.build(), new_state)
    :show_line_numbers -> Renderer.initial_render(Graph.build(), new_state)
    _ -> Renderer.update_render(scene.assigns.graph, state, new_state)
  end

  {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
end

defp apply_config_change(state, :font_size, size) do
  font = %{state.font | size: size}
  %{state | font: font, max_visible_lines: calculate_max_lines(state.frame, font)}
end

defp apply_config_change(state, :font, font) do
  %{state | font: font, max_visible_lines: calculate_max_lines(state.frame, font)}
end

defp apply_config_change(state, :wrap_mode, mode) when mode in [:none, :word, :char] do
  %{state | wrap_mode: mode}
end

defp apply_config_change(state, key, value) do
  Map.put(state, key, value)
end
```

### Text Wrapping Implementation Details

**Calculating Wrapped Lines**:
```elixir
defmodule ScenicWidgets.TextField.TextWrapper do
  @moduledoc "Handles text wrapping calculations"

  def wrap_lines(lines, wrap_mode, max_width, font) do
    case wrap_mode do
      :none ->
        # No wrapping - return lines as-is
        Enum.map(lines, fn line -> [line] end)

      :word ->
        # Word-wrap each line
        Enum.map(lines, fn line ->
          wrap_line_words(line, max_width, font)
        end)

      :char ->
        # Character-wrap each line
        Enum.map(lines, fn line ->
          wrap_line_chars(line, max_width, font)
        end)
    end
  end

  defp wrap_line_words(line, max_width, font) do
    words = String.split(line, " ")
    wrap_words(words, max_width, font, "", [])
  end

  defp wrap_words([], _max_width, _font, current_line, acc) do
    Enum.reverse([current_line | acc])
  end

  defp wrap_words([word | rest], max_width, font, current_line, acc) do
    test_line = if current_line == "", do: word, else: current_line <> " " <> word
    width = calculate_text_width(test_line, font)

    if width <= max_width do
      wrap_words(rest, max_width, font, test_line, acc)
    else
      # Word doesn't fit - start new line
      if current_line == "" do
        # Single word is too long - break at character level
        {first_part, rest_part} = split_long_word(word, max_width, font)
        wrap_words([rest_part | rest], max_width, font, "", [first_part | acc])
      else
        wrap_words(rest, max_width, font, word, [current_line | acc])
      end
    end
  end

  defp wrap_line_chars(line, max_width, font) do
    chars = String.graphemes(line)
    wrap_chars(chars, max_width, font, "", [])
  end

  defp wrap_chars([], _max_width, _font, current_line, acc) do
    Enum.reverse([current_line | acc])
  end

  defp wrap_chars([char | rest], max_width, font, current_line, acc) do
    test_line = current_line <> char
    width = calculate_text_width(test_line, font)

    if width <= max_width do
      wrap_chars(rest, max_width, font, test_line, acc)
    else
      wrap_chars(rest, max_width, font, char, [current_line | acc])
    end
  end

  defp calculate_text_width(text, %{metrics: metrics, size: size}) do
    # Use FontMetrics (or TruetypeMetrics) to get accurate width
    FontMetrics.width(text, size, metrics)
  end
end
```

**Cursor Mapping (Logical ↔ Display)**:

When text is wrapped, we need to map between:
- **Logical position**: `{line, col}` in original lines array
- **Display position**: `{display_line, display_col}` in wrapped/rendered lines

```elixir
defmodule ScenicWidgets.TextField.CursorMapper do
  def logical_to_display({logical_line, logical_col}, wrapped_lines) do
    # Find which display line corresponds to logical position
    # wrapped_lines is list of lists: [[wrapped_line1, wrapped_line2], [line2], ...]

    # TODO: Implement mapping
  end

  def display_to_logical({display_line, display_col}, wrapped_lines) do
    # Reverse mapping
    # TODO: Implement
  end
end
```

### Auto-scroll Behavior

**Vertical Auto-scroll** (when cursor moves off-screen):
```elixir
defp ensure_cursor_visible(state) do
  {line, _col} = state.cursor
  line_height = state.font.size
  cursor_y = (line - 1) * line_height
  viewport_height = state.frame.size.height

  cond do
    # Cursor above visible area
    cursor_y < state.vertical_scroll_offset ->
      %{state | vertical_scroll_offset: cursor_y}

    # Cursor below visible area
    cursor_y + line_height > state.vertical_scroll_offset + viewport_height ->
      new_offset = cursor_y + line_height - viewport_height
      %{state | vertical_scroll_offset: new_offset}

    true ->
      state
  end
end
```

**Horizontal Auto-scroll** (when cursor moves past edge):
```elixir
defp ensure_cursor_visible_horizontal(state) do
  {line, col} = state.cursor
  current_line = Enum.at(state.lines, line - 1, "")

  # Calculate cursor X position
  text_before_cursor = String.slice(current_line, 0, col - 1)
  cursor_x = calculate_text_width(text_before_cursor, state.font)

  viewport_width = state.frame.size.width - state.line_number_width

  cond do
    cursor_x < state.horizontal_scroll_offset ->
      %{state | horizontal_scroll_offset: max(0, cursor_x - 20)}  # 20px margin

    cursor_x > state.horizontal_scroll_offset + viewport_width ->
      new_offset = cursor_x - viewport_width + 20
      %{state | horizontal_scroll_offset: new_offset}

    true ->
      state
  end
end
```

---

## Implementation Plan

### Phase 1: Core Structure ✓ (Next)

**Tasks**:
1. Create 4-file skeleton
   - `lib/components/text_field/text_field.ex`
   - `lib/components/text_field/state.ex`
   - `lib/components/text_field/reducer.ex`
   - `lib/components/text_field/renderer.ex`

2. Implement `state.ex`
   - Full defstruct with all fields
   - `new/1` function (Frame or config map)
   - Query functions: `point_inside?/2`, `get_text/1`, etc.

3. Implement basic `renderer.ex`
   - `initial_render/2` - background, lines, cursor
   - Inline cursor rendering (no child component)
   - Line numbers (if configured)

4. Implement `text_field.ex` skeleton
   - `validate/1`
   - `init/3` - create state, render graph
   - `handle_info/2` for blink timer

**Acceptance**: Can load TextField in Widget Workbench (no input yet)

### Phase 2: Direct Input Mode

**Tasks**:
1. Implement `reducer.ex` input handlers
   - Cursor movement (arrows, home, end)
   - Character insertion
   - Backspace/delete
   - Enter (newline or submit event)

2. Implement `text_field.ex` input handling
   - `handle_input/3` for keyboard events
   - Request input when `input_mode == :direct`
   - Route to reducer, emit events

3. Implement focus management
   - Click to focus/unfocus
   - Visual border change
   - Start/stop cursor blink

4. Implement `renderer.ex` incremental updates
   - `update_render/3` - only update changed lines
   - Cursor position updates
   - Focus state changes

**Acceptance**: Can type, edit, move cursor in Widget Workbench

### Phase 3: External Control Mode

**Tasks**:
1. Implement `reducer.ex` action handlers
   - `process_action/2` for high-level actions
   - Actions: insert, delete, move, set_text

2. Implement `text_field.ex` external control
   - `handle_put/2` for action messages
   - `handle_put/2` for text replacement
   - Do NOT request input when `input_mode == :external`

3. Write test harness
   - Parent scene that sends actions via `put_child`
   - Test all action types

**Acceptance**: Can control TextField programmatically via put_child

### Phase 4: Widget Workbench Integration

**Tasks**:
1. Add TextField to available components
   - Update `widget_wkb_scene.ex` available_components list
   - Add default configuration

2. Add codepoint input support
   - Add `:codepoint` to `request_input` in widget_wkb_scene.ex
   - Forward keyboard events to loaded component

3. Test keyboard forwarding
   - Ensure key events reach TextField
   - Verify focus behavior works

**Acceptance**: TextField fully functional in Widget Workbench

### Phase 5: Scrolling & Wrapping

**Tasks**:
1. Vertical scrolling
   - Handle `:cursor_scroll` input
   - Track `vertical_scroll_offset` in state
   - Auto-scroll when cursor moves off-screen
   - Render vertical scrollbar (optional)

2. Horizontal scrolling (no-wrap mode)
   - Track `horizontal_scroll_offset` in state
   - Auto-scroll when cursor moves past edge
   - Render horizontal scrollbar (optional)

3. Text wrapping (word mode)
   - Implement `TextWrapper` module
   - Calculate wrapped lines before rendering
   - Map cursor between logical and display positions
   - Update renderer to show wrapped lines

4. Text wrapping (char mode)
   - Character-level wrapping (simpler than word)
   - Update cursor movement for wrapped lines

5. Height modes
   - Implement `:auto`, `{:fixed_lines, n}`, `{:fixed_pixels, n}`
   - Calculate `max_visible_lines` correctly
   - Emit `:height_changed` events for auto-expand mode

**Acceptance**: All wrap/scroll combinations work correctly

### Phase 6: Dynamic Configuration

**Tasks**:
1. Font updates via `handle_put`
   - `{:config, :font_size, size}`
   - `{:config, :font, font_map}`
   - Trigger full re-render on font changes

2. Visual config updates
   - `{:config, :colors, colors_map}`
   - `{:config, :show_line_numbers, boolean}`
   - `{:config, :wrap_mode, mode}`
   - `{:config, :scroll_mode, mode}`

3. Apply configuration changes
   - Determine if full or incremental re-render needed
   - Update `max_visible_lines` when font/frame changes
   - Recalculate wrapped lines when wrap mode changes

**Acceptance**: All visual properties updateable at runtime

### Phase 7: Advanced Features

**Tasks**:
1. Single-line mode
   - Prevent newlines when `mode == :single_line`
   - Emit `:enter_pressed` event instead
   - Horizontal scroll only

2. Mouse click cursor positioning
   - Calculate character position from click coords
   - Use FontMetrics for accurate placement
   - Support clicking in wrapped lines

3. Scrollbar interaction
   - Drag scrollbar thumb to scroll
   - Click track to page up/down
   - Auto-hide when content fits

4. Selection (future)
   - Mouse drag to select text
   - Shift+arrow keys to select
   - Copy selected text event

**Acceptance**: All features configurable and working

### Phase 8: Spex Tests

**Tasks**:
1. Basic load test
   - Loads in Widget Workbench
   - Renders correctly
   - Has semantic ID registered

2. Direct input tests
   - Typing characters updates text
   - Cursor movement works
   - Backspace/delete work
   - Focus/unfocus behavior

3. External control tests
   - put_child actions work
   - Events emitted correctly
   - State updates properly

4. Configuration tests
   - Single vs multi-line mode
   - Line numbers show/hide
   - Font customization

**Acceptance**: Full spex coverage, all tests passing

---

## Usage Examples

### Example 1: Simple Text Input (Widget Workbench)

```elixir
# In Widget Workbench, just load the component
# Default configuration: multi-line, direct input, no line numbers

graph
|> ScenicWidgets.TextField.add_to_graph(
  %{
    frame: Widgex.Frame.new(pin: {100, 100}, size: {400, 300}),
    initial_text: "Hello\nWorld",
    id: :my_field
  }
)

# Parent receives events
def handle_event({:text_changed, :my_field, new_text}, _from, scene) do
  IO.puts("Text changed to: #{new_text}")
  {:noreply, scene}
end
```

### Example 2: Form Input (Direct Mode)

```elixir
defmodule MyFormScene do
  use Scenic.Scene

  def init(scene, _params, _opts) do
    graph =
      Graph.build()
      |> ScenicWidgets.TextField.add_to_graph(
        %{
          frame: Widgex.Frame.new(pin: {20, 20}, size: {300, 40}),
          mode: :single_line,
          input_mode: :direct,
          initial_text: "",
          id: :username_field
        }
      )
      |> ScenicWidgets.TextField.add_to_graph(
        %{
          frame: Widgex.Frame.new(pin: {20, 80}, size: {300, 40}),
          mode: :single_line,
          input_mode: :direct,
          initial_text: "",
          id: :password_field
        }
      )

    {:ok, scene |> assign(graph: graph) |> push_graph(graph)}
  end

  def handle_event({:enter_pressed, :username_field, _text}, _from, scene) do
    # Focus password field
    {:noreply, scene}
  end

  def handle_event({:enter_pressed, :password_field, password}, _from, scene) do
    # Submit form
    {:ok, [username]} = Scene.get_child(scene, :username_field)
    submit_login(username, password)
    {:noreply, scene}
  end
end
```

### Example 3: Code Editor (External Control)

```elixir
defmodule MyCodeEditor do
  use Scenic.Scene

  def init(scene, _params, _opts) do
    graph =
      Graph.build()
      |> ScenicWidgets.TextField.add_to_graph(
        %{
          frame: Widgex.Frame.new(pin: {0, 0}, size: {800, 600}),
          mode: :multi_line,
          input_mode: :external,  # Parent controls input
          show_line_numbers: true,
          initial_text: load_file("my_code.ex"),
          id: :editor
        }
      )

    scene =
      scene
      |> assign(graph: graph, mode: :normal)
      |> request_input([:key, :codepoint])
      |> push_graph(graph)

    {:ok, scene}
  end

  def handle_input({:key, {:key_i, 1, _}}, _ctx, %{assigns: %{mode: :normal}} = scene) do
    # Enter insert mode
    {:noreply, assign(scene, mode: :insert)}
  end

  def handle_input({:key, {:key_escape, 1, _}}, _ctx, %{assigns: %{mode: :insert}} = scene) do
    # Exit insert mode
    {:noreply, assign(scene, mode: :normal)}
  end

  def handle_input({:codepoint, {char, _}}, _ctx, %{assigns: %{mode: :insert}} = scene) do
    # In insert mode: send character to editor
    Scene.put_child(scene, :editor, {:action, :insert_text, <<char::utf8>>})
    {:noreply, scene}
  end

  def handle_input({:key, {:key_h, 1, _}}, _ctx, %{assigns: %{mode: :normal}} = scene) do
    # Vim 'h' - move left
    Scene.put_child(scene, :editor, {:action, :move_cursor, :left})
    {:noreply, scene}
  end

  def handle_event({:text_changed, :editor, new_text}, _from, scene) do
    # Save to file, update undo stack, etc.
    save_file("my_code.ex", new_text)
    {:noreply, scene}
  end
end
```

### Example 4: Chat Application (Read-Only + Editable)

```elixir
defmodule MyChatApp do
  use Scenic.Scene
  alias ScenicWidgets.TextField

  def init(scene, _params, _opts) do
    # Chat messages (read-only TextFields with transparent backgrounds)
    graph =
      Graph.build()
      # Message 1: From other user
      |> TextField.add_to_graph(
        %{
          frame: Widgex.Frame.new(pin: {20, 20}, size: {400, 60}),
          initial_text: "Hey! How are you?",
          editable: false,
          selectable: true,
          wrap_mode: :word,
          scroll_mode: :none,
          show_line_numbers: false,
          colors: %{
            text: :white,
            background: :clear,    # Transparent - let parent draw bubble
            border: :clear
          },
          id: :msg_1
        },
        id: :msg_1
      )
      # Message 2: From me
      |> TextField.add_to_graph(
        %{
          frame: Widgex.Frame.new(pin: {20, 100}, size: {400, 40}),
          initial_text: "Great! Just coding.",
          editable: false,
          selectable: true,
          wrap_mode: :word,
          scroll_mode: :none,
          colors: %{
            text: :black,
            background: :clear,
            border: :clear
          },
          id: :msg_2
        },
        id: :msg_2
      )
      # Input field at bottom (editable)
      |> TextField.add_to_graph(
        %{
          frame: Widgex.Frame.new(pin: {20, 500}, size: {400, 80}),
          initial_text: "",
          mode: :multi_line,
          input_mode: :direct,
          editable: true,
          wrap_mode: :word,
          scroll_mode: :vertical,
          height_mode: {:fixed_lines, 3},
          show_line_numbers: false,
          colors: %{
            text: :black,
            background: :white,
            border: {200, 200, 200},
            focused_border: {100, 150, 255}
          },
          id: :chat_input
        },
        id: :chat_input
      )

    {:ok, scene |> assign(graph: graph) |> push_graph(graph)}
  end

  def handle_event({:text_changed, :chat_input, text}, _from, scene) do
    # User is typing in input field
    IO.puts("Input: #{text}")
    {:noreply, scene}
  end

  def handle_event({:enter_pressed, :chat_input, message}, _from, scene) do
    # User pressed enter - send message
    send_message(message)

    # Clear input field
    Scene.put_child(scene, :chat_input, "")

    # Add new message to chat (would update graph with new message TextField)
    {:noreply, scene}
  end

  def handle_event({:text_selected, msg_id, selected_text}, _from, scene) do
    # User selected text in a message (to copy)
    IO.puts("Selected from #{msg_id}: #{selected_text}")
    {:noreply, scene}
  end
end
```

**Chat message rendering pattern**:
```elixir
# For each chat message, render:
# 1. Background bubble (parent scene draws this)
# 2. TextField with transparent background (shows text)

defp render_chat_message(graph, message, y_pos, from_me?) do
  bubble_color = if from_me?, do: {100, 200, 100}, else: {100, 100, 200}
  text_color = :white

  graph
  # Draw chat bubble background
  |> Primitives.rrect(
    {400, 60, 10},  # width, height, radius
    fill: bubble_color,
    translate: {20, y_pos},
    id: {:bubble, message.id}
  )
  # Overlay TextField with transparent background
  |> TextField.add_to_graph(
    %{
      frame: Widgex.Frame.new(pin: {30, y_pos + 10}, size: {380, 40}),
      initial_text: message.text,
      editable: false,
      selectable: true,
      colors: %{
        text: text_color,
        background: :clear,  # See through to bubble
        border: :clear
      }
    },
    id: {:msg, message.id}
  )
end
```

### Example 5: Flamelex Integration

```elixir
defmodule Flamelex.BufferPane do
  use Scenic.Component

  def validate(data) do
    {:ok, data}
  end

  def init(scene, %{buffer_ref: buf_ref} = data, _opts) do
    # Subscribe to external buffer changes
    PubSub.subscribe({:buffer, buf_ref.uuid})

    # Load current buffer content
    {:ok, buffer} = BufferManager.get_buffer(buf_ref)

    graph =
      Graph.build()
      |> ScenicWidgets.TextField.add_to_graph(
        %{
          frame: data.frame,
          mode: :multi_line,
          input_mode: :external,  # Flamelex controls everything
          show_line_numbers: true,
          initial_text: Enum.join(buffer.lines, "\n"),
          font: %{name: :ibm_plex_mono, size: 24, metrics: buffer.font.metrics},
          id: :textfield
        }
      )

    scene =
      scene
      |> assign(graph: graph, buffer_ref: buf_ref)
      |> request_input([:key, :codepoint])
      |> push_graph(graph)

    {:ok, scene}
  end

  # Flamelex root scene sends input here
  def handle_cast({:user_input, input}, scene) do
    # Determine what to do based on buffer mode
    buffer_mode = scene.assigns.buffer_ref.mode

    action = case buffer_mode do
      :edit -> NotepadKeyMap.handle(input)
      {:vim, :insert} -> VimInsertMap.handle(input)
      {:vim, :normal} -> VimNormalMap.handle(input)
    end

    # Send action to TextField
    case action do
      {:insert, text, :at_cursor} ->
        Scene.put_child(scene, :textfield, {:action, :insert_text, text})
      {:move_cursor, direction, _count} ->
        Scene.put_child(scene, :textfield, {:action, :move_cursor, direction})
      {:delete, :before_cursor} ->
        Scene.put_child(scene, :textfield, {:action, :delete_char, :before})
      _ ->
        :ok
    end

    {:noreply, scene}
  end

  # TextField emits text_changed events
  def handle_event({:text_changed, :textfield, new_text}, _from, scene) do
    # Update external buffer
    BufferManager.update_buffer(scene.assigns.buffer_ref.uuid, new_text)
    {:noreply, scene}
  end

  # External buffer changed (from different source)
  def handle_info({:buffer_updated, new_buffer}, scene) do
    # Update TextField display
    Scene.put_child(scene, :textfield, {:action, :set_text, Enum.join(new_buffer.lines, "\n")})
    {:noreply, scene}
  end
end
```

---

## Testing Strategy

### Unit Tests (ExUnit)

**State Tests** (`test/components/text_field/state_test.exs`):
```elixir
defmodule ScenicWidgets.TextField.StateTest do
  use ExUnit.Case
  alias ScenicWidgets.TextField.State

  test "new/1 with Frame creates default state" do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {400, 300})
    state = State.new(frame)

    assert state.frame == frame
    assert state.lines == [""]
    assert state.cursor == {1, 1}
    assert state.mode == :multi_line
    assert state.input_mode == :direct
  end

  test "point_inside?/2 detects clicks correctly" do
    frame = Widgex.Frame.new(pin: {100, 100}, size: {200, 200})
    state = State.new(frame)

    assert State.point_inside?(state, {150, 150})
    refute State.point_inside?(state, {50, 50})
  end

  test "get_text/1 joins lines with newlines" do
    state = %State{lines: ["hello", "world"]}
    assert State.get_text(state) == "hello\nworld"
  end
end
```

**Reducer Tests** (`test/components/text_field/reducer_test.exs`):
```elixir
defmodule ScenicWidgets.TextField.ReducerTest do
  use ExUnit.Case
  alias ScenicWidgets.TextField.{State, Reducer}

  setup do
    state = %State{
      lines: ["hello"],
      cursor: {1, 6},
      focused: true,
      id: :test_field
    }
    {:ok, state: state}
  end

  test "insert character at cursor", %{state: state} do
    {:event, event, new_state} = Reducer.process_input(state, {:codepoint, {?x, nil}})

    assert new_state.lines == ["hellox"]
    assert new_state.cursor == {1, 7}
    assert event == {:text_changed, :test_field, "hellox"}
  end

  test "move cursor left", %{state: state} do
    {:noop, new_state} = Reducer.process_input(state, {:key, {:key_left, 1, []}})

    assert new_state.cursor == {1, 5}
    assert new_state.lines == state.lines
  end

  test "backspace at start of line joins with previous", %{state: state} do
    state = %{state | lines: ["hello", "world"], cursor: {2, 1}}

    {:event, _event, new_state} = Reducer.process_input(state, {:key, {:key_backspace, 1, []}})

    assert new_state.lines == ["helloworld"]
    assert new_state.cursor == {1, 6}
  end

  test "enter creates newline in multi-line mode", %{state: state} do
    state = %{state | cursor: {1, 3}, mode: :multi_line}

    {:event, _event, new_state} = Reducer.process_input(state, {:key, {:key_return, 1, []}})

    assert new_state.lines == ["he", "llo"]
    assert new_state.cursor == {2, 1}
  end

  test "enter emits event in single-line mode", %{state: state} do
    state = %{state | mode: :single_line}

    {:event, event, new_state} = Reducer.process_input(state, {:key, {:key_return, 1, []}})

    assert event == {:enter_pressed, :test_field, "hello"}
    assert new_state.lines == state.lines  # Unchanged
  end

  test "external action: insert_text", %{state: state} do
    {:event, _event, new_state} = Reducer.process_action(state, {:insert_text, "xyz"})

    assert new_state.lines == ["helloxyz"]
    assert new_state.cursor == {1, 9}
  end
end
```

### Integration Tests (Spex)

**Basic Load Test** (`test/spex/text_field/01_load_spex.exs`):
```elixir
defmodule ScenicWidgets.TextField.LoadSpex do
  use SexySpex

  alias ScenicWidgets.TestHelpers.{SemanticUI, ScriptInspector}

  setup_all do
    # Standard viewport setup (from WIDGET_WKB_BASE_PROMPT.md)
    {:ok, %{viewport_pid: viewport_pid}}
  end

  spex "TextField loads successfully" do
    scenario "Load TextField in Widget Workbench", context do
      given_ "Widget Workbench is running", context do
        SemanticUI.verify_widget_workbench_loaded()
      end

      when_ "we load TextField component", context do
        SemanticUI.load_component("Text Field")
      end

      then_ "TextField should be visible with default text", context do
        {:ok, elements} = SemanticUI.find_clickable_elements()
        assert Enum.any?(elements, fn e -> e.id == :text_field end)
        :ok
      end
    end
  end
end
```

**Direct Input Test** (`test/spex/text_field/02_typing_spex.exs`):
```elixir
defmodule ScenicWidgets.TextField.TypingSpex do
  use SexySpex

  setup_all do
    # Setup viewport
    {:ok, %{viewport_pid: viewport_pid}}
  end

  spex "Typing updates text" do
    scenario "Type characters into TextField", context do
      given_ "TextField is loaded and focused", context do
        SemanticUI.load_component("Text Field")
        SemanticUI.click_element(:text_field)
        {:ok, context}
      end

      when_ "we type 'hello'", context do
        SemanticUI.send_keys("hello")
        Process.sleep(100)  # Wait for render
        {:ok, context}
      end

      then_ "text should contain 'hello'", context do
        # Verify via screenshot or inspect_viewport
        {:ok, ui} = SemanticUI.inspect_viewport()
        assert ui =~ "hello"
        :ok
      end
    end
  end
end
```

**External Control Test** (`test/spex/text_field/03_external_control_spex.exs`):
```elixir
defmodule ScenicWidgets.TextField.ExternalControlSpex do
  use SexySpex

  spex "External control via put_child works" do
    scenario "Parent sends actions to TextField", context do
      given_ "TextField is loaded in external mode", context do
        # Custom test scene that loads TextField with input_mode: :external
        {:ok, context}
      end

      when_ "parent sends insert_text action", context do
        # Scene.put_child(scene, :text_field, {:action, :insert_text, "test"})
        {:ok, context}
      end

      then_ "TextField should display the text", context do
        # Verify text appears
        :ok
      end
    end
  end
end
```

---

## Configuration Reference

### Complete Configuration Options

```elixir
%{
  # ===== REQUIRED =====
  frame: %Widgex.Frame{},       # Position and size

  # ===== CORE BEHAVIOR =====
  mode: :multi_line,            # :single_line | :multi_line
  input_mode: :direct,          # :direct | :external
  initial_text: "",             # Starting text content
  id: :my_field,                # Component ID (for events)

  # ===== TEXT WRAPPING =====
  wrap_mode: :none,             # :none | :word | :char

  # ===== SCROLLING =====
  scroll_mode: :both,           # :none | :vertical | :horizontal | :both
  height_mode: :auto,           # :auto | {:fixed_lines, n} | {:fixed_pixels, n}
  max_lines: nil,               # Integer or nil (limit total lines)

  # ===== VISUAL =====
  show_line_numbers: false,     # Boolean
  line_number_width: 40,        # Pixels (if line numbers enabled)
  show_scrollbars: true,        # Boolean
  scrollbar_width: 12,          # Pixels
  scrollbar_style: :modern,     # :modern | :classic | :minimal

  # ===== FONTS =====
  font: %{
    name: :roboto_mono,         # Atom (font registered with Scenic)
    size: 20,                   # Integer (pixels)
    metrics: nil                # FontMetrics struct (loaded automatically)
  },

  # ===== COLORS =====
  colors: %{
    text: :white,               # Text color
    background: {30, 30, 30},   # Background color
    cursor: :white,             # Cursor color
    line_numbers: {100, 100, 100},   # Line number color
    border: {60, 60, 60},       # Border when not focused
    focused_border: {100, 150, 200}, # Border when focused
    scrollbar_track: {40, 40, 40},   # Scrollbar background
    scrollbar_thumb: {80, 80, 80}    # Scrollbar handle
  },

  # ===== INTERACTION =====
  editable: true,               # Boolean (allow editing)
  selectable: true,             # Boolean (allow text selection)

  # ===== ADVANCED =====
  cursor_blink_rate: 500,       # Milliseconds
  tab_width: 4,                 # Spaces per tab character
  selection_color: {100, 150, 255, 80}  # RGBA for text selection
}
```

### Configuration Presets

**Preset 1: Code Editor**
```elixir
ScenicWidgets.TextField.Presets.code_editor(frame, %{
  language: :elixir,            # Optional syntax highlighting hint
  show_line_numbers: true,
  font_size: 16
})

# Expands to:
%{
  frame: frame,
  mode: :multi_line,
  input_mode: :direct,
  wrap_mode: :none,
  scroll_mode: :both,
  height_mode: :auto,
  show_line_numbers: true,
  font: %{name: :ibm_plex_mono, size: 16},
  colors: %{
    text: {200, 200, 200},
    background: {20, 20, 20},
    line_numbers: {80, 80, 80},
    # ... code-editor themed colors
  }
}
```

**Preset 2: Text Document Editor**
```elixir
ScenicWidgets.TextField.Presets.document_editor(frame)

# Expands to:
%{
  frame: frame,
  mode: :multi_line,
  input_mode: :direct,
  wrap_mode: :word,             # Word wrap enabled
  scroll_mode: :vertical,       # Vertical scroll only
  height_mode: :auto,
  show_line_numbers: false,
  font: %{name: :roboto, size: 18},
  colors: %{
    text: {40, 40, 40},
    background: {255, 255, 255}, # White background
    # ... document-themed colors
  }
}
```

**Preset 3: Chat Input Box**
```elixir
ScenicWidgets.TextField.Presets.chat_input(frame)

# Expands to:
%{
  frame: frame,
  mode: :multi_line,
  input_mode: :direct,
  wrap_mode: :char,             # Character wrap
  scroll_mode: :vertical,
  height_mode: {:fixed_lines, 3}, # Max 3 lines visible
  max_lines: 10,                # Max 10 total lines
  show_line_numbers: false,
  font: %{name: :roboto, size: 14}
}
```

**Preset 4: Single-Line Form Input**
```elixir
ScenicWidgets.TextField.Presets.form_input(frame, placeholder: "Enter email...")

# Expands to:
%{
  frame: frame,
  mode: :single_line,
  input_mode: :direct,
  wrap_mode: :none,
  scroll_mode: :horizontal,
  height_mode: {:fixed_lines, 1},
  show_line_numbers: false,
  placeholder: "Enter email...",  # Shown when empty
  font: %{name: :roboto, size: 16}
}
```

**Preset 5: Read-Only Text Display (Chat Message)**
```elixir
ScenicWidgets.TextField.Presets.text_display(frame, %{
  text: "Hello world!\nThis is a message.",
  author_color: :blue
})

# Expands to:
%{
  frame: frame,
  mode: :multi_line,
  input_mode: :external,        # No direct input
  initial_text: "Hello world!\nThis is a message.",
  editable: false,              # Read-only
  selectable: true,             # Can select to copy
  wrap_mode: :word,             # Wrap text to fit
  scroll_mode: :vertical,       # Scroll if needed
  height_mode: :auto,           # Use full frame
  show_line_numbers: false,
  show_scrollbars: false,       # Clean display
  colors: %{
    text: :white,
    background: :clear,         # Transparent background!
    border: :clear              # No border
  },
  font: %{name: :roboto, size: 14}
}
```

**Preset 6: Code Block Display (Read-Only)**
```elixir
ScenicWidgets.TextField.Presets.code_block(frame, %{
  text: "defmodule MyApp do\n  def start do\n    :ok\n  end\nend",
  language: :elixir
})

# Expands to:
%{
  frame: frame,
  mode: :multi_line,
  input_mode: :external,
  initial_text: "...",
  editable: false,              # Read-only code display
  selectable: true,             # Can select to copy
  wrap_mode: :none,             # Don't wrap code
  scroll_mode: :both,           # Scroll if needed
  height_mode: :auto,
  show_line_numbers: true,      # Show line numbers for code
  colors: %{
    text: {200, 200, 200},
    background: {30, 30, 35},   # Dark code background
    line_numbers: {100, 100, 100},
    border: {60, 60, 70}
  },
  font: %{name: :ibm_plex_mono, size: 13}
}
```

### Runtime Configuration Changes

All configuration options can be changed at runtime via `Scene.put_child`:

```elixir
# Example: Toggle between code and prose modes

# Start as code editor
config = ScenicWidgets.TextField.Presets.code_editor(frame)

# Later... switch to prose mode
Scene.put_child(scene, :editor, {:config, :wrap_mode, :word})
Scene.put_child(scene, :editor, {:config, :scroll_mode, :vertical})
Scene.put_child(scene, :editor, {:config, :show_line_numbers, false})

# Or batch multiple config changes:
Scene.put_child(scene, :editor, {:config_batch, %{
  wrap_mode: :word,
  scroll_mode: :vertical,
  show_line_numbers: false,
  font: %{name: :roboto, size: 18}
}})
```

### Editable vs Read-Only Modes

TextField supports three interaction modes:

| Mode | `editable` | `selectable` | Input? | Cursor? | Use Case |
|------|-----------|-------------|--------|---------|----------|
| **Editable** | `true` | `true` | ✅ | ✅ Blinks | Text editor, forms |
| **Read-Only Selectable** | `false` | `true` | ❌ | ✅ No blink | Chat messages, code blocks |
| **Display Only** | `false` | `false` | ❌ | ❌ Hidden | Labels, static text |

**Behavior by Mode**:

#### Editable Mode (`editable: true`)
```elixir
%{
  editable: true,
  selectable: true  # Usually true when editable
}
```

- ✅ Accepts keyboard input (if `input_mode: :direct`)
- ✅ Shows blinking cursor
- ✅ Can select text (mouse drag, shift+arrows)
- ✅ Can copy/cut/paste
- ✅ Emits `{:text_changed, id, text}` events
- ✅ Visual focus indication (border changes)

**Reducer behavior**:
```elixir
def process_input(%{editable: true} = state, {:codepoint, {char, _}}) do
  # Insert character
  new_state = insert_char(state, <<char::utf8>>)
  {:event, {:text_changed, state.id, get_text(new_state)}, new_state}
end
```

#### Read-Only Selectable Mode (`editable: false, selectable: true`)
```elixir
%{
  editable: false,
  selectable: true
}
```

- ❌ Rejects keyboard text input
- ✅ Shows cursor (no blink) when focused
- ✅ Can select text (for copying)
- ✅ Can scroll with arrow keys, mouse wheel
- ✅ Emits `{:text_selected, id, selected_text}` events
- ✅ Can focus/unfocus

**Reducer behavior**:
```elixir
def process_input(%{editable: false, selectable: true} = state, {:codepoint, _}) do
  # Ignore text input
  {:noop, state}
end

def process_input(%{editable: false, selectable: true} = state, {:key, {:key_left, 1, _}}) do
  # Allow cursor movement for selection
  {:noop, move_cursor(state, :left)}
end
```

**Use cases**:
- Chat message display (can select to copy)
- Code snippet display (can select code)
- Read-only document viewer
- Log viewer

#### Display Only Mode (`editable: false, selectable: false`)
```elixir
%{
  editable: false,
  selectable: false
}
```

- ❌ No keyboard interaction
- ❌ No cursor shown
- ❌ Cannot select text
- ✅ Can scroll (if `scroll_mode` enabled)
- ❌ Does not capture focus
- Essentially a "fancy label"

**Reducer behavior**:
```elixir
def process_input(%{editable: false, selectable: false} = state, _input) do
  # Ignore all input except scroll
  {:noop, state}
end

def process_input(%{editable: false, selectable: false} = state, {:cursor_scroll, _}) do
  # Allow scrolling
  {:noop, handle_scroll(state)}
end
```

**Use cases**:
- Text labels with wrapping
- Info panels
- Status displays
- Tooltips with multi-line text

### Transparent Backgrounds

TextField supports `:clear` (transparent) backgrounds for overlaying text on other UI:

```elixir
%{
  colors: %{
    background: :clear,  # Transparent background
    border: :clear       # No border
  }
}
```

**Rendering**:
```elixir
# In renderer.ex
defp render_background(graph, state) do
  case state.colors.background do
    :clear ->
      # Don't render background rect
      graph

    color ->
      graph
      |> Primitives.rect(
        {state.frame.size.width, state.frame.size.height},
        fill: color,
        id: :background
      )
  end
end
```

**Use cases**:
- Chat bubbles (message text over bubble shape)
- Code blocks in documentation (over card background)
- Inline labels in complex layouts
- Tooltip text (over tooltip background)

### Wrap/Scroll Compatibility Matrix

| wrap_mode | scroll_mode | Valid? | Use Case |
|-----------|------------|--------|----------|
| `:none` | `:both` | ✅ | Code editor |
| `:none` | `:vertical` | ✅ | Fixed-width logs |
| `:none` | `:horizontal` | ✅ | Single-line input |
| `:none` | `:none` | ✅ | Fixed-size display |
| `:word` | `:vertical` | ✅ | Text editor |
| `:word` | `:both` | ⚠️ | Rare (why wrap if you h-scroll?) |
| `:word` | `:horizontal` | ❌ | Invalid (wrapped text doesn't h-scroll) |
| `:word` | `:none` | ✅ | Auto-expanding textarea |
| `:char` | `:vertical` | ✅ | Chat input, mobile |
| `:char` | `:both` | ⚠️ | Rare |
| `:char` | `:horizontal` | ❌ | Invalid |
| `:char` | `:none` | ✅ | Auto-expanding |

**Validation**:
```elixir
# TextField will validate on init and return error for invalid combinations
{:error, "Invalid config: wrap_mode :word with scroll_mode :horizontal"}
```

---

## Appendix: Key Takeaways

### What Makes This Architecture Special

1. **Flexible Input Handling**
   - Simple apps: TextField handles everything
   - Complex apps: Parent has full control
   - Both modes always emit events for observability

2. **True Reusability**
   - Works in Widget Workbench (simple demo)
   - Works in Flamelex (complex editor with modes)
   - Works in forms, chat apps, code editors, etc.

3. **Scenic Best Practices**
   - Uses `handle_put/2` for external updates
   - Emits events via `send_parent_event/2`
   - Follows 4-file scenic-widget-contrib pattern
   - Incremental rendering (only update what changed)

4. **State Ownership Options**
   - Direct mode: State lives in TextField
   - External mode: State can live anywhere, synced via put_child
   - Hybrid: TextField owns display state, parent owns logical state

### Comparison with Quillex BufferPane

| Feature | BufferPane | TextField |
|---------|-----------|-----------|
| **Architecture** | Custom (3 files + cursor child) | 4-file scenic-widget-contrib pattern |
| **State** | External (GenServer) | Internal + external via put_child |
| **Input** | Via parent forwarding only | Direct OR external |
| **Cursor** | Child component | Inline rendering |
| **Modes** | Vim/Notepad handlers | Configurable, parent-controlled |
| **Reusability** | Quillex-specific | General-purpose |
| **PubSub** | Required | Optional (via events) |

### Migration Path from BufferPane

For projects currently using BufferPane:

1. **Keep external buffer process** (if desired)
2. **Load TextField in external mode**
3. **Route input through existing key handlers**
4. **Use put_child to send actions**
5. **Sync changes via text_changed events**

No need to rewrite existing mode logic - TextField is designed to be controlled!

---

## Next Steps

1. ✅ Write this architecture document
2. ▶️ **Implement Phase 1: Core Structure**
   - Create 4-file skeleton
   - Implement State module
   - Implement basic Renderer
   - Get basic display working in Widget Workbench

3. Continue with Phase 2-6 as outlined above

---

**Document Version**: 1.0
**Last Updated**: 2025-11-02
**Author**: Claude (based on investigation & collaboration)
