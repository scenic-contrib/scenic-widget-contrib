# Semantic Element Registration Architecture for Scenic

## Executive Summary

I propose a **parallel semantic compilation pipeline** that operates alongside the existing script compilation, building a queryable semantic tree with automatic transform calculation. This design introduces minimal overhead, requires zero changes to existing apps, and enables Playwright-like testing capabilities.

## 1. High-Level Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Scene Graph                              │
│                    (Primitives + Components)                     │
└──────────────────┬──────────────────────┬───────────────────────┘
                   │                      │
                   ▼                      ▼
        ┌──────────────────┐    ┌──────────────────┐
        │  GraphCompiler   │    │ SemanticCompiler │ ← NEW
        │    (existing)    │    │   (parallel)     │
        └──────────────────┘    └──────────────────┘
                   │                      │
                   ▼                      ▼
        ┌──────────────────┐    ┌──────────────────┐
        │  Script Table    │    │  Semantic Table  │ ← NEW
        │      (ETS)       │    │      (ETS)       │
        └──────────────────┘    └──────────────────┘
                   │                      │
                   ▼                      ▼
        ┌──────────────────┐    ┌──────────────────┐
        │     Driver       │    │   MCP/Testing    │
        │   (rendering)    │    │  (automation)    │
        └──────────────────┘    └──────────────────┘
```

### Key Design Decisions

1. **Parallel Pipeline**: Semantic compilation runs parallel to script compilation, not integrated
2. **Transform Matrix Caching**: Store accumulated transform matrices during compilation
3. **Hierarchical + Flat Hybrid**: Store both tree structure and flat lookup table
4. **Lazy Component Resolution**: Defer sub-scene boundary calculation until query time
5. **Copy-on-Write Updates**: Minimize churn on graph updates

## 2. Detailed Technical Design

### 2.1 ViewPort Changes

```elixir
defmodule Scenic.ViewPort do
  defstruct [
    :name,
    :pid,
    :script_table,
    :semantic_table,      # NEW: ETS table for semantic data
    :semantic_index,      # NEW: ETS table for fast lookups
    :semantic_enabled,    # NEW: boolean flag
    :size
  ]

  # Modified initialization
  def init(config) do
    script_table = :ets.new(:_vp_script_table_, [:public, {:read_concurrency, true}])
    
    # NEW: Create semantic tables if enabled
    {semantic_table, semantic_index, semantic_enabled} = 
      if config[:semantic_registration] != false do
        st = :ets.new(:_vp_semantic_table_, [
          :public, 
          :ordered_set,  # For hierarchical traversal
          {:read_concurrency, true}
        ])
        si = :ets.new(:_vp_semantic_index_, [
          :public,
          :set,
          {:read_concurrency, true}
        ])
        {st, si, true}
      else
        {nil, nil, false}
      end

    %ViewPort{
      name: config[:name],
      script_table: script_table,
      semantic_table: semantic_table,
      semantic_index: semantic_index,
      semantic_enabled: semantic_enabled,
      size: config[:size]
    }
  end
