# Widgex Component Design Guide

AI-oriented reference for building Scenic components with the Widgex library.

## Frame System

Frames are the layout primitive — a rectangle with a pin (top-left) and size.

```elixir
%Widgex.Frame{
  pin: %Coordinates{x: 0, y: 0, point: {0, 0}},
  size: %Dimensions{width: 800, height: 600, box: {800, 600}}
}
```

### Constructors

```elixir
Frame.new(pin: {x, y}, size: {w, h})
Frame.new(%Scenic.ViewPort{})          # full viewport
```

### Splitting & Layout

```elixir
[left, right] = Frame.h_split(frame)                # 50/50 horizontal
[left, right] = Frame.h_split(frame, px: 300)       # left = 300px
[left, right] = Frame.h_split(frame, fraction: 0.3) # left = 30%

[top, bottom] = Frame.v_split(frame, px: 60)        # top = 60px

columns = Frame.col_split(frame, 4)                 # 4 equal columns

smaller = Frame.shrink(frame, 0.5, :top)             # half height from top
```

### Corners & Center

```elixir
Frame.center(frame)       # => %Coordinates{x, y}
Frame.top_left(frame)
Frame.top_right(frame)
Frame.bottom_left(frame)
Frame.bottom_right(frame)
```

### Debug Guides

```elixir
graph |> Frame.draw_guides(frame)                          # X-box outline
graph |> Frame.draw_guidewires(frame, background: :red)    # filled guide
```

## Scrollable Pattern

Widgex.Scrollable is a macro that injects scroll management functions into your module.

### Setup

```elixir
defmodule MyComponent.State do
  use Widgex.Scrollable, direction: :vertical   # :horizontal | :both
  # Also accepts: scroll_speed: 50  (default: 40 px/tick)

  defstruct [:frame, :items, :scroll]

  def new(frame, items) do
    content_height = length(items) * 30
    %__MODULE__{
      frame: frame,
      items: items,
      scroll: init_scroll(frame, content_height: content_height)
    }
  end
end
```

**Important:** `use Widgex.Scrollable` must come before `defstruct` — it defines `@scroll_direction` and `@scroll_speed` module attributes.

### ScrollState Structure

```elixir
%ScrollState{
  offset_x: 0,              # current scroll position
  offset_y: 0,
  content_width: 0,          # full content size
  content_height: 0,
  viewport_width: 0,         # visible area
  viewport_height: 0,
  direction: :vertical,
  scroll_speed: 40,
  scrollbar_visible: false,
  scrollbar_opacity: 0,
  scrollbar_fade_timer: nil,
  shift_held: false
}
```

### Input Handling

```elixir
# In your reducer/input handler:
def handle_input({:cursor_scroll, {{_x, y}, _}}, _ctx, scene) do
  state = scene.assigns.state
  new_scroll = handle_scroll(state.scroll, -y)   # NEGATE delta!

  if scroll_changed?(state.scroll, new_scroll) do
    new_state = %{state | scroll: new_scroll}
    graph = render(new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  else
    {:noreply, scene}
  end
end
```

### Rendering with Scrollable Groups

```elixir
def render(graph, state) do
  graph
  |> scrollable_group(state.scroll, state.frame, fn g ->
    # Render content here — coordinates are in content space
    render_items(g, state.items)
  end, id: :my_content)
  |> render_scrollbars(state.scroll, state.frame)
end
```

`scrollable_group` creates a nested structure:
- **Outer group:** has `scissor: {width, height}` to clip overflow
- **Inner group:** has `translate: {-offset_x, -offset_y}` to shift content

### Efficient Updates

When only the scroll position changes (not the content):

```elixir
graph
|> update_scroll_transform(:my_content, old_scroll, new_scroll)
|> update_scrollbars(old_scroll, new_scroll, frame)
```

### Other Scroll Functions

```elixir
update_content_size(scroll, width, height)    # when items change
scroll_to_show(scroll, {x, y, w, h}, margin)  # auto-scroll to rect
show_scrollbars(scroll) / hide_scrollbars(scroll)
scroll_changed?(old, new)                      # needs re-render?
```

