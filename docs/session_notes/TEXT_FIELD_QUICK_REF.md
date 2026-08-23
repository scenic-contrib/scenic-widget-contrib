# TextField Quick Reference Card

**One-page cheat sheet for TextField implementation**

---

## Files

```
lib/components/text_field/
├── text_field.ex    # Component lifecycle (validate, init, handle_input, handle_put)
├── state.ex         # State struct + queries (new/1, point_inside?/2, get_text/1)
├── reducer.ex       # Pure transitions (process_input/2, process_action/2)
└── renderer.ex      # Rendering (initial_render/2, update_render/3)
```

---

## State Fields (Minimal for Phase 1)

```elixir
defstruct [
  frame: nil,              # Widgex.Frame
  lines: [""],             # ["line 1", "line 2"]
  cursor: {1, 1},          # {line, col} - 1-indexed
  focused: false,
  cursor_visible: true,
  cursor_timer: nil,
  mode: :multi_line,       # :single_line | :multi_line
  input_mode: :direct,     # :direct | :external
  editable: true,          # Allow editing
  show_line_numbers: false,
  font: %{name: :roboto_mono, size: 20, metrics: nil},
  colors: %{text: :white, background: {30,30,30}, cursor: :white}
]
```

---

## Validation Pattern

```elixir
def validate(%Widgex.Frame{} = frame), do: {:ok, frame}
def validate(%{frame: %Widgex.Frame{}} = data), do: {:ok, data}
def validate(_), do: {:error, "TextField requires Widgex.Frame"}
```

---

## Init Pattern

```elixir
def init(scene, data, _opts) do
  state = State.new(data)
  graph = Renderer.initial_render(Graph.build(), state)

  {:ok, timer} = if state.editable do
    :timer.send_interval(500, :blink)
  else
    {:ok, nil}
  end

  scene =
    scene
    |> assign(state: %{state | cursor_timer: timer}, graph: graph)
    |> push_graph(graph)

  {:ok, scene}
end
```

---

## Blink Timer

```elixir
def handle_info(:blink, scene) do
  state = %{scene.assigns.state | cursor_visible: !scene.assigns.state.cursor_visible}
  graph = Renderer.update_render(scene.assigns.graph, scene.assigns.state, state)
  {:noreply, scene |> assign(state: state, graph: graph) |> push_graph(graph)}
end
```

---

## Renderer Pattern (Phase 1 - Basic)

```elixir
def initial_render(graph, state) do
  graph
  |> render_background(state)
  |> render_lines(state)
  |> render_cursor(state)
end

defp render_background(graph, %{colors: %{background: :clear}}), do: graph
defp render_background(graph, state) do
  graph
  |> rect({state.frame.size.width, state.frame.size.height}, fill: state.colors.background)
end

defp render_lines(graph, state) do
  Enum.reduce(Enum.with_index(state.lines, 1), graph, fn {line, idx}, g ->
    y = (idx - 1) * state.font.size + state.font.size
    g
    |> text(line, translate: {10, y}, fill: state.colors.text, font_size: state.font.size)
  end)
end

defp render_cursor(graph, state) do
  {line, col} = state.cursor
  x = 10 + (col - 1) * 10  # TODO: use FontMetrics
  y = (line - 1) * state.font.size

  graph
  |> rect({2, state.font.size},
      translate: {x, y},
      fill: state.colors.cursor,
      hidden: !state.cursor_visible)
end
```

---

## Add to Widget Workbench

In `widget_wkb_scene.ex`:

```elixir
defp available_components do
  [
    # ... existing components
    %{
      name: "Text Field",
      module: ScenicWidgets.TextField,
      generate_frame: fn ->
        Widgex.Frame.new(pin: {100, 100}, size: {400, 300})
      end,
      default_data: fn frame ->
        %{
          frame: frame,
          initial_text: "Hello World!\nType here...",
          mode: :multi_line,
          show_line_numbers: false
        }
      end
    }
  ]
end
```

---

## Configuration Examples

**Minimal**:
```elixir
%{frame: frame}
```

**Code Editor**:
```elixir
%{
  frame: frame,
  show_line_numbers: true,
  wrap_mode: :none,
  scroll_mode: :both
}
```

**Chat Message (Read-only)**:
```elixir
%{
  frame: frame,
  initial_text: "Hello!",
  editable: false,
  selectable: true,
  colors: %{background: :clear, border: :clear}
}
```

---

## Input Modes

### Direct Mode (Phase 2)
```elixir
def init(scene, data, _opts) do
  # ...
  scene = if state.input_mode == :direct do
    request_input(scene, [:cursor_button, :key, :codepoint])
  else
    scene
  end
  # ...
end

def handle_input({:codepoint, {char, _}}, _ctx, scene) do
  # Process via Reducer.process_input
end
```

### External Mode (Phase 3)
```elixir
def handle_put({:action, :insert_text, text}, scene) do
  # Process via Reducer.process_action
end

def handle_put(text, scene) when is_bitstring(text) do
  # Replace all text
end
```

---

## Events Emitted

```elixir
{:text_changed, id, full_text}
{:cursor_moved, id, {line, col}}
{:focus_gained, id}
{:focus_lost, id}
{:enter_pressed, id, text}  # Single-line mode
```

---

## Testing Checklist

- [ ] Compiles without warnings
- [ ] Loads in Widget Workbench
- [ ] Displays text correctly
- [ ] Cursor blinks every 500ms
- [ ] Line numbers show/hide
- [ ] Transparent background works
- [ ] No crashes on init

---

## Phase 1 Acceptance

```bash
iex -S mix
# In Widget Workbench:
# 1. Click "Load Component"
# 2. Select "Text Field"
# 3. See text render with blinking cursor
# 4. Toggle line numbers in config
```

**Phase 1 Done!** → Move to Phase 2 (Input Handling)
