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
        # Last, so the drop line sits above the tabs it is pointing between.
        |> render_drop_indicator(state)
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
    |> update_drag_if_changed(old_state, new_state)
    |> update_semantic_if_changed(old_state, new_state)
  end

  # Drag feedback is patched in, never rebuilt.
  #
  # The drop indicator is always present in the graph and merely painted
  # `:clear` when idle, for the same reason the rest of this module works by
  # `Graph.modify`: a press is the start of an ordinary tab click, and
  # discarding the whole graph on every mouse-down made each click cost two full
  # graph rebuilds and re-pushes.
  defp update_drag_if_changed(graph, old_state, new_state) do
    if old_state.drag_active? == new_state.drag_active? and
         old_state.dragging_tab_id == new_state.dragging_tab_id do
      graph
    else
      graph
      |> restyle_tab(old_state.dragging_tab_id, new_state)
      |> restyle_tab(new_state.dragging_tab_id, new_state)
      |> update_drop_indicator(new_state)
    end
  end

  defp restyle_tab(graph, nil, _state), do: graph

  defp restyle_tab(graph, tab_id, state) do
    Graph.modify(graph, {:tab_bg, tab_id}, fn p ->
      Primitives.update_opts(p, fill: tab_background_color(state, tab_id))
    end)
  end

  defp update_drop_indicator(graph, %State{} = state) do
    Graph.modify(graph, :tab_drop_indicator, fn p ->
      Primitives.update_opts(p,
        fill: drop_indicator_fill(state),
        translate: drop_indicator_translate(state)
      )
    end)
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
    is_dragging = dragging?(state, tab.id)
    bg_color = tab_background_color(state, tab.id)

    text_color =
      if is_selected or is_dragging, do: theme.text_selected_color, else: theme.text_color

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
          font: tab_font(tab, theme),
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

  defp dragging?(%State{drag_active?: true, dragging_tab_id: id}, id) when not is_nil(id), do: true
  defp dragging?(_state, _tab_id), do: false

  # The one place a tab's fill is decided, so the hover, selection and drag
  # update paths cannot disagree about what colour a tab should be — hovering a
  # tab mid-drag used to be able to paint over its lifted background.
  defp tab_background_color(%State{theme: theme} = state, tab_id) do
    cond do
      # Lifted: the tab in flight reads as picked up rather than merely
      # selected, so it stays findable as the others shuffle around it.
      dragging?(state, tab_id) ->
        Map.get(theme, :tab_drag_background, theme.tab_hover_background)

      state.selected_id == tab_id ->
        theme.tab_selected_background

      state.hovered_tab_id == tab_id ->
        theme.tab_hover_background

      true ->
        theme.tab_background
    end
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

  # The line marking where the dragged tab will land.
  #
  # Anchored to the leading edge of the dragged tab's current slot, not to the
  # pointer: tabs shuffle live as you cross a neighbour's centre, so the slot IS
  # the answer to "where will this drop?", and a line chasing the cursor would
  # disagree with the tabs the moment they moved.
  #
  # Always drawn, and simply invisible when no drag is in flight, so showing it
  # is one Graph.modify rather than a rebuild.
  defp render_drop_indicator(graph, %State{theme: theme} = state) do
    Primitives.rect(
      graph,
      {Map.get(theme, :drop_indicator_width, 3), theme.height},
      id: :tab_drop_indicator,
      fill: drop_indicator_fill(state),
      translate: drop_indicator_translate(state)
    )
  end

  defp drop_indicator_fill(%State{drag_active?: false}), do: :clear
  defp drop_indicator_fill(%State{dragging_tab_id: nil}), do: :clear

  defp drop_indicator_fill(%State{theme: theme} = state) do
    if State.get_tab_bounds(state, state.dragging_tab_id) do
      Map.get(theme, :drop_indicator_color, theme.selection_indicator_color)
    else
      :clear
    end
  end

  defp drop_indicator_translate(%State{drag_active?: false}), do: {0, 0}
  defp drop_indicator_translate(%State{dragging_tab_id: nil}), do: {0, 0}

  defp drop_indicator_translate(%State{theme: theme} = state) do
    case State.get_tab_bounds(state, state.dragging_tab_id) do
      # Straddling the boundary reads as "between these two tabs" rather than
      # as a stripe belonging to the one on the right.
      {x, _y, _width, _height} -> {x - Map.get(theme, :drop_indicator_width, 3) / 2, 0}
      nil -> {0, 0}
    end
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
          restyle_tab(graph, old_state.hovered_tab_id, new_state)
        else
          graph
        end

      # Update newly hovered tab background
      graph =
        if new_state.hovered_tab_id && old_state.hovered_tab_id != new_state.hovered_tab_id do
          restyle_tab(graph, new_state.hovered_tab_id, new_state)
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
        graph
        |> restyle_tab(old_state.selected_id, new_state)
        |> Graph.modify({:tab_label, old_state.selected_id}, fn p ->
          Primitives.update_opts(p, fill: theme.text_color)
        end)
      else
        graph
      end

    # Highlight newly selected tab
    if new_state.selected_id do
      graph
      |> restyle_tab(new_state.selected_id, new_state)
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

  # A provisional ("preview") tab is set in the theme's italic face. Slant, not
  # colour: it survives every palette and every kind of colour vision.
  defp tab_font(%{style: :italic}, theme), do: Map.get(theme, :italic_font, theme.font)
  defp tab_font(_tab, theme), do: theme.font

  defp truncate_label(label, max_width, font_size) do
    char_width = font_size * 0.6

    # The epsilon matters. State.calculate_tab_widths/1 sizes a tab as
    # `length * char_width + padding`, so a label that exactly fills its own tab
    # arrives here as `length * char_width / char_width` — which in float
    # arithmetic can be 6.999999999999999 rather than 7. Without the tolerance,
    # "beta.ex" got a tab sized precisely for "beta.ex" and was then rendered as
    # "bet...", while "alpha.ex" rounded the other way and displayed in full.
    max_chars = trunc(max_width / char_width + 1.0e-9)

    if String.length(label) <= max_chars do
      label
    else
      String.slice(label, 0, max(0, max_chars - 3)) <> "..."
    end
  end
end