end
```

### 2.2 Semantic Compiler

```elixir
defmodule Scenic.Semantic.Compiler do
  @moduledoc """
  Compiles scene graphs into semantic trees with transform calculations.
  Runs in parallel with GraphCompiler.
  """

  alias Scenic.Graph
  alias Scenic.Primitive
  alias Scenic.Math.Matrix
  
  defmodule Entry do
    @type t :: %__MODULE__{
      id: atom() | binary(),
      type: atom(),
      module: module(),
      parent_id: atom() | binary() | nil,
      children: list(atom() | binary()),
      
      # Bounds
      local_bounds: bounds(),
      screen_bounds: bounds(),
      
      # Transform data
      local_transform: Matrix.t(),
      accumulated_transform: Matrix.t(),
      
      # Semantic metadata
      clickable: boolean(),
      focusable: boolean(),
      label: String.t() | nil,
      role: atom() | nil,
      value: any(),
      hidden: boolean(),
      z_index: integer(),
      
      # Component data
      is_component: boolean(),
      component_name: String.t() | nil,
      component_pid: pid() | nil
    }
    
    defstruct [
      :id, :type, :module, :parent_id, 
      children: [],
      local_bounds: %{left: 0, top: 0, width: 0, height: 0},
      screen_bounds: %{left: 0, top: 0, width: 0, height: 0},
      local_transform: Matrix.identity(),
      accumulated_transform: Matrix.identity(),
      clickable: false,
      focusable: false,
      label: nil,
      role: nil,
      value: nil,
      hidden: false,
      z_index: 0,
      is_component: false,
      component_name: nil,
      component_pid: nil
    ]
  end

  @type bounds :: %{
    left: number(),
    top: number(), 
    width: number(),
    height: number()
  }

  @doc """
  Compiles a graph into semantic entries.
  """
  def compile(%Graph{primitives: primitives}, opts \\ []) do
    viewport_transforms = opts[:viewport_transforms] || Matrix.identity()
    
    # Start from root primitive
    {entries, _} = compile_primitive(
      [],
      primitives[0],
      primitives,
      viewport_transforms,
      nil,  # parent_id
      0     # z_index
    )
    
    {:ok, entries}
  end

  defp compile_primitive(entries, uid, all_primitives, parent_transform, parent_id, z_index) do
    primitive = all_primitives[uid]
    
    # Skip if no semantic relevance
    unless should_register?(primitive) do
      return compile_children(entries, primitive, all_primitives, parent_transform, parent_id, z_index)
    end
    
    # Calculate transforms
    local_transform = build_transform_matrix(primitive.transforms)
    accumulated_transform = Matrix.multiply(parent_transform, local_transform)
    
    # Build semantic entry
    entry = build_semantic_entry(
      primitive,
      parent_id,
      accumulated_transform,
      z_index
    )
    
    # Add to entries
    entries = [entry | entries]
    
    # Process children with updated transform and z_index
    compile_children(
      entries, 
      primitive, 
      all_primitives,
      accumulated_transform,
      entry.id,
      z_index + 1
    )
  end

  defp should_register?(primitive) do
    # Register if:
    # 1. Has explicit :id in opts
    # 2. Is a semantic primitive (button, text_field, etc.)
    # 3. Has semantic metadata
    has_id = primitive.opts[:id] != nil
    is_semantic = semantic_primitive?(primitive.module)
    has_semantic_meta = primitive.opts[:semantic] != nil
    
    has_id or is_semantic or has_semantic_meta
  end

  defp semantic_primitive?(module) do
    module in [
      Scenic.Component.Button,
      Scenic.Component.TextField, 
      Scenic.Component.Checkbox,
      Scenic.Component.RadioButton,
      Scenic.Component.Dropdown,
      Scenic.Component.Slider
      # ... other interactive components
    ]
  end

  defp build_semantic_entry(primitive, parent_id, transform, z_index) do
    %Entry{
      id: get_semantic_id(primitive),
      type: get_semantic_type(primitive),
      module: primitive.module,
      parent_id: parent_id,
      
      # Calculate bounds
      local_bounds: calculate_local_bounds(primitive),
      screen_bounds: calculate_screen_bounds(primitive, transform),
      
      # Store transforms
      local_transform: build_transform_matrix(primitive.transforms),
      accumulated_transform: transform,
      
      # Extract semantic properties
      clickable: is_clickable?(primitive),
      focusable: is_focusable?(primitive),
      label: get_label(primitive),
      role: get_role(primitive),
      value: primitive.data,
      hidden: primitive.styles[:hidden] || false,
      z_index: z_index,
      
      # Component handling
      is_component: primitive.module == Scenic.Primitive.Component,
      component_name: get_component_name(primitive)
    }
  end

  defp calculate_screen_bounds(primitive, transform) do
    local = calculate_local_bounds(primitive)
    
    # Apply transform to all four corners
    corners = [
      {local.left, local.top},
      {local.left + local.width, local.top},
      {local.left, local.top + local.height},
      {local.left + local.width, local.top + local.height}
    ]
    
    transformed_corners = Enum.map(corners, fn {x, y} ->
      Matrix.project_point(transform, {x, y})
    end)
    
    # Find bounding box of transformed corners
    xs = Enum.map(transformed_corners, &elem(&1, 0))
    ys = Enum.map(transformed_corners, &elem(&1, 1))
    
    min_x = Enum.min(xs)
    max_x = Enum.max(xs)
    min_y = Enum.min(ys)
    max_y = Enum.max(ys)
    
    %{
      left: min_x,
      top: min_y,
      width: max_x - min_x,
      height: max_y - min_y
    }
  end

  defp build_transform_matrix(nil), do: Matrix.identity()
  defp build_transform_matrix(transforms) do
    transforms
    |> Enum.reduce(Matrix.identity(), fn
      {:translate, {x, y}}, mx -> Matrix.translate(mx, x, y)
      {:scale, {sx, sy}}, mx -> Matrix.scale(mx, sx, sy)
      {:scale, s}, mx -> Matrix.scale(mx, s, s)
      {:rotate, angle}, mx -> Matrix.rotate(mx, angle)
      {:matrix, m}, mx -> Matrix.multiply(mx, m)
      {:pin, {x, y}}, mx -> Matrix.translate(mx, -x, -y)
      _, mx -> mx
    end)
  end