## Scenic Retained Mode & Graph Updates

Scenic is a **retained mode** rendering system. The `%Graph{}` is a persistent data structure held by each scene — you don't redraw from scratch every frame. This has major implications for how you write render functions.

### Prefer In-Place Graph Modification

Render functions should accept an existing `%Graph{}` and return it with modifications applied, not build a new one:

```elixir
# GOOD — takes graph, returns graph
defp render_sidebar(graph, state) do
  graph
  |> rect({200, 600}, fill: {40, 42, 52}, translate: {0, 0})
  |> text(state.title, translate: {10, 30}, fill: :white, font_size: 14)
end

# BAD — builds from scratch, discards everything else in the graph
defp render_sidebar(state) do
  Graph.build()
  |> rect({200, 600}, fill: {40, 42, 52})
  |> text(state.title, translate: {10, 30}, fill: :white, font_size: 14)
end
```

### Graph.modify for Targeted Updates

When only one part of the UI changed, use `Graph.modify/3` to update just that primitive by its `:id`:

```elixir
# Give primitives an id during initial render:
graph
|> text("0 items", id: :item_count, translate: {10, 30}, fill: :white, font_size: 14)

# Later, update just that primitive:
graph = Graph.modify(graph, :item_count, fn prim ->
  Scenic.Primitive.put_style(prim, :fill, :green)
  |> Scenic.Primitive.merge_opts(data: "#{count} items")
end)
```

This is far cheaper than rebuilding the whole graph. Use it for counters, status text, highlight changes, etc.

### Composing Render Pipelines

A typical scene builds its graph by piping through render functions:

```elixir
defp render_graph(state) do
  Graph.build()
  |> rect({state.width, state.height}, fill: @background)
  |> render_header(state)
  |> render_sidebar(state)
  |> render_content(state)
end
```

Each `render_*` function takes and returns the graph. This is the standard Scenic composition pattern.

## Click Handling — Prefer Primitive-Level Input

**Almost always** capture clicks by declaring `input:` on the primitive itself, not by manually hit-testing coordinates in the scene.

### The Right Way

```elixir
graph
|> rect({100, 40}, id: :save_btn, input: :cursor_button,
    fill: {60, 140, 80}, translate: {10, 200})
|> text("Save", translate: {30, 225}, fill: :white, font_size: 13)
```

Then handle it in the scene:

```elixir
@impl Scenic.Component
def handle_input({:cursor_button, {:btn_left, 1, _, _}}, :save_btn, scene) do
  # :save_btn is the id of the primitive that captured the click
  do_save(scene)
end
```

The second argument to `handle_input` is the **id of the primitive** that received the input. Scenic routes the event to the correct primitive automatically based on spatial hit-testing — no manual coordinate math needed.

### When to Use Process Dict Click Targets Instead

The process-dictionary approach (see below) is a fallback for cases where:
- You're rendering a **dynamic list** of items and assigning individual `:id` + `:input` to each would be unwieldy
- You need hit-testing that accounts for **scroll offsets** in a custom scroll implementation
- You're working with a legacy component that already uses this pattern

For new components with a known set of buttons, prefer `id: + input:` on the primitive.

## Scissor Clipping

For overflow containment without using `Widgex.Scrollable`:

```elixir
graph
|> group(fn g ->
  g
  |> rrect({panel_width, panel_height, 3}, fill: {30, 30, 40})
  |> text("Long text...", translate: {10, 14}, fill: :white, font_size: 11)
end,
  translate: {panel_x, panel_y},
  scissor: {panel_width, panel_height}
)
```

**Key points:**
- `scissor: {w, h}` clips all content in the group to those dimensions
- Content coordinates inside the group are relative to the group origin (0, 0)
- The `translate:` on the group positions it in parent space
- Scissor dimensions are in the group's local coordinate space

## Process Dictionary Click Targets (Fallback)

