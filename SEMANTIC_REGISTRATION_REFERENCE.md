# Semantic Registration System - Quick Reference

**Status**: ✅ Phase 1 Complete (2025-11-23)

This document provides a quick reference for using the semantic element registration system in Scenic. For complete documentation, see `scenic_local/guides/testing_and_automation.md`.

## What Is It?

The semantic registration system enables Playwright/Puppeteer-like automated testing and AI control of Scenic applications. Elements can be found and clicked by ID rather than hardcoded screen coordinates.

## Quick Start

### 1. Add IDs to Elements

```elixir
graph =
  Graph.build()
  |> rectangle({100, 50}, id: :save_button, translate: {200, 100})
  |> circle(25, id: :status_indicator, translate: {50, 50})
  |> text("Click Me", id: :button_label, translate: {210, 115})
```

That's it! Any primitive with an `:id` is automatically registered.

### 2. Query Elements

```elixir
# Get viewport
{:ok, viewport} = Scenic.ViewPort.info(:main_viewport)

# Find element by ID
{:ok, button} = Scenic.ViewPort.Semantic.find_element(viewport, :save_button)

# Inspect what you got
button.id              #=> :save_button
button.type            #=> :rect
button.local_bounds    #=> %{left: 0, top: 0, width: 100, height: 50}
button.screen_bounds   #=> %{left: 0, top: 0, width: 100, height: 50}  # Phase 1: no transforms
button.clickable       #=> false (rectangles aren't clickable by default)
```

### 3. Click Elements

```elixir
# Click by ID (automatically calculates center point!)
{:ok, {x, y}} = Scenic.ViewPort.Semantic.click_element(viewport, :save_button)
#=> {:ok, {50.0, 25.0}}  # Center of the button

# Sends real mouse events through driver - just like a user clicking!
```

## Common Queries

```elixir
# Find all clickable elements
{:ok, elements} = Scenic.ViewPort.Semantic.find_clickable_elements(viewport)

# Find elements by filter
{:ok, buttons} = Scenic.ViewPort.Semantic.find_clickable_elements(
  viewport,
  %{type: :component}
)

# Find element at coordinates
{:ok, element} = Scenic.ViewPort.Semantic.element_at_point(viewport, 150, 60)

# Get hierarchical tree
{:ok, tree} = Scenic.ViewPort.Semantic.get_semantic_tree(viewport)
```

## Explicit Semantic Metadata (Optional)

For more control, add explicit semantic metadata:

```elixir
graph
|> rectangle(
  {100, 50},
  semantic: %{
    id: :custom_button,
    type: :button,
    clickable: true,
    focusable: true,
    label: "Save File",
    role: :primary_action
  },
  translate: {100, 100}
)
```

## Widget Development Pattern

When building widgets, add semantic IDs to interactive elements:

```elixir
defmodule MyApp.Components.MenuBar do
  def render(graph, state) do
    graph
    |> group(
      fn g ->
        g
        |> rectangle({200, 40}, id: :menu_bar_background)
        |> text("File", id: :file_menu_label, translate: {10, 20})
        |> text("Edit", id: :edit_menu_label, translate: {60, 20})
        |> text("View", id: :view_menu_label, translate: {110, 20})
      end,
      id: :menu_bar,
      translate: {state.frame.pin.x, state.frame.pin.y}
    )
  end
end
```

Now in tests/automation:

```elixir
# Click by semantic ID
{:ok, _} = Scenic.ViewPort.Semantic.click_element(viewport, :file_menu_label)

# Find the menu bar
{:ok, menu} = Scenic.ViewPort.Semantic.find_element(viewport, :menu_bar)
```

## Integration with scenic_mcp

The semantic system is used by scenic_mcp tools:

```
# From MCP client (Claude Desktop, etc.)
connect_scenic(port: 9999)
click_element(element_id: "save_button")  # Calls Scenic.ViewPort.Semantic under the hood
find_clickable_elements()
```

## Configuration

Semantic registration is **enabled by default**. To disable:

```elixir
ViewPort.start_link(
  name: :main_viewport,
  size: {800, 600},
  semantic_registration: false,  # Disable if you don't need it
  # ... other opts
)
```

## Phase 1 Limitations

Current implementation (Phase 1) has these limitations:

- ⚠️  **No transform calculations** - `screen_bounds` equals `local_bounds`
  - `translate`, `rotate`, `scale` not applied to bounds yet
  - Click coordinates don't account for transforms
  - Coming in Phase 2

- ⚠️  **No component sub-scenes** - Components register, but not their internal graphs
  - Coming in Phase 3

- ⚠️  **Text bounds are estimates** - Fixed 100x20 size, no font metrics
  - Coming in Phase 2

Despite limitations, Phase 1 is extremely useful for:
- Clicking elements at their local coordinates
- Testing components in isolation
- Finding elements by ID
- Building test infrastructure

## Implementation Files

