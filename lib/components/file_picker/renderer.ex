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
  @header_height 92
  @footer_height_open 76
  @footer_height_save 128
  @item_height 30
  @padding 18
  @border_radius 8
  @input_height 32

  @doc """
  Initial render of the FilePicker modal.
  """
  def initial_render(graph, %State{frame: frame} = state) do
    {modal_frame, list_frame} = calculate_frames(state)

    graph
    |> render_overlay(frame, state)
    |> render_modal_background(modal_frame, state)
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
        |> Graph.delete(:header_bg)
        |> Graph.delete(:path_text)
        |> Graph.delete(:up_button)
        |> Graph.delete(:project_root_button)
        |> Graph.delete(:home_button)
        |> Graph.delete(:disk_root_button)
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
  defp render_overlay(graph, %Frame{} = frame, state) do
    ScenicWidgets.ModalShell.overlay(graph, frame, :overlay,
      fill: color(state, :overlay, @bg_overlay)
    )
  end

  # Render modal background
  defp render_modal_background(graph, %Frame{} = modal_frame, state) do
    {width, height} = modal_frame.size.box
    {x, y} = modal_frame.pin.point

    graph
    |> Primitives.rrect({width, height, @border_radius},
      id: :modal_bg,
      fill: color(state, :panel, @modal_bg),
      stroke: {1, color(state, :panel_border, @modal_border)},
      translate: {x, y}
    )
  end

  # Render header with path
  defp render_header(graph, %Frame{} = modal_frame, %State{} = state) do
    {width, _height} = modal_frame.size.box
    {x, y} = modal_frame.pin.point

    # Truncate path if too long
    display_path = truncate_path(state.current_path, width - 36)

    graph
    # Header background
    |> Primitives.rrect({width, @header_height, @border_radius},
      id: :header_bg,
      fill: color(state, :header, @header_bg),
      translate: {x, y}
    )
    |> render_location_button(:up, "Up", :up_button, {x + 16, y + 12}, {64, 32}, state)
    |> render_button(
      "Project root",
      :project_root_button,
      {x + 88, y + 12},
      {108, 32},
      :default,
      state
    )
    |> render_location_button(:home, nil, :home_button, {x + 204, y + 12}, {44, 32}, state)
    |> render_location_button(
      :disk,
      nil,
      :disk_root_button,
      {x + 256, y + 12},
      {44, 32},
      state
    )
    # Path text
    |> Primitives.text(display_path,
      id: :path_text,
      font_size: 14,
      fill: color(state, :dim_text, @path_color),
      translate: {x + 16, y + 70}
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
          fill: color(state, :surface, @list_bg),
          stroke: {1, color(state, :panel_border, {200, 200, 200})}
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
  defp render_entries(graph, %State{entries: entries, selected_index: selected_idx} = state) do
    entries
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {entry, idx}, g ->
      render_entry(g, entry, idx, idx == selected_idx, state)
    end)
  end

  # Render a single entry (file or folder)
  defp render_entry(graph, entry, idx, selected, state) do
    y = idx * @item_height

    {bg_color, text_color} =
      if selected do
        {color(state, :selected, @selected_bg), color(state, :selected_text, @selected_text)}
      else
        {:transparent,
         if(entry.type == :directory,
           do: color(state, :accent, @folder_color),
           else: color(state, :text, @file_color)
         )}
      end

    graph
    |> Primitives.group(
      fn g ->
        g
        # Selection background
        |> Primitives.rect({600, @item_height},
          id: :"entry_bg_#{idx}",
          fill: bg_color
        )
        |> maybe_render_entry_icon(entry.type, text_color)
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

  defp maybe_render_entry_icon(graph, :file, _color), do: graph

  defp maybe_render_entry_icon(graph, :directory, color) do
    location_icon(graph, :folder, 18, 15, color)
  end

  # Render footer with buttons (open mode)
  defp render_footer(graph, %Frame{} = modal_frame, %State{mode: :open} = state) do
    {width, height} = modal_frame.size.box
    {x, y} = modal_frame.pin.point

    footer_y = y + height - @footer_height_open

    graph
    # Footer background for visibility
    |> Primitives.rect({width, @footer_height_open},
      id: :footer_bg,
      fill: color(state, :header, @header_bg),
      translate: {x, footer_y}
    )
    # Cancel button (custom drawn)
    |> render_button(
      "Cancel",
      :cancel_button,
      {x + width - 208, footer_y + 20},
      {88, 36},
      :default,
      state
    )
    # Open button (custom drawn, primary style)
    |> render_button(
      "Open",
      :open_button,
      {x + width - 108, footer_y + 20},
      {88, 36},
      :primary,
      state
    )
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
      fill: color(state, :header, @header_bg),
      translate: {x, footer_y}
    )
    # "File name:" label
    |> Primitives.text("File name:",
      id: :filename_label,
      font_size: 14,
      fill: color(state, :dim_text, @path_color),
      translate: {x + @padding, footer_y + 23}
    )
    # Filename input field
    |> render_filename_input({x + @padding, footer_y + 32}, input_width, state)
    # Cancel button
    |> render_button(
      "Cancel",
      :cancel_button,
      {x + width - 208, footer_y + 80},
      {88, 36},
      :default,
      state
    )
    # Save button (primary style)
    |> render_button(
      "Save",
      :save_button,
      {x + width - 108, footer_y + 80},
      {88, 36},
      :primary,
      state
    )
  end

  # Render the filename text input
  defp render_filename_input(
         graph,
         {input_x, input_y},
         width,
         %State{
           filename: filename,
           font: font
         } = state
       ) do
    ScenicWidgets.TextField.add_to_graph(
      graph,
      %{
        id: :filename_input,
        # Components draw and hit-test in their own coordinate system. Pinning
        # the field's internal frame at its parent-space position made it look
        # displaced and made clicks miss; the component itself is translated.
        frame: Frame.new(pin: {0, 0}, size: {width, @input_height}),
        initial_text: filename,
        mode: :single_line,
        input_mode: :direct,
        show_line_numbers: false,
        font: font,
        placeholder: "Name this file",
        colors: text_field_colors(state)
      },
      id: :filename_input,
      translate: {input_x, input_y}
    )
  end

  # Update filename input when typing
  defp update_filename_input(graph, _modal_frame, _state), do: graph

  # Custom button renderer using primitives
  defp render_button(graph, label, id, {bx, by}, {bw, bh}, style, state) do
    {bg_color, text_color, border_color} =
      case style do
        :primary ->
          {color(state, :accent, {66, 133, 244}), color(state, :accent_text, :white),
           color(state, :accent, {55, 120, 220})}

        _ ->
          {color(state, :button, {220, 220, 220}), color(state, :button_text, {50, 50, 50}),
           color(state, :panel_border, {180, 180, 180})}
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

  # Navigation icons are Scenic primitives, not font characters. This keeps
  # them crisp and present regardless of which editor font the host supplies.
  defp render_location_button(graph, icon, label, id, {bx, by}, {bw, bh}, state) do
    bg = color(state, :button, {220, 220, 220})
    fg = color(state, :button_text, {50, 50, 50})
    border = color(state, :panel_border, {180, 180, 180})
    icon_x = if label, do: 18, else: bw / 2

    graph
    |> Primitives.group(
      fn g ->
        g
        |> Primitives.rrect({bw, bh, 4}, fill: bg, stroke: {2, border})
        |> location_icon(icon, icon_x, bh / 2, fg)
        |> maybe_location_label(label, bw, bh, fg)
      end,
      id: id,
      translate: {bx, by}
    )
  end

  defp maybe_location_label(graph, nil, _bw, _bh, _color), do: graph

  defp maybe_location_label(graph, label, bw, bh, color) do
    Primitives.text(graph, label,
      font_size: 13,
      fill: color,
      text_align: :center,
      translate: {(bw + 18) / 2, bh / 2 + 5}
    )
  end

  defp location_icon(graph, :up, cx, cy, color) do
    graph
    |> Primitives.line({{cx, cy + 6}, {cx, cy - 6}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx, cy - 6}, {cx - 5, cy - 1}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx, cy - 6}, {cx + 5, cy - 1}}, stroke: {2, color}, cap: :round)
  end

  defp location_icon(graph, :home, cx, cy, color) do
    graph
    |> Primitives.line({{cx - 8, cy - 1}, {cx, cy - 8}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx, cy - 8}, {cx + 8, cy - 1}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx - 6, cy - 2}, {cx - 6, cy + 7}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx + 6, cy - 2}, {cx + 6, cy + 7}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx - 6, cy + 7}, {cx + 6, cy + 7}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx - 2, cy + 7}, {cx - 2, cy + 1}}, stroke: {2, color}, cap: :round)
  end

  defp location_icon(graph, :folder, cx, cy, color) do
    graph
    |> Primitives.rrect({18, 12, 2},
      translate: {cx - 9, cy - 4},
      stroke: {2, color},
      fill: :transparent
    )
    |> Primitives.line({{cx - 7, cy - 4}, {cx - 4, cy - 8}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx - 4, cy - 8}, {cx + 1, cy - 8}}, stroke: {2, color}, cap: :round)
    |> Primitives.line({{cx + 1, cy - 8}, {cx + 4, cy - 4}}, stroke: {2, color}, cap: :round)
  end

  defp location_icon(graph, :disk, cx, cy, color) do
    graph
    |> Primitives.rrect({22, 12, 3},
      translate: {cx - 11, cy - 6},
      stroke: {2, color},
      fill: :transparent
    )
    |> Primitives.line({{cx - 9, cy + 1}, {cx + 9, cy + 1}},
      stroke: {1.5, color},
      cap: :round
    )
    |> Primitives.line({{cx - 7, cy + 4}, {cx + 1, cy + 4}},
      stroke: {1.5, color},
      cap: :round
    )
    |> Primitives.circle(1.4, fill: color, translate: {cx + 7, cy + 4})
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
      |> maybe_update_entry_style(old_idx, old_entry, false, new_state)
      # Set new selection
      |> maybe_update_entry_style(new_idx, new_entry, true, new_state)
    end
  end

  defp maybe_update_entry_style(graph, _idx, nil, _selected, _state), do: graph

  defp maybe_update_entry_style(graph, idx, entry, selected, state) do
    {bg_color, text_color} =
      if selected do
        {color(state, :selected, @selected_bg), color(state, :selected_text, @selected_text)}
      else
        {:transparent,
         if(entry.type == :directory,
           do: color(state, :accent, @folder_color),
           else: color(state, :text, @file_color)
         )}
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

  defp color(%State{theme: theme}, key, fallback), do: Map.get(theme || %{}, key, fallback)

  defp text_field_colors(state) do
    %{
      background: color(state, :surface, {30, 30, 35}),
      text: color(state, :text, :white),
      cursor: color(state, :accent, :white),
      selection: selection_color(state),
      border: color(state, :field_border, {90, 90, 100}),
      focused_border: color(state, :focus_border, {0, 150, 255}),
      placeholder: color(state, :dim_text, {140, 140, 150})
    }
  end

  # TextField's selection renderer deliberately wraps this value as an RGBA
  # paint, so an opaque three-channel design token must be made explicit.
  defp selection_color(state) do
    case color(state, :selected, {70, 130, 180, 180}) do
      {r, g, b} -> {r, g, b, 255}
      rgba -> rgba
    end
  end
end
