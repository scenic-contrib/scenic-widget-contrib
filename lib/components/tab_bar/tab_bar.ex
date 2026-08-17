defmodule ScenicWidgets.TabBar do
  @moduledoc """
  A horizontal tab bar component with VS Code-style appearance.

  ## Features
  - Horizontal scrolling when tabs overflow
  - Close buttons on individual tabs
  - Selection indicator (colored bottom stripe)
  - Hover highlighting
  - Dynamic tab width based on label length

  ## Usage

      tabs = [
        %{id: :file1, label: "main.ex"},
        %{id: :file2, label: "README.md"},
        %{id: :file3, label: "mix.exs", closeable: false}
      ]

      graph
      |> ScenicWidgets.TabBar.add_to_graph(
        %{frame: frame, tabs: tabs},
        id: :my_tab_bar
      )

  ## Events

  TabBar sends these events to the parent scene:
  - `{:tab_selected, tab_id}` - When a tab is clicked/selected
  - `{:tab_closed, tab_id}` - When a tab's close button is clicked

  Handle in your scene:

      def handle_event({:tab_selected, tab_id}, _from, scene) do
        # Switch to the selected tab's content
        {:noreply, scene}
      end

      def handle_event({:tab_closed, tab_id}, _from, scene) do
        # Handle tab closure (e.g., close file, prompt to save)
        {:noreply, scene}
      end

  ## Theme Customization

  Pass a `:theme` map to override defaults:

      %{
        frame: frame,
        tabs: tabs,
        theme: %{
          selection_indicator_color: {255, 100, 0},  # Orange indicator
          height: 40
        }
      }
  """

  use Scenic.Component, has_children: false
  require Logger

  alias ScenicWidgets.TabBar.{State, Reducer, Renderer}
  alias Scenic.Graph

  # Sample tabs for Widget Workbench demo
  @demo_tabs [
    %{id: :tab1, label: "main.ex"},
    %{id: :tab2, label: "lib/components/tab_bar.ex"},
    %{id: :tab3, label: "README.md"},
    %{id: :tab4, label: "mix.exs", closeable: false},
    %{id: :tab5, label: "config/config.exs"},
    %{id: :tab6, label: "test/tab_bar_test.exs"},
    %{id: :tab7, label: "very_long_filename_that_should_truncate.ex"}
  ]

  @impl Scenic.Component
  def validate(%Widgex.Frame{} = frame) do
    # Widget Workbench passes bare frame - add demo tabs
    {:ok, %{frame: frame, tabs: @demo_tabs}}
  end

  def validate(%{frame: %Widgex.Frame{}} = data) do
    {:ok, data}
  end

  def validate(%{frame: %{pin: _, size: _}} = data) do
    {:ok, data}
  end

  def validate(_) do
    {:error, "TabBar requires :frame (Widgex.Frame) and optional :tabs list"}
  end

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    state = State.new(data)
    graph = Renderer.initial_render(Graph.build(), state)

    scene =
      scene
      |> assign(state: state, graph: graph)
      |> push_graph(graph)

    # Request input for mouse interaction
    request_input(scene, [:cursor_pos, :cursor_button, :cursor_scroll])

    # Register semantic elements so ScenicMCP click_element can find individual tabs
    register_semantic_elements(scene, state)

    {:ok, scene}
  end

  @impl Scenic.Scene
  def handle_input(input, _context, scene) do
    state = scene.assigns.state

    case Reducer.process_input(state, input) do
      {:noop, ^state} ->
        # No change
        {:noreply, scene}

      {:noop, new_state} ->
        # Internal state changed (hover, scroll)
        update_scene(scene, state, new_state)

      {:tabs_dragged, new_state} ->
        graph = Renderer.initial_render(Graph.build(), new_state)
        scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
        register_semantic_elements(scene, new_state)
        {:noreply, scene}

      {:tab_selected, tab_id, new_state} ->
        send_parent_event(scene, {:tab_selected, tab_id})
        update_scene(scene, state, new_state)

      {:tab_closed, tab_id, _new_state} ->
        # Don't apply the reducer's optimistic tab removal — the parent owns the
        # authoritative buffer list and may decide NOT to close (e.g. show an
        # "unsaved changes" dialog). Let the parent drive the visual close via
        # its own state update (which triggers a rebuild) or via an explicit
        # `put({:close_tab, tab_id}, ...)` message.
        send_parent_event(scene, {:tab_closed, tab_id})
        {:noreply, scene}

      {:tabs_reordered, tab_ids, new_state} ->
        send_parent_event(scene, {:tabs_reordered, tab_ids})
        graph = Renderer.initial_render(Graph.build(), new_state)
        scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
        register_semantic_elements(scene, new_state)
        {:noreply, scene}
    end
  end

  @impl Scenic.Scene
  def handle_put({:add_tab, tab}, scene) do
    state = scene.assigns.state

    case Reducer.add_tab(state, tab) do
      {:tab_added, _tab_id, new_state} ->
        graph = Renderer.initial_render(Graph.build(), new_state)

        scene =
          scene
          |> assign(state: new_state, graph: graph)
          |> push_graph(graph)

        # Re-register after tab list change
        register_semantic_elements(scene, new_state)
        {:noreply, scene}
    end
  end

  def handle_put({:select_tab, tab_id}, scene) do
    state = scene.assigns.state

    case Reducer.select_tab(state, tab_id) do
      {:noop, ^state} ->
        {:noreply, scene}

      {:tab_selected, _tab_id, new_state} ->
        update_scene_tuple(scene, state, new_state)
    end
  end

  def handle_put({:close_tab, tab_id}, scene) do
    state = scene.assigns.state

    case Reducer.close_tab(state, tab_id) do
      {:noop, ^state} ->
        {:noreply, scene}

      {:tab_closed, _tab_id, new_state} ->
        update_scene_tuple(scene, state, new_state)
    end
  end

  @doc """
  Replace the whole tab set (and selection) in place.

  This is the update path for hosts that treat the tab list as derived
  state (e.g. published store snapshots): message the surviving component
  instead of delete+recreating it — recreation churn under rapid successive
  updates can kill a TabBar instance mid-init.
  """
  def handle_put({:set_tabs, tabs, selected_id}, scene) do
    state = scene.assigns.state
    new_state = %{state | tabs: State.normalize_tabs(tabs), selected_id: selected_id}
    # tab_widths is a layout cache derived from tabs — recompute or
    # get_tab_bounds returns nil and rendering crashes
    new_state = %{new_state | tab_widths: State.calculate_tab_widths(new_state)}
    new_state = State.ensure_selected_visible(new_state)

    cond do
      new_state.tabs == state.tabs and new_state.selected_id == state.selected_id ->
        {:noreply, scene}

      new_state.tabs == state.tabs ->
        # Same tab set, different selection — surgical update path
        update_scene_tuple(scene, state, new_state)

      true ->
        # Tab set changed: update_render is surgical (it cannot add/remove tab
        # primitives), so rebuild our own graph — primitives only, the
        # component instance survives (same pattern as {:add_tab, _})
        graph = Renderer.initial_render(Graph.build(), new_state)

        scene =
          scene
          |> assign(state: new_state, graph: graph)
          |> push_graph(graph)

        register_semantic_elements(scene, new_state)
        {:noreply, scene}
    end
  end

  def handle_put({:update_frame, frame}, scene) do
    state = scene.assigns.state
    new_state = %{state | frame: frame}
    new_state = %{new_state | tab_widths: State.calculate_tab_widths(new_state)}
    new_state = State.ensure_selected_visible(new_state)
    graph = Renderer.initial_render(Graph.build(), new_state)

    scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
    register_semantic_elements(scene, new_state)
    {:noreply, scene}
  end

  def handle_put(_msg, scene) do
    {:noreply, scene}
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp update_scene(scene, old_state, new_state) do
    graph = Renderer.update_render(scene.assigns.graph, old_state, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    # Re-register if tabs, scroll, or selection changed.
    # selected_id must be included because the aggregate entry written by
    # register_tab_bar_aggregate/3 carries the selected_id, and tests poll
    # get_selected_tab_label() after direct tab clicks routed through handle_input.
    if old_state.tabs != new_state.tabs or
         old_state.scroll_offset != new_state.scroll_offset or
         old_state.selected_id != new_state.selected_id do
      register_semantic_elements(scene, new_state)
    end

    {:noreply, scene}
  end

  defp update_scene_tuple(scene, old_state, new_state) do
    graph = Renderer.update_render(scene.assigns.graph, old_state, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    # Re-register when tabs or selection changes (tab positions may have shifted)
    register_semantic_elements(scene, new_state)
    {:noreply, scene}
  end

  # ===========================================================================
  # Semantic Registration (for ScenicMCP click_element support)
  # ===========================================================================
  #
  # Registers each tab and its close button with pre-computed screen bounds
  # in the semantic ETS table, enabling ScenicMCP's click_element/1 to click
  # tabs by their semantic ID ("tab_bar_<uuid>" and "tab_bar_close_<uuid>").
  #
  # Follows the same pattern as IconMenu.register_semantic_elements/2.

  defp register_semantic_elements(scene, %State{} = state) do
    viewport = scene.viewport

    # Only register when semantic infrastructure is available
    unless viewport.semantic_table && viewport.semantic_enabled do
      :ok
    else
      scene_name = scene.assigns[:id] || :tab_bar

      # Get the tab bar's top-left screen position from its frame
      {bar_x, bar_y} = state.frame.pin.point

      # Register aggregate tab bar metadata so SemanticHelpers.find_tab_bar/1 can
      # read tab_count, tabs (with labels), and selected_id.
      # The Scenic.Semantic.Compiler.Entry struct has no custom fields, so we
      # store the rich metadata as a plain map under a dedicated key.
      register_tab_bar_aggregate(viewport, scene_name, state)

      # Only register tabs that are actually on screen. A scrolled-off tab's
      # bounds are negative (or past the right edge), so registering it
      # publishes a "clickable" element at a point OUTSIDE the bar — clicking
      # it hits whatever happens to be there, or nothing. See
      # State.tab_visible?/2.
      state.tabs
      |> Enum.filter(&State.tab_visible?(state, &1.id))
      |> Enum.each(fn tab ->
        case State.get_tab_bounds(state, tab.id) do
          {tab_x, _tab_y, tab_w, tab_h} ->
            # Register the tab body as a clickable element
            tab_semantic_id = "tab_bar_#{tab.id}"

            register_tab_element(
              viewport,
              scene_name,
              tab_semantic_id,
              :tab,
              bar_x + tab_x,
              bar_y,
              tab_w,
              tab_h
            )

            # Register the close button separately if this tab is closeable
            if tab.closeable do
              theme = state.theme
              close_size = theme.close_button_size
              close_margin = theme.close_button_margin
              close_local_x = tab_x + tab_w - close_size - close_margin
              close_local_y = (tab_h - close_size) / 2
              close_semantic_id = "tab_bar_close_#{tab.id}"

              register_tab_element(
                viewport,
                scene_name,
                close_semantic_id,
                :tab_close,
                bar_x + close_local_x,
                bar_y + close_local_y,
                close_size,
                close_size
              )
            end

          nil ->
            :ok
        end
      end)
    end
  end

  # Write aggregate tab bar info (tab_count, tabs with labels, selected_id) to ETS.
  # Stored as a plain map (not a %Scenic.Semantic.Compiler.Entry{}) so the full
  # metadata survives — the Entry struct has no fields for custom data.
  defp register_tab_bar_aggregate(viewport, scene_name, %State{} = state) do
    tab_bar_data = %{
      tab_count: length(state.tabs),
      selected_id: state.selected_id,
      tabs:
        Enum.map(state.tabs, fn tab ->
          %{
            id: tab.id,
            label: tab.label,
            selected: tab.id == state.selected_id,
            closeable: tab.closeable,
            # Scrolled out of the bar? Then it has no clickable element
            # registered — consumers must scroll it into view first.
            visible: State.tab_visible?(state, tab.id)
          }
        end)
    }

    :ets.insert(viewport.semantic_table, {{scene_name, :tab_bar_aggregate}, tab_bar_data})
  end

  defp register_tab_element(viewport, scene_name, id, type, x, y, w, h) do
    entry = %Scenic.Semantic.Compiler.Entry{
      id: id,
      type: type,
      local_bounds: %{left: x, top: y, width: w, height: h},
      screen_bounds: %{left: x, top: y, width: w, height: h},
      clickable: true,
      focusable: false,
      label: nil,
      role: :button,
      value: nil,
      hidden: false,
      z_index: 5
    }

    :ets.insert(viewport.semantic_table, {{scene_name, id}, entry})
    :ets.insert(viewport.semantic_index, {id, {scene_name, id}})
  end
end
