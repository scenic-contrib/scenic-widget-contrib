defmodule ScenicWidgets.FilePicker.Reducer do
  @moduledoc """
  Input handling for the FilePicker component.
  """

  use Widgex.Scrollable, direction: :vertical

  alias ScenicWidgets.FilePicker.State

  # ===========================================================================
  # Save Mode Keyboard Input
  # ===========================================================================

  @doc """
  Process keyboard input in save mode - handles filename typing.
  Returns `{:state, new_state}` or `{:action, action}` or `:noop`.
  """
  def process_input(%State{mode: :save} = state, {:key, {key, 1, _mods}}) do
    case key do
      :key_up ->
        {:state, State.select_prev(state)}

      :key_down ->
        {:state, State.select_next(state)}

      :key_enter ->
        # In save mode, Enter confirms the save if filename is valid
        if State.valid_filename?(state) do
          {:action, {:file_saved, State.save_path(state)}}
        else
          :noop
        end

      :key_backspace ->
        # Backspace deletes from filename
        {:state, State.backspace(state)}

      :key_delete ->
        {:state, State.delete_at_cursor(state)}

      :key_left ->
        {:state, State.cursor_left(state)}

      :key_right ->
        {:state, State.cursor_right(state)}

      :key_home ->
        {:state, State.cursor_home(state)}

      :key_end ->
        {:state, State.cursor_end(state)}

      :key_esc ->
        {:action, :cancel}

      _ ->
        :noop
    end
  end

  # Handle character input in save mode
  def process_input(%State{mode: :save} = state, {:codepoint, {char, _}}) do
    {:state, State.insert_char(state, char)}
  end

  # ===========================================================================
  # Open Mode Keyboard Input
  # ===========================================================================

  @doc """
  Process keyboard input in open mode.
  Returns `{:state, new_state}` or `{:action, action}` or `:noop`.
  """
  def process_input(%State{mode: :open} = state, {:key, {key, 1, _mods}}) do
    case key do
      :key_up ->
        {:state, State.select_prev(state)}

      :key_down ->
        {:state, State.select_next(state)}

      :key_enter ->
        case State.activate_selection(state) do
          {:directory, new_state} -> {:state, new_state}
          {:file, path} -> {:action, {:file_selected, path}}
          {:none, _} -> :noop
        end

      :key_backspace ->
        {:state, State.navigate_up(state)}

      :key_esc ->
        {:action, :cancel}

      _ ->
        :noop
    end
  end

  def process_input(%State{} = state, {:key, _}), do: :noop

  @doc """
  Process scroll wheel input.
  """
  def process_input(%State{scroll: scroll} = state, {:cursor_scroll, scroll_data}) do
    case normalize_scroll_input(scroll_data) do
      {_dx, dy} when dy != 0 ->
        new_scroll = handle_scroll(scroll, dy)
        {:state, %{state | scroll: new_scroll}}

      _ ->
        :noop
    end
  end

  def process_input(_state, _input), do: :noop

  @doc """
  Handle button click events.
  """
  def process_event(:up_button, %State{} = state) do
    {:state, State.navigate_up(state)}
  end

  # Save/Open button in save mode
  def process_event(:save_button, %State{mode: :save} = state) do
    if State.valid_filename?(state) do
      {:action, {:file_saved, State.save_path(state)}}
    else
      :noop
    end
  end

  # Open button in open mode
  def process_event(:open_button, %State{mode: :open} = state) do
    case State.selected_entry(state) do
      %{type: :directory, path: path} ->
        {:state, State.navigate_to(state, path)}

      %{type: :file, path: path} ->
        {:action, {:file_selected, path}}

      nil ->
        :noop
    end
  end

  def process_event(:cancel_button, _state) do
    {:action, :cancel}
  end

  def process_event(_button_id, _state), do: :noop

  @doc """
  Handle click on a file entry at given y coordinate.
  """
  def process_click(%State{scroll: scroll, entries: entries} = state, {_x, y}) do
    # Adjust y for scroll offset
    adjusted_y = y + scroll.offset_y
    idx = trunc(adjusted_y / State.item_height())

    if idx >= 0 and idx < length(entries) do
      new_state = %{state | selected_index: idx}
      {:state, new_state}
    else
      :noop
    end
  end

  @doc """
  Handle double-click on a file entry.
  """
  def process_double_click(%State{} = state, coords) do
    case process_click(state, coords) do
      {:state, new_state} ->
        case State.activate_selection(new_state) do
          {:directory, updated_state} -> {:state, updated_state}
          {:file, path} -> {:action, {:file_selected, path}}
          {:none, _} -> {:state, new_state}
        end

      :noop ->
        :noop
    end
  end

  # Normalize scroll input from various Scenic formats
  defp normalize_scroll_input({dx, dy, _x, _y}), do: {dx, dy}
  defp normalize_scroll_input({{dx, dy}, _coords}), do: {dx, dy}
  defp normalize_scroll_input({dx, dy}), do: {dx, dy}
  defp normalize_scroll_input(_), do: {0, 0}
end
