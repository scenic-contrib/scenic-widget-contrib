defmodule ScenicWidgets.TidbitColumn.Reducer do
  @moduledoc """
  Pure state transition functions for TidbitColumn.

  Uses the Scrollable macro for scroll handling.
  """

  use Widgex.Scrollable

  alias ScenicWidgets.TidbitColumn.State

  @doc """
  Process user input and return state transitions.

  Returns:
  - `{:noop, state}` - State unchanged or only internal state changed
  - `{:item_selected, item_id, state}` - Item was selected
  """
  def process_input(%State{} = state, {:cursor_pos, coords}) do
    handle_hover(state, coords)
  end

  def process_input(%State{} = state, {:cursor_button, {:btn_left, 1, [], coords}}) do
    handle_click(state, coords)
  end

  # Handle both scroll input formats from different Scenic drivers
  def process_input(%State{} = state, {:cursor_scroll, {{_dx, dy}, {_x, _y}}}) do
    handle_scroll_input(state, dy)
  end

  def process_input(%State{} = state, {:cursor_scroll, {_dx, dy, _x, _y}}) do
    handle_scroll_input(state, dy)
  end

  def process_input(state, _input) do
    {:noop, state}
  end

  @doc """
  Handle cursor position for hover effects.
  """
  def handle_hover(%State{} = state, coords) do
    if State.point_inside?(state, coords) do
      case State.hit_test(state, coords) do
        {:item, item_id} ->
          if state.hovered_id != item_id do
            {:noop, %{state | hovered_id: item_id}}
          else
            {:noop, state}
          end

        :none ->
          if state.hovered_id do
            {:noop, %{state | hovered_id: nil}}
          else
            {:noop, state}
          end
      end
    else
      # Mouse outside - clear hover
      if state.hovered_id do
        {:noop, %{state | hovered_id: nil}}
      else
        {:noop, state}
      end
    end
  end

  @doc """
  Handle click events for item selection.
  """
  def handle_click(%State{} = state, coords) do
    if State.point_inside?(state, coords) do
      case State.hit_test(state, coords) do
        {:item, item_id} ->
          select_item(state, item_id)

        :none ->
          {:noop, state}
      end
    else
      {:noop, state}
    end
  end

  @doc """
  Handle scroll input.
  """
  def handle_scroll_input(%State{} = state, delta_y) do
    # Negate delta for natural scrolling (scroll down = content moves up)
    new_scroll = handle_scroll(state.scroll, -delta_y)

    if scroll_changed?(state.scroll, new_scroll) do
      {:noop, %{state | scroll: new_scroll}}
    else
      {:noop, state}
    end
  end

  @doc """
  Select an item by ID.
  """
  def select_item(%State{selected_id: current_id} = state, item_id) when current_id == item_id do
    # Deselect if already selected
    {:item_deselected, item_id, %{state | selected_id: nil}}
  end

  def select_item(%State{} = state, item_id) do
    {:item_selected, item_id, %{state | selected_id: item_id}}
  end
end
