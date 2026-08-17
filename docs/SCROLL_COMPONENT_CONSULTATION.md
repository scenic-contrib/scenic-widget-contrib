# Expert Consultation Request: Reusable Vertical Scroll Component for Scenic GUI

## Context
Working on **WidgetWorkbench** - a Scenic GUI application for developing/testing UI components. We have a modal popup (lines 458-508 in `widget_wkb_scene.ex`) that displays a list of selectable components as buttons. Currently it renders without scroll - when the list exceeds the modal height, items overflow and become inaccessible.

## Current Architecture
- **Scenic Framework**: Immediate-mode GUI using graph-based rendering
- **Component Pattern**: Components use `Scenic.Component` behaviour with `init/3`, `handle_input/3`, `handle_event/3`
- **Existing Scroll Code**: Commented-out horizontal scrollbar exists at `lib/components/scroll_bars/scroll_bar.ex` (currently disabled)
- **Modal Location**: `lib/widget_workbench/components/modal.ex` & rendering in `widget_wkb_scene.ex:458-508`
- **Frame System**: Uses `Widgex.Frame` for layout with `%{pin: {x,y}, size: {w,h}}`

## Requirements

**Primary Goal**: Design a reusable vertical scroll component for Scenic that can:
1. **Clip content** to visible area (modal height constraint)
2. **Scroll via mouse wheel** and/or draggable scrollbar thumb
3. **Work with dynamic content** (button lists, text, arbitrary components)
4. **Be truly reusable** across different parent components

**Constraints**:
- Scenic has no built-in scrolling primitives
- Must handle Scenic's immediate-mode rendering (re-render on state change)
- Need to manage viewport transformation (translate) for scrolled content
- Should integrate with existing component pattern

## Specific Questions

1. **Architecture Pattern**: What's the best pattern for a scroll container in Scenic?
   - Wrapper component that takes children?
   - Higher-order function that modifies graph rendering?
   - Separate scroll state manager with renderizer?

2. **Clipping Strategy**: How to clip overflowing content?
   - Scenic has `Primitives.ScissorBox` - is this the way?
   - Alternative approaches for content masking?

3. **Scroll State Management**:
   - Where should scroll position live? (parent scene vs scroll component)
   - How to calculate scroll bounds from content height?
   - How to handle dynamic content size changes?

4. **Input Handling**:
   - Best way to capture mouse wheel events in bounded area?
   - Should scrollbar be separate component or part of scroll container?
   - Touch/drag scrolling considerations?

5. **Reusability Design**:
   - What data contract should the scroll component accept?
   - How to make it work with both primitive lists (buttons) and arbitrary components?
   - Performance considerations for large lists?

## Current Implementation Context

**Modal rendering (needs scroll)**:
```elixir
# In widget_wkb_scene.ex:458-508
defp render_component_selection_modal(graph, %Frame{} = frame) do
  modal_width = 400
  modal_height = 500  # Fixed height - content overflows!

  # Currently renders ALL components without scroll
  graph
  |> render_component_list(components, modal_x, modal_y + 60, modal_width)
end

defp render_component_list(graph, components, x, start_y, width) do
  button_height = 40
  components
  |> Enum.with_index()
  |> Enum.reduce(graph, fn {{name, id}, index}, acc_graph ->
    y = start_y + (button_height + button_margin) * index  # Keeps going down!
    acc_graph |> Components.button(name, ...)
  end)
end
```

## Desired API (Conceptual)

Ideally something like:
```elixir
graph
|> ScrollContainer.add_to_graph(%{
  frame: %{pin: {modal_x, modal_y + 60}, size: {380, 350}},  # Visible area
  content_height: calculated_content_height,
  render_content: fn(graph, viewport_offset) ->
    # Render only visible portion, translated by offset
  end
}, id: :component_scroll)
```

## What We Need Back

Please provide:
1. **Recommended architecture** with rationale
2. **Key implementation considerations** for Scenic's rendering model
3. **Example pseudocode** showing scroll component structure
4. **Gotchas/pitfalls** specific to Scenic's immediate-mode rendering
5. **Alternative approaches** if scroll container isn't optimal

## Codebase Reference
- Working directory: `/Users/luke/workbench/flx/scenic-widget-contrib`
- Modal implementation: `lib/widget_workbench/components/modal.ex`
- Scene rendering: `lib/widget_workbench/widget_wkb_scene.ex`
- Existing (disabled) scroll: `lib/components/scroll_bars/scroll_bar.ex`

---

**Status**: Awaiting expert architectural guidance before implementation.
