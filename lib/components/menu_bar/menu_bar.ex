defmodule ScenicWidgets.MenuBar do
  @moduledoc """
  A menu bar component with dropdown menus, following the renderizer pattern.
  This component avoids flickering by pre-rendering all dropdowns and toggling visibility.

  ## Features
  - Click to open/close dropdowns
  - Hover-to-switch between open menus
  - Nested sub-menus with smooth navigation
  - Keyboard support (Escape to close)
  - Action callbacks for deterministic testing
  - MCP semantic element registration for automation

  ## Usage

      menu_map = [
        {:sub_menu, "File", [
          {"new_file", "New File"},
          {"open_file", "Open File"},
          {:sub_menu, "Recent Files", [
            {"recent_1", "Document 1.txt"},
            {"recent_2", "Project Notes.md"}
          ]},
          {"save", "Save"}
        ]},
        {:sub_menu, "Edit", [
          {"undo", "Undo"},
          {"redo", "Redo"}
        ]}
      ]

      graph
      |> MenuBar.add_to_graph(
        %{
          frame: frame,
          menu_map: menu_map
        },
        id: :my_menu_bar
      )

  ## Menu Item Formats

  Menu items support two formats:

  ### 2-tuple format (Event-based)
      {"item_id", "Label"}

  When clicked, sends `{:menu_item_clicked, "item_id"}` event to parent scene.

  ### 3-tuple format (Action callback)
      {"item_id", "Label", fn -> IO.puts("Action!") end}

  When clicked, executes the function immediately AND sends the event to parent.
  This is useful for:
  - Deterministic testing (send message to test process)
  - Direct state updates
  - Logging/analytics

  Example with action callbacks:

      test_pid = self()
      menu_map = [
        {:sub_menu, "File", [
          {"new_file", "New File", fn ->
            send(test_pid, {:action, :new_file})
          end},
          {"save", "Save", fn ->
            save_document()
          end}
        ]}
      ]

  ## Events

  MenuBar sends these events to the parent scene:
  - `{:menu_item_clicked, item_id}` - When a menu item is clicked

  The parent scene handles these via `handle_event/3`:

      def handle_event({:menu_item_clicked, item_id}, _from, scene) do
        case item_id do
          "new_file" -> # Handle new file action
          "save" -> # Handle save action
          _ -> :ok
        end
        {:noreply, scene}
      end
  """
  use Scenic.Component, has_children: false
  require Logger

  alias ScenicWidgets.MenuBar.{State, OptimizedRenderizer, Reducer, Api}
  alias Scenic.Graph


  def validate(data) when is_map(data) do
    # Required: frame and menu_map
    case {Map.get(data, :frame), Map.get(data, :menu_map)} do
      {%{pin: _, size: _}, menu_map} when is_list(menu_map) ->
        # Convert old format [{:sub_menu, label, items}, ...] to new format
        converted_map = convert_menu_map(menu_map)
        {:ok, Map.put(data, :menu_map, converted_map)}
      {%{pin: _, size: _}, menu_map} when is_map(menu_map) ->
        {:ok, data}
      _ ->
        {:error, "MenuBar requires :frame and :menu_map"}
    end
  end

  # Convert old menu format to new format
  defp convert_menu_map(menu_list) when is_list(menu_list) do
    menu_list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {item, index}, acc ->
      case item do
        {:sub_menu, label, items} ->
          # Generate unique menu ID based on label and index
          menu_id = String.to_atom("menu_#{index}_#{String.downcase(String.replace(label, " ", "_"))}")
          # Convert items to ensure they're in the correct format
          converted_items = convert_menu_items(items)
          Map.put(acc, menu_id, {label, converted_items})
        {label, items} when is_binary(label) and is_list(items) ->
          # Also handle simple tuple format
          menu_id = String.to_atom("menu_#{index}_#{String.downcase(String.replace(label, " ", "_"))}")
          converted_items = convert_menu_items(items)
          Map.put(acc, menu_id, {label, converted_items})
        _ ->
          acc
      end
    end)
  end

  # Convert menu items to ensure they're in the correct {id, label} or {id, label, action} format
  defp convert_menu_items(items) when is_list(items) do
    Enum.map(items, fn item ->
      result = case item do
        # Already in 3-tuple format with action
        {id, label, action} when is_binary(id) and is_binary(label) and is_function(action, 0) ->
          item

        # Already in 2-tuple format {id, label}
        {id, label} when is_binary(id) and is_binary(label) ->
          item

        # 2-tuple format with function: {label, function} -> {id, label, function}
        # Use label as both ID and display text
        {label, action} when is_binary(label) and is_function(action, 0) ->
          # Generate ID from label
          id = label
               |> String.downcase()
               |> String.replace(~r/[^a-z0-9]+/, "_")
               |> String.trim("_")
          {id, label, action}

        # Sub-menu: recursively convert items
        {:sub_menu, label, sub_items} ->
          {:sub_menu, label, convert_menu_items(sub_items)}

        # Pass through anything else unchanged
        other ->
          Logger.warning("  - Unexpected format: #{inspect(other)}")
          other
      end
      result
    end)
  end

  @impl Scenic.Component
  def init(scene, data, _opts) do
    # Logger.debug("🎯 ScenicWidgets.MenuBar component initializing (regular MenuBar, NOT Enhanced)")
    # Logger.debug("MenuBar init called with data: #{inspect(data)}")

    # Initialize component state
    state = State.new(data)

    # Initial render with all elements pre-rendered
    graph = OptimizedRenderizer.initial_render(Graph.build(), state)

    scene =
      scene
      |> assign(state: state, graph: graph)
      |> push_graph(graph)

    # Request keyboard input for Escape key handling
    # Cursor input comes through hit testing on primitives, so we don't request it here
    request_input(scene, [:key])

    # Register semantic elements for MCP interaction
    register_semantic_elements(scene, state)

    # Logger.debug("MenuBar initialized successfully")

    {:ok, scene}

  end

  # @impl Scenic.Scene
  # def handle_put({:cursor_pos, coords}, scene) do
  #   Logger.debug("MenuBar received cursor_pos via handle_put: #{inspect(coords)}")
  #   state = scene.assigns.state

  #   # Update hover state
  #   new_state = Reducer.handle_cursor_pos(state, coords)

  #   scene = if new_state != state do
  #     Logger.debug("MenuBar state changed: active_menu #{state.active_menu} -> #{new_state.active_menu}")
  #     # Update only changed elements
  #     graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)

  #     scene
  #     |> assign(state: new_state, graph: graph)
  #     |> push_graph(graph)
  #   else
  #     scene
  #   end

  #   {:noreply, scene}
  # end

  # def handle_put({:click, coords}, scene) do
  #   Logger.debug("MenuBar received click via handle_put: #{inspect(coords)}")
  #   state = scene.assigns.state

  #   # Handle click
  #   scene = case Reducer.handle_click(state, coords) do
  #     {:menu_item_clicked, item_id, new_state} ->
  #       # Send event to parent
  #       send_parent_event(scene, {:menu_item_clicked, item_id})

  #       graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)

  #       scene
  #       |> assign(state: new_state, graph: graph)
  #       |> push_graph(graph)

  #     {:noop, new_state} ->
  #       graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)

  #       scene
  #       |> assign(state: new_state, graph: graph)
  #       |> push_graph(graph)
  #   end

  #   {:noreply, scene}
  # end

  def handle_put(:close_all_menus, scene) do
    # Logger.debug("MenuBar received :close_all_menus via handle_put")
    state = scene.assigns.state

    # Close all menus
    scene = if state.active_menu do
      # Release input capture when closing menus
      release_input(scene)

      new_state = %{state | active_menu: nil, hovered_item: nil, hovered_dropdown: nil, active_sub_menus: %{}}
      graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)

      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)
    else
      scene
    end

    {:noreply, scene}
  end

  def handle_put({:set_active_menu, menu_id}, scene) do
    # Logger.debug("MenuBar received {:set_active_menu, #{inspect(menu_id)}} via handle_put")
    state = scene.assigns.state
    new_state = Api.set_active_menu(state, menu_id)

    graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_put(_value, scene) do
    # Ignore unknown values
    {:noreply, scene}
  end

  def handle_input({:cursor_pos, coords}, _context, scene) do
    state = scene.assigns.state
    new_state = Reducer.handle_cursor_pos(state, coords)

    if new_state != state do
      # Handle input capture if menu closed due to cursor leaving area
      if state.active_menu != nil and new_state.active_menu == nil do
        Logger.debug("🎯 MenuBar: cursor_pos caused menu close at coords #{inspect(coords)}")
        release_input(scene)
      end

      graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)
      scene = scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)
      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  def handle_input({:cursor_button, {:btn_left, 1, [], coords}}, _context, scene) do
    Logger.debug("🎯 MenuBar: click at #{inspect(coords)}, active_menu=#{inspect(scene.assigns.state.active_menu)}")
    state = scene.assigns.state
    old_active_menu = state.active_menu

    case Reducer.handle_click(state, coords) do
      {:menu_item_clicked, item_id, new_state} ->
        Logger.debug("🎯 MenuBar: menu item clicked: #{inspect(item_id)}")
        # Menu closed - release input capture
        if old_active_menu != nil do
          release_input(scene)
        end

        # Send event to parent
        send_parent_event(scene, {:menu_item_clicked, item_id})

        # Update the graph
        graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)
        scene = scene
        |> assign(state: new_state, graph: graph)
        |> push_graph(graph)
        {:noreply, scene}

      {:noop, new_state} ->
        Logger.debug("🎯 MenuBar: noop, old_active=#{inspect(old_active_menu)}, new_active=#{inspect(new_state.active_menu)}")
        # Handle input capture transitions
        scene = handle_input_capture_transition(scene, old_active_menu, new_state.active_menu)

        graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)
        scene = scene
        |> assign(state: new_state, graph: graph)
        |> push_graph(graph)
        {:noreply, scene}
    end
  end

  # Handle capture/release based on menu open/close transitions
  defp handle_input_capture_transition(scene, nil, new_menu) when not is_nil(new_menu) do
    # Menu opened - capture input so clicks go to us, not underlying components
    Logger.debug("🎯 MenuBar: Capturing input for dropdown #{inspect(new_menu)}")
    :ok = capture_input(scene, [:cursor_button, :cursor_pos])
    scene
  end

  defp handle_input_capture_transition(scene, old_menu, nil) when not is_nil(old_menu) do
    # Menu closed - release input capture
    Logger.debug("🎯 MenuBar: Releasing input capture (menu #{inspect(old_menu)} closed)")
    :ok = release_input(scene)
    scene
  end

  defp handle_input_capture_transition(scene, _old, _new) do
    # No transition (both nil or both non-nil) - no change needed
    scene
  end

  def handle_input({:key, {:key_esc, 1, _}}, _context, scene) do
    state = scene.assigns.state
    new_state = Reducer.handle_escape(state)

    if new_state != state do
      # Menu closed via Escape - release input capture
      if state.active_menu != nil and new_state.active_menu == nil do
        release_input(scene)
      end

      graph = OptimizedRenderizer.update_render(scene.assigns.graph, state, new_state)
      scene = scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)
      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  # Helper to register semantic elements for MCP
  defp register_semantic_elements(scene, %State{} = state) do
    viewport = scene.viewport
    scene_name = scene.assigns[:id] || :menu_bar

    # Get offset from frame pin
    {offset_x, offset_y} = state.frame.pin.point

    # Get theme values (with defaults matching optimized_renderizer)
    menu_height = Map.get(state.theme, :menu_height, 40)
    item_height = Map.get(state.theme, :item_height, 30)
    item_width = Map.get(state.theme, :item_width, 150)
    dropdown_padding = Map.get(state.theme, :padding, 5)

    # Only register if semantic tables are available
    unless viewport.semantic_table && viewport.semantic_enabled do
      :ok
    else
      # Register each menu header button as a clickable semantic element
      state.menu_map
      |> Enum.with_index()
      |> Enum.each(fn {{menu_id, {label, items}}, index} ->
        # Calculate bounds for this menu header
        local_x = index * item_width
        local_y = 0

        # Create semantic ID like "menu_file" for the menu header
        menu_label = label |> String.downcase() |> String.replace(" ", "_")
        semantic_id = String.to_atom("menu_#{menu_label}")

        # Register the menu header button
        register_button(viewport, scene_name, semantic_id, label,
          offset_x + local_x, offset_y + local_y, item_width, menu_height)

        # Also register menu items (for when dropdown is open)
        # Dropdown is translated to y = menu_height, items start at padding
        items
        |> Enum.with_index()
        |> Enum.each(fn {item, item_index} ->
          # Item y position: menu_height + padding + (index * item_height)
          item_y = offset_y + menu_height + dropdown_padding + (item_index * item_height)

          case item do
            {item_id, item_label} when is_binary(item_id) and is_binary(item_label) ->
              register_menu_item(viewport, scene_name, item_id, item_label, menu_label,
                offset_x + local_x, item_y, item_width, item_height)

            {item_id, item_label, _action} when is_binary(item_id) and is_binary(item_label) ->
              register_menu_item(viewport, scene_name, item_id, item_label, menu_label,
                offset_x + local_x, item_y, item_width, item_height)

            {:sub_menu, _sub_label, _sub_items} ->
              # TODO: Register sub-menu items recursively
              :ok

            _ ->
              :ok
          end
        end)
      end)

      Logger.debug("✅ MenuBar semantic registration complete")
      :ok
    end
  end

  defp register_button(viewport, scene_name, id, label, x, y, w, h) do
    entry = %Scenic.Semantic.Compiler.Entry{
      id: id,
      type: :button,
      module: nil,
      parent_id: nil,
      children: [],
      local_bounds: %{left: x, top: y, width: w, height: h},
      screen_bounds: %{left: x, top: y, width: w, height: h},
      clickable: true,
      focusable: false,
      label: label,
      role: :button,
      value: nil,
      hidden: false,
      z_index: 0
    }
    :ets.insert(viewport.semantic_table, {{scene_name, id}, entry})
    :ets.insert(viewport.semantic_index, {id, {scene_name, id}})
  end

  defp register_menu_item(viewport, scene_name, item_id, item_label, menu_label, x, y, w, h) do
    # Create semantic ID like "menu_file_new_tidbit"
    semantic_id = String.to_atom("menu_#{menu_label}_#{item_id}")

    entry = %Scenic.Semantic.Compiler.Entry{
      id: semantic_id,
      type: :menuitem,
      module: nil,
      parent_id: nil,
      children: [],
      local_bounds: %{left: x, top: y, width: w, height: h},
      screen_bounds: %{left: x, top: y, width: w, height: h},
      clickable: true,
      focusable: false,
      label: item_label,
      role: :menuitem,
      value: nil,
      hidden: false,
      z_index: 1
    }
    :ets.insert(viewport.semantic_table, {{scene_name, semantic_id}, entry})
    :ets.insert(viewport.semantic_index, {semantic_id, {scene_name, semantic_id}})
  end

  # Remove handle_cast - we're using handle_put for state updates now
end
