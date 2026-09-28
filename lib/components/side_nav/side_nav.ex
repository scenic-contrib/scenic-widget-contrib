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

  ## Inline rename

  Choosing Rename from the context menu opens a single-line text box on the
  row, pre-filled with the item's current name and the caret at its end — the
  name is the starting text, not a placeholder, so a rename that only changes
  one character costs one keystroke. Left/Right move the caret, Home/End jump
  to the ends, typing inserts at the caret, Backspace and Delete cut either
  side of it, Enter commits and Escape cancels. While the box is open it owns
  the keyboard, so the arrow keys do not also move the tree's selection.
  """

  use Scenic.Component, has_children: false
  require Logger

  alias ScenicWidgets.SideNav.{State, Renderizer, Reducer, Api, Item}
  alias Scenic.Graph
  alias Widgex.Scroll.{Drag, ScrollState}

  # Pointer travel, in pixels, before a press becomes a drag rather than a click.
  @drag_threshold 6

  # How long the pointer must rest on a collapsed directory before it springs
  # open. Long enough not to fire while merely crossing a folder on the way
  # somewhere else; short enough not to feel stuck.
  @auto_expand_ms 550

  # Height of the strip at the top and bottom of the pane that scrolls while a
  # drag hovers in it, and how fast — from just-perceptible at the outer edge of
  # the strip to brisk at the very edge of the pane.
  @drag_scroll_zone 28
  @drag_scroll_tick_ms 33
  @drag_scroll_min_step 3
  @drag_scroll_max_step 18

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

  @doc """
  Repaint with new theme keys, merged over the current theme.

  A colour scheme can change while the tree is on screen, and rebuilding the
  component to apply it would throw away the expanded folders, the selection
  and the scroll offset — the very thing that made the navigator feel broken
  when a status toast rebuilt it.
  """
  # Through the API rather than a bare merge: a theme that changes the row
  # height has to lay the rows out again, or the labels grow at the next zoom
  # and the rows they sit in do not.
  def handle_put({:set_theme, theme}, scene) when is_map(theme) do
    state = scene.assigns.state
    new_state = Api.update_theme(state, theme)
    graph = Renderizer.initial_render(Graph.build(), new_state)

    scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
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

  def handle_put(:clear_hover, scene) do
    state = scene.assigns.state
    new_state = %{state | hovered_id: nil}
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
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

    {:noreply, assign(scene, state: Drag.stop(scene.assigns.state))}
  end

  def handle_input(
        {:cursor_pos, {x, y}},
        _context,
        %{assigns: %{state: %State{drag_source: source}}} = scene
      )
      when not is_nil(source) do
    old_state = scene.assigns.state
    {start_x, start_y} = old_state.drag_start
    dragging = old_state.dragging or abs(x - start_x) + abs(y - start_y) >= @drag_threshold

    {drag_target, drop_valid} =
      if dragging, do: drop_target(old_state, {x, y}), else: {nil, false}

    new_state =
      old_state
      |> arm_auto_expand(dragging, drag_target)
      |> arm_auto_scroll(dragging, y)
      |> Map.merge(%{
        dragging: dragging,
        drag_target: drag_target,
        drop_valid: drop_valid,
        drag_pos: if(dragging, do: {x, y}, else: nil)
      })

    graph = Renderizer.update_render(scene.assigns.graph, old_state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  def handle_input(
        {:cursor_button, {:btn_left, 0, _mods, {x, y}}},
        _context,
        %{assigns: %{state: %State{drag_source: source}}} = scene
      )
      when not is_nil(source) do
    state = scene.assigns.state |> cancel_auto_expand() |> cancel_auto_scroll()
    :ok = release_input(scene, [:cursor_pos, :cursor_button])

    if state.dragging do
      # Hit-tested/captured component input is already in SideNav-local
      # coordinates. Subtracting the frame pin a second time makes drops near
      # the top miss the tree entirely.
      #
      # drop_target/2 rather than a raw hit_test, so that the same rules the
      # highlight was drawn from decide the drop — including empty space
      # resolving to :root_id. A green row that then refuses the drop is worse
      # than no highlight at all.
      case drop_target(state, {x, y}) do
        {target_id, true} when not is_nil(target_id) ->
          paths = MapSet.to_list(state.selected_ids)
          send_parent_event(scene, {:sidebar, :move_requested, paths, target_id})

        _ ->
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
        drag_pos: nil,
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

  # Cursor not over any row - clear hover.
  def handle_input({:cursor_pos, _coords}, _context, scene) do
    state = scene.assigns.state
    new_state = %{state | hovered_id: nil}

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

    # Inline rename is a one-task text input just like a dialog field. Merely
    # requesting codepoints loses to the editor's existing capture, leaving
    # the painted rename box active while every typed character goes nowhere.
    unless state.focused, do: send_parent_event(scene, {:focus_taken, :file_nav})
    :ok = capture_input(scene, [:key, :codepoint])

    new_state =
      %{state | context_menu: nil, focused: true}
      |> Reducer.start_rename(item_id)

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

    # This click gives the sidebar the keyboard. Clicks never reach the host —
    # they are positional, and they land here — so unless it is told, whatever
    # had the keyboard before keeps it, and the arrow keys then move the
    # sidebar selection AND the document cursor at the same time.
    unless state.focused, do: send_parent_event(scene, {:focus_taken, :file_nav})

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

  # All three delegate to Widgex.Scroll.Drag, which is where this belongs: the
  # geometry and the arithmetic were written here first, then again in
  # TextField, and SearchPane got the state fields with no code at all. Only
  # the input routing has to stay in a component, because that is what Scenic
  # delivers to.
  defp start_scrollbar_drag(scene, axis, coords) do
    :ok = capture_input(scene, [:cursor_pos, :cursor_button])
    {:noreply, assign(scene, state: Drag.start(scene.assigns.state, axis, coords))}
  end

  # The axis is already on the state, put there when the drag began.
  defp drag_scrollbar(scene, _axis, coords) do
    state = scene.assigns.state
    redraw_scroll(scene, Drag.move(state, state.frame, coords))
  end

  defp page_scrollbar(scene, axis, {x, y}) do
    state = scene.assigns.state
    pointer = if axis == :x, do: x, else: y
    redraw_scroll(scene, Drag.page(state, state.frame, axis, pointer))
  end

  defp redraw_scroll(scene, new_state) do
    state = scene.assigns.state
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)

    # Scrolling moves every row on screen, so the positions published to the
    # semantic layer are stale until re-registered.
    register_semantic_elements(scene, new_state)
    {:noreply, scene}
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

  # While the rename box is open it owns the keyboard: these clauses sit above
  # the tree's own arrow-key navigation, so Left/Right move the caret through
  # the name instead of moving the selection out from under it.
  def handle_input(
        {:key, {:key_backspace, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    update_rename(scene, &Reducer.rename_backspace/1)
  end

  def handle_input(
        {:key, {:key_delete, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    update_rename(scene, &Reducer.rename_delete/1)
  end

  def handle_input(
        {:key, {:key_left, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    update_rename(scene, &Reducer.rename_caret_left/1)
  end

  def handle_input(
        {:key, {:key_right, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    update_rename(scene, &Reducer.rename_caret_right/1)
  end

  def handle_input(
        {:key, {:key_home, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    update_rename(scene, &Reducer.rename_caret_home/1)
  end

  def handle_input(
        {:key, {:key_end, 1, _}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) do
    update_rename(scene, &Reducer.rename_caret_end/1)
  end

  def handle_input(
        {:codepoint, {codepoint, _mods}},
        _context,
        %{assigns: %{state: %State{renaming_id: id}}} = scene
      )
      when not is_nil(id) and is_binary(codepoint) do
    update_rename(scene, &Reducer.rename_insert(&1, codepoint))
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

  def handle_input(
        {:key, {:key_esc, 1, _}},
        _context,
        %{assigns: %{state: %State{drag_source: source}}} = scene
      )
      when not is_nil(source) do
    old_state = scene.assigns.state
    state = old_state |> cancel_auto_expand() |> cancel_auto_scroll()
    :ok = release_input(scene, [:cursor_pos, :cursor_button])

    new_state = %{
      state
      | drag_source: nil,
        drag_start: nil,
        drag_mods: [],
        dragging: false,
        drag_target: nil,
        drop_valid: false,
        drag_pos: nil
    }

    graph = Renderizer.update_render(scene.assigns.graph, old_state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  def handle_input({:key, {:key_esc, 1, _}}, _context, scene) do
    handle_keyboard(scene, &Reducer.handle_key_escape/1)
  end

  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  # Where would a drop at these coordinates land, and would it be allowed?
  #
  # Hitting no row at all is a real answer, not a miss: the space below the last
  # row belongs to the tree's own container, and dragging something out of a
  # subdirectory and back to the top level is otherwise impossible without a
  # root row to aim at. Parents that do not supply :root_id opt out.
  defp drop_target(%State{} = state, {x, y}) do
    case State.hit_test(state, {x, y}) do
      {target_id, _region} ->
        target = Item.find_by_id(state.tree, target_id)

        if target && Item.get_type(target) == :group do
          {target_id, valid_drop?(state, target_id)}
        else
          # A file is shown as a rejection rather than silently retargeting its
          # parent — the pointer is over something that cannot receive a drop.
          {target_id, false}
        end

      nil ->
        if state.root_id && inside_frame?(state, {x, y}) do
          {state.root_id, valid_drop?(state, state.root_id)}
        else
          {nil, false}
        end
    end
  end

  defp valid_drop?(%State{} = state, target_id) do
    MapSet.size(state.selected_ids) > 0 and
      Enum.all?(state.selected_ids, fn source ->
        # Already sitting in the target. Easy to do by accident once empty space
        # is a drop zone, and the move would only bounce back as an error.
        source != target_id and
          not descendant_path?(target_id, source) and
          Path.dirname(source) != target_id
      end)
  end

  defp inside_frame?(%State{frame: frame}, {x, y}) do
    x >= 0 and x <= frame.size.width and y >= 0 and y <= frame.size.height
  end

  # --- spring-loaded folders -------------------------------------------------
  #
  # Resting the pointer over a collapsed directory opens it, so a drag can reach
  # into a subtree it started outside of. Without this a drop can only ever land
  # somewhere that happened to be expanded before the drag began.

  defp arm_auto_expand(state, false, _target_id), do: cancel_auto_expand(state)
  defp arm_auto_expand(state, true, nil), do: cancel_auto_expand(state)
  defp arm_auto_expand(%{drag_hover_id: same} = state, true, same), do: state

  defp arm_auto_expand(state, true, target_id) do
    state = cancel_auto_expand(state)
    target = Item.find_by_id(state.tree, target_id)

    # `target` is nil for :root_id, which is a legitimate drop target with no
    # row of its own — and there is nothing to spring open in that case.
    springable? =
      not is_nil(target) and Item.get_type(target) == :group and
        not MapSet.member?(state.expanded, target_id)

    if springable? do
      timer = Process.send_after(self(), {:drag_auto_expand, target_id}, @auto_expand_ms)
      %{state | drag_hover_id: target_id, drag_hover_timer: timer}
    else
      %{state | drag_hover_id: target_id}
    end
  end

  defp cancel_auto_expand(%{drag_hover_timer: nil} = state),
    do: %{state | drag_hover_id: nil}

  defp cancel_auto_expand(state) do
    Process.cancel_timer(state.drag_hover_timer)
    %{state | drag_hover_id: nil, drag_hover_timer: nil}
  end

  # --- edge auto-scroll ------------------------------------------------------
  #
  # The pointer is holding a drag, so the wheel is not available to bring the
  # rest of the tree into view. Sitting in the top or bottom strip scrolls
  # instead, faster the further in you push.

  defp arm_auto_scroll(state, false, _y), do: cancel_auto_scroll(state)

  defp arm_auto_scroll(state, true, y) do
    cond do
      edge_scroll_step(state, y) == 0 -> cancel_auto_scroll(state)
      state.drag_scroll_timer != nil -> state
      true -> %{state | drag_scroll_timer: schedule_drag_scroll()}
    end
  end

  defp cancel_auto_scroll(%{drag_scroll_timer: nil} = state), do: state

  defp cancel_auto_scroll(state) do
    Process.cancel_timer(state.drag_scroll_timer)
    %{state | drag_scroll_timer: nil}
  end

  defp schedule_drag_scroll,
    do: Process.send_after(self(), :drag_auto_scroll, @drag_scroll_tick_ms)

  # Pixels to move per tick, signed: negative scrolls back toward the top.
  # Zero means the pointer is not in either edge strip.
  defp edge_scroll_step(%State{frame: frame}, y) do
    bottom_edge = frame.size.height - @drag_scroll_zone

    cond do
      y < @drag_scroll_zone -> -ramp(@drag_scroll_zone - y)
      y > bottom_edge -> ramp(y - bottom_edge)
      true -> 0
    end
  end

  defp ramp(depth) do
    depth
    |> max(0)
    |> min(@drag_scroll_zone)
    |> Kernel./(@drag_scroll_zone)
    |> Kernel.*(@drag_scroll_max_step - @drag_scroll_min_step)
    |> Kernel.+(@drag_scroll_min_step)
    |> round()
  end

  @impl GenServer
  def handle_info({:drag_auto_expand, item_id}, scene) do
    old_state = scene.assigns.state

    # The pointer may have moved on, or the drag ended, between the timer being
    # set and it firing.
    if old_state.dragging and old_state.drag_hover_id == item_id do
      new_state = %{State.expand(old_state, item_id) | drag_hover_timer: nil}
      graph = Renderizer.update_render(scene.assigns.graph, old_state, new_state)

      scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)

      # Rows below the newly opened folder have all moved down.
      register_semantic_elements(scene, new_state)
      send_parent_event(scene, {:sidebar, :expand, item_id})

      {:noreply, scene}
    else
      {:noreply, assign(scene, state: %{old_state | drag_hover_timer: nil})}
    end
  end

  def handle_info(:drag_auto_scroll, scene) do
    old_state = %{scene.assigns.state | drag_scroll_timer: nil}

    step =
      case {old_state.dragging, old_state.drag_pos} do
        {true, {_x, y}} -> edge_scroll_step(old_state, y)
        _ -> 0
      end

    case step != 0 && Reducer.drag_scroll(old_state, step) do
      {:scroll_changed, scrolled} ->
        # The tree slid under a stationary pointer, so what it is pointing at
        # has changed. Recompute rather than leave the highlight on the row that
        # used to be there.
        {drag_target, drop_valid} = drop_target(scrolled, old_state.drag_pos)

        new_state =
          scrolled
          |> arm_auto_expand(true, drag_target)
          |> Map.merge(%{
            drag_target: drag_target,
            drop_valid: drop_valid,
            drag_scroll_timer: schedule_drag_scroll()
          })

        graph = Renderizer.update_render(scene.assigns.graph, old_state, new_state)
        {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}

      _ ->
        # Drag over, pointer left the strip, or the content will not move any
        # further — stop ticking rather than spin. A later cursor_pos re-arms.
        {:noreply, assign(scene, state: old_state)}
    end
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

  defp update_rename(scene, edit_fn) do
    state = scene.assigns.state
    new_state = edit_fn.(state)
    graph = Renderizer.update_render(scene.assigns.graph, state, new_state)
    {:noreply, scene |> assign(state: new_state, graph: graph) |> push_graph(graph)}
  end

  defp finish_rename(scene) do
    state = scene.assigns.state
    :ok = release_input(scene, [:key, :codepoint])

    new_state = %{state | renaming_id: nil, rename_value: "", rename_caret: 0}

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
