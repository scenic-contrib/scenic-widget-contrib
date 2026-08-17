defmodule ScenicWidgets.SideNav.Renderizer do
  @moduledoc """
  Rendering logic for the SideNav component.

  Follows HexDocs visual style:
  - Hierarchical tree with indentation
  - Chevron icons for expandable nodes (right = collapsed, down = expanded)
  - Text labels with overflow handling
  - Active item highlighting with left accent bar
  - Hover states
  - Focus ring for keyboard navigation
  - Scrollable viewport via Widgex.Scrollable
  """

  use Widgex.Scrollable, direction: :both

  alias Scenic.Graph
  alias Scenic.Primitives
  alias ScenicWidgets.SideNav.{State, Item}

  @doc """
  Perform initial render of the entire sidebar.
  This builds the complete graph structure.
  """
  def initial_render(graph, %State{} = state) do
    border_color = Map.get(state.theme, :border, {220, 220, 220})

    # Note: Parent component positions us via `translate:` option in add_to_graph
    # So we render at local origin (0,0) - do NOT apply frame.pin.point here
    # as that would cause double-positioning
    graph
    |> Primitives.group(
      fn g ->
        g
        # Background with border
        |> Primitives.rect(
          state.frame.size.box,
          id: :sidebar_background,
          fill: state.theme.background,
          stroke: {1, border_color}
        )
        # Scrollable content area using Widgex.Scrollable macro
        |> scrollable_group(
          state.scroll,
          state.frame,
          fn scroll_g ->
            scroll_g
            |> render_tree(state.tree, state, 0)
          end,
          id: :sidebar_scroll_group,
          overlay_scrollbars: true
        )
        # Scrollbars on top
        |> render_scrollbars(state.scroll, state.frame,
          color: Map.get(state.theme, :scrollbar_color, {160, 160, 160})
        )
        |> render_context_menu(state)
      end,
      # Render at local origin - parent handles positioning via translate
      translate: {0, 0}
    )
  end

  @doc """
  Update render - only modifies changed elements.
  More efficient than full re-render for state changes like hover, scroll, expand/collapse.
  """
  def update_render(graph, old_state, new_state) do
    cond do
      # Tree structure changed (expand/collapse) - need full re-render
      old_state.expanded != new_state.expanded ->
        initial_render(Graph.build(), new_state)

      old_state.context_menu != new_state.context_menu ->
        initial_render(Graph.build(), new_state)

      old_state.drag_target != new_state.drag_target ||
        old_state.drop_valid != new_state.drop_valid ||
        old_state.renaming_id != new_state.renaming_id ||
          old_state.rename_value != new_state.rename_value ->
        initial_render(Graph.build(), new_state)

      # Scroll changed - use efficient transform update from Widgex.Scrollable
      scroll_changed?(old_state.scroll, new_state.scroll) ->
        graph
        |> update_scroll_transform(:sidebar_scroll_group, old_state.scroll, new_state.scroll)
        |> update_scrollbars(old_state.scroll, new_state.scroll, new_state.frame,
          color: Map.get(new_state.theme, :scrollbar_color, {160, 160, 160})
        )

      # Hover/focus/active changed - update individual item styling
      old_state.hovered_id != new_state.hovered_id ||
        old_state.focused_id != new_state.focused_id ||
        old_state.active_id != new_state.active_id ||
          old_state.selected_ids != new_state.selected_ids ->
        update_item_states(graph, old_state, new_state)

      # No visual changes
      true ->
        graph
    end
  end

  defp render_context_menu(graph, %{context_menu: nil}), do: graph

  defp render_context_menu(graph, %{context_menu: %{x: x, y: y}, frame: frame}) do
    width = 150
    row_height = 30
    menu_height = row_height * 2
    left = min(x, max(frame.size.width - width - 4, 4))
    top = min(y, max(frame.size.height - menu_height - 4, 4))

    Primitives.group(
      graph,
      fn menu ->
        menu
        |> Primitives.rect(frame.size.box,
          id: :side_nav_context_menu_shield,
          fill: :clear,
          input: [:cursor_button],
          translate: {-left, -top}
        )
        |> Primitives.rrect({width, menu_height, 4},
          fill: {45, 49, 58},
          stroke: {1, {105, 112, 126}}
        )
        |> Primitives.rect({width, row_height},
          id: {:context_action, :rename},
          fill: :clear,
          input: [:cursor_button, :cursor_pos]
        )
        |> Primitives.text("Rename",
          fill: :white,
          font_size: 14,
          translate: {12, 20}
        )
        |> Primitives.rect({width, row_height},
          id: {:context_action, :delete},
          fill: :clear,
          input: [:cursor_button, :cursor_pos],
          translate: {0, row_height}
        )
        |> Primitives.text("Delete…",
          fill: :white,
          font_size: 14,
          translate: {12, row_height + 20}
        )
      end,
      id: :side_nav_context_menu,
      translate: {left, top}
    )
  end

  # Recursively render tree structure
  defp render_tree(graph, items, state, depth) when is_list(items) do
    Enum.reduce(items, graph, fn item, acc_graph ->
      item_id = Item.get_id(item)
      is_expanded = MapSet.member?(state.expanded, item_id)

      # Render this item
      new_graph = render_item(acc_graph, item, state, depth, is_expanded)

      # If expanded and has children, render children
      if is_expanded && Item.has_children?(item) do
        render_tree(new_graph, Item.get_children(item), state, depth + 1)
      else
        new_graph
      end
    end)
  end

  # Render a single item as a self-contained row group
  # Each row is a group translated to its y position, containing:
  # - Background rect (for visual styling)
  # - Full-width clickable rect (for row click/navigate)
  # - Chevron hit area ON TOP (if has children) - catches clicks before row rect
  # - Optional active accent bar
  # - Chevron visual (triangle)
  # - Text label
  # - Optional focus ring
  #
  # Scenic hit-testing: later primitives are "on top" and catch clicks first
  # So chevron rect is rendered AFTER row rect to intercept clicks in that area
  defp render_item(graph, item, state, depth, is_expanded) do
    item_id = Item.get_id(item)
    bounds = Map.get(state.item_bounds, item_id)

    if bounds do
      theme = state.theme
      is_active = state.active_id == item_id
      is_selected = MapSet.member?(state.selected_ids, item_id)
      is_focused = state.focused_id == item_id
      is_hovered = Map.get(state, :hovered_id) == item_id
      is_drop_target = state.drag_target == item_id
      has_children = Item.has_children?(item)

      # Row positioning
      row_y = bounds.y
      row_height = theme.item_height
      row_width = state.frame.size.width

      # X positions within the row (relative to row start)
      indent_x = theme.padding_left + depth * theme.indent
      chevron_area_width = theme.chevron_size + theme.chevron_margin
      text_x = indent_x + chevron_area_width

      # Vertical center of the row (for centering elements)
      v_center = row_height / 2

      # Determine colors based on state
      {bg_fill, text_fill} =
        cond do
          is_drop_target and state.drop_valid -> {{54, 92, 67}, :white}
          is_drop_target -> {{105, 48, 52}, :white}
          is_active -> {theme.active_bg, theme.text}
          is_selected -> {theme.selection_bg, theme.text}
          is_hovered -> {theme.hover_bg, theme.text}
          true -> {theme.background, theme.text}
        end

      # Build semantic IDs
      row_id = String.to_atom("row_#{item_id}")

      # Render the entire row as a group
      graph
      |> Primitives.group(
        fn g ->
          g
          # 1. Visual background
          |> Primitives.rect({row_width, row_height},
            id: String.to_atom("item_bg_#{item_id}"),
            fill: bg_fill
          )
          # 2. Full-width clickable rect for row navigation (covers entire row)
          #    Also handles hover detection
          |> Primitives.rect({row_width, row_height},
            fill: :clear,
            input: [:cursor_button, :cursor_pos],
            id: {:row_click, item_id}
          )
          # 3. Chevron clickable area ON TOP - rendered after row rect so it catches clicks first
          |> then(fn g2 ->
            if has_children do
              # Chevron hit area is slightly larger than the visual for easier clicking
              Primitives.rect(g2, {chevron_area_width + 4, row_height},
                fill: :clear,
                input: [:cursor_button],
                id: {:chevron_click, item_id},
                translate: {indent_x - 2, 0}
              )
            else
              g2
            end
          end)
          # 4. Active accent bar (left edge) - visual only
          |> then(fn g2 ->
            if is_active do
              Primitives.rect(g2, {3, row_height}, fill: theme.active_bar)
            else
              g2
            end
          end)
          # 5. Chevron visual (triangle) - no input, just visual
          |> then(fn g2 ->
            if has_children do
              chevron_y = v_center - theme.chevron_size / 2

              render_chevron_visual(
                g2,
                indent_x,
                chevron_y,
                theme.chevron_size,
                is_expanded,
                theme.chevron
              )
            else
              g2
            end
          end)
          # 6. Text label - visual only
          |> then(fn g2 ->
            if state.renaming_id == item_id do
              g2
              |> Primitives.rrect({max(row_width - text_x - 6, 20), row_height - 6, 3},
                fill: {35, 39, 47},
                stroke: {1, theme.focus_ring},
                translate: {text_x, 3}
              )
              |> Primitives.text(state.rename_value <> "|",
                fill: :white,
                font: theme.font,
                font_size: theme.font_size,
                translate: {text_x + 5, v_center + theme.font_size / 3}
              )
            else
              Primitives.text(g2, Item.get_title(item),
                id: String.to_atom("item_text_#{item_id}"),
                fill: text_fill,
                font: theme.font,
                font_size: theme.font_size,
                translate: {text_x, v_center + theme.font_size / 3}
              )
            end
          end)
          # 7. Focus ring
          |> then(fn g2 ->
            if is_focused do
              Primitives.rect(g2, {row_width - 2, row_height - 2},
                stroke: {2, theme.focus_ring},
                fill: :clear,
                translate: {1, 1}
              )
            else
              g2
            end
          end)
        end,
        id: row_id,
        translate: {0, row_y}
      )
    else
      graph
    end
  end

  # Render chevron visual (triangle only, no input)
  defp render_chevron_visual(graph, x, y, size, is_expanded, color) do
    # Center of chevron
    cx = x + size / 2
    cy = y + size / 2

    # Triangle points
    points =
      if is_expanded do
        # Pointing down
        [
          {cx - size * 0.35, cy - size * 0.15},
          {cx + size * 0.35, cy - size * 0.15},
          {cx, cy + size * 0.3}
        ]
      else
        # Pointing right
        [
          {cx - size * 0.15, cy - size * 0.35},
          {cx - size * 0.15, cy + size * 0.35},
          {cx + size * 0.3, cy}
        ]
      end

    graph
    |> Primitives.triangle(List.to_tuple(points), fill: color)
  end

  # Update item visual states (hover/focus/active)
  defp update_item_states(graph, old_state, new_state) do
    # Collect all items that changed state
    changed_items = collect_changed_items(old_state, new_state)

    # Update each changed item's background and text color
    Enum.reduce(changed_items, graph, fn item_id, acc_graph ->
      update_item_styling(acc_graph, item_id, new_state)
    end)
  end

  defp collect_changed_items(old_state, new_state) do
    [
      old_state.hovered_id,
      new_state.hovered_id,
      old_state.focused_id,
      new_state.focused_id,
      old_state.active_id,
      new_state.active_id
    ]
    |> Kernel.++(MapSet.to_list(old_state.selected_ids))
    |> Kernel.++(MapSet.to_list(new_state.selected_ids))
    |> Enum.filter(&(&1 != nil))
    |> Enum.uniq()
  end

  defp update_item_styling(graph, item_id, state) do
    is_active = state.active_id == item_id
    is_selected = MapSet.member?(state.selected_ids, item_id)
    is_focused = state.focused_id == item_id
    is_hovered = Map.get(state, :hovered_id) == item_id

    theme = state.theme

    {bg_fill, text_fill} =
      cond do
        is_active ->
          {theme.active_bg, theme.text}

        is_selected ->
          {theme.selection_bg, theme.text}

        is_hovered ->
          {theme.hover_bg, theme.text}

        true ->
          {theme.background, theme.text}
      end

    # Build semantic IDs (must match those in render_item)
    bg_id = String.to_atom("item_bg_#{item_id}")
    text_id = String.to_atom("item_text_#{item_id}")

    # Try to update background
    graph =
      try do
        graph
        |> Graph.modify(bg_id, fn primitive ->
          Scenic.Primitive.put_style(primitive, :fill, bg_fill)
        end)
      rescue
        _ -> graph
      end

    # Try to update text color
    graph =
      try do
        graph
        |> Graph.modify(text_id, fn primitive ->
          Scenic.Primitive.put_style(primitive, :fill, text_fill)
        end)
      rescue
        _ -> graph
      end

    graph
  end

  # Calculate vertical position for text (centering)
  defp calculate_v_pos(theme) do
    # Use Scenic's font metrics if available
    # For now, use a simple approximation
    font_size = theme.font_size
    -font_size / 3
  end
end