For custom hit-testing in dynamic lists or scroll-offset-aware contexts where primitive-level `id: + input:` is impractical:

```elixir
# Store targets during render:
defp put_click_target(id, {x, y, w, h}) do
  targets = Process.get(:pipeline_click_targets, %{})
  Process.put(:pipeline_click_targets, Map.put(targets, id, {x, y, w, h}))
end

# Check on click:
defp check_click(x, y) do
  targets = Process.get(:pipeline_click_targets, %{})
  Enum.find_value(targets, fn {id, {tx, ty, tw, th}} ->
    if x >= tx and x <= tx + tw and y >= ty and y <= ty + th, do: id
  end)
end
```

**Clear targets before each render** to avoid stale entries.

## Key Gotchas

1. **Negate scroll delta.** `handle_scroll/2` internally applies the scroll speed, but Scenic's raw delta needs negation for natural scroll direction. Pass `-delta_y`.

2. **Module attribute order.** `use Widgex.Scrollable` must come before any code that references `@scroll_direction` or `@scroll_speed`.

3. **Hit testing with scroll offset.** Convert mouse coords to content space: `content_y = mouse_y + scroll.offset_y`.

4. **Content height updates.** Call `update_content_size/3` whenever items change, otherwise scroll bounds are wrong.

5. **Scrollbar fade.** Components using scrollbars must handle `:scrollbar_fade` messages (sent via `Process.send_after`).

6. **Graph.modify safety.** If you use `Graph.modify(graph, :id, ...)`, the ID must exist or it raises. Wrap in try/rescue if uncertain.

## Minimal Scrollable Component

```elixir
defmodule MyScrollList do
  use Scenic.Component, has_children: false
  use Widgex.Scrollable, direction: :vertical

  import Scenic.Primitives
  alias Widgex.Frame

  @item_height 30

  @impl Scenic.Scene
  def init(scene, %{frame: frame, items: items}, _opts) do
    content_height = length(items) * @item_height
    scroll = init_scroll(frame, content_height: content_height)

    state = %{frame: frame, items: items, scroll: scroll}
    graph = render_graph(state)

    scene = scene |> assign(state: state, graph: graph) |> push_graph(graph)
    request_input(scene, [:cursor_scroll])
    {:ok, scene}
  end

  @impl Scenic.Component
  def handle_input({:cursor_scroll, {{_x, y}, _}}, _ctx, scene) do
    state = scene.assigns.state
    new_scroll = handle_scroll(state.scroll, -y)

    if scroll_changed?(state.scroll, new_scroll) do
      new_state = %{state | scroll: new_scroll}
      graph = render_graph(new_state)
      {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
    else
      {:noreply, scene}
    end
  end

  def handle_input(_, _, scene), do: {:noreply, scene}

  defp render_graph(state) do
    %{width: w, height: h} = state.frame.size

    Scenic.Graph.build()
    |> rect({w, h}, fill: {30, 32, 40})
    |> scrollable_group(state.scroll, state.frame, fn g ->
      state.items
      |> Enum.with_index()
      |> Enum.reduce(g, fn {item, i}, acc ->
        y = i * @item_height + 16
        acc |> text(item, translate: {10, y}, fill: :white, font_size: 13)
      end)
    end, id: :list_content)
    |> render_scrollbars(state.scroll, state.frame)
  end
end
```

## Frame Grid (CSS Grid-like)

For complex layouts:

```elixir
alias Widgex.Frame.Grid

grid = Grid.new(parent_frame)
  |> Grid.rows([60, 0.7, :auto])        # px, fraction, auto
  |> Grid.columns([200, 0.5, 200])
  |> Grid.row_gap(8)
  |> Grid.column_gap(8)
  |> Grid.define_areas(%{
    header:  {0, 0, 1, 3},   # {row_start, col_start, row_end, col_end}
    sidebar: {1, 0, 2, 1},
    content: {1, 1, 2, 2}
  })

cells = Grid.calculate(grid)
header_frame = Grid.area_frame(grid, cells, :header)
```
