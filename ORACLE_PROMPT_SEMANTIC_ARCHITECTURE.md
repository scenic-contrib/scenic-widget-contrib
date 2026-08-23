# Oracle Prompt: Semantic Element Registration Architecture for Scenic

## Context: You Are The Oracle

You are a senior software architect with deep expertise in:
- GUI framework internals (X11, Wayland, HTML/DOM, native UI toolkits)
- Browser automation tools (Puppeteer, Playwright, Selenium)
- Accessibility trees (ARIA, Windows UIA, macOS Accessibility API)
- Immediate-mode vs retained-mode graphics
- Elixir/Erlang/OTP design patterns
- ETS tables and concurrent data structures

You have been asked to design a **semantic element registration system** for Scenic, a declarative GUI framework written in Elixir. This system will enable automated testing and AI control similar to how Playwright/Puppeteer work with web browsers.

## The Challenge

We need to architect a system where **every visual element in a Scenic application can be automatically discoverable, addressable, and interactable** without hardcoded coordinates. Think of it as creating an "accessibility tree" or "DOM-like semantic layer" for Scenic.

### Key Requirements

1. **Automatic Registration**: Components should register themselves with minimal/zero boilerplate
2. **Hierarchical Structure**: Preserve parent-child relationships (like DOM tree)
3. **Coordinate Calculation**: Automatically compute screen coordinates from transforms
4. **Minimal Overhead**: Zero performance cost when not used
5. **Optional Integration**: Work alongside existing script compilation pipeline
6. **Playwright-like API**: Enable `click_element(id: :save_button)` instead of `click(x: 450, y: 200)`

## Current Scenic Architecture

### Graph Compilation Pipeline

```
Scene                                ViewPort                       Driver
  ↓                                     ↓                            ↓
Graph (primitives/components)  →  Script Table (ETS)  →  OpenGL/Graphics Rendering
  |                                     |
  |                                     |
  |                              [Compiled binary
  |                               rendering commands]
  |
  └─ Primitives: rect, circle, text, etc.
  └─ Components: button, text_field, etc. (create sub-scenes)
```

### Key Files & Concepts

#### 1. Graph Compiler (`scenic_local/lib/scenic/graph/compiler.ex`)

**Purpose**: Compiles a scene graph into binary scripts for rendering

**Process**:
```elixir
def compile(%Graph{primitives: primitives}) do
  {ops, _} = compile_primitive(
    Script.start(),
    primitives[0],  # Root primitive
    primitives,
    %Compiler{reqs: Scenic.Primitive.Style.default()}
  )
  {:ok, Script.finish(ops)}
end
```

**Key Points**:
- Walks primitive tree recursively
- Applies transforms (translate, rotate, scale)
- Compiles styles (fill, stroke, fonts)
- Handles special cases: Component, Script, Group, Text
- Components (`Primitive.Component`) compile to script names, creating sub-scenes
- Transform stacking via push/pop state

**Relevant Code** (lines 109-153):
```elixir
defp do_compile_primitive(ops, primitive, primitives, state) do
  # Get transforms
  tx = Map.get(primitive, :transforms)
  tx_ops = compile_transforms([], tx, primitive)

  # Handle push/pop if transforms exist
  cond do
    tx_ops == [] && style_ops == [] ->
      {[prim_ops | ops], state}
    tx_ops == [] ->
      {[prim_ops, style_ops | ops], state}
    true ->
      # transforms changed. do a push/pop
      ops =
        ops
        |> Script.push_state()
        |> List.insert_at(0, tx_ops)
        |> List.insert_at(0, style_ops)
        |> List.insert_at(0, prim_ops)
        |> Script.pop_state()
      {ops, state}
  end
end
```

#### 2. ViewPort (`scenic_local/lib/scenic/view_port.ex`)

**Purpose**: Central coordinator between scenes and drivers

**Current State**:
- Creates ETS table for scripts: `:script_table`
- NO semantic_table yet (this is what we need to add)
- Handles input routing (mouse, keyboard)
- Manages scene lifecycle
- Compiles graphs to scripts via `GraphCompiler.compile/1`

