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

  # Border drawn around the whole pane when a drag targets the tree's root.
  @root_drop_stroke 3

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
        # Background and independently selectable edges. A SideNav placed
        # directly beneath a breadcrumb/header must not draw a second seam;
        # standalone navigators retain all four edges by default.
        |> Primitives.rect(
          state.frame.size.box,
          id: :sidebar_background,
          fill: state.theme.background
        )
        |> render_border(state.frame.size.box, border_color, Map.get(state.theme, :border_sides))
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
        # Both sit outside the scrollable group: the pane outline frames the
        # viewport, and the ghost tracks the pointer in screen space. Scrolling
        # either of them with the content would be wrong.
        |> render_root_drop_target(state)
        |> render_drag_ghost(state)
      end,
      # Render at local origin - parent handles positioning via translate
      translate: {0, 0}
    )
  end

  defp render_border(graph, {width, height}, color, sides) do
    sides = sides || [:top, :right, :bottom, :left]

    Enum.reduce(sides, graph, fn
      :top, g -> Primitives.line(g, {{0, 0}, {width, 0}}, stroke: {1, color})
      :right, g -> Primitives.line(g, {{width, 0}, {width, height}}, stroke: {1, color})
      :bottom, g -> Primitives.line(g, {{0, height}, {width, height}}, stroke: {1, color})
      :left, g -> Primitives.line(g, {{0, 0}, {0, height}}, stroke: {1, color})
      _other, g -> g
    end)
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

      # A drag starting or ending adds or removes the ghost and the pane
      # outline, so the graph has to be rebuilt rather than tweaked.
      old_state.dragging != new_state.dragging ->
        initial_render(Graph.build(), new_state)

      old_state.drag_target != new_state.drag_target ||
        old_state.drop_valid != new_state.drop_valid ||
        old_state.renaming_id != new_state.renaming_id ||
          old_state.rename_value != new_state.rename_value ->
        initial_render(Graph.build(), new_state)

      # The pointer moved but nothing else did. Rebuilding the whole tree on
      # every cursor_pos of a drag is the one case where that is plainly too
      # expensive, so the ghost is moved on its own.
      new_state.dragging and old_state.drag_pos != new_state.drag_pos ->
        move_drag_ghost(graph, new_state)

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

  defp move_drag_ghost(graph, %State{drag_pos: {_, _} = pos}) do
    Graph.modify(graph, :side_nav_drag_ghost, fn primitive ->
      Scenic.Primitive.put_transform(primitive, :translate, ghost_offset(pos))
    end)
  end

  defp move_drag_ghost(graph, _state), do: graph

  # Down and to the right of the pointer, so the ghost never covers the row the
  # drop is aimed at.
  defp ghost_offset({x, y}), do: {x + 14, y + 8}

  # Drop feedback colours come from the theme so a light-themed sidebar does not
  # flash the dark theme's greens. The fallbacks are the values these were
  # hardcoded to before themes carried them.
  defp drop_fill(theme, :valid), do: Map.get(theme, :drop_valid_bg, {54, 92, 67})
  defp drop_fill(theme, :invalid), do: Map.get(theme, :drop_invalid_bg, {105, 48, 52})
  defp drop_text(theme), do: Map.get(theme, :drop_text, :white)

  # Dropping on empty space targets the tree's container, which has no row to
  # light up — so the pane itself is the affordance.
  defp render_root_drop_target(graph, %State{drag_target: target, root_id: root})
       when is_nil(target) or is_nil(root),
       do: graph

  defp render_root_drop_target(graph, %State{drag_target: target, root_id: target} = state) do
    kind = if state.drop_valid, do: :valid, else: :invalid
    %{width: width, height: height} = state.frame.size

    # Inset by half the stroke width. Scenic centres a stroke on its path, so a
    # rect on the frame's own edge loses half its border off-screen and the
    # affordance reads as a hairline.
    Primitives.rect(graph, {width - @root_drop_stroke, height - @root_drop_stroke},
      id: :side_nav_root_drop_target,
      fill: :clear,
      stroke: {@root_drop_stroke, drop_fill(state.theme, kind)},
      translate: {@root_drop_stroke / 2, @root_drop_stroke / 2}
    )
  end

  defp render_root_drop_target(graph, _state), do: graph

  # A label riding the cursor, so it is obvious what is in flight and that a
  # drag is happening at all — the row highlight alone reads as hover.
  defp render_drag_ghost(graph, %State{dragging: false}), do: graph
  defp render_drag_ghost(graph, %State{drag_pos: nil}), do: graph

  defp render_drag_ghost(graph, %State{drag_pos: {x, y}} = state) do
    theme = state.theme
    label = ghost_label(state)
    font_size = theme.font_size
    width = max(64, round(String.length(label) * font_size * 0.62) + 20)
    height = theme.item_height

    Primitives.group(
      graph,
      fn g ->
        g
        |> Primitives.rrect({width, height, 4},
          id: :side_nav_drag_ghost_body,
          fill: Map.get(theme, :ghost_bg, {28, 30, 38}),
          stroke: {1, drop_fill(theme, if(state.drop_valid, do: :valid, else: :invalid))}
        )
        |> Primitives.text(label,
          id: :side_nav_drag_ghost_label,
          fill: Map.get(theme, :ghost_text, theme.text),
          font: theme.font,
          font_size: font_size,
          text_align: :left,
          translate: {10, height / 2 + font_size * 0.35}
        )
      end,
      id: :side_nav_drag_ghost,
      translate: ghost_offset({x, y})
    )
  end

  defp ghost_label(%State{selected_ids: ids, drag_source: source}) do
    case MapSet.size(ids) do
      n when n > 1 -> "#{n} items"
      _ -> source |> to_string() |> Path.basename()
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
          is_drop_target and state.drop_valid -> {drop_fill(theme, :valid), drop_text(theme)}
          is_drop_target -> {drop_fill(theme, :invalid), drop_text(theme)}
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
