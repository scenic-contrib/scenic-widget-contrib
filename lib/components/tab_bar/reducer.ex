defmodule ScenicWidgets.TabBar.Reducer do
  @moduledoc """
  Pure state transition functions for TabBar.

  All functions are pure - they take state + input and return {:action, new_state}.
  No side effects or mutations.
  """

  alias ScenicWidgets.TabBar.State

  # Pixels to scroll per wheel tick
  @scroll_amount 50

  # Horizontal travel, in pixels, before a press on a tab becomes a reorder drag.
  @drag_threshold 5

  # How long after a press a second press on the same tab still counts as a
  # double click.
  @double_click_ms 450

  @doc """
  Process user input and return state transitions.

  Returns:
  - `{:noop, state}` - State unchanged or only internal state changed
  - `{:tab_selected, tab_id, state}` - Tab was selected
  - `{:tab_closed, tab_id, state}` - Tab was closed
  """
  def process_input(%State{} = state, {:cursor_pos, coords}) do
    if state.dragging_tab_id, do: handle_drag(state, coords), else: handle_hover(state, coords)
  end

  def process_input(%State{} = state, {:cursor_button, {:btn_left, 1, _mods, coords}}) do
    handle_press(state, coords)
  end

  def process_input(
        %State{dragging_tab_id: id} = state,
        {:cursor_button, {:btn_left, 0, _mods, _coords}}
      )
      when not is_nil(id) do
    new_state = %{
      state
      | dragging_tab_id: nil,
        drag_reordered?: false,
        drag_origin_x: nil,
        drag_active?: false
    }

    if state.drag_reordered?,
      do: {:tabs_reordered, Enum.map(state.tabs, & &1.id), new_state},
      else: select_tab(new_state, id)
  end

  def process_input(%State{} = state, {:cursor_scroll, {_dx, dy, x, y}}) do
    maybe_scroll(state, dy, {x, y})
  end

  def process_input(%State{} = state, {:cursor_scroll, {{dx, dy}, coords}}) do
    delta = if dx == 0, do: dy, else: dx
    maybe_scroll(state, delta, coords)
  end

  def process_input(%State{} = state, {:cursor_scroll, {_dx, dy}}) do
    handle_scroll(state, dy)
  end

  def process_input(state, _input) do
    {:noop, state}
  end

  defp maybe_scroll(state, delta, coords) do
    if State.point_inside?(state, coords),
      do: handle_scroll(state, delta),
      else: {:noop, state}
  end

  @doc """
  Handle cursor position for hover effects.
  """
  def handle_hover(%State{} = state, coords) do
    if State.point_inside?(state, coords) do
      case State.hit_test(state, coords) do
        {:close, tab_id} ->
          new_state = %{state | hovered_tab_id: tab_id, hovered_close_id: tab_id}
          {:noop, new_state}

        {:tab, tab_id} ->
          new_state = %{state | hovered_tab_id: tab_id, hovered_close_id: nil}
          {:noop, new_state}

        :none ->
          new_state = %{state | hovered_tab_id: nil, hovered_close_id: nil}
          {:noop, new_state}
      end
    else
      # Mouse outside tab bar - clear hover
      if state.hovered_tab_id || state.hovered_close_id do
        {:noop, %{state | hovered_tab_id: nil, hovered_close_id: nil}}
      else
        {:noop, state}
      end
    end
  end

  @doc """
  Handle click events for tab selection and closing.
  """
  def handle_click(%State{} = state, coords) do
    if State.point_inside?(state, coords) do
      case State.hit_test(state, coords) do
        {:close, tab_id} ->
          close_tab(state, tab_id)

        {:tab, tab_id} ->
          select_tab(state, tab_id)

        :none ->
          {:noop, state}
      end
    else
      {:noop, state}
    end
  end

  defp handle_press(state, {x, _y} = coords) do
    case if(State.point_inside?(state, coords), do: State.hit_test(state, coords), else: :none) do
      {:close, _id} ->
        handle_click(state, coords)

      {:tab, id} ->
        now = System.monotonic_time(:millisecond)

        pressed = %{
          state
          | dragging_tab_id: id,
            drag_reordered?: false,
            drag_origin_x: x,
            drag_active?: false,
            last_press: {id, now}
        }

        if double_click?(state.last_press, id, now),
          do: {:tab_double_clicked, id, %{pressed | last_press: nil}},
          else: {:noop, pressed}

      :none ->
        {:noop, state}
    end
  end

  # Two presses on the same tab inside the window are a double click. The
  # window is generous: the gesture promotes a preview tab to a permanent one,
  # and a missed promotion is far more annoying than a late one.
  defp double_click?({id, at}, id, now), do: now - at <= @double_click_ms
  defp double_click?(_last_press, _id, _now), do: false

  defp handle_drag(state, {x, _y} = coords) do
    index = Enum.find_index(state.tabs, &(&1.id == state.dragging_tab_id))
    left = index > 0 && Enum.at(state.tabs, index - 1)
    right = index < length(state.tabs) - 1 && Enum.at(state.tabs, index + 1)

    # A press is not yet a drag. Showing the drop line the instant the button
    # goes down would flash it on every ordinary tab click.
    active? = state.drag_active? or abs(x - state.drag_origin_x) >= @drag_threshold

    target_index =
      cond do
        left && x < tab_center(state, left.id) -> index - 1
        right && x > tab_center(state, right.id) -> index + 1
        true -> index
      end

    if target_index == index do
      handle_hover(state, coords)
      |> then(fn {:noop, hovered} ->
        {:noop,
         %{
           hovered
           | dragging_tab_id: state.dragging_tab_id,
             drag_reordered?: state.drag_reordered?,
             drag_origin_x: state.drag_origin_x,
             drag_active?: active?
         }}
      end)
    else
      tab = Enum.at(state.tabs, index)
      tabs = state.tabs |> List.delete_at(index) |> List.insert_at(target_index, tab)
      new_state = %{state | tabs: tabs, drag_reordered?: true, drag_active?: active?}
      new_state = %{new_state | tab_widths: State.calculate_tab_widths(new_state)}
      {:tabs_dragged, new_state}
    end
  end

  defp tab_center(state, id) do
    {x, _y, width, _height} = State.get_tab_bounds(state, id)
    x + width / 2
  end

  @doc """
  Handle horizontal scrolling.
  """
  def handle_scroll(%State{} = state, delta_y) do
    # Negative delta = scroll right, positive = scroll left (natural scrolling)
    new_offset = state.scroll_offset - delta_y * @scroll_amount

    # Clamp to valid range
    max_offset = State.max_scroll_offset(state)
    clamped_offset = new_offset |> max(0) |> min(max_offset)

    if clamped_offset != state.scroll_offset do
      {:noop, %{state | scroll_offset: clamped_offset}}
    else
      {:noop, state}
    end
  end

  @doc """
  Select a tab by ID.
  """
  def select_tab(%State{selected_id: current_id} = state, tab_id) when current_id == tab_id do
    # Already selected, no change
    {:noop, state}
  end

  def select_tab(%State{} = state, tab_id) do
    new_state = State.ensure_selected_visible(%{state | selected_id: tab_id})
    {:tab_selected, tab_id, new_state}
  end

  @doc """
  Close a tab by ID.
  """
  def close_tab(%State{tabs: tabs} = state, tab_id) do
    tab = Enum.find(tabs, &(&1.id == tab_id))

    cond do
      # Tab not found or not closeable
      tab == nil or not tab.closeable ->
        {:noop, state}

      # Last tab - don't close
      length(tabs) == 1 ->
        {:noop, state}

      true ->
        # Remove the tab
        new_tabs = Enum.reject(tabs, &(&1.id == tab_id))

        # If we closed the selected tab, select an adjacent one
        new_selected =
          if state.selected_id == tab_id do
            select_adjacent_tab(tabs, tab_id)
          else
            state.selected_id
          end

        # Recalculate tab widths
        new_state = %{
          state
          | tabs: new_tabs,
            selected_id: new_selected,
            hovered_tab_id: nil,
            hovered_close_id: nil
        }

        new_state = %{new_state | tab_widths: State.calculate_tab_widths(new_state)}

        # Adjust scroll if needed
        max_offset = State.max_scroll_offset(new_state)
        new_state = %{new_state | scroll_offset: min(new_state.scroll_offset, max_offset)}

        {:tab_closed, tab_id, new_state}
    end
  end

  @doc """
  Add a new tab.
  """
  def add_tab(%State{tabs: tabs} = state, tab) do
    normalized = hd(State.normalize_tabs([tab]))
    new_tabs = tabs ++ [normalized]

    new_state = %{state | tabs: new_tabs}
    new_state = %{new_state | tab_widths: State.calculate_tab_widths(new_state)}

    {:tab_added, normalized.id, new_state}
  end

  # Find the tab to select when closing the current one
  defp select_adjacent_tab(tabs, closing_id) do
    index = Enum.find_index(tabs, &(&1.id == closing_id))

    cond do
      # Try to select the tab to the right
      index < length(tabs) - 1 ->
        Enum.at(tabs, index + 1).id

      # Otherwise select the tab to the left
      index > 0 ->
        Enum.at(tabs, index - 1).id

      # Shouldn't happen (single tab case handled above)
      true ->
        nil
    end
  end
end