**Key Data Structure** (lines 112-123):
```elixir
@type t :: %ViewPort{
  name: atom,
  pid: pid,
  script_table: reference,  # ETS table
  size: {number, number}
}
```

**Initialization** (line 504):
```elixir
script_table = :ets.new(:_vp_script_table_, [:public, {:read_concurrency, true}])
```

#### 3. Components (`scenic_local/lib/scenic/primitive/component.ex`)

**Purpose**: Create sub-scenes with encapsulated state

**How They Work**:
- Component primitive in parent graph → ViewPort creates new scene process
- Each component has unique name (16-byte random ID or explicit name)
- Components compile to script references: `Script.render_script(ops, name)`
- Sub-scene graphs are independent from parent graph

**Compilation** (from Compiler, lines 219-226):
```elixir
defp do_primitive(%Primitive{module: Primitive.Component, data: {_, _, name}}, _, state) do
  {st_ops, state} = compile_styles(Primitive.Component.valid_styles(), state)
  {do_compile_script_name([], name), st_ops, state}
end

defp do_compile_script_name(ops, name) do
  Script.render_script(ops, name)
end
```

#### 4. ScriptInspector (`scenic-widget-contrib/test/helpers/script_inspector.ex`)

**Purpose**: Test helper that reads rendered content from script_table

**How It Works** (lines 102-117):
```elixir
def get_script_table_directly() do
  viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :main_viewport)

  case Scenic.ViewPort.info(viewport_name) do
    {:ok, vp_info} ->
      script_table = vp_info.script_table
      :ets.tab2list(script_table)
    _error -> []
  end
end
```

**Key Insight**:
- Script table contains: `{script_name, compiled_binary, owner_pid}`
- Can extract text primitives, rect primitives, etc.
- Used for black-box testing of rendered output

#### 5. Existing Semantic Infrastructure (scenic_mcp)

**Files**:
- `scenic_mcp/lib/scenic_mcp/tools.ex` - has `find_clickable_elements/1` stub
- `scenic_mcp/SEMANTIC_INTERACTION_GUIDE.md` - documents desired API
- `scenic-widget-contrib/test/helpers/semantic_ui.ex` - high-level test helpers

**Partially Implemented** (from tools.ex, lines 227-262):
```elixir
def find_clickable_elements(params) do
  filter = Map.get(params, "filter")

  with {:ok, vp_state} <- viewport_state(),
       semantic_table <- Map.get(vp_state, :semantic_table),
       elements <- :ets.tab2list(semantic_table) do

    clickable = elements
    |> Enum.filter(fn {_key, data} ->
      Map.get(data, :clickable, false)
    end)
    |> Enum.map(fn {id, data} ->
      %{
        id: id,
        type: Map.get(data, :type),
        bounds: Map.get(data, :bounds),
        center: calculate_center(Map.get(data, :bounds))
      }
    end)

    {:ok, %{status: "ok", count: length(clickable), elements: clickable}}
  end
end

defp calculate_center(%{left: l, top: t, width: w, height: h}) do
  %{x: l + w / 2, y: t + h / 2}
end
```

**Problem**: ViewPort doesn't have `:semantic_table` yet!

## Current Problem

### What Exists (But Doesn't Work)
1. ✅ `scenic_mcp` has `find_clickable_elements/1` function
2. ✅ Documentation describes the API we want
3. ✅ Test helpers expect semantic registration
4. ❌ **ViewPort has no semantic_table**
5. ❌ **Components don't auto-register**
6. ❌ **No coordinate calculation from transforms**

### Why Manual Registration Is Painful

Currently, to make a button clickable via MCP:

```elixir
# In component init/3:
viewport = Scene.viewport(scene)
Scenic.ViewPort.register_semantic(viewport, :my_button, %{
  type: :button,
  clickable: true,
  bounds: %{left: x, top: y, width: w, height: h}  # Manual calculation!
})
```

**Problems**:
- Requires explicit registration in every component
- Bounds must be manually calculated
- Transforms (translate, rotate, scale) not accounted for
- Parent graph transforms not included
- Breaks when layout changes

## Your Mission: Design The Architecture

We need you to design a system that achieves these goals:

### Goal 1: Automatic Registration
**Playwright Reference**: Every DOM element is automatically in the accessibility tree

