defmodule ScenicWidgets.IconMenu do
  @moduledoc """
  A compact icon-based menu bar with dropdown menus.

  Displays a row of icon buttons (single characters like letters or symbols).
  Clicking an icon opens a dropdown menu below it. Perfect for toolbars
  that sit next to a tab bar.

  ## Features
  - Compact icon buttons (letters, symbols, emoji as icons)
  - Dropdown menus on click
  - Hover highlighting
  - Menu item callbacks
  - Keyboard navigation (Escape to close)

  ## Usage

      menus = [
        %{id: :file, icon: "F", items: [
          {"new", "New File"},
          {"open", "Open..."},
          {"save", "Save"}
        ]},
        %{id: :edit, icon: "E", items: [
          {"undo", "Undo"},
          {"redo", "Redo"}
        ]}
      ]

      graph
      |> ScenicWidgets.IconMenu.add_to_graph(
        %{frame: frame, menus: menus},
        id: :my_icon_menu
      )

  ## Events

  IconMenu sends these events to the parent scene:
  - `{:menu_item_clicked, item_id}` - When a menu item is clicked

  Handle in your scene:

      def handle_event({:menu_item_clicked, "new"}, _from, scene) do
        # Handle "New File" action
        {:noreply, scene}
      end

  ## Theme Customization

  Pass a `:theme` map to override defaults:

      %{
        frame: frame,
        menus: menus,
        theme: %{
          icon_button_size: 40,
          dropdown_width: 200
        }
      }
  """

  use Scenic.Component, has_children: false
  require Logger

  alias ScenicWidgets.IconMenu.{State, Reducer, Renderer}
  alias Scenic.Graph

  @impl Scenic.Component
  def validate(%Widgex.Frame{} = frame) do
    {:ok, %{frame: frame, menus: State.demo_menus()}}
  end

  def validate(%{frame: %Widgex.Frame{}} = data) do
    {:ok, data}
  end

  def validate(%{frame: %{pin: _, size: _}} = data) do
    {:ok, data}
  end

  def validate(_) do
    {:error, "IconMenu requires :frame (Widgex.Frame) and optional :menus list"}
  end

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    state = State.new(data)
    graph = Renderer.initial_render(Graph.build(), state)

    scene =
      scene
      |> assign(state: state, graph: graph, tooltip_timer: nil, tooltip_token: nil)
      |> push_graph(graph)

    # Request input for mouse and keyboard interaction
    request_input(scene, [:cursor_pos, :cursor_button, :key])

    # Register semantic elements for MCP automation
    register_semantic_elements(scene, state)

    {:ok, scene}
  end

  @impl Scenic.Scene
  def handle_input(input, _context, scene) do
    state = scene.assigns.state
    result = Reducer.process_input(state, input)
    {result, scene} = track_tooltip(result, input, scene)

    case result do
      {:noop, ^state} ->
        # No change
        {:noreply, scene}

      {:noop, new_state} ->
        # Internal state changed (hover, menu open/close)
        update_scene(scene, state, new_state)

      {:menu_item_clicked, item_id, new_state} ->
        send_parent_event(scene, {:menu_item_clicked, item_id})
        update_scene(scene, state, new_state)

      {:menu_value_changed, item_id, value, new_state} ->
        send_parent_event(scene, {:menu_value_changed, item_id, value})
        update_scene(scene, state, new_state)
    end
  end

  @impl true
  def handle_info(
        {:show_menu_tooltip, token, text, anchor},
        %{assigns: %{tooltip_token: token}} = scene
      ) do
    state = scene.assigns.state
    new_state = %{state | tooltip: %{text: text, at: anchor}}
    graph = Renderer.initial_render(Graph.build(), new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph, tooltip_timer: nil)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_info({:show_menu_tooltip, _token, _text, _anchor}, scene), do: {:noreply, scene}

  @impl Scenic.Scene
  def handle_put({:open_menu, menu_id}, scene) do
    state = scene.assigns.state
    new_state = %{state | active_menu: menu_id}
    update_scene_tuple(scene, state, new_state)
  end

  def handle_put({:close_menu}, scene) do
    scene = cancel_tooltip_timer(scene)
    state = scene.assigns.state
    new_state = %{state | active_menu: nil, hovered_item: nil, tooltip: nil}
    update_scene_tuple(scene, state, new_state)
  end

  def handle_put(:clear_hover, scene) do
    scene = cancel_tooltip_timer(scene)
    state = scene.assigns.state

    update_scene_tuple(scene, state, %{
      state
      | hovered_menu: nil,
        hovered_item: nil,
        tooltip: nil
    })
  end

  # Update menus (e.g., to change toggle states)
  def handle_put({:update_menus, menus}, scene) do
    state = scene.assigns.state
    new_state = %{state | menus: menus}
    new_state = %{new_state | dropdown_bounds: State.calculate_dropdown_bounds(new_state)}

    # Re-render from scratch to reflect menu changes
    graph = Renderer.initial_render(Graph.build(), new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_put({:update_frame, frame}, scene) do
    state = scene.assigns.state
    new_state = %{state | frame: frame}
    new_state = %{new_state | dropdown_bounds: State.calculate_dropdown_bounds(new_state)}
    graph = Renderer.initial_render(Graph.build(), new_state)

    scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
    register_semantic_elements(scene, new_state)
    {:noreply, scene}
  end

  def handle_put({:show_shortcuts, show?}, scene) when is_boolean(show?) do
    state = scene.assigns.state

    if state.show_shortcuts == show? do
      {:noreply, scene}
    else
      new_state = %{state | show_shortcuts: show?}
      new_state = %{new_state | dropdown_bounds: State.calculate_dropdown_bounds(new_state)}
      graph = Renderer.initial_render(Graph.build(), new_state)

      scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
      notify_dropdown_state(scene, state, new_state)
      {:noreply, scene}
    end
  end

  def handle_put(_msg, scene) do
    {:noreply, scene}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Tell the parent when a dropdown opens or closes.
  #
  # A dropdown renders ABOVE sibling components, but sibling components that
  # request positional input non-positionally still receive clicks meant for
  # it. Without this signal they can only guess (badly) from geometry
  # whether a click was theirs. Emitted from the single place every menu
  # transition passes through, so open/close can never be missed.
  defp notify_dropdown_state(
         scene,
         %{active_menu: same, dropdown_bounds: bounds},
         %{active_menu: same, dropdown_bounds: bounds}
       ),
       do: scene

  defp notify_dropdown_state(scene, _old_state, %{active_menu: nil}) do
    send_parent_event(scene, {:dropdown_closed})
    scene
  end

  defp notify_dropdown_state(scene, _old_state, %{active_menu: menu_id} = new_state) do
    # Send the dropdown's BOUNDS, not just "a menu is open". A consumer that
    # only knows "open" has to ignore every click while it is set, so a
    # single missed close event makes the whole UI beneath it unclickable.
    # With bounds, a stale state can only ever affect the dropdown's own area.
    bounds = Map.get(new_state.dropdown_bounds || %{}, menu_id)
    send_parent_event(scene, {:dropdown_opened, menu_id, bounds})
    scene
  end

  defp update_scene(scene, old_state, new_state) do
    graph = Renderer.update_render(scene.assigns.graph, old_state, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    notify_dropdown_state(scene, old_state, new_state)

    {:noreply, scene}
  end

  defp update_scene_tuple(scene, old_state, new_state) do
    graph = Renderer.update_render(scene.assigns.graph, old_state, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    notify_dropdown_state(scene, old_state, new_state)

    {:noreply, scene}
  end

  defp track_tooltip(result, {:cursor_pos, _coords}, scene) do
    state = result_state(result)
    scene = cancel_tooltip_timer(scene)
    state = %{state | tooltip: nil}

    case {tooltip_text(state), tooltip_anchor(state)} do
      {text, anchor} when is_binary(text) and text != "" and not is_nil(anchor) ->
        token = make_ref()

        timer =
          Process.send_after(
            self(),
            {:show_menu_tooltip, token, text, anchor},
            state.tooltip_delay_ms
          )

        {replace_result_state(result, state),
         assign(scene, tooltip_timer: timer, tooltip_token: token)}

      _ ->
        {replace_result_state(result, state), assign(scene, tooltip_token: nil)}
    end
  end

  defp track_tooltip(result, {:cursor_button, _}, scene) do
    state = %{result_state(result) | tooltip: nil}
    {replace_result_state(result, state), cancel_tooltip_timer(scene)}
  end

  defp track_tooltip(result, _input, scene), do: {result, scene}

  defp tooltip_text(%State{hovered_item: item_id} = state) when not is_nil(item_id) do
    state |> State.find_item(item_id) |> State.item_tooltip()
  end

  defp tooltip_text(%State{hovered_menu: menu_id, menus: menus}) when not is_nil(menu_id) do
    menus |> Enum.find(&(&1.id == menu_id)) |> State.menu_tooltip()
  end

  defp tooltip_text(_state), do: nil

  defp tooltip_anchor(%State{hovered_item: item_id, active_menu: menu_id} = state)
       when not is_nil(item_id) and not is_nil(menu_id) do
    case get_in(state.dropdown_bounds, [menu_id, :items, item_id]) do
      %{x: x, y: y, height: height} -> {x, y + height}
      _ -> nil
    end
  end

  defp tooltip_anchor(%State{hovered_menu: menu_id} = state) when not is_nil(menu_id) do
    case State.get_icon_button_bounds(state, menu_id) do
      {x, y, _width, height} -> {x, y + height}
      _ -> nil
    end
  end

  defp tooltip_anchor(_state), do: nil

  defp cancel_tooltip_timer(%{assigns: %{tooltip_timer: timer}} = scene)
       when is_reference(timer) do
    Process.cancel_timer(timer)
    assign(scene, tooltip_timer: nil, tooltip_token: nil)
  end

  defp cancel_tooltip_timer(scene), do: scene

  defp result_state({:noop, state}), do: state
  defp result_state({:menu_item_clicked, _id, state}), do: state
  defp result_state({:menu_value_changed, _id, _value, state}), do: state

  defp replace_result_state({:noop, _}, state), do: {:noop, state}

  defp replace_result_state({:menu_item_clicked, id, _}, state),
    do: {:menu_item_clicked, id, state}

  defp replace_result_state({:menu_value_changed, id, value, _}, state),
    do: {:menu_value_changed, id, value, state}

  # ===========================================================================
  # Semantic Registration (for MCP automation/testing)
  # ===========================================================================

  defp register_semantic_elements(scene, %State{} = state) do
    viewport = scene.viewport
    scene_name = scene.assigns[:id] || :icon_menu

    # Get offset from frame pin (this is where the component is translated to)
    {offset_x, offset_y} = state.frame.pin.point

    # Get theme values
    button_size = Map.get(state.theme, :icon_button_size, 40)

    # Get the alignment offset (for right-aligned menus, icons start from the right)
    x_offset = State.alignment_offset(state)

    # Only register if semantic tables are available
    unless viewport.semantic_table && viewport.semantic_enabled do
      :ok
    else
      # Register each menu icon button using the same positioning as rendering
      state.menus
      |> Enum.with_index()
      |> Enum.each(fn {menu, index} ->
        # Calculate button position (same as rendering)
        button_x = x_offset + index * button_size
        button_y = 0

        # Create semantic ID like "icon_menu_file" for the menu icon
        menu_id_str = Atom.to_string(menu.id)
        semantic_id = String.to_atom("icon_menu_#{menu_id_str}")

        # Register the icon button (convert local to screen coordinates)
        register_button(
          viewport,
          scene_name,
          semantic_id,
          Map.get(menu, :label, humanize(menu.id)),
          offset_x + button_x,
          offset_y + button_y,
          button_size,
          button_size
        )

        # Register menu items using the pre-calculated dropdown bounds
        case Map.get(state.dropdown_bounds, menu.id) do
          nil ->
            :ok

          dropdown ->
            Enum.each(dropdown.items, fn {item_id, item_bounds} ->
              # Get the label from the menu items
              item_label = find_item_label(menu.items, item_id)

              # Convert local bounds to screen coordinates
              screen_x = offset_x + item_bounds.x
              screen_y = offset_y + item_bounds.y

              register_menu_item(
                viewport,
                scene_name,
                item_id,
                item_label,
                menu_id_str,
                screen_x,
                screen_y,
                item_bounds.width,
                item_bounds.height
              )
            end)
        end
      end)

      :ok
    end
  end

  defp humanize(id), do: id |> Atom.to_string() |> String.capitalize()

  # Find the label for a menu item by its ID
  defp find_item_label(items, item_id) do
    Enum.find_value(items, item_id, fn
      {id, label} when id == item_id -> label
      {id, label, _opts} when id == item_id -> label
      %{id: id, label: label} when id == item_id -> label
      _ -> nil
    end)
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

  defp register_menu_item(viewport, scene_name, item_id, item_label, menu_id_str, x, y, w, h) do
    # Create semantic ID like "icon_menu_file_new"
    semantic_id = String.to_atom("icon_menu_#{menu_id_str}_#{item_id}")

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
      value: item_id,
      # Will be visible when dropdown is open
      hidden: false,
      z_index: 10
    }

    :ets.insert(viewport.semantic_table, {{scene_name, semantic_id}, entry})
    :ets.insert(viewport.semantic_index, {semantic_id, {scene_name, semantic_id}})
  end
end