end
```

### 2.3 Integration with ViewPort.put_graph

```elixir
defmodule Scenic.ViewPort do
  def put_graph(%ViewPort{} = viewport, name, %Graph{} = graph, opts \\ []) do
    # Existing script compilation
    with {:ok, script} <- GraphCompiler.compile(graph),
         {:ok, input_list} <- compile_input(graph) do
      
      # NEW: Parallel semantic compilation
      if viewport.semantic_enabled do
        Task.async(fn ->
          compile_and_store_semantics(viewport, name, graph, opts)
        end)
      end
      
      # Continue with existing logic
      case get_script(viewport, name) do
        {:ok, ^script} -> :ok
        _ ->
          owner = opts[:owner]
          put_script(viewport, name, script, owner: owner)
          GenServer.cast(viewport.pid, {:input_list, input_list, name, owner})
      end
      
      {:ok, name}
    end
  end

  defp compile_and_store_semantics(viewport, scene_name, graph, opts) do
    # Get viewport transform if this is a sub-scene
    parent_transform = case scene_name do
      "_root" -> Matrix.identity()
      _ -> get_component_transform(viewport, scene_name)
    end
    
    # Compile semantic tree
    {:ok, entries} = Semantic.Compiler.compile(
      graph, 
      viewport_transforms: parent_transform
    )
    
    # Store in ETS tables
    Enum.each(entries, fn entry ->
      # Store in main semantic table (hierarchical key)
      key = {scene_name, entry.id}
      :ets.insert(viewport.semantic_table, {key, entry})
      
      # Store in index table (flat lookup)
      :ets.insert(viewport.semantic_index, {entry.id, key})
    end)
    
    # Broadcast semantic update event
    GenServer.cast(viewport.pid, {:semantic_updated, scene_name})
  end
end
```

### 2.4 Query API

```elixir
defmodule Scenic.ViewPort.Semantic do
  @moduledoc """
  Query API for semantic elements.
  """

  @doc """
  Find element by ID, returning full semantic data with screen bounds.
  """
  def find_element(viewport, element_id) do
    case lookup_element(viewport, element_id) do
      {:ok, entry} ->
        # Resolve component boundaries if needed
        entry = resolve_component_bounds(viewport, entry)
        {:ok, entry}
      error -> 
        error
    end
  end

  @doc """
  Find all clickable elements matching filter.
  """
  def find_clickable_elements(viewport, filter \\ %{}) do
    viewport.semantic_table
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&(&1.clickable))
    |> apply_filters(filter)
    |> Enum.map(&resolve_component_bounds(viewport, &1))
    |> Enum.sort_by(&(&1.z_index))
  end

  @doc """
  Get element at screen coordinates.
  """
  def element_at_point(viewport, x, y) do
    viewport.semantic_table
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(fn entry ->
      bounds = entry.screen_bounds
      x >= bounds.left && 
      x <= bounds.left + bounds.width &&
      y >= bounds.top && 
      y <= bounds.top + bounds.height
    end)
    |> Enum.max_by(&(&1.z_index), fn -> nil end)
  end

  @doc """
  Click element by ID.
  """
  def click_element(viewport, element_id) do
    with {:ok, element} <- find_element(viewport, element_id),
         {:ok, center} <- calculate_center(element.screen_bounds) do
      
      # Send mouse events
      input = {:cursor_button, {:btn_left, 1, [], center}}
      ViewPort.input(viewport, input)
      
      input = {:cursor_button, {:btn_left, 0, [], center}}
      ViewPort.input(viewport, input)
      
      {:ok, center}
    end
  end

  @doc """
  Get hierarchical tree of semantic elements.
  """
  def get_semantic_tree(viewport, root_id \\ "_root") do
    build_tree(viewport, root_id)
  end

  # Private helpers

  defp resolve_component_bounds(viewport, %{is_component: true} = entry) do
    # For components, aggregate bounds from child primitives
    children_bounds = get_component_children_bounds(viewport, entry.component_name)
    
    %{entry | 
      screen_bounds: aggregate_bounds(children_bounds),
      children: get_component_children_ids(viewport, entry.component_name)
    }
  end
  defp resolve_component_bounds(_viewport, entry), do: entry

  defp calculate_center(%{left: x, top: y, width: w, height: h}) do
    {:ok, {x + w / 2, y + h / 2}}
  end

  defp build_tree(viewport, parent_id) do
    # Get entry for parent
    {:ok, parent} = find_element(viewport, parent_id)
    
    # Recursively build children
    children = parent.children
    |> Enum.map(&build_tree(viewport, &1))
    
    Map.put(parent, :children, children)
  end