Components should register automatically based on:
- Having an `:id` in their opts
- Being a "semantic primitive" (button, text_field, checkbox, etc.)
- Explicit opt-in via `semantic: %{type: :custom, ...}`

**Question**: Where in the compilation pipeline should registration happen?
- During `GraphCompiler.compile/1`?
- During `ViewPort.put_graph/4`?
- During primitive/component init?
- Some combination?

### Goal 2: Transform-Aware Coordinates
**Playwright Reference**: `element.getBoundingClientRect()` returns screen coordinates

When a button is translated, rotated, scaled, or inside a scrolling container:
```elixir
graph
|> group(fn g ->
  g
  |> rect(..., translate: {100, 200})
  |> group(fn g2 ->
    g2
    |> button("Click", id: :my_button, translate: {50, 50})
  end, translate: {25, 25})
end, scale: {2.0, 2.0})
```

The button's **actual screen position** should be automatically calculated:
- Base: (0, 0)
- Button translate: (50, 50)
- Inner group translate: (25, 25)
- Rect translate: (100, 200)
- Scale: 2.0x
- **Final**: ((50+25+100)*2, (50+25+200)*2) = (350, 550)

**Question**: How do we capture and apply the transform stack?
- Store transforms during compilation?
- Walk the primitive tree to build matrix?
- Hook into `compile_transforms/3`?
- Use existing matrix calculations?

### Goal 3: Component Sub-Scene Handling
**Playwright Reference**: iframes are separate documents but accessible

Components create sub-scenes with their own graphs:
```elixir
# Parent scene
graph |> button("Save", id: :save_button, translate: {100, 200})

# Button component creates sub-scene with text + rect primitives
# How do we link :save_button ID to its actual rendered bounds?
```

**Question**: Should semantic registration happen at:
- Component level (registers the component bounds)?
- Primitive level (registers each rect/text inside component)?
- Both (hierarchical registration)?

### Goal 4: Minimal Performance Overhead
**Playwright Reference**: Accessibility tree built on-demand

Registration should have:
- Zero cost when semantic_table not queried
- Fast lookups when needed
- Minimal memory overhead
- No impact on rendering performance

**Question**: What data structure?
- Simple ETS table like script_table?
- Hierarchical tree structure?
- Flat map with parent references?
- Spatial index for coordinate-based queries?

### Goal 5: Optional Two-Path Integration
**Desired**: Semantic system should be:
- Optional (apps work without it)
- Parallel to script compilation (can coexist or replace)
- Configurable (enable/disable at compile time or runtime)

**Question**: How do we integrate?
```
Option A: Parallel pipeline
  Graph → GraphCompiler → Scripts (existing)
       ↘ SemanticBuilder → SemanticTable (new)

Option B: Extended compiler
  Graph → GraphCompiler → Scripts + SemanticTable (integrated)

Option C: Post-compilation
  Graph → GraphCompiler → Scripts
              ↓
         SemanticExtractor → SemanticTable (from scripts)
```

## Detailed Technical Questions

### Architecture Questions

1. **Where should semantic_table live?**
   - In ViewPort state (alongside script_table)?
   - Separate GenServer/Agent?
   - Registry pattern?

2. **When should registration happen?**
   - During graph compilation?
   - After script generation?
   - During scene init?
   - Lazy on first query?

3. **How do we handle updates?**
   - Re-register on every graph push?
   - Diff old/new and update?
   - Incremental updates only?
   - Garbage collection of old entries?

4. **How do we handle component hierarchies?**
   ```
   Scene :_root_
     └─ Component :menu_bar
          ├─ Button :file_menu
          ├─ Button :edit_menu
          └─ Button :view_menu
   ```
   - Flat structure: Store all buttons with full paths?
   - Hierarchical: Store tree structure?
   - Both: Flat + parent references?

5. **How do we compute transforms?**
   - Store accumulated matrix per element?
   - Recompute on query from primitive tree?
   - Cache during compilation?
   - Use existing `Scenic.Math` utilities?

6. **How do we handle these cases?**
   - Hidden elements (`:hidden` style)?
   - Clipped elements (`:scissor` style)?
   - Overlapping elements (z-order)?
   - Dynamic elements (appear/disappear)?

