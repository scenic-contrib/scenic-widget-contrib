defmodule ScenicWidgets.ListSelectorDialog.Renderer do
  @moduledoc """
  Rendering functions for ListSelectorDialog component.

  Handles all visual rendering including the modal backdrop, dialog box,
  scrollable list of items, and action buttons.
  """

  import Scenic.Primitives

  alias ScenicWidgets.ListSelectorDialog.State

  @doc """
  Renders the complete dialog graph.
  """
  def render(%State{} = state) do
    Scenic.Graph.build()
    |> render_backdrop(state)
    |> render_dialog(state)
  end

  # Renders the semi-transparent modal backdrop
  defp render_backdrop(graph, %State{frame: frame, theme: theme}) do
    {vp_width, vp_height} = get_size(frame)
    graph |> rect({vp_width, vp_height}, fill: theme.backdrop)
  end

  # Renders the main dialog box with all contents
  defp render_dialog(graph, %State{} = state) do
    %{dialog_x: dx, dialog_y: dy, dimensions: dims, theme: theme} = state

    graph
    |> group(fn g ->
      g
      # Dialog background
      |> rrect({dims.dialog_width, dims.dialog_height, 8},
          fill: theme.dialog_bg,
          stroke: {2, theme.dialog_border})
      # Title
      |> text(state.title,
          translate: {20, 35},
          fill: theme.title,
          font_size: 20)
      # Subtitle
      |> text(state.subtitle,
          translate: {20, 60},
          fill: theme.subtitle,
          font_size: 12)
      # List area background
      |> rect({dims.dialog_width - 40, dims.list_height},
          fill: theme.list_bg,
          translate: {20, 75})
      # Clipped list content
      |> group(fn list_g ->
        render_items(list_g, state)
      end,
        scissor: {dims.dialog_width - 40, dims.list_height},
        translate: {20, 75})
      # Scrollbar (outside scissor)
      |> render_scrollbar(state)
      # Buttons
      |> render_buttons(state)
    end,
    translate: {dx, dy})
  end

  # Renders list items inside the scissor-clipped group
  defp render_items(graph, %State{} = state) do
    %{items: items, dimensions: dims, theme: theme, scroll_offset: scroll_offset} = state
    scrollbar_width = dims.scrollbar_width
    item_w = dims.dialog_width - 40 - 2 * dims.list_padding - scrollbar_width - 5

    items
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {item, idx}, g ->
      item_y = dims.list_padding + idx * dims.item_height - scroll_offset

      # Only render if potentially visible
      if item_y > -dims.item_height and item_y < dims.list_height do
        bg_color = cond do
          idx == state.selected_index -> theme.item_selected
          idx == state.hover_index -> theme.item_hover
          true -> theme.item_bg
        end

        name = State.item_name(state, item)
        description = State.item_description(state, item)

        g
        |> rrect({item_w, dims.item_height - 5, 4},
            fill: bg_color,
            translate: {dims.list_padding, item_y})
        |> text(name,
            translate: {dims.list_padding + 10, item_y + 22},
            fill: theme.item_text,
            font_size: 14)
        |> text(description,
            translate: {dims.list_padding + 10, item_y + 40},
            fill: theme.item_description,
            font_size: 11)
      else
        g
      end
    end)
  end

  # Renders the scrollbar if content overflows
  defp render_scrollbar(graph, %State{} = state) do
    %{items: items, dimensions: dims, theme: theme, scroll_offset: scroll_offset} = state
    total_content_height = dims.list_padding * 2 + length(items) * dims.item_height

    if total_content_height > dims.list_height do
      scrollbar_x = dims.dialog_width - 40 - dims.scrollbar_width + 15
      scrollbar_track_y = 75 + 5
      scrollbar_track_height = dims.list_height - 10

      # Calculate thumb size and position
      visible_ratio = dims.list_height / total_content_height
      thumb_height = max(20, scrollbar_track_height * visible_ratio)
      max_scroll = total_content_height - dims.list_height
      scroll_ratio = if max_scroll > 0, do: scroll_offset / max_scroll, else: 0
      thumb_y = scrollbar_track_y + (scrollbar_track_height - thumb_height) * scroll_ratio

      graph
      |> rrect({dims.scrollbar_width, scrollbar_track_height, 3},
          fill: theme.scrollbar_track,
          translate: {scrollbar_x, scrollbar_track_y})
      |> rrect({dims.scrollbar_width, thumb_height, 3},
          fill: theme.scrollbar_thumb,
          translate: {scrollbar_x, thumb_y})
    else
      graph
    end
  end

  # Renders the Cancel and Confirm buttons
  defp render_buttons(graph, %State{} = state) do
    %{dimensions: dims, theme: theme} = state

    confirm_color = if state.selected_index do
      theme.button_confirm
    else
      theme.button_confirm_disabled
    end

    {cancel_x, cancel_y, btn_w, btn_h} = State.cancel_button_bounds(state)
    {confirm_x, confirm_y, _, _} = State.confirm_button_bounds(state)

    graph
    # Cancel button
    |> rrect({btn_w, btn_h, 4},
        fill: theme.button_cancel,
        translate: {cancel_x, cancel_y})
    |> text(state.cancel_label,
        translate: {cancel_x + 15, cancel_y + 22},
        fill: theme.button_text,
        font_size: 14)
    # Confirm button
    |> rrect({btn_w, btn_h, 4},
        fill: confirm_color,
        translate: {confirm_x, confirm_y})
    |> text(state.confirm_label,
        translate: {confirm_x + 20, confirm_y + 22},
        fill: theme.button_text,
        font_size: 14)
  end

  # Helper to get viewport size from frame
  defp get_size(%{size: %{width: w, height: h}}), do: {w, h}
  defp get_size(%{size: {w, h}}), do: {w, h}
  defp get_size(frame) when is_map(frame) do
    case frame[:size] do
      {w, h} -> {w, h}
      %{width: w, height: h} -> {w, h}
      _ -> {800, 600}
    end
  end
end