end
```

### 2.5 Automatic Registration Hooks

```elixir
defmodule Scenic.Component do
  @doc """
  Modified base component macro to auto-register semantic elements.
  """
  defmacro __using__(opts) do
    quote do
      use Scenic.Scene, unquote(opts)
      
      # Auto-register if component has semantic relevance
      @before_compile Scenic.Component.SemanticHook
    end
  end
end

defmodule Scenic.Component.SemanticHook do
  defmacro __before_compile__(_env) do
    quote do
      # Override init to auto-register
      defoverridable init: 3
      
      def init(scene, args, opts) do
        scene = super(scene, args, opts)
        
        # Auto-register if ID present
        if opts[:id] do
          viewport = scene.viewport
          semantic_data = build_semantic_data(__MODULE__, opts, args)
          
          Task.async(fn ->
            Scenic.ViewPort.Semantic.auto_register(
              viewport,
              opts[:id],
              semantic_data
            )
          end)
        end
        
        scene
      end
      
      defp build_semantic_data(module, opts, args) do
        %{
          type: semantic_type_for(module),
          clickable: clickable_for(module),
          focusable: focusable_for(module),
          label: extract_label(args, opts),
          metadata: opts[:semantic] || %{}
        }
      end
    end
  end
end
```

## 3. Implementation Plan

### Phase 1: Foundation (Week 1-2)
1. Add semantic_table to ViewPort struct
2. Create basic Semantic.Compiler module
3. Implement simple registration API
4. Basic coordinate calculation (no transforms)
5. Simple find_element/2 function

**Deliverable**: Can find and click buttons with explicit IDs

### Phase 2: Transform Support (Week 3-4)
1. Implement Matrix operations for transforms
2. Calculate accumulated transforms during compilation
3. Handle nested groups and transforms
4. Test with rotated/scaled elements

**Deliverable**: Correct screen coordinates with any transform

### Phase 3: Component Integration (Week 5-6)
1. Handle component sub-scenes
2. Aggregate component boundaries
3. Link parent-child relationships
4. Resolve component names to PIDs

**Deliverable**: Components fully integrated in semantic tree

### Phase 4: Advanced Features (Week 7-8)
1. Query by type, text, role
2. Visibility and z-order handling
3. Performance optimizations
4. Caching strategies

**Deliverable**: Full Playwright-like query capabilities

### Phase 5: Testing & Documentation (Week 9-10)
1. Integration with scenic_mcp
2. Test helper library
3. Documentation and examples
4. Performance benchmarking

**Deliverable**: Production-ready system

## 4. Alternative Approaches

### Alternative A: Script Table Analysis
**Concept**: Extract semantic data from compiled scripts
```elixir
# Parse compiled binary scripts to reconstruct element positions
{:ok, semantics} = ScriptAnalyzer.extract_semantics(script_binary)
```

**Pros:**
- No changes to compilation pipeline
- Works with existing scripts

**Cons:**
- Reverse engineering binary format
- Lost semantic metadata
- Complex transform reconstruction

### Alternative B: Scene Graph Decoration
**Concept**: Decorate graph nodes with semantic data during construction
```elixir
graph
|> button("Save", id: :save_button)
|> Semantic.annotate(:save_button, %{bounds: {...}})
```

**Pros:**
- Explicit control
- Clear data flow

**Cons:**
- Manual annotation required
- Boilerplate code
- Transform calculation burden on developer

### Alternative C: Runtime Introspection
**Concept**: Query live scene processes for element data
```elixir
{:ok, elements} = Scene.introspect(scene_pid)
```

**Pros:**
- Always current state
- No compilation overhead

**Cons:**
- Performance impact on scenes
- Complex inter-process communication
- Race conditions

## 5. Risk Analysis & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Performance degradation | High | Low | Lazy compilation, caching, feature flag |
| Memory overhead | Medium | Medium | Bounded table size, TTL entries |
| Transform calculation errors | High | Medium | Extensive testing, matrix validation |
| Breaking changes | High | Low | Backward compatibility layer |
| Component boundary ambiguity | Medium | High | Clear documentation, conventions |

## 6. Performance Considerations

### Memory Overhead
```elixir
# Estimated per element
semantic_entry_size = 
  8 +   # id atom
  8 +   # type atom
  8 +   # parent reference
  16 +  # local bounds (4 floats)
  16 +  # screen bounds (4 floats)
  64 +  # transform matrix (16 floats)
  20    # metadata
  = 140 bytes per element