### Implementation Questions

1. **What should the semantic data structure look like?**
   ```elixir
   # Option A: Flat with references
   %{
     :save_button => %{
       type: :button,
       parent: :toolbar,
       bounds: %{left: 100, top: 200, width: 150, height: 40},
       screen_bounds: %{...},  # After transforms
       clickable: true,
       label: "Save",
       metadata: %{...}
     }
   }

   # Option B: Hierarchical
   %{
     :_root_ => %{
       children: [:toolbar, :main_panel],
       elements: %{}
     },
     :toolbar => %{
       parent: :_root_,
       transform: {...},
       children: [:save_button, :open_button],
       elements: %{...}
     },
     :save_button => %{
       parent: :toolbar,
       type: :button,
       local_bounds: %{...},
       screen_bounds: %{...},
       ...
     }
   }
   ```

2. **Should registration be explicit or implicit?**
   ```elixir
   # Explicit (current proposal):
   Scenic.ViewPort.register_semantic(vp, :my_button, %{...})

   # Implicit (automatic from graph):
   graph |> button("Save", id: :save_button)  # Auto-registers!

   # Opt-in via metadata:
   graph |> button("Save", semantic: %{type: :button, ...})
   ```

3. **How do we make it zero-cost when disabled?**
   ```elixir
   # Compile-time feature flag?
   @compile {:no_semantic_table, true}

   # Runtime config?
   config :scenic, semantic_registration: :enabled

   # Per-viewport?
   ViewPort.start(semantic_dom: true)
   ```

4. **API Design - What should the public API be?**
   ```elixir
   # Registration (called by components/scenes):
   Scenic.ViewPort.register_semantic(viewport, id, semantic_data)
   Scenic.ViewPort.update_semantic(viewport, id, changes)
   Scenic.ViewPort.unregister_semantic(viewport, id)

   # Query (called by scenic_mcp/tests):
   Scenic.ViewPort.find_semantic(viewport, id)
   Scenic.ViewPort.query_semantic(viewport, filter)
   Scenic.ViewPort.get_semantic_tree(viewport)

   # Transform helpers:
   Scenic.ViewPort.screen_bounds(viewport, id)
   Scenic.ViewPort.local_to_screen(viewport, id, point)
   ```

5. **How do we handle the transform stack?**

   The compiler already builds transform ops. Can we hook in?

   ```elixir
   # From compiler.ex lines 380-411:
   defp compile_transforms(ops, %{rotate: _} = txs, p), do: complex_tx(ops, txs, p)
   defp compile_transforms(ops, %{scale: _} = txs, p), do: complex_tx(ops, txs, p)
   defp compile_transforms(ops, %{matrix: _} = txs, p), do: complex_tx(ops, txs, p)

   defp compile_transforms(ops, %{translate: {x, y}}, _) do
     Script.translate(ops, x, y)
   end

   # Can we capture these transforms during compilation?
   # Store them in a transform_stack alongside semantic_table?
   ```

## Reference: How Playwright/Puppeteer Work

### Playwright Architecture

```
Page/Frame
   ↓
 DOM Tree (HTML)
   ↓
Accessibility Tree (Browser's internal)
   ↓
Playwright Selectors (CSS, text, role, etc.)
   ↓
Element Handle → Bounding Box → Click Center
```

**Key Features**:
1. **Automatic**: Every element in the accessibility tree
2. **Hierarchical**: Respects DOM structure and iframes
3. **Coordinate-aware**: `element.boundingBox()` returns screen coords
4. **Transform-aware**: Respects CSS transforms
5. **Actionability checks**: Visible, enabled, stable, not obscured

**Selector Examples**:
```javascript
// By role + text
await page.click('button:has-text("Save")');

// By test ID
await page.click('[data-testid="save-button"]');

// By CSS selector
await page.click('#save-button');

// Hierarchical
await page.click('nav >> button:has-text("File")');
```

### How Puppeteer Calculates Click Coordinates

