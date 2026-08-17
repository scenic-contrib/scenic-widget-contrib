defmodule ScenicWidgets.FilePicker.Renderer do
  @moduledoc """
  Rendering functions for the FilePicker component.
  """

  use Widgex.Scrollable, direction: :vertical

  alias Scenic.Graph
  alias Scenic.Primitives
  alias Scenic.Components
  alias Widgex.Frame
  alias ScenicWidgets.FilePicker.State

  # Colors
  @bg_overlay {0, 0, 0, 128}
  @modal_bg :white
  @modal_border :dark_gray
  @header_bg {240, 240, 240}
  @list_bg :white
  @selected_bg {51, 153, 255}
  @selected_text :white
  @folder_color {66, 133, 244}
  @file_color {97, 97, 97}
  @path_color {100, 100, 100}

  # Dimensions
  @header_height 60
  @footer_height_open 70
  @footer_height_save 110
  @item_height 28
  @padding 20
  @border_radius 8
  @input_height 32

  @doc """
  Initial render of the FilePicker modal.
  """
  def initial_render(graph, %State{frame: frame} = state) do
    {modal_frame, list_frame} = calculate_frames(state)

    graph
    |> render_overlay(frame)
    |> render_modal_background(modal_frame)
    |> render_header(modal_frame, state)
    |> render_file_list(modal_frame, list_frame, state)
    |> render_footer(modal_frame, state)
  end

  @doc """
  Update render when state changes.
  """
  def update_render(graph, %State{} = old_state, %State{} = new_state) do
    {modal_frame, list_frame} = calculate_frames(new_state)

    # Check what changed
    path_changed = old_state.current_path != new_state.current_path
    selection_changed = old_state.selected_index != new_state.selected_index
    scroll_changed = scroll_changed?(old_state.scroll, new_state.scroll)

    filename_changed =
      old_state.filename != new_state.filename or
        old_state.filename_cursor != new_state.filename_cursor

    cond do
      path_changed ->
        # Full re-render of list when directory changes
        graph
        |> Graph.delete(:file_list_group)
        |> Graph.delete(:path_text)
        |> render_header(modal_frame, new_state)
        |> render_file_list(modal_frame, list_frame, new_state)

      filename_changed and new_state.mode == :save ->
        # Update filename input in save mode
        graph
        |> update_filename_input(modal_frame, new_state)

      selection_changed or scroll_changed ->
        # Update list content and scroll position
        graph
        |> update_scroll_transform(:file_list_content, old_state.scroll, new_state.scroll)
        |> update_selection(old_state, new_state)
        |> update_scrollbars(old_state.scroll, new_state.scroll, list_frame)

      true ->
        graph
    end
  end

  # Calculate modal and list frames based on mode
  defp calculate_frames(%State{frame: frame, mode: mode}) do
    {frame_width, frame_height} = frame.size.box
    modal_width = frame_width * 0.7
    modal_height = frame_height * 0.7
    modal_x = (frame_width - modal_width) / 2
    modal_y = (frame_height - modal_height) / 2

    modal_frame =
      Frame.new(
        pin: {modal_x, modal_y},
        size: {modal_width, modal_height}
      )

    footer_height = if mode == :save, do: @footer_height_save, else: @footer_height_open
    list_height = modal_height - @header_height - footer_height

    list_frame =
      Frame.new(
        pin: {0, 0},
        size: {modal_width - @padding * 2, list_height}
      )

    {modal_frame, list_frame}
  end

  # Render semi-transparent overlay
  defp render_overlay(graph, %Frame{} = frame) do
    ScenicWidgets.ModalShell.overlay(graph, frame, :overlay, fill: @bg_overlay)
  end

  # Render modal background
  defp render_modal_background(graph, %Frame{} = modal_frame) do
    {width, height} = modal_frame.size.box
    {x, y} = modal_frame.pin.point

    graph
    |> Primitives.rrect({width, height, @border_radius},
      id: :modal_bg,
      fill: @modal_bg,
      stroke: {2, @modal_border},
      translate: {x, y}
    )
  end

  # Render header with path
  defp render_header(graph, %Frame{} = modal_frame, %State{} = state) do
    {width, _height} = modal_frame.size.box
    {x, y} = modal_frame.pin.point

    # Truncate path if too long
    display_path = truncate_path(state.current_path, width - 120)

    graph
    # Header background
    |> Primitives.rrect({width, @header_height, @border_radius},
      id: :header_bg,
      fill: @header_bg,
      translate: {x, y}
    )
    # Up button (custom drawn)
    |> render_button("< Up", :up_button, {x + 15, y + 12}, {60, 36})
    # Path text
    |> Primitives.text(display_path,
      id: :path_text,
      font_size: 14,
      fill: @path_color,
      translate: {x + 90, y + 38}
    )
  end

  # Render the scrollable file list
  defp render_file_list(graph, %Frame{} = modal_frame, %Frame{} = list_frame, %State{} = state) do
    {modal_width, modal_height} = modal_frame.size.box
    {modal_x, modal_y} = modal_frame.pin.point
    {list_width, list_height} = list_frame.size.box

    list_x = modal_x + @padding
    list_y = modal_y + @header_height

    graph
    |> Primitives.group(
      fn g ->
        g
        # List background
        |> Primitives.rect({list_width, list_height},
          fill: @list_bg,
          stroke: {1, {200, 200, 200}}
        )
        # Scrollable file list content
        |> scrollable_group(
          state.scroll,
          list_frame,
          fn list_g ->
            render_entries(list_g, state)
          end,
          id: :file_list_content
        )
        # Scrollbars
        |> render_scrollbars(state.scroll, list_frame)
      end,
      id: :file_list_group,
      translate: {list_x, list_y}
    )
  end

  # Render all file/folder entries
  defp render_entries(graph, %State{entries: entries, selected_index: selected_idx}) do
    entries
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {entry, idx}, g ->
      render_entry(g, entry, idx, idx == selected_idx)
    end)
  end

  # Render a single entry (file or folder)
  defp render_entry(graph, entry, idx, selected) do
    y = idx * @item_height

    {bg_color, text_color} =
      if selected do
        {@selected_bg, @selected_text}
      else
        {:transparent, if(entry.type == :directory, do: @folder_color, else: @file_color)}
      end

    icon = if entry.type == :directory, do: "[D]", else: "   "

    graph
    |> Primitives.group(
      fn g ->
        g
        # Selection background
        |> Primitives.rect({600, @item_height},
          id: :"entry_bg_#{idx}",
          fill: bg_color
        )
        # Icon
        |> Primitives.text(icon,
          font_size: 14,
          fill: text_color,
          translate: {8, 18}
        )
        # Name
        |> Primitives.text(entry.name,
          id: :"entry_text_#{idx}",
          font_size: 14,
          fill: text_color,
          translate: {40, 18}
        )
      end,
      id: :"entry_#{idx}",
      translate: {0, y}
    )
  end

  # Render footer with buttons (open mode)
  defp render_footer(graph, %Frame{} = modal_frame, %State{mode: :open}) do
    {width, height} = modal_frame.size.box
    {x, y} = modal_frame.pin.point

    footer_y = y + height - @footer_height_open

    graph
    # Footer background for visibility
    |> Primitives.rect({width, @footer_height_open},
      id: :footer_bg,
      fill: @header_bg,
      translate: {x, footer_y}
    )
    # Cancel button (custom drawn)
    |> render_button("Cancel", :cancel_button, {x + width - 200, footer_y + 15}, {85, 36})
    # Open button (custom drawn, primary style)
    |> render_button("Open", :open_button, {x + width - 100, footer_y + 15}, {85, 36}, :primary)
  end

  # Render footer with filename input and buttons (save mode)
  defp render_footer(graph, %Frame{} = modal_frame, %State{mode: :save} = state) do
    {width, height} = modal_frame.size.box
    {x, y} = modal_frame.pin.point

    footer_y = y + height - @footer_height_save
    input_width = width - @padding * 2

    graph
    # Footer background
    |> Primitives.rect({width, @footer_height_save},
      id: :footer_bg,
      fill: @header_bg,
      translate: {x, footer_y}
    )
    # "File name:" label
    |> Primitives.text("File name:",
      id: :filename_label,
      font_size: 14,
      fill: @path_color,
      translate: {x + @padding, footer_y + 22}
    )
    # Filename input field
    |> render_filename_input({x + @padding, footer_y + 30}, input_width, state)
    # Cancel button
    |> render_button("Cancel", :cancel_button, {x + width - 200, footer_y + 72}, {85, 36})
    # Save button (primary style)
    |> render_button("Save", :save_button, {x + width - 100, footer_y + 72}, {85, 36}, :primary)
  end

  # Render the filename text input
  defp render_filename_input(graph, {input_x, input_y}, width, %State{
         filename: filename,
         font: font
       }) do
    ScenicWidgets.TextField.add_to_graph(
      graph,
      %{
        id: :filename_input,
        frame: Frame.new(pin: {input_x, input_y}, size: {width, @input_height}),
        initial_text: filename,
        mode: :single_line,
        input_mode: :direct,
        show_line_numbers: false,
        font: font
      },
      id: :filename_input
    )
  end

  # Update filename input when typing
  defp update_filename_input(graph, _modal_frame, _state), do: graph

  # Custom button renderer using primitives
  defp render_button(graph, label, id, {bx, by}, {bw, bh}, style \\ :default) do
    {bg_color, text_color, border_color} =
      case style do
        :primary -> {{66, 133, 244}, :white, {55, 120, 220}}
        _ -> {{220, 220, 220}, {50, 50, 50}, {180, 180, 180}}
      end

    graph
    |> Primitives.group(
      fn g ->
        g
        # Button background
        |> Primitives.rrect({bw, bh, 4},
          fill: bg_color,
          stroke: {2, border_color}
        )
        # Button label
        |> Primitives.text(label,
          font_size: 14,
          fill: text_color,
          text_align: :center,
          translate: {bw / 2, bh / 2 + 5}
        )
      end,
      id: id,
      translate: {bx, by}
    )
  end

  # Update selection highlighting
  defp update_selection(graph, old_state, new_state) do
    old_idx = old_state.selected_index
    new_idx = new_state.selected_index

    if old_idx == new_idx do
      graph
    else
      old_entry = Enum.at(old_state.entries, old_idx)
      new_entry = Enum.at(new_state.entries, new_idx)

      graph
      # Clear old selection
      |> maybe_update_entry_style(old_idx, old_entry, false)
      # Set new selection
      |> maybe_update_entry_style(new_idx, new_entry, true)
    end
  end

  defp maybe_update_entry_style(graph, _idx, nil, _selected), do: graph

  defp maybe_update_entry_style(graph, idx, entry, selected) do
    {bg_color, text_color} =
      if selected do
        {@selected_bg, @selected_text}
      else
        {:transparent, if(entry.type == :directory, do: @folder_color, else: @file_color)}
      end

    graph
    |> Graph.modify(:"entry_bg_#{idx}", fn prim ->
      Scenic.Primitive.put_style(prim, :fill, bg_color)
    end)
    |> Graph.modify(:"entry_text_#{idx}", fn prim ->
      Scenic.Primitive.put_style(prim, :fill, text_color)
    end)
  rescue
    # Entry might not exist
    _ -> graph
  end

  # Truncate path to fit in available width
  defp truncate_path(path, max_width) do
    # Rough estimate: ~7 pixels per character
    max_chars = trunc(max_width / 7)

    if String.length(path) <= max_chars do
      path
    else
      # Show ".../" + last part of path
      parts = Path.split(path)
      truncated = ["...", List.last(parts)] |> Path.join()

      if String.length(truncated) <= max_chars do
        truncated
      else
        String.slice(path, -max_chars..-1)
      end
    end
  end
end