**Created**:
- `scenic_local/lib/scenic/semantic/compiler.ex` - Compiles graphs to semantic entries
- `scenic_local/lib/scenic/view_port/semantic.ex` - Query API
- `scenic_local/test/scenic/semantic/compiler_test.exs` - Test suite
- `scenic_local/guides/testing_and_automation.md` - Complete documentation

**Modified**:
- `scenic_local/lib/scenic/view_port.ex` - Added semantic table infrastructure
  - Lines 122-129: New struct fields (semantic_table, semantic_index, semantic_enabled)
  - Lines 512-532: ETS table initialization
  - Lines 379-384: Parallel semantic compilation via Task.start
  - Lines 1213-1238: compile_and_store_semantics helper

**Updated Documentation**:
- `scenic_local/guides/overview_viewport.md` - ViewPort guide
- `scenic_local/guides/overview_graph.md` - Graph guide (added section on IDs)
- `scenic_local/guides/welcome.md` - Added testing guide to index
- `scenic-widget-contrib/WIDGET_WKB_BASE_PROMPT.md` - Updated semantic section
- `CLAUDE.md` - Added semantic system to project structure

## Architecture Summary

```
┌─────────────────────────────────────────┐
│  Scene: graph |> rect({100, 50}, id: :btn)
└─────────────────┬───────────────────────┘
                  │ push_graph
        ┌─────────▼─────────┐
        │     ViewPort      │
        │                   │
        │ ┌───────────────┐ │
        │ │ Script Compile│ │ ← Scenic.GraphCompiler (existing)
        │ └───────────────┘ │
        │                   │
        │ ┌───────────────┐ │
        │ │Semantic Compile│ │ ← NEW: Scenic.Semantic.Compiler (parallel)
        │ └───────────────┘ │
        │                   │
        │ ┌───────────────┐ │
        │ │ ETS Tables:   │ │
        │ │ - semantic_table │
        │ │ - semantic_index │
        │ └───────────────┘ │
        └───────────────────┘
                  │
        ┌─────────▼─────────┐
        │ Query API         │
        │ ViewPort.Semantic │
        └───────────────────┘
```

## Performance Notes

- **Zero overhead when disabled** - No ETS tables created
- **Parallel compilation** - Uses `Task.start` (fire-and-forget)
- **Fast lookups** - ETS with read concurrency
- **No blocking** - Never delays rendering pipeline

## Common Patterns

### Testing Pattern

```elixir
test "user can save document" do
  # Start app
  {:ok, viewport} = Scenic.ViewPort.info(:main_viewport)

  # Click new document button
  {:ok, _} = Scenic.ViewPort.Semantic.click_element(viewport, :new_doc_btn)
  Process.sleep(100)

  # Type content would go here (via send_keys through driver)

  # Save
  {:ok, _} = Scenic.ViewPort.Semantic.click_element(viewport, :save_btn)

  # Verify
  assert File.exists?("test_doc.txt")
end
```

### Spex Pattern

```elixir
scenario "Load component from modal", context do
  given_ "Widget Workbench is running", context do
    {:ok, Map.put(context, :viewport, get_viewport())}
  end

  when_ "we click load component button", context do
    Scenic.ViewPort.Semantic.click_element(context.viewport, :load_component_btn)
    {:ok, context}
  end

  then_ "modal should be visible", context do
    {:ok, modal} = Scenic.ViewPort.Semantic.find_element(context.viewport, :component_modal)
    assert modal.hidden == false
    :ok
  end
end
```

## Troubleshooting

**Element not found**:
- Ensure element has `:id` option
- Check spelling of ID (atoms are case-sensitive)
- Verify element is in current graph (use `inspect_viewport`)

**Click not working**:
- Phase 1: Clicks work at local coordinates only
- Check element actually exists at expected location
- Use `take_screenshot` to verify visual state

**Semantic disabled error**:
- Check viewport config: `semantic_registration: true` (default)
- Verify ETS tables exist: `viewport.semantic_table`

## Future Phases

**Phase 2: Transform-Aware Coordinates** (Planned)
- Calculate screen_bounds with transforms applied
- Click elements accounting for translate/rotate/scale
- Support for nested groups with multiple transforms

**Phase 3: Component Sub-Scenes** (Planned)
- Register elements inside component sub-graphs
- Full hierarchical tree including components

**Phase 4: Advanced Features** (Planned)
- Font metrics for accurate text bounds
- Visibility calculations (hidden elements, scissor boxes)
- Performance optimizations for large graphs

## Resources

- **Complete Guide**: `scenic_local/guides/testing_and_automation.md`
- **ViewPort Guide**: `scenic_local/guides/overview_viewport.md`
- **Graph Guide**: `scenic_local/guides/overview_graph.md`
- **Implementation Doc**: `PHASE_1_SEMANTIC_IMPLEMENTATION_COMPLETE.md`
- **Architecture Doc**: `semantic_scenic.md` (oracle AI's design)
- **Test Suite**: `scenic_local/test/scenic/semantic/compiler_test.exs`

---

**Last Updated**: 2025-11-23
**Status**: Phase 1 Complete ✅
**Tests**: 10/10 Passing ✅
**Integration**: Widget Workbench ✅