```javascript
// 1. Find element by selector
const element = await page.$('button#save');

// 2. Get bounding box (accounts for transforms, scrolling)
const box = await element.boundingBox();
// Returns: { x: 100, y: 200, width: 150, height: 40 }

// 3. Calculate center
const clickX = box.x + box.width / 2;
const clickY = box.y + box.height / 2;

// 4. Click
await element.click(); // or page.mouse.click(clickX, clickY)
```

### Applying to Scenic

**Scenic Equivalent**:
```elixir
# 1. Find element by ID
{:ok, element} = Scenic.ViewPort.find_semantic(viewport, :save_button)

# 2. Get screen bounds (accounts for transforms)
%{left: x, top: y, width: w, height: h} = element.screen_bounds

# 3. Calculate center
click_x = x + w / 2
click_y = y + h / 2

# 4. Click
Scenic.ViewPort.input(viewport, {:cursor_button, {:btn_left, 1, [], {click_x, click_y}}})
Scenic.ViewPort.input(viewport, {:cursor_button, {:btn_left, 0, [], {click_x, click_y}}})
```

**Or simplified**:
```elixir
# High-level API
Scenic.ViewPort.click_semantic(viewport, :save_button)
```

## Design Constraints

### Must Have
1. Work with existing Scenic apps (no breaking changes)
2. Handle component sub-scenes correctly
3. Account for transforms (translate, rotate, scale)
4. Support hierarchical queries (find button in toolbar)
5. Minimal performance impact
6. Work with scenic_mcp for automated testing

### Nice to Have
1. Query by type (all buttons, all text_fields)
2. Query by text content ("button containing 'Save'")
3. Query by position (element at x, y)
4. Visibility filtering (hidden elements)
5. Z-order handling (top-most element at point)
6. Bounding box queries (elements in rect)

### Should Not
1. Require changes to every existing component
2. Slow down rendering/compilation
3. Use significant memory
4. Complicate the core Scenic API

## Deliverables Requested

Please provide a comprehensive architectural design covering:

### 1. High-Level Architecture
- System overview diagram
- Data flow (from graph to semantic_table)
- Integration points with existing Scenic code
- Trade-offs analysis

### 2. Detailed Technical Design

#### ViewPort Changes
- New fields in ViewPort struct?
- New ETS table(s)?
- New GenServer handlers?
- Initialization and cleanup

#### Compiler Integration
- Hooks during compilation?
- Transform capture strategy
- Component handling
- Performance considerations

#### Registration API
- Public functions
- Internal implementation
- Error handling
- Update/invalidation strategy

#### Query API
- Finding elements
- Computing screen bounds
- Filtering and searching
- Performance optimizations

### 3. Implementation Plan

#### Phase 1: Foundation
- Minimal viable semantic_table
- Basic registration API
- Simple coordinate calculation

#### Phase 2: Transform Support
- Capture transform stack
- Apply to bounds
- Handle component hierarchies

#### Phase 3: Advanced Features
- Hierarchical queries
- Visibility filtering
- Performance optimization

#### Phase 4: Integration
- scenic_mcp tooling
- Test helpers
- Documentation

### 4. Code Examples

Provide pseudo-code or actual Elixir code for:
- ViewPort.register_semantic/3 implementation
- Transform accumulation during compilation
- Screen bounds calculation
- Query functions

### 5. Migration Strategy

How do existing apps adopt this?
- Opt-in vs automatic
- Compatibility plan
- Breaking changes (if any)
- Documentation needs

## Success Criteria

A successful design will enable:

```elixir
# Test code (scenic_mcp)
{:ok, _} = ScenicMcp.Tools.connect_scenic(port: 9999)

# Find all clickable elements
{:ok, %{elements: elements}} = ScenicMcp.Tools.find_clickable_elements(%{})
IO.inspect(elements)
# => [
#   %{id: :save_button, type: :button, center: %{x: 175, y: 220}, ...},
#   %{id: :open_button, type: :button, center: %{x: 325, y: 220}, ...},
# ]

# Click by semantic ID (no coordinates needed!)
{:ok, _} = ScenicMcp.Tools.click_element(%{"element_id" => "save_button"})

# Verify click visualization shows exact center hit
{:ok, screenshot} = ScenicMcp.Tools.take_screenshot(%{})
```

**Without changing component code** or manually calculating coordinates.

## Your Task

