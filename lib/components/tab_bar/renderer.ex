defmodule ScenicWidgets.TabBar.Renderer do
  @moduledoc """
  Rendering functions for TabBar.

  Structure:
  - Background rect (full width)
  - Tab group (contains all tabs, translated for scrolling)
  - Selection indicator (colored stripe at bottom of selected tab)
  """

  alias Scenic.Graph
  alias Scenic.Primitives
  alias ScenicWidgets.TabBar.State

  @doc """
  Initial render - create all UI elements.
  """
  def initial_render(graph, %State{} = state) do
    graph
    |> render_background(state)
    |> Primitives.group(
      fn clipped ->
        clipped
        |> render_all_tabs(state)
        |> render_selection_indicator(state)
      end,
      id: :tab_viewport,
      scissor: {state.frame.size.width, state.theme.height}
    )
    |> render_semantic_content(state)
  end

  @doc """
  Update render - only modify elements that changed.
  """
  def update_render(graph, %State{} = old_state, %State{} = new_state) do
    graph
    |> update_scroll_if_changed(old_state, new_state)
    |> update_hover_if_changed(old_state, new_state)
    |> update_selection_if_changed(old_state, new_state)
    |> update_selection_indicator(old_state, new_state)
    |> update_semantic_if_changed(old_state, new_state)
  end

  # ===========================================================================
  # Initial Rendering
  # ===========================================================================

  defp render_background(graph, %State{frame: frame, theme: theme}) do
    graph
    |> Primitives.rect(
      {frame.size.width, theme.height},
      id: :tab_bar_background,
      fill: theme.background
    )
  end

  defp render_all_tabs(graph, %State{tabs: tabs} = state) do
    # Build each tab as a separate group on the graph
    # They will be positioned based on cumulative widths
    Enum.reduce(tabs, graph, fn tab, acc ->
      build_tab_group(acc, state, tab)
    end)
  end

  defp build_tab_group(graph, %State{theme: theme, scroll_offset: offset} = state, tab) do
    # Calculate position
    {base_x, _y, width, height} = State.get_tab_bounds(state, tab.id)
    # get_tab_bounds already accounts for scroll, so base_x is the visual position
    # But we want the logical position, then translate the whole group
    logical_x = base_x + offset

    is_selected = state.selected_id == tab.id
    is_hovered = state.hovered_tab_id == tab.id

    bg_color =
      cond do
        is_selected -> theme.tab_selected_background
        is_hovered -> theme.tab_hover_background
        true -> theme.tab_background
      end

    text_color = if is_selected, do: theme.text_selected_color, else: theme.text_color

    # Calculate text bounds (leave room for close button if closeable)
    close_width =
      if tab.closeable, do: theme.close_button_size + theme.close_button_margin, else: 0

    text_max_width = width - theme.tab_padding * 2 - close_width
    truncated_label = truncate_label(tab.label, text_max_width, theme.font_size)

    # Build the tab group
    # Use string ID so ScenicMCP click_element("tab_bar_<uuid>") can find this element
    tab_semantic_id = "tab_bar_#{tab.id}"

    graph
    |> Primitives.group(
      fn g ->
        g
        # Tab background
        |> Primitives.rect(
          {width, height},
          id: {:tab_bg, tab.id},
          fill: bg_color
        )
        # Right separator line
        |> Primitives.line(
          {{width - 1, 4}, {width - 1, height - 4}},
          id: {:tab_separator, tab.id},
          stroke: {1, theme.separator_color}
        )
        # Tab label
        |> Primitives.text(
          truncated_label,
          id: {:tab_label, tab.id},
          fill: text_color,
          font: theme.font,
          font_size: theme.font_size,
          translate: {theme.tab_padding, height / 2 + theme.font_size / 3}
        )
        # Close button (if closeable)
        |> maybe_build_close_button(tab, state)
      end,
      id: tab_semantic_id,
      semantic: %{type: :tab, tab_id: tab.id},
      # Apply scroll offset to position
      translate: {logical_x - offset, 0}
    )
  end

  defp maybe_build_close_button(graph, %{closeable: false}, _state), do: graph

  defp maybe_build_close_button(graph, tab, %State{theme: theme} = state) do
    is_hovered = state.hovered_close_id == tab.id
    color = if is_hovered, do: theme.close_button_hover_color, else: theme.close_button_color

    {_tab_x, _tab_y, tab_width, tab_height} = State.get_tab_bounds(state, tab.id)
    size = theme.close_button_size
    margin = theme.close_button_margin

    # Position relative to tab (we're inside the tab group)
    x = tab_width - size - margin
    y = (tab_height - size) / 2

    # Draw X shape
    # Use string ID so ScenicMCP click_element("tab_bar_close_<uuid>") can find this element
    close_semantic_id = "tab_bar_close_#{tab.id}"

    padding = 4

    graph
    |> Primitives.group(
      fn g ->
        g
        # Hover background circle
        |> Primitives.circle(
          size / 2,
          id: {:close_bg, tab.id},
          fill: if(is_hovered, do: {80, 80, 80}, else: :clear),
          translate: {size / 2, size / 2}
        )
        # X lines
        |> Primitives.line(
          {{padding, padding}, {size - padding, size - padding}},
          id: {:close_x1, tab.id},
          stroke: {1.5, color}
        )
        |> Primitives.line(
          {{size - padding, padding}, {padding, size - padding}},
          id: {:close_x2, tab.id},
          stroke: {1.5, color}
        )
      end,
      id: close_semantic_id,
      semantic: %{type: :tab_close, tab_id: tab.id},
      translate: {x, y}
    )
  end

  defp render_selection_indicator(graph, %State{selected_id: nil}), do: graph

  defp render_selection_indicator(graph, %State{theme: theme} = state) do
    case State.get_tab_bounds(state, state.selected_id) do
      nil ->
        graph

      {x, _y, width, _height} ->
        # Render indicator at bottom of tab bar (using theme.height for consistency)
        indicator_y = theme.height - theme.selection_indicator_height

        graph
        |> Primitives.rect(
          {width, theme.selection_indicator_height},
          id: :selection_indicator,
          fill: theme.selection_indicator_color,
          translate: {x, indicator_y}
        )
    end
  end

  # ===========================================================================
  # Update Rendering
  # ===========================================================================

  defp update_scroll_if_changed(graph, %{scroll_offset: old}, %{scroll_offset: new})
       when old == new do
    graph
  end

  defp update_scroll_if_changed(
         graph,
         _old_state,
         %{tabs: tabs, scroll_offset: offset} = new_state
       ) do
    # Update each tab's position based on new scroll offset
    Enum.reduce(tabs, graph, fn tab, acc ->
      {base_x, _y, _w, _h} = State.get_tab_bounds(new_state, tab.id)
      logical_x = base_x + offset

      Graph.modify(acc, "tab_bar_#{tab.id}", fn p ->
        Primitives.update_opts(p, translate: {logical_x - offset, 0})
      end)
    end)
  end

  defp update_hover_if_changed(graph, old_state, new_state) do
    # Only update if hover state changed
    if old_state.hovered_tab_id == new_state.hovered_tab_id and
         old_state.hovered_close_id == new_state.hovered_close_id do
      graph
    else
      theme = new_state.theme

      # Update previously hovered tab background
      graph =
        if old_state.hovered_tab_id && old_state.hovered_tab_id != new_state.hovered_tab_id do
          is_selected = old_state.hovered_tab_id == new_state.selected_id
          bg_color = if is_selected, do: theme.tab_selected_background, else: theme.tab_background

          Graph.modify(graph, {:tab_bg, old_state.hovered_tab_id}, fn p ->
            Primitives.update_opts(p, fill: bg_color)
          end)
        else
          graph
        end

      # Update newly hovered tab background
      graph =
        if new_state.hovered_tab_id && old_state.hovered_tab_id != new_state.hovered_tab_id do
          is_selected = new_state.hovered_tab_id == new_state.selected_id

          bg_color =
            if is_selected, do: theme.tab_selected_background, else: theme.tab_hover_background

          Graph.modify(graph, {:tab_bg, new_state.hovered_tab_id}, fn p ->
            Primitives.update_opts(p, fill: bg_color)
          end)
        else
          graph
        end

      # Update close button hover states
      graph =
        if old_state.hovered_close_id && old_state.hovered_close_id != new_state.hovered_close_id do
          update_close_button_hover(graph, old_state.hovered_close_id, false, theme)
        else
          graph
        end

      if new_state.hovered_close_id && old_state.hovered_close_id != new_state.hovered_close_id do
        update_close_button_hover(graph, new_state.hovered_close_id, true, theme)
      else
        graph
      end
    end
  end

  defp update_close_button_hover(graph, tab_id, is_hovered, theme) do
    color = if is_hovered, do: theme.close_button_hover_color, else: theme.close_button_color
    bg_fill = if is_hovered, do: {80, 80, 80}, else: :clear

    graph
    |> Graph.modify({:close_bg, tab_id}, fn p ->
      Primitives.update_opts(p, fill: bg_fill)
    end)
    |> Graph.modify({:close_x1, tab_id}, fn p ->
      Primitives.update_opts(p, stroke: {1.5, color})
    end)
    |> Graph.modify({:close_x2, tab_id}, fn p ->
      Primitives.update_opts(p, stroke: {1.5, color})
    end)
  end

  defp update_selection_if_changed(graph, %{selected_id: old}, %{selected_id: new})
       when old == new do
    graph
  end

  defp update_selection_if_changed(graph, old_state, new_state) do
    theme = new_state.theme

    # Un-highlight previously selected tab
    graph =
      if old_state.selected_id do
        is_hovered = old_state.selected_id == new_state.hovered_tab_id
        bg_color = if is_hovered, do: theme.tab_hover_background, else: theme.tab_background

        graph
        |> Graph.modify({:tab_bg, old_state.selected_id}, fn p ->
          Primitives.update_opts(p, fill: bg_color)
        end)
        |> Graph.modify({:tab_label, old_state.selected_id}, fn p ->
          Primitives.update_opts(p, fill: theme.text_color)
        end)
      else
        graph
      end

    # Highlight newly selected tab
    if new_state.selected_id do
      graph
      |> Graph.modify({:tab_bg, new_state.selected_id}, fn p ->
        Primitives.update_opts(p, fill: theme.tab_selected_background)
      end)
      |> Graph.modify({:tab_label, new_state.selected_id}, fn p ->
        Primitives.update_opts(p, fill: theme.text_selected_color)
      end)
    else
      graph
    end
  end

  defp update_selection_indicator(graph, old_state, new_state) do
    theme = new_state.theme
    indicator_y = theme.height - theme.selection_indicator_height

    cond do
      # Selection changed
      old_state.selected_id != new_state.selected_id ->
        case State.get_tab_bounds(new_state, new_state.selected_id) do
          nil ->
            Graph.modify(graph, :selection_indicator, fn p ->
              Primitives.update_opts(p, hidden: true)
            end)

          {x, _y, width, _height} ->
            graph
            |> Graph.modify(:selection_indicator, fn p ->
              p
              |> Primitives.update_opts(
                hidden: false,
                translate: {x, indicator_y}
              )
              |> Primitives.rect({width, theme.selection_indicator_height})
            end)
        end

      # Just scroll changed - update indicator position
      old_state.scroll_offset != new_state.scroll_offset ->
        case State.get_tab_bounds(new_state, new_state.selected_id) do
          nil ->
            graph

          {x, _y, _w, _height} ->
            Graph.modify(graph, :selection_indicator, fn p ->
              Primitives.update_opts(p, translate: {x, indicator_y})
            end)
        end

      true ->
        graph
    end
  end

  # ===========================================================================
  # Semantic Content (for testing/automation)
  # ===========================================================================

  defp render_semantic_content(graph, %State{} = state) do
    graph
    |> Primitives.text(
      # Empty text - just used as semantic carrier
      "",
      id: :semantic_tab_bar_content,
      hidden: true,
      semantic: semantic_metadata(state)
    )
  end

  defp update_semantic_if_changed(graph, old_state, new_state) do
    if semantic_changed?(old_state, new_state) do
      Graph.modify(graph, :semantic_tab_bar_content, fn p ->
        Primitives.update_opts(p, semantic: semantic_metadata(new_state))
      end)
    else
      graph
    end
  end

  defp semantic_changed?(old_state, new_state) do
    old_state.tabs != new_state.tabs or
      old_state.selected_id != new_state.selected_id
  end

  defp semantic_metadata(%State{tabs: tabs, selected_id: selected_id}) do
    %{
      type: :tab_bar,
      tab_count: length(tabs),
      selected_id: selected_id,
      tabs:
        Enum.map(tabs, fn tab ->
          %{
            id: tab.id,
            label: tab.label,
            selected: tab.id == selected_id,
            closeable: tab.closeable
          }
        end)
    }
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp truncate_label(label, max_width, font_size) do
    char_width = font_size * 0.6
    max_chars = trunc(max_width / char_width)

    if String.length(label) <= max_chars do
      label
    else
      String.slice(label, 0, max(0, max_chars - 3)) <> "..."
    end
  end
end
