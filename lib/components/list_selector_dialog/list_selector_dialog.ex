defmodule ScenicWidgets.ListSelectorDialog do
  @moduledoc """
  A modal dialog component for selecting an item from a scrollable list.

  This is a reusable component that displays a centered modal dialog with:
  - A title and subtitle
  - A scrollable list of items with name and description
  - Cancel and confirm buttons
  - Keyboard navigation (arrows, Enter, Escape)
  - Double-click to confirm

  ## Usage

      Scenic.Scene.child_spec({
        ScenicWidgets.ListSelectorDialog,
        %{
          id: :my_selector,
          frame: frame,
          title: "Select File",
          subtitle: "Choose a file to open:",
          items: [
            %{name: "file1.txt", description: "/path/to/file1.txt"},
            %{name: "file2.txt", description: "/path/to/file2.txt"}
          ],
          confirm_label: "Open",
          cancel_label: "Cancel"
        }
      })

  ## Events sent to parent

  - `{:list_selector_confirmed, id, selected_item}` - When user confirms selection
  - `{:list_selector_cancelled, id}` - When user cancels (Escape, Cancel button, or click outside)

  ## Options

  - `:id` - Component identifier (default: `:list_selector_dialog`)
  - `:frame` - Widgex.Frame or map with `:size` (required)
  - `:title` - Dialog title (default: "Select Item")
  - `:subtitle` - Subtitle text (default: "Choose an item from the list:")
  - `:items` - List of items to display (default: [])
  - `:item_key` - Key to use for item display name (default: `:name`)
  - `:item_description_key` - Key for item description (default: `:description`)
  - `:confirm_label` - Confirm button label (default: "OK")
  - `:cancel_label` - Cancel button label (default: "Cancel")
  - `:theme` - Map of theme color overrides
  - `:dimensions` - Map of dimension overrides
  - `:double_click_ms` - Double-click threshold in ms (default: 400)
  """

  use Scenic.Component
  require Logger

  alias ScenicWidgets.ListSelectorDialog.{State, Renderer}

  # ─────────────────────────────────────────────────────────────
  # Scenic Component Callbacks
  # ─────────────────────────────────────────────────────────────

  @doc """
  Adds a ListSelectorDialog to a graph.
  """
  def add_to_graph(graph, data, opts \\ []) do
    super(graph, data, opts)
  end

  @doc false
  def validate(%{frame: frame} = data) when is_map(frame) do
    {:ok, data}
  end

  def validate(data) do
    {:error, "ListSelectorDialog requires :frame, got: #{inspect(data)}"}
  end

  @impl Scenic.Component
  def init(scene, data, opts) do
    id = opts[:id] || data[:id] || :list_selector_dialog

    state = State.new(Map.merge(data, %{id: id}))
    graph = Renderer.render(state)

    scene =
      scene
      |> assign(id: id, state: state, graph: graph)
      |> push_graph(graph)

    request_input(scene, [:cursor_button, :cursor_pos, :key, :cursor_scroll])

    {:ok, scene}
  end

  # ─────────────────────────────────────────────────────────────
  # Keyboard Input
  # ─────────────────────────────────────────────────────────────

  @impl Scenic.Component
  def handle_input({:key, {:key_esc, 1, _}}, _context, scene) do
    emit_cancel(scene)
    {:noreply, scene}
  end

  def handle_input({:key, {:key_enter, 1, _}}, _context, scene) do
    state = scene.assigns.state
    if item = State.selected_item(state) do
      emit_confirm(scene, item)
    end
    {:noreply, scene}
  end

  def handle_input({:key, {:key_up, 1, _}}, _context, scene) do
    state = State.select_previous(scene.assigns.state)
    {:noreply, update_and_render(scene, state)}
  end

  def handle_input({:key, {:key_down, 1, _}}, _context, scene) do
    state = State.select_next(scene.assigns.state)
    {:noreply, update_and_render(scene, state)}
  end

  # ─────────────────────────────────────────────────────────────
  # Mouse Input
  # ─────────────────────────────────────────────────────────────

  def handle_input({:cursor_button, {:btn_left, 1, _, coords}}, _context, scene) do
    state = scene.assigns.state
    {x, y} = coords

    local_x = x - state.dialog_x
    local_y = y - state.dialog_y

    {cancel_x, cancel_y, btn_w, btn_h} = State.cancel_button_bounds(state)
    {confirm_x, confirm_y, _, _} = State.confirm_button_bounds(state)

    cond do
      # Cancel button
      State.in_rect?(local_x, local_y, cancel_x, cancel_y, btn_w, btn_h) ->
        emit_cancel(scene)
        {:noreply, scene}

      # Confirm button
      State.in_rect?(local_x, local_y, confirm_x, confirm_y, btn_w, btn_h) ->
        if item = State.selected_item(state) do
          emit_confirm(scene, item)
        end
        {:noreply, scene}

      # Click in list area
      State.in_list_area?(state, local_y) ->
        handle_list_click(scene, state, local_y)

      # Click outside dialog = cancel
      not State.in_dialog?(state, local_x, local_y) ->
        emit_cancel(scene)
        {:noreply, scene}

      true ->
        {:noreply, scene}
    end
  end

  def handle_input({:cursor_pos, coords}, _context, scene) do
    state = scene.assigns.state
    {x, y} = coords

    local_x = x - state.dialog_x
    local_y = y - state.dialog_y

    hover_index = if State.in_list_area?(state, local_y) do
      idx = State.index_at_position(state, local_y)
      if idx >= 0 and idx < length(state.items), do: idx, else: nil
    else
      nil
    end

    if hover_index != state.hover_index do
      state = State.set_hover(state, hover_index)
      {:noreply, update_and_render(scene, state)}
    else
      {:noreply, scene}
    end
  end

  def handle_input({:cursor_scroll, {{_x, y}, _}}, _context, scene) do
    state = scene.assigns.state
    delta = -y * 20
    new_state = State.scroll(state, delta)

    if new_state.scroll_offset != state.scroll_offset do
      {:noreply, update_and_render(scene, new_state)}
    else
      {:noreply, scene}
    end
  end

  def handle_input(_input, _context, scene), do: {:noreply, scene}

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp handle_list_click(scene, state, local_y) do
    clicked_idx = State.index_at_position(state, local_y)

    if clicked_idx >= 0 and clicked_idx < length(state.items) do
      {is_double_click, new_state} = State.record_click(state, clicked_idx)

      if is_double_click do
        item = Enum.at(state.items, clicked_idx)
        emit_confirm(scene, item)
        {:noreply, scene}
      else
        {:noreply, update_and_render(scene, new_state)}
      end
    else
      {:noreply, scene}
    end
  end

  defp update_and_render(scene, state) do
    graph = Renderer.render(state)
    scene
    |> assign(state: state, graph: graph)
    |> push_graph(graph)
  end

  defp emit_confirm(scene, item) do
    id = scene.assigns.id
    send_parent_event(scene, {:list_selector_confirmed, id, item})
  end

  defp emit_cancel(scene) do
    id = scene.assigns.id
    send_parent_event(scene, {:list_selector_cancelled, id})
  end
end