Please analyze this architecture deeply and provide:

1. **Your recommended architecture** with full justification
2. **Alternative approaches** with pros/cons
3. **Implementation strategy** with phases and risks
4. **Code examples** for key functions
5. **Open questions** we should discuss

Focus on:
- **Elegance**: How does this fit into Scenic's existing design?
- **Performance**: What's the overhead?
- **Usability**: How easy is this for app developers?
- **Completeness**: Does it handle all edge cases?
- **Maintainability**: Can we evolve this over time?

Be thorough. Be critical. Challenge assumptions. This is a foundational piece of infrastructure that will affect every Scenic application using automated testing or AI control.

We trust your expertise. Design the system you would want to use and maintain.

---

## Appendix: Key Code References

### Current ViewPort Initialization (scenic_local/lib/scenic/view_port.ex:504)
```elixir
script_table = :ets.new(:_vp_script_table_, [:public, {:read_concurrency, true}])
```

### Graph Compilation Entry Point (scenic_local/lib/scenic/graph/compiler.ex:56-68)
```elixir
def compile(%Graph{primitives: primitives}) do
  {ops, _} =
    compile_primitive(
      Script.start(),
      primitives[0],
      primitives,
      %Compiler{reqs: Scenic.Primitive.Style.default()}
    )
  {:ok, Script.finish(ops)}
end
```

### Transform Compilation (scenic_local/lib/scenic/graph/compiler.ex:448-467)
```elixir
defp combined_tx(ops, pin, txs) do
  mx =
    txs
    |> Map.put(:pin, pin)
    |> Scenic.Primitive.Transform.combine()

  <<
    m00::float-size(32)-native,
    m10::float-size(32)-native,
    _m20::size(32),
    m30::float-size(32)-native,
    m01::float-size(32)-native,
    m11::float-size(32)-native,
    _a21::size(32),
    m31::float-size(32)-native,
    _::binary
  >> = mx

  Script.transform(ops, m00, m01, m10, m11, m30, m31)
end
```

### ViewPort.put_graph (scenic_local/lib/scenic/view_port.ex:361-394)
```elixir
def put_graph(%ViewPort{pid: pid} = viewport, name, %Graph{} = graph, opts \\ []) do
  with {:ok, script} <- GraphCompiler.compile(graph),
       {:ok, input_list} <- compile_input(graph) do
    case get_script(viewport, name) do
      {:ok, ^script} -> :ok
      _ ->
        owner = opts[:owner]
        put_script(viewport, name, script, owner: owner)
        GenServer.cast(pid, {:input_list, input_list, name, owner})
    end
    {:ok, name}
  end
end
```

### Existing find_clickable_elements stub (scenic_mcp/lib/scenic_mcp/tools.ex:227-275)
```elixir
def find_clickable_elements(params) do
  filter = Map.get(params, "filter")

  with {:ok, vp_state} <- viewport_state(),
       semantic_table <- Map.get(vp_state, :semantic_table),
       elements <- :ets.tab2list(semantic_table) do

    clickable = elements
    |> Enum.filter(fn {_key, data} ->
      Map.get(data, :clickable, false)
    end)
    |> Enum.filter(fn {id, _data} ->
      if filter do
        # Support both :atom and "string" formats
        id_str = Atom.to_string(id)
        String.contains?(id_str, String.trim_leading(filter, ":"))
      else
        true
      end
    end)
    |> Enum.map(fn {id, data} ->
      %{
        id: id,
        type: Map.get(data, :type),
        bounds: Map.get(data, :bounds),
        center: calculate_center(Map.get(data, :bounds))
      }
    end)

    filtered = if filter, do: Enum.take(clickable, 1), else: clickable
    {:ok, %{status: "ok", count: length(filtered), elements: filtered}}
  else
    _ -> {:error, "No semantic table found"}
  end
end

defp calculate_center(%{left: l, top: t, width: w, height: h}) do
  %{x: l + w / 2, y: t + h / 2}
end

defp calculate_center(nil), do: nil
```

---

**Date**: 2025-11-23
**Prepared for**: Oracle AI Architecture Review
**Project**: Scenic Semantic Registration System
**Status**: Awaiting architectural design recommendations