# For 1000 elements = ~140KB overhead
```

### CPU Overhead
- Compilation: O(n) where n = primitives with IDs
- Transform calculation: O(d) where d = tree depth
- Query: O(1) for ID lookup, O(n) for filters
- Updates: O(k) where k = changed elements

### Optimization Strategies
1. **Lazy Loading**: Only compile semantics when first queried
2. **Incremental Updates**: Diff and update only changed elements  
3. **Transform Caching**: Store and reuse matrix calculations
4. **Spatial Indexing**: R-tree for coordinate queries

## 7. Code Example: End-to-End Flow

```elixir
# 1. Developer writes normal Scenic code
defmodule MyApp.Scene do
  use Scenic.Scene
  
  def init(_, _opts) do
    graph = 
      Graph.build()
      |> group(
        fn g ->
          g
          |> button("Save", id: :save_btn, t: {100, 50})
          |> button("Cancel", id: :cancel_btn, t: {250, 50})
        end,
        t: {50, 100}, scale: 1.5
      )
    
    {:ok, graph, push: graph}
  end
end

# 2. Semantic compilation happens automatically
# ViewPort.put_graph triggers both pipelines:
#   - GraphCompiler → Scripts → Rendering
#   - SemanticCompiler → Semantic Table → Testing

# 3. Test/automation code
defmodule MyApp.Test do
  test "save button click" do
    # Connect to running app
    {:ok, viewport} = Scenic.ViewPort.connect(:main_viewport)
    
    # Find button by ID (no coordinates!)
    {:ok, save_btn} = Scenic.ViewPort.Semantic.find_element(viewport, :save_btn)
    
    # Verify calculated screen position (group + button transforms)
    assert save_btn.screen_bounds == %{
      left: 225,   # (50 + 100) * 1.5
      top: 225,    # (100 + 50) * 1.5  
      width: 120,  # 80 * 1.5
      height: 45   # 30 * 1.5
    }
    
    # Click it
    {:ok, clicked_at} = Scenic.ViewPort.Semantic.click_element(viewport, :save_btn)
    assert clicked_at == {285, 247.5}  # Center of transformed button
  end
end
```

## 8. Migration Strategy

### For Existing Apps

```elixir
# Option 1: Opt-in via config
config :scenic, :semantic_registration, true

# Option 2: Per-viewport
ViewPort.start(semantic_registration: true)

# Option 3: Gradual adoption - add IDs to enable
graph |> button("Save")  # Not registered
graph |> button("Save", id: :save_btn)  # Automatically registered!
```

### Compatibility Guarantees
1. **Zero breaking changes** to existing API
2. **No performance impact** when disabled
3. **Incremental adoption** - add IDs as needed
4. **Fallback to coordinates** - old tests still work

## 9. Open Questions for Discussion

1. **Should we support CSS-like selectors?**
   ```elixir
   find_elements(viewport, "button:contains('Save')")
   find_elements(viewport, ".toolbar > button")
   ```

2. **How to handle dynamic content?**
   - Animations changing bounds
   - Conditional rendering
   - Virtual scrolling

3. **Security considerations?**
   - Should semantic data be exposed to external tools?
   - Authentication for MCP connections?

4. **Standardization with web semantics?**
   - Adopt ARIA roles?
   - WAI-ARIA compatibility?

5. **Performance thresholds?**
   - Maximum elements before switching strategies?
   - Acceptable query latency?

## Conclusion

This architecture provides a robust, performant, and elegant solution for semantic registration in Scenic. The parallel compilation pipeline ensures zero impact on existing applications while enabling powerful testing capabilities. The transform-aware coordinate system handles all edge cases, and the hierarchical structure supports complex component compositions.

The phased implementation allows for iterative development and testing, reducing risk while delivering value early. Most importantly, this design feels natural within Scenic's existing architecture - it's not a bolt-on but a proper extension of the framework's capabilities.

This foundation will enable Scenic applications to be tested as easily as web applications, finally bringing GUI testing in Elixir to parity with modern browser automation tools.