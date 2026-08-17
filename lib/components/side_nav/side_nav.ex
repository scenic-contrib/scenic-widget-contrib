defmodule ScenicWidgets.SideNav do
  @moduledoc """
  A hierarchical sidebar navigation component following HexDocs style.

  ## Features
  - Expandable/collapsible tree structure
  - Click chevron to expand/collapse
  - Click text to navigate (emits events)
  - Full keyboard navigation (arrows, enter, home/end)
  - Active item highlighting with accent bar
  - Hover states
  - Focus ring for keyboard navigation
  - Smooth scrolling
  - MCP semantic element registration

  ## Usage

      tree = [
        %SideNav.Item{
          id: "getting_started",
          title: "GETTING STARTED",
          type: :group,
          children: [
            %SideNav.Item{
              id: "intro",
              title: "Introduction",
              type: :page,
              url: "/intro"
            }
          ]
        }
      ]

      graph
      |> SideNav.add_to_graph(
        %{
          frame: frame,
          tree: tree,
          active_id: "intro"
        },
        id: :sidebar
      )

  ## Events

  SideNav sends these events to the parent scene:
  - `{:sidebar, :navigate, item_id}` - When an item is clicked or Enter pressed
  - `{:sidebar, :expand, item_id}` - When a node is expanded
  - `{:sidebar, :collapse, item_id}` - When a node is collapsed
  - `{:sidebar, :hover, item_id}` - When mouse hovers over an item
  - `{:sidebar, :rename_requested, item_id, new_name}` - Inline rename committed
  """

  use Scenic.Component, has_children: false
  require Logger

  alias ScenicWidgets.SideNav.{State, Renderizer, Reducer, Api, Item}
  alias Scenic.Graph
  alias Widgex.Scroll.{ScrollController, ScrollState}

  # Override add_to_graph for custom initialization
  def add_to_graph(graph, data, opts \\ []) do
    # Call the default implementation provided by `use Scenic.Component`
    super(graph, data, opts)
  end

  @doc """
  Validate initialization data.
  """
  def validate(data) when is_map(data) do
    case {Map.get(data, :frame), Map.get(data, :tree)} do
      {%{pin: _, size: _}, tree} when is_list(tree) ->
        {:ok, data}

      {%{pin: _, size: _}, nil} ->
        # No tree provided, use test tree
        {:ok, Map.put(data, :tree, Item.test_tree())}

      _ ->
        {:error, "SideNav requires :frame and :tree"}
    end
  end

  @impl Scenic.Component
  def init(scene, data, _opts) do
    Logger.debug("🎯 SideNav component initializing!")

    # Initialize component state
    state = State.new(data)

    Logger.debug("   State created with #{map_size(state.item_bounds)} item bounds")

    # Initial render
    graph = Renderizer.initial_render(Graph.build(), state)

    scene =
      scene
      |> assign(state: state, graph: graph)
      |> push_graph(graph)

    # Keyboard, plus scroll.
    #
    # Mouse clicks and cursor_pos are handled via primitives with `input: [...]`
    # style, which uses Scenic's hit-testing. Requesting :cursor_button here
    # would cause double-delivery when the parent scene also requests it.
    #
    # Scroll is different, and has to be requested. It is positional, but
    # hit-testing only considers primitives that named :cursor_scroll in their
    # own `input:` list — and none of this component's do. So a wheel event over
    # the sidebar found no scroll target here and the sidebar never scrolled.
    # Requesting it delivers every scroll event globally, so handle_input
    # bounds-checks against our frame before acting (the same shape TextField
    # uses; without the check an editor beside a sidebar would both scroll on
    # one wheel event).
    request_input(scene, [:key, :codepoint, :cursor_scroll])

    Logger.debug("   Graph pushed, now calling register_semantic_elements...")
    # Register semantic elements for MCP interaction
    register_semantic_elements(scene, state)

    Logger.debug("✅ SideNav initialized successfully")

    {:ok, scene}
  end

  @impl Scenic.Scene
  def handle_put({:set_active, item_id}, scene) do
    state = scene.assigns.state
    new_state = Api.set_active(state, item_id)

    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_put({:toggle_expand, item_id}, scene) do
    state = scene.assigns.state
    new_state = Api.toggle_expand(state, item_id)

    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_put({:update_tree, new_tree}, scene) do
    state = scene.assigns.state
    new_state = Api.update_tree(state, new_tree)

    # Full re-render for tree changes
    graph = Renderizer.initial_render(Graph.build(), new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    # The rows changed, so the semantic map of rows must too — otherwise
    # tooling still sees the old tree (rows added by the update are
    # unclickable by id, removed ones linger).
    register_semantic_elements(scene, new_state)

    {:noreply, scene}
  end

  def handle_put({:set_filter, filter_term}, scene) do
    state = scene.assigns.state
    new_state = Api.set_filter(state, filter_term)

    # Full re-render for filtered tree
    graph = Renderizer.initial_render(Graph.build(), new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_put({:update_frame, frame}, scene) do
    state = scene.assigns.state

    resized_scroll = ScrollState.update_viewport_size(state.scroll, frame)

    new_scroll =
      %{
        resized_scroll
        | offset_x: min(resized_scroll.offset_x, ScrollState.max_offset_x(resized_scroll)),
          offset_y: min(resized_scroll.offset_y, ScrollState.max_offset_y(resized_scroll))
      }
      |> State.sync_scrollbar_visibility()

    new_state = %{state | frame: frame, scroll: new_scroll}
    graph = Renderizer.initial_render(Graph.build(), new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    register_semantic_elements(scene, new_state)
    {:noreply, scene}
  end

  # Component-level focus, granted/revoked by the parent scene — the same
  # :focus/:blur contract TextField uses. Keyboard input is ignored while
  # unfocused (see the {:key, _} gate in handle_input/3).
  def handle_put(:focus, scene) do
    {:noreply, assign(scene, state: %{scene.assigns.state | focused: true})}
  end

  def handle_put(:blur, scene) do
    {:noreply, assign(scene, state: %{scene.assigns.state | focused: false})}
  end

  def handle_put(_value, scene) do
    {:noreply, scene}
  end

  @impl Scenic.Scene
  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, coords}},
        {:scrollbar_y_thumb, _group_id},
        scene
      ) do
    start_scrollbar_drag(scene, :y, coords)
  end

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, coords}},
        {:scrollbar_x_thumb, _group_id},
        scene
      ) do
    start_scrollbar_drag(scene, :x, coords)
  end

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, coords}},
        {:scrollbar_y_track, _group_id},
        scene
      ) do
    page_scrollbar(scene, :y, coords)
  end

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, coords}},
        {:scrollbar_x_track, _group_id},
        scene
      ) do
    page_scrollbar(scene, :x, coords)
  end

  def handle_input(
        {:cursor_pos, coords},
        _context,
        %{assigns: %{state: %{scrollbar_drag: axis}}} = scene
      )
      when axis in [:x, :y] do
    drag_scrollbar(scene, axis, coords)
  end

  def handle_input(
        {:cursor_button, {:btn_left, 0, _mods, _coords}},
        _context,
        %{assigns: %{state: %{scrollbar_drag: axis}}} = scene
      )
      when axis in [:x, :y] do
    :ok = release_input(scene, [:cursor_pos, :cursor_button])

    state = scene.assigns.state

    new_state = %{
      state
      | scrollbar_drag: nil,
        scrollbar_drag_start: nil,
        scrollbar_drag_offset: nil
    }

    {:noreply, assign(scene, state: new_state)}
  end

  def handle_input(
        {:cursor_pos, {x, y}},
        _context,
        %{assigns: %{state: %State{drag_source: source}}} = scene
      )
      when not is_nil(source) do
    {start_x, start_y} = scene.assigns.state.drag_start
    state = scene.assigns.state
    dragging = state.dragging or abs(x - start_x) + abs(y - start_y) >= 6

    {drag_target, drop_valid} =
      if dragging do
        case State.hit_test(state, {x, y}) do
          {target_id, _} ->
            target = Item.find_by_id(state.tree, target_id)

            valid =
              target && Item.get_type(target) == :group &&
                Enum.all?(state.selected_ids, fn source ->
                  source != target_id and
                    not descendant_path?(target_id, source)
                end)

            {target_id, valid}

          nil ->
            {nil, false}
        end
      else
        {nil, false}
      end

    new_state = %{state | dragging: dragging, drag_target: drag_target, drop_valid: drop_valid}
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  def handle_input(
        {:cursor_button, {:btn_left, 0, _mods, {x, y}}},
        _context,
        %{assigns: %{state: %State{drag_source: source}}} = scene
      )
      when not is_nil(source) do
    state = scene.assigns.state
    :ok = release_input(scene, [:cursor_pos, :cursor_button])

    if state.dragging do
      # Hit-tested/captured component input is already in SideNav-local
      # coordinates. Subtracting the frame pin a second time makes drops near
      # the top miss the tree entirely.
      case State.hit_test(state, {x, y}) do
        {target_id, _region} ->
          target = Item.find_by_id(state.tree, target_id)

          if target && Item.get_type(target) == :group &&
               not MapSet.member?(state.selected_ids, target_id) do
            paths = MapSet.to_list(state.selected_ids)

            send_parent_event(
              scene,
              {:sidebar, :move_requested, paths, target_id}
            )
          end

        nil ->
          :ok
      end
    else
      item = Item.find_by_id(state.tree, source)

      if item && Item.get_type(item) != :group &&
           Enum.all?(state.drag_mods, &(&1 not in [:ctrl, :shift])) do
        send_parent_event(scene, {:sidebar, :navigate, source})
      end
    end

    selected_state =
      if not state.dragging && state.drag_mods == [] do
        State.select(state, source)
      else
        state
      end

    pending_path_moves =
      if state.dragging and state.drop_valid do
        Enum.map(state.selected_ids, &{&1, Path.join(state.drag_target, Path.basename(&1))})
      else
        state.pending_path_moves
      end

    new_state = %{
      selected_state
      | drag_source: nil,
        drag_start: nil,
        drag_mods: [],
        dragging: false,
        drag_target: nil,
        drop_valid: false,
        pending_path_moves: pending_path_moves
    }

    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  # Match the normal dropdown contract: drifting outside the popup dismisses
  # it. Component input coordinates and context-menu coordinates are local.
  def handle_input(
        {:cursor_pos, {x, y}},
        _context,
        %{assigns: %{state: %State{context_menu: %{x: menu_x, y: menu_y}}}} = scene
      ) do
    %{frame: frame} = scene.assigns.state
    left = min(menu_x, max(frame.size.width - 150 - 4, 4))
    top = min(menu_y, max(frame.size.height - 60 - 4, 4))

    if x >= left and x <= left + 150 and y >= top and y <= top + 60 do
      {:noreply, scene}
    else
      close_context_menu(scene)
    end
  end

  # Handle cursor position for hover effects (via hit-tested primitive)
  def handle_input({:cursor_pos, _coords}, {:row_click, item_id}, scene) do
    state = scene.assigns.state
    new_state = Map.put(state, :hovered_id, item_id)

    if new_state != state do
      graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
      scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  # Cursor not over any row - clear hover
  def handle_input({:cursor_pos, _coords}, _context, scene) do
    state = scene.assigns.state
    new_state = Map.put(state, :hovered_id, nil)

    if new_state != state do
      graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
      scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  # Handle click on CHEVRON - toggle expand/collapse
  # Note: Uses debounce to prevent double-click issues
  def handle_input(
        {:cursor_button, {:btn_left, 1, [], _coords}},
        {:chevron_click, item_id},
        scene
      ) do
    now = :erlang.monotonic_time(:millisecond)
    last_click = scene.assigns[:last_click_time]

    # Debounce: ignore clicks within 100ms of each other
    should_debounce = last_click != nil and now - last_click < 100

    if should_debounce do
      {:noreply, scene}
    else
      Logger.debug("🔽 SideNav chevron clicked: #{item_id}")
      state = scene.assigns.state

      # Toggle expansion state
      new_state = %{State.toggle_expanded(state, item_id) | focused: true}

      # Send expand/collapse event to parent
      if MapSet.member?(new_state.expanded, item_id) do
        send_parent_event(scene, {:sidebar, :expand, item_id})
      else
        send_parent_event(scene, {:sidebar, :collapse, item_id})
      end

      graph = Renderizer.update_render(scene.assigns.graph, state, new_state)

      scene =
        scene
        |> assign(state: new_state, graph: graph, last_click_time: now)
        |> push_graph(graph)

      # Re-register semantic elements since expansion state changed
      register_semantic_elements(scene, new_state)

      {:noreply, scene}
    end
  end

  # Handle click on ROW - navigate to item (full row is clickable)
  # For GROUP items with children, toggle expansion instead of navigating
  # Note: Uses debounce to prevent double-click issues
  def handle_input(
        {:cursor_button, {:btn_left, 1, mods, coords}},
        {:row_click, item_id},
        scene
      ) do
    now = :erlang.monotonic_time(:millisecond)
    last_click = scene.assigns[:last_click_time]

    # Debounce: ignore clicks within 100ms of each other
    should_debounce = last_click != nil and now - last_click < 100

    if should_debounce do
      {:noreply, scene}
    else
      handle_row_click(scene, item_id, mods, coords, now)
    end
  end

  def handle_input(
        {:cursor_button, {:btn_right, 1, _mods, {x, y}}},
        {:row_click, item_id},
        scene
      ) do
    state = scene.assigns.state

    selected_state =
      if MapSet.member?(state.selected_ids, item_id),
        do: State.set_focused(state, item_id),
        else: State.select(state, item_id)

    new_state = %{
      selected_state
      | context_menu: %{x: x, y: y, item_id: item_id},
        focused: true
    }

    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, _coords}},
        {:context_action, :rename},
        scene
      ) do
    state = scene.assigns.state
    item_id = state.context_menu.item_id

    new_state = %{
      state
      | context_menu: nil,
        renaming_id: item_id,
        rename_value: Path.basename(item_id),
        rename_replace_on_input: true,
        focused: true
    }

    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, _coords}},
        {:context_action, :delete},
        scene
      ) do
    state = scene.assigns.state
    send_parent_event(scene, {:sidebar, :delete_requested, MapSet.to_list(state.selected_ids)})
    new_state = %{state | context_menu: nil}
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, _coords}},
        :side_nav_context_menu_shield,
        scene
      ) do
    close_context_menu(scene)
  end

  # Actual row click handling (after debounce check)
  defp handle_row_click(scene, item_id, mods, coords, now) do
    Logger.debug("🖱️ SideNav row clicked: #{item_id}")
    state = scene.assigns.state

    # Find the item to determine its type
    item = Item.find_by_id(state.tree, item_id)

    Logger.debug(
      "   Found item: #{inspect(item != nil)}, has_children: #{inspect(item && Item.has_children?(item))}"
    )

    # If it's a group with children, toggle expansion instead of navigating
    if item && Item.get_type(item) == :group do
      Logger.debug("   📂 Group item - toggling expansion")
      new_state = state |> State.select(item_id, mods) |> State.toggle_expanded(item_id)
      new_state = %{new_state | focused: true}

      # Send expand/collapse event to parent (informational only)
      if MapSet.member?(new_state.expanded, item_id) do
        send_parent_event(scene, {:sidebar, :expand, item_id})
      else
        send_parent_event(scene, {:sidebar, :collapse, item_id})
      end

      graph = Renderizer.update_render(scene.assigns.graph, state, new_state)

      scene =
        scene
        |> assign(state: new_state, graph: graph, last_click_time: now)
        |> push_graph(graph)

      scene = begin_row_drag(scene, item_id, mods, coords)

      register_semantic_elements(scene, new_state)
      {:noreply, scene}
    else
      # Leaf item - select. Modified clicks build an operation selection
      # without changing the active editor buffer.
      action = Item.get_action(item)

      Logger.debug("📍 ITEM CLICKED: #{item_id}")
      Logger.debug("   📤 Sending parent message: {:sidebar, :navigate, #{inspect(item_id)}}")

      # Execute action callback if present (OPTIONAL)
      if action do
        Logger.debug("   🔥 Executing action callback for #{item_id}")
        action.()
      else
        Logger.debug("   ℹ️  No action callback - parent message only")
      end

      # active_id is updated only from the application's active-buffer
      # snapshot; selection and keyboard focus are independent.
      selected_state =
        if mods == [] and MapSet.size(state.selected_ids) > 1 and
             MapSet.member?(state.selected_ids, item_id) do
          State.set_focused(state, item_id)
        else
          State.select(state, item_id, mods)
        end

      new_state = Map.put(selected_state, :focused, true)

      graph = Renderizer.update_render(scene.assigns.graph, state, new_state)

      scene =
        scene
        |> assign(state: new_state, graph: graph, last_click_time: now)
        |> push_graph(graph)

      scene = begin_row_drag(scene, item_id, mods, coords)

      {:noreply, scene}
    end
  end

  defp begin_row_drag(scene, item_id, mods, coords) do
    :ok = capture_input(scene, [:cursor_pos, :cursor_button])

    assign(scene,
      state: %{
        scene.assigns.state
        | drag_source: item_id,
          drag_start: coords,
          drag_mods: mods,
          dragging: false,
          context_menu: nil
      }
    )
  end

  # Click not on any recognized element - log for debugging
  def handle_input({:cursor_button, {:btn_left, 1, [], coords}}, context, scene) do
    Logger.debug(
      "🔴 SideNav cursor_button NOT MATCHED - context: #{inspect(context)}, coords: #{inspect(coords)}"
    )

    # Log tree info for debugging
    state = scene.assigns.state

    Logger.debug(
      "   Tree items: #{inspect(Enum.map(state.tree, fn item -> {ScenicWidgets.SideNav.Item.get_id(item), ScenicWidgets.SideNav.Item.has_children?(item)} end))}"
    )

    {:noreply, scene}
  end

  # Scroll. Requested globally (see init/3), so act only when the pointer is
  # actually over this sidebar. Both wheel-event shapes Scenic emits are
  # accepted; the payload goes to the reducer unchanged so it can use both axes.
  def handle_input({:cursor_scroll, {{_dx, _dy}, {x, y}}} = input, _context, scene) do
    maybe_scroll(scene, input, x, y)
  end

  def handle_input({:cursor_scroll, {_dx, _dy, x, y}} = input, _context, scene) do
    maybe_scroll(scene, input, x, y)
  end

  defp maybe_scroll(scene, {:cursor_scroll, payload}, x, y) do
    state = scene.assigns.state

    if point_in_frame?(state.frame, x, y) do
      case Reducer.handle_scroll_input(state, payload) do
        {:scroll_changed, new_state} ->
          graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
          scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)

          # Scrolling moves every row on screen, so the positions published to
          # the semantic layer are stale until re-registered — same reason
          # expand/collapse re-registers.
          register_semantic_elements(scene, new_state)

          {:noreply, scene}

        {:noop, _state} ->
          {:noreply, scene}
      end
    else
      {:noreply, scene}
    end
  end

  # Input coords arrive in the parent's coordinate space — the same space as
  # state.frame's pin for a component placed by a root scene.
  # Requested positional input arrives already transformed into this component's
  # local coordinates; frame.pin is expressed in the parent scene.
  defp point_in_frame?(%{size: %{width: w, height: h}}, x, y) do
    x >= 0 and x <= w and y >= 0 and y <= h
  end

  defp start_scrollbar_drag(scene, axis, coords) do
    :ok = capture_input(scene, [:cursor_pos, :cursor_button])
    state = scene.assigns.state

    start_offset =
      case axis do
        :x -> state.scroll.offset_x
        :y -> state.scroll.offset_y
      end

    new_state = %{
      state
      | scrollbar_drag: axis,
        scrollbar_drag_start: coords,
        scrollbar_drag_offset: start_offset
    }

    {:noreply, assign(scene, state: new_state)}
  end

  defp drag_scrollbar(scene, axis, {x, y}) do
    state = scene.assigns.state
    {start_x, start_y} = state.scrollbar_drag_start

    {track_length, content_size, viewport_size, max_offset, pointer_delta} =
      scrollbar_drag_geometry(state, axis, x - start_x, y - start_y)

    thumb_length =
      ScrollController.thumb_length(track_length, content_size, viewport_size)

    offset =
      ScrollController.drag_offset(
        state.scrollbar_drag_offset,
        pointer_delta,
        track_length,
        thumb_length,
        max_offset
      )

    new_scroll =
      case axis do
        :x -> %{state.scroll | offset_x: offset, scrollbar_visible: true, scrollbar_opacity: 255}
        :y -> %{state.scroll | offset_y: offset, scrollbar_visible: true, scrollbar_opacity: 255}
      end

    new_state = %{state | scroll: new_scroll}
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)

    scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
    register_semantic_elements(scene, new_state)
    {:noreply, scene}
  end

  defp page_scrollbar(scene, axis, {x, y}) do
    state = scene.assigns.state

    {track_length, content_size, viewport_size, max_offset, pointer, current_offset} =
      case axis do
        :x ->
          track_length = horizontal_track_length(state)

          {track_length, state.scroll.content_width, state.scroll.viewport_width,
           ScrollState.max_offset_x(state.scroll), x, state.scroll.offset_x}

        :y ->
          track_length = state.frame.size.height - 4

          {track_length, state.scroll.content_height, state.scroll.viewport_height,
           ScrollState.max_offset_y(state.scroll), y, state.scroll.offset_y}
      end

    thumb_length = ScrollController.thumb_length(track_length, content_size, viewport_size)

    thumb_start =
      if max_offset > 0 do
        current_offset / max_offset * max(track_length - thumb_length, 0)
      else
        0
      end

    offset =
      ScrollController.page_offset(
        current_offset,
        pointer,
        thumb_start,
        thumb_length,
        viewport_size,
        max_offset
      )

    new_scroll =
      case axis do
        :x -> %{state.scroll | offset_x: offset, scrollbar_visible: true, scrollbar_opacity: 255}
        :y -> %{state.scroll | offset_y: offset, scrollbar_visible: true, scrollbar_opacity: 255}
      end

    new_state = %{state | scroll: new_scroll}
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
    register_semantic_elements(scene, new_state)
    {:noreply, scene}
  end

  defp scrollbar_drag_geometry(state, :x, dx, _dy) do
    track_length = horizontal_track_length(state)
    scroll = state.scroll

    {track_length, scroll.content_width, scroll.viewport_width, ScrollState.max_offset_x(scroll),
     dx}
  end

  defp scrollbar_drag_geometry(state, :y, _dx, dy) do
    track_length = state.frame.size.height - 4
    scroll = state.scroll

    {track_length, scroll.content_height, scroll.viewport_height,
     ScrollState.max_offset_y(scroll), dy}
  end

  defp horizontal_track_length(state) do
    # ScrollRenderer shortens the horizontal track when the vertical bar is
    # present: width - scrollbar width (12) - three 2px padding gaps.
    if ScrollState.scrollable_y?(state.scroll) do
      state.frame.size.width - 18
    else
      state.frame.size.width - 4
    end
  end

  # Keyboard navigation — gated on component focus. SideNav requests [:key]
  # globally, so without this gate every keystroke on screen reaches it:
  # Enter typed into an editor would also "open" the focused nav item
  # (double-delivery). TextField has the equivalent gate in its handle_input.
  def handle_input(
        {:key, {:key_esc, 1, _}},
        _context,
        %{assigns: %{state: %State{context_menu: menu}}} = scene
      )
      when not is_nil(menu) do
    close_context_menu(scene)
  end

  def handle_input(
        {:key, {:key_enter, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    state = scene.assigns.state
    value = String.trim(state.rename_value)

    if value != "" and value != Path.basename(id) do
      send_parent_event(scene, {:sidebar, :rename_requested, id, value})
    end

    finish_rename(scene)
  end

  def handle_input(
        {:key, {:key_esc, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    finish_rename(scene)
  end

  def handle_input(
        {:key, {:key_backspace, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    state = scene.assigns.state

    value =
      if state.rename_replace_on_input,
        do: "",
        else: String.slice(state.rename_value, 0, max(String.length(state.rename_value) - 1, 0))

    update_rename(scene, value)
  end

  def handle_input(
        {:codepoint, {codepoint, _mods}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) and is_binary(codepoint) do
    state = scene.assigns.state
    value = if state.rename_replace_on_input, do: codepoint, else: state.rename_value <> codepoint
    update_rename(scene, value)
  end

  def handle_input({:key, _}, _context, %{assigns: %{state: %State{focused: false}}} = scene) do
    {:noreply, scene}
  end

  def handle_input({:key, {:key_down, 1, _}}, _context, scene) do
    handle_keyboard(scene, &Reducer.handle_key_down/1)
  end

  def handle_input({:key, {:key_up, 1, _}}, _context, scene) do
    handle_keyboard(scene, &Reducer.handle_key_up/1)
  end

  def handle_input({:key, {:key_left, 1, _}}, _context, scene) do
    handle_keyboard(scene, &Reducer.handle_key_left/1)
  end

  def handle_input({:key, {:key_right, 1, _}}, _context, scene) do
    handle_keyboard(scene, &Reducer.handle_key_right/1)
  end

  def handle_input({:key, {:key_enter, 1, _}}, _context, scene) do
    state = scene.assigns.state

    case Reducer.handle_key_enter(state) do
      {:navigate, item_id, new_state} ->
        send_parent_event(scene, {:sidebar, :navigate, item_id})

        # Execute action callback if present
        item = Item.find_by_id(state.tree, item_id)

        if action = Item.get_action(item) do
          action.()
        end

        graph = Renderizer.update_render(scene.assigns.graph, state, new_state)

        scene =
          scene
          |> assign(state: new_state, graph: graph)
          |> push_graph(graph)

        {:noreply, scene}

      {:noop, _} ->
        {:noreply, scene}
    end
  end

  def handle_input({:key, {:key_home, 1, _}}, _context, scene) do
    handle_keyboard(scene, &Reducer.handle_key_home/1)
  end

  def handle_input({:key, {:key_end, 1, _}}, _context, scene) do
    handle_keyboard(scene, &Reducer.handle_key_end/1)
  end

  def handle_input({:key, {:key_esc, 1, _}}, _context, scene) do
    handle_keyboard(scene, &Reducer.handle_key_escape/1)
  end

  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  # Helper for keyboard input handling
  defp handle_keyboard(scene, reducer_fn) do
    state = scene.assigns.state
    new_state = reducer_fn.(state)

    if new_state != state do
      graph = Renderizer.update_render(scene.assigns.graph, state, new_state)

      scene =
        scene
        |> assign(state: new_state, graph: graph)
        |> push_graph(graph)

      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  defp close_context_menu(scene) do
    state = scene.assigns.state
    new_state = %{state | context_menu: nil}
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  defp update_rename(scene, value) do
    state = scene.assigns.state
    new_state = %{state | rename_value: value, rename_replace_on_input: false}
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  defp finish_rename(scene) do
    state = scene.assigns.state

    new_state = %{
      state
      | renaming_id: nil,
        rename_value: "",
        rename_replace_on_input: false
    }

    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  defp descendant_path?(candidate, directory) do
    relative = Path.relative_to(candidate, directory)
    relative != candidate and relative != "." and not String.starts_with?(relative, "..")
  end

  # Register semantic elements for MCP interaction
  # Manually registers elements into Phase 1 semantic tables
  # (Phase 1 doesn't handle component sub-scenes automatically)
  defp register_semantic_elements(scene, %State{} = state) do
    viewport = scene.viewport
    scene_name = scene.assigns[:id] || :side_nav

    # The component's screen position, less however far the content is
    # scrolled. Item bounds are content-space coordinates, and the rendered
    # content group is translated by ScrollState.translate_offset/1
    # ({-offset_x, -offset_y}) — so registering `pin + bounds` alone described
    # where a row would be if the sidebar had never been scrolled. Rows kept
    # their original advertised positions after a scroll, which is wrong for
    # anything that trusts the semantic layer to say where a thing is, clicks
    # included.
    {pin_x, pin_y} = state.frame.pin.point
    {scroll_tx, scroll_ty} = Widgex.Scroll.ScrollState.translate_offset(state.scroll)
    offset_x = pin_x + scroll_tx
    offset_y = pin_y + scroll_ty

    Logger.debug("🔍 SideNav attempting semantic registration...")
    Logger.debug("   Viewport has semantic_table? #{inspect(!!viewport.semantic_table)}")
    Logger.debug("   Semantic enabled? #{inspect(viewport.semantic_enabled)}")
    Logger.debug("   Component offset: (#{offset_x}, #{offset_y})")
    Logger.debug("   Item bounds count: #{inspect(map_size(state.item_bounds))}")

    # Only register if semantic tables are available
    if viewport.semantic_table && viewport.semantic_enabled do
      # Register chevrons and text for each visible item
      state.item_bounds
      |> Enum.each(fn {item_id, bounds} ->
        item = Item.find_by_id(state.tree, item_id)

        if item do
          has_children = Item.has_children?(item)
          theme = state.theme

          # Calculate positions matching render_item logic
          depth = bounds.depth
          indent_x = theme.padding_left + depth * theme.indent
          chevron_area_width = theme.chevron_size + theme.chevron_margin

          # Register chevron (if item has children)
          if has_children do
            chevron_id = String.to_atom("chevron_#{item_id}")

            # Local bounds (within component)
            local_left = indent_x
            local_top = bounds.y

            # Screen bounds (add component offset)
            screen_left = offset_x + local_left
            screen_top = offset_y + local_top

            chevron_entry = %Scenic.Semantic.Compiler.Entry{
              id: chevron_id,
              type: :button,
              module: nil,
              parent_id: nil,
              children: [],
              local_bounds: %{
                left: local_left,
                top: local_top,
                width: theme.chevron_size,
                height: theme.item_height
              },
              screen_bounds: %{
                left: screen_left,
                top: screen_top,
                width: theme.chevron_size,
                height: theme.item_height
              },
              clickable: true,
              focusable: false,
              label: "Chevron for #{Item.get_title(item)}",
              role: :toggle,
              value: nil,
              hidden: false,
              z_index: 0
            }

            :ets.insert(viewport.semantic_table, {{scene_name, chevron_id}, chevron_entry})
            :ets.insert(viewport.semantic_index, {chevron_id, {scene_name, chevron_id}})

            Logger.debug(
              "     ✅ Registered chevron: #{chevron_id} at screen (#{screen_left}, #{screen_top})"
            )
          end

          # Register item text
          text_id = String.to_atom("item_text_#{item_id}")

          # Text starts after chevron area
          local_text_left = indent_x + chevron_area_width
          local_text_top = bounds.y
          text_width = bounds.width - chevron_area_width

          # Screen bounds
          screen_text_left = offset_x + local_text_left
          screen_text_top = offset_y + local_text_top

          text_entry = %Scenic.Semantic.Compiler.Entry{
            id: text_id,
            type: :text,
            module: nil,
            parent_id: nil,
            children: [],
            local_bounds: %{
              left: local_text_left,
              top: local_text_top,
              width: text_width,
              height: theme.item_height
            },
            screen_bounds: %{
              left: screen_text_left,
              top: screen_text_top,
              width: text_width,
              height: theme.item_height
            },
            clickable: true,
            focusable: false,
            label: Item.get_title(item),
            role: :link,
            value: nil,
            hidden: false,
            z_index: 0
          }

          :ets.insert(viewport.semantic_table, {{scene_name, text_id}, text_entry})
          :ets.insert(viewport.semantic_index, {text_id, {scene_name, text_id}})
        end
      end)

      Logger.debug("✅ SideNav semantic registration complete!")
    else
      Logger.warning("⚠️  SideNav semantic registration skipped - semantic tables not available")
    end

    :ok
  end
end
