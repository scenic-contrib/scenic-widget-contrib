defmodule ScenicWidgets.ListSelectorDialog.State do
  @moduledoc """
  State management for ListSelectorDialog component.

  The state holds all configuration and runtime data for the dialog,
  including items to display, selection state, scroll position, and theming.
  """

  alias Widgex.Frame

  @default_theme %{
    backdrop: {0, 0, 0, 180},
    dialog_bg: {50, 50, 55},
    dialog_border: {80, 80, 85},
    title: :white,
    subtitle: {150, 150, 150},
    list_bg: {40, 40, 45},
    item_bg: {60, 60, 65},
    item_hover: {70, 80, 90},
    item_selected: {70, 130, 180},
    item_text: :white,
    item_description: {150, 150, 150},
    button_confirm: {70, 130, 180},
    button_confirm_disabled: {60, 60, 65},
    button_cancel: {100, 100, 100},
    button_text: :white,
    scrollbar_track: {60, 60, 65},
    scrollbar_thumb: {100, 100, 110}
  }

  @default_dimensions %{
    dialog_width: 450,
    dialog_height: 370,
    list_height: 220,
    item_height: 52,
    list_padding: 10,
    button_width: 80,
    button_height: 32,
    scrollbar_width: 6
  }

  defstruct [
    :id,
    :frame,
    :title,
    :subtitle,
    :items,
    :item_key,
    :item_description_key,
    :confirm_label,
    :cancel_label,
    :theme,
    :dimensions,
    :dialog_x,
    :dialog_y,
    :selected_index,
    :hover_index,
    :scroll_offset,
    :last_click_index,
    :last_click_time,
    :double_click_ms
  ]

  @doc """
  Creates a new state struct with the given options.

  ## Required Options
  - `:frame` - Widgex.Frame defining the viewport size

  ## Optional Options
  - `:id` - Component identifier (default: `:list_selector_dialog`)
  - `:title` - Dialog title (default: "Select Item")
  - `:subtitle` - Subtitle text (default: "Choose an item from the list:")
  - `:items` - List of items to display (default: [])
  - `:item_key` - Key to use for item display name (default: `:name`)
  - `:item_description_key` - Key for item description (default: `:description`)
  - `:confirm_label` - Confirm button label (default: "OK")
  - `:cancel_label` - Cancel button label (default: "Cancel")
  - `:theme` - Map of theme colors (merged with defaults)
  - `:dimensions` - Map of dimension overrides (merged with defaults)
  - `:double_click_ms` - Double-click detection threshold in ms (default: 400)
  """
  def new(opts) do
    frame = opts[:frame] || raise ArgumentError, "frame is required"
    {vp_width, vp_height} = get_size(frame)

    theme = Map.merge(@default_theme, opts[:theme] || %{})
    dimensions = Map.merge(@default_dimensions, opts[:dimensions] || %{})

    dialog_x = (vp_width - dimensions.dialog_width) / 2
    dialog_y = (vp_height - dimensions.dialog_height) / 2

    %__MODULE__{
      id: opts[:id] || :list_selector_dialog,
      frame: frame,
      title: opts[:title] || "Select Item",
      subtitle: opts[:subtitle] || "Choose an item from the list:",
      items: opts[:items] || [],
      item_key: opts[:item_key] || :name,
      item_description_key: opts[:item_description_key] || :description,
      confirm_label: opts[:confirm_label] || "OK",
      cancel_label: opts[:cancel_label] || "Cancel",
      theme: theme,
      dimensions: dimensions,
      dialog_x: dialog_x,
      dialog_y: dialog_y,
      selected_index: nil,
      hover_index: nil,
      scroll_offset: 0,
      last_click_index: nil,
      last_click_time: 0,
      double_click_ms: opts[:double_click_ms] || 400
    }
  end

  @doc """
  Gets the currently selected item, or nil if nothing selected.
  """
  def selected_item(%__MODULE__{selected_index: nil}), do: nil
  def selected_item(%__MODULE__{selected_index: idx, items: items}) do
    Enum.at(items, idx)
  end

  @doc """
  Sets the selected index, clamping to valid range.
  """
  def set_selected(%__MODULE__{items: items} = state, index) when is_integer(index) do
    max_idx = length(items) - 1
    clamped = max(0, min(index, max_idx))
    %{state | selected_index: if(max_idx >= 0, do: clamped, else: nil)}
  end

  @doc """
  Moves selection up by one.
  """
  def select_previous(%__MODULE__{selected_index: nil} = state) do
    set_selected(state, 0)
  end
  def select_previous(%__MODULE__{selected_index: idx} = state) do
    set_selected(state, idx - 1)
  end

  @doc """
  Moves selection down by one.
  """
  def select_next(%__MODULE__{selected_index: nil} = state) do
    set_selected(state, 0)
  end
  def select_next(%__MODULE__{selected_index: idx} = state) do
    set_selected(state, idx + 1)
  end

  @doc """
  Sets the hover index.
  """
  def set_hover(%__MODULE__{} = state, index) do
    %{state | hover_index: index}
  end

  @doc """
  Records a click for double-click detection.
  Returns {is_double_click, updated_state}
  """
  def record_click(%__MODULE__{} = state, index) do
    now = System.monotonic_time(:millisecond)
    is_double = index == state.last_click_index and
                (now - state.last_click_time) < state.double_click_ms

    new_state = %{state |
      selected_index: index,
      last_click_index: index,
      last_click_time: now
    }

    {is_double, new_state}
  end

  @doc """
  Updates scroll offset, clamping to valid range.
  """
  def scroll(%__MODULE__{dimensions: dims, items: items} = state, delta) do
    total_content = dims.list_padding * 2 + length(items) * dims.item_height
    max_scroll = max(0, total_content - dims.list_height)
    new_offset = state.scroll_offset + delta
    new_offset = max(0, min(new_offset, max_scroll))
    %{state | scroll_offset: new_offset}
  end

  @doc """
  Checks if a point is within the list area (in dialog-local coordinates).
  """
  def in_list_area?(%__MODULE__{dimensions: dims}, local_y) do
    list_top = 75
    list_bottom = list_top + dims.list_height
    local_y >= list_top and local_y < list_bottom
  end

  @doc """
  Gets the item index at a given y position (in dialog-local coordinates).
  """
  def index_at_position(%__MODULE__{dimensions: dims} = state, local_y) do
    list_y = local_y - 75 - dims.list_padding + state.scroll_offset
    trunc(list_y / dims.item_height)
  end

  @doc """
  Checks if a point is within a rectangle.
  """
  def in_rect?(x, y, rect_x, rect_y, width, height) do
    x >= rect_x and x <= rect_x + width and y >= rect_y and y <= rect_y + height
  end

  @doc """
  Checks if a point is within the dialog bounds (in dialog-local coordinates).
  """
  def in_dialog?(%__MODULE__{dimensions: dims}, local_x, local_y) do
    local_x >= 0 and local_x <= dims.dialog_width and
    local_y >= 0 and local_y <= dims.dialog_height
  end

  @doc """
  Gets the confirm button bounds (in dialog-local coordinates).
  """
  def confirm_button_bounds(%__MODULE__{dimensions: dims}) do
    {dims.dialog_width - 90, dims.dialog_height - 50,
     dims.button_width, dims.button_height}
  end

  @doc """
  Gets the cancel button bounds (in dialog-local coordinates).
  """
  def cancel_button_bounds(%__MODULE__{dimensions: dims}) do
    {dims.dialog_width - 180, dims.dialog_height - 50,
     dims.button_width, dims.button_height}
  end

  @doc """
  Gets the display name for an item.
  """
  def item_name(%__MODULE__{item_key: key}, item) when is_map(item) do
    Map.get(item, key, "")
  end
  def item_name(_, item) when is_binary(item), do: item
  def item_name(_, _), do: ""

  @doc """
  Gets the description for an item.
  """
  def item_description(%__MODULE__{item_description_key: key}, item) when is_map(item) do
    Map.get(item, key, "")
  end
  def item_description(_, _), do: ""

  # Private helpers

  defp get_size(%Frame{size: %{width: w, height: h}}), do: {w, h}
  defp get_size(%{size: {w, h}}), do: {w, h}
  defp get_size(%{size: %{width: w, height: h}}), do: {w, h}
  defp get_size(frame) when is_map(frame) do
    case frame[:size] do
      {w, h} -> {w, h}
      %{width: w, height: h} -> {w, h}
      _ -> {800, 600}
    end
  end
end
