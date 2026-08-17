defmodule ScenicWidgets.SideNav.State do
  @moduledoc """
  State management for the SideNav component.

  Follows the HexDocs sidebar pattern with:
  - Hierarchical tree structure
  - Expand/collapse state per node
  - Active item tracking
  - Focused item for keyboard navigation
  - Scroll state via Widgex.Scrollable
  """

  use Widgex.Scrollable, direction: :both

  alias ScenicWidgets.SideNav.Item

  # The horizontal bar occupies 16px (12px bar + 2px padding on each side).
  # Keep a little breathing room so the final row never shares its hit strip.
  @horizontal_scrollbar_clearance 20
  @vertical_scrollbar_clearance 16

  defstruct [
    # Component frame
    :frame,
    # Hierarchical tree of Sidebar.Item structs
    :tree,
    # Currently active/selected item ID
    :active_id,
    # Filesystem-operation selection, distinct from the active editor buffer.
    :selected_ids,
    :selection_anchor,
    :context_menu,
    :drag_source,
    :drag_start,
    :drag_mods,
    :dragging,
    :drag_target,
    :drop_valid,
    :pending_path_moves,
    :renaming_id,
    :rename_value,
    :rename_replace_on_input,
    # Currently focused item (for keyboard nav)
    :focused_id,
    # Currently hovered item (for hover effects)
    :hovered_id,
    # MapSet of expanded node IDs
    :expanded,
    # Widgex.Scroll.ScrollState for scrolling
    :scroll,
    # Visual theme configuration
    :theme,
    # Pre-calculated bounds for hit-testing
    :item_bounds,
    # Active scrollbar-thumb drag (:x | :y | nil), pointer origin, and the
    # corresponding content offset at grab time.
    :scrollbar_drag,
    :scrollbar_drag_start,
    :scrollbar_drag_offset,
    # Component-level keyboard focus — all key input is ignored while false
    focused: false
  ]

  @default_theme %{
    # Colors - HexDocs light theme (with visible background)
    # Solid white background
    background: :white,
    # #222222
    text: {34, 34, 34},
    # #E5F2FF
    active_bg: {229, 242, 255},
    # Darker slate blue for active bar
    active_bar: {76, 86, 106},
    # Slightly darker hover
    hover_bg: {240, 240, 240},
    # Neutral operation selection; blue is reserved for the active buffer.
    selection_bg: {214, 218, 224},
    # Dark gray for chevrons
    chevron: {80, 80, 80},
    # #0070D6
    focus_ring: {0, 112, 214},
    # Visible border
    border: {200, 200, 200},

    # Dimensions
    # Slightly smaller item height
    item_height: 28,
    # Indentation per level
    indent: 16,
    # Use Roboto (standard Scenic font)
    font: :roboto,
    # Font size
    font_size: 14,
    line_height: 20,

    # Spacing
    # Left padding for top-level items
    padding_left: 12,
    # Right padding
    padding_right: 12,
    # No spacing between items
    item_spacing: 0,

    # Chevron - LARGER for visibility
    # Larger chevron
    chevron_size: 16,
    # Space between chevron and text
    chevron_margin: 6
  }

  @doc """
  Create a new SideNav state from initialization data.
  """
  def new(data) do
    theme = Map.merge(@default_theme, Map.get(data, :theme, %{}))
    tree = Map.get(data, :tree, [])

    # Build expanded set from data or from items marked as expanded
    initial_expanded = Map.get(data, :expanded, build_initial_expanded_set(tree))

    # Calculate item bounds to determine content height
    item_bounds = calculate_item_bounds(tree, theme, initial_expanded)

    content_width =
      tree
      |> calculate_content_width(theme, initial_expanded)
      |> scroll_content_width(item_bounds, data.frame)

    content_height = scroll_content_height(item_bounds, content_width, data.frame)

    %__MODULE__{
      frame: data.frame,
      tree: tree,
      active_id: Map.get(data, :active_id),
      selected_ids: MapSet.new(Map.get(data, :selected_ids, [])),
      selection_anchor: nil,
      context_menu: nil,
      drag_source: nil,
      drag_start: nil,
      drag_mods: [],
      dragging: false,
      drag_target: nil,
      drop_valid: false,
      pending_path_moves: [],
      renaming_id: nil,
      rename_value: "",
      rename_replace_on_input: false,
      focused_id: Map.get(data, :focused_id),
      expanded: initial_expanded,
      scroll:
        init_scroll(data.frame,
          content_width: content_width,
          content_height: content_height,
          initially_visible: true
        ),
      theme: theme,
      item_bounds: item_bounds,
      scrollbar_drag: nil,
      scrollbar_drag_start: nil,
      scrollbar_drag_offset: nil
    }
  end

  @doc """
  Calculate total content height from item bounds.
  """
  def calculate_content_height(item_bounds) when map_size(item_bounds) == 0, do: 0

  def calculate_content_height(item_bounds) do
    item_bounds
    |> Map.values()
    |> Enum.map(fn bounds -> bounds.y + bounds.height end)
    |> Enum.max()
  end

  def calculate_content_width(tree, theme), do: calculate_content_width(tree, theme, :all)

  def calculate_content_width(tree, theme, expanded) do
    tree
    |> item_widths(theme, 0, expanded)
    |> Enum.max(fn -> 0 end)
  end

  defp item_widths(items, theme, depth, expanded) do
    Enum.flat_map(items, fn item ->
      item_id = Item.get_id(item)

      own =
        theme.padding_left + depth * theme.indent + theme.chevron_size +
          theme.chevron_margin + String.length(Item.get_title(item)) * theme.font_size * 0.6 +
          theme.padding_right

      children =
        if expanded == :all or MapSet.member?(expanded, item_id) do
          item_widths(Item.get_children(item) || [], theme, depth + 1, expanded)
        else
          []
        end

      [own | children]
    end)
  end

  @doc false
  def scroll_content_width(content_width, item_bounds, frame) do
    vertical_overflow? = calculate_content_height(item_bounds) > frame.size.height
    horizontal_overflow? = content_width > frame.size.width

    if vertical_overflow? and horizontal_overflow? do
      content_width + @vertical_scrollbar_clearance
    else
      content_width
    end
  end

  # Build expanded set from items that have expanded: true
  defp build_initial_expanded_set(tree) do
    collect_expanded_items(tree, MapSet.new())
  end

  defp collect_expanded_items([], acc), do: acc

  defp collect_expanded_items([item | rest], acc) do
    item_id = Item.get_id(item)

    # Add this item to expanded set if it's marked as expanded
    acc =
      if Item.is_expanded?(item) do
        MapSet.put(acc, item_id)
      else
        acc
      end

    # Recursively check children
    acc =
      if Item.has_children?(item) do
        collect_expanded_items(Item.get_children(item), acc)
      else
        acc
      end

    collect_expanded_items(rest, acc)
  end

  @doc """
  Calculate bounds for all visible items in the tree.
  This enables fast hit-testing for mouse clicks.

  Only visible items (not hidden by collapsed parents) get bounds.
  """
  def calculate_item_bounds(tree, theme, expanded_set) do
    item_height = theme.item_height
    indent = theme.indent

    {bounds, _final_y} = do_calculate_bounds(tree, 0, 0, item_height, indent, expanded_set, %{})
    bounds
  end

  # Recursive bounds calculation
  defp do_calculate_bounds([], _depth, y_offset, _item_height, _indent, _expanded, acc) do
    {acc, y_offset}
  end

  defp do_calculate_bounds([item | rest], depth, y_offset, item_height, indent, expanded, acc) do
    item_id = Item.get_id(item)

    # Calculate bounds for this item
    # Note: x is the INDENT position, not including padding_left
    # The full row starts at 0, but content starts at padding_left + indent
    x = depth * indent

    bounds = %{
      x: x,
      y: y_offset,
      # Sidebar width minus indent
      width: 280 - x,
      height: item_height,
      depth: depth,
      has_children: Item.has_children?(item),
      expanded: MapSet.member?(expanded, item_id)
    }

    new_acc = Map.put(acc, item_id, bounds)
    next_y = y_offset + item_height

    # If this item has children and is expanded, process them
    {final_acc, final_y} =
      if Item.has_children?(item) and MapSet.member?(expanded, item_id) do
        children = Item.get_children(item)
        do_calculate_bounds(children, depth + 1, next_y, item_height, indent, expanded, new_acc)
      else
        {new_acc, next_y}
      end

    # Process remaining siblings
    do_calculate_bounds(rest, depth, final_y, item_height, indent, expanded, final_acc)
  end

  @doc """
  Toggle expansion state of a node.
  """
  def toggle_expanded(%__MODULE__{} = state, item_id) do
    new_expanded =
      if MapSet.member?(state.expanded, item_id) do
        MapSet.delete(state.expanded, item_id)
      else
        MapSet.put(state.expanded, item_id)
      end

    # Recalculate bounds with new expansion state
    new_bounds = calculate_item_bounds(state.tree, state.theme, new_expanded)

    content_width =
      state.tree
      |> calculate_content_width(state.theme, new_expanded)
      |> scroll_content_width(new_bounds, state.frame)

    content_height = scroll_content_height(new_bounds, content_width, state.frame)

    new_scroll =
      update_content_size(
        state.scroll,
        content_width,
        content_height
      )
      |> sync_scrollbar_visibility()

    %{state | expanded: new_expanded, item_bounds: new_bounds, scroll: new_scroll}
  end

  @doc """
  Set a node as expanded.
  """
  def expand(%__MODULE__{} = state, item_id) do
    if MapSet.member?(state.expanded, item_id) do
      state
    else
      new_expanded = MapSet.put(state.expanded, item_id)
      new_bounds = calculate_item_bounds(state.tree, state.theme, new_expanded)

      content_width =
        state.tree
        |> calculate_content_width(state.theme, new_expanded)
        |> scroll_content_width(new_bounds, state.frame)

      content_height = scroll_content_height(new_bounds, content_width, state.frame)

      new_scroll =
        update_content_size(
          state.scroll,
          content_width,
          content_height
        )
        |> sync_scrollbar_visibility()

      %{state | expanded: new_expanded, item_bounds: new_bounds, scroll: new_scroll}
    end
  end

  @doc """
  Set a node as collapsed.
  """
  def collapse(%__MODULE__{} = state, item_id) do
    if MapSet.member?(state.expanded, item_id) do
      new_expanded = MapSet.delete(state.expanded, item_id)
      new_bounds = calculate_item_bounds(state.tree, state.theme, new_expanded)

      content_width =
        state.tree
        |> calculate_content_width(state.theme, new_expanded)
        |> scroll_content_width(new_bounds, state.frame)

      content_height = scroll_content_height(new_bounds, content_width, state.frame)

      new_scroll =
        update_content_size(
          state.scroll,
          content_width,
          content_height
        )
        |> sync_scrollbar_visibility()

      %{state | expanded: new_expanded, item_bounds: new_bounds, scroll: new_scroll}
    else
      state
    end
  end

  @doc """
  Set the active (selected) item.
  Automatically expands ancestors to make it visible.
  """
  def set_active(%__MODULE__{} = state, nil), do: %{state | active_id: nil}

  def set_active(%__MODULE__{} = state, item_id) do
    # Find all ancestors and expand them
    # A move can publish the active buffer's new path just before the
    # asynchronously refreshed tree contains it. That is a valid transient
    # state, so retain the id without trying to enumerate nil ancestors.
    ancestors = find_ancestors(state.tree, item_id, []) || []

    new_expanded =
      Enum.reduce(ancestors, state.expanded, fn ancestor_id, acc ->
        MapSet.put(acc, ancestor_id)
      end)

    new_bounds = calculate_item_bounds(state.tree, state.theme, new_expanded)

    content_width =
      state.tree
      |> calculate_content_width(state.theme, new_expanded)
      |> scroll_content_width(new_bounds, state.frame)

    content_height = scroll_content_height(new_bounds, content_width, state.frame)

    new_scroll =
      update_content_size(
        state.scroll,
        content_width,
        content_height
      )
      |> sync_scrollbar_visibility()

    %{
      state
      | active_id: item_id,
        expanded: new_expanded,
        item_bounds: new_bounds,
        scroll: new_scroll
    }
  end

  @doc false
  def sync_scrollbar_visibility(scroll) do
    if Widgex.Scroll.ScrollState.scrollable?(scroll) do
      %{scroll | scrollbar_visible: true, scrollbar_opacity: 255}
    else
      %{scroll | scrollbar_visible: false, scrollbar_opacity: 0}
    end
  end

  @doc """
  Set the focused item (for keyboard navigation).
  """
  def set_focused(%__MODULE__{} = state, item_id) do
    %{state | focused_id: item_id}
  end

  @doc "Apply conventional plain, Ctrl-toggle, or Shift-range selection."
  def select(%__MODULE__{} = state, item_id, mods \\ []) do
    mods = normalize_mods(mods)
    visible_ids = visible_items(state)

    cond do
      :shift in mods and state.selection_anchor in visible_ids ->
        range = selection_range(visible_ids, state.selection_anchor, item_id)
        %{state | selected_ids: MapSet.new(range), focused_id: item_id}

      :ctrl in mods ->
        selected_ids =
          if MapSet.member?(state.selected_ids, item_id),
            do: MapSet.delete(state.selected_ids, item_id),
            else: MapSet.put(state.selected_ids, item_id)

        %{state | selected_ids: selected_ids, selection_anchor: item_id, focused_id: item_id}

      true ->
        %{
          state
          | selected_ids: MapSet.new([item_id]),
            selection_anchor: item_id,
            focused_id: item_id
        }
    end
  end

  defp normalize_mods(mods) do
    Enum.map(mods, fn
      mod when mod in [:key_left_control, :key_right_control, :control] -> :ctrl
      mod when mod in [:key_left_shift, :key_right_shift] -> :shift
      mod -> mod
    end)
  end

  defp selection_range(ids, from, to) do
    from_index = Enum.find_index(ids, &(&1 == from))
    to_index = Enum.find_index(ids, &(&1 == to))
    {first, last} = Enum.min_max([from_index, to_index])
    Enum.slice(ids, first..last)
  end

  @doc false
  def scroll_content_height(item_bounds, content_width, frame) do
    clearance =
      if content_width > frame.size.width, do: @horizontal_scrollbar_clearance, else: 0

    calculate_content_height(item_bounds) + clearance
  end

  @doc """
  Find which item (if any) is at the given coordinates.
  Returns {item_id, :chevron | :text} if hit, nil otherwise.
  """
  def hit_test(%__MODULE__{} = state, {x, y}) do
    # Adjust y for scroll offset
    adjusted_y = y + state.scroll.offset_y
    theme = state.theme

    Enum.find_value(state.item_bounds, fn {item_id, bounds} ->
      # Row spans full width, starting at x=0
      # Content starts at padding_left + depth * indent
      row_left = 0
      row_right = state.frame.size.width

      if x >= row_left && x <= row_right &&
           adjusted_y >= bounds.y && adjusted_y <= bounds.y + bounds.height do
        # Calculate content positions (matching render_item)
        indent_x = theme.padding_left + bounds.depth * theme.indent
        chevron_area_width = theme.chevron_size + theme.chevron_margin

        # Determine if click is on chevron or text
        hit_region =
          if bounds.has_children do
            chevron_right = indent_x + chevron_area_width

            if x >= indent_x && x <= chevron_right do
              :chevron
            else
              :text
            end
          else
            :text
          end

        {item_id, hit_region}
      else
        nil
      end
    end)
  end

  @doc """
  Get list of all visible item IDs (respecting collapsed parents).
  Used for keyboard navigation.
  """
  def visible_items(%__MODULE__{} = state) do
    state.item_bounds
    |> Map.keys()
    |> Enum.sort_by(fn id ->
      bounds = Map.get(state.item_bounds, id)
      bounds.y
    end)
  end

  @doc """
  Get the next visible item after the given ID.
  """
  def next_item(%__MODULE__{} = state, current_id) do
    visible = visible_items(state)
    current_index = Enum.find_index(visible, &(&1 == current_id))

    if current_index && current_index < length(visible) - 1 do
      Enum.at(visible, current_index + 1)
    else
      nil
    end
  end

  @doc """
  Get the previous visible item before the given ID.
  """
  def prev_item(%__MODULE__{} = state, current_id) do
    visible = visible_items(state)
    current_index = Enum.find_index(visible, &(&1 == current_id))

    if current_index && current_index > 0 do
      Enum.at(visible, current_index - 1)
    else
      nil
    end
  end

  # Helper: Find all ancestor IDs of an item
  defp find_ancestors(tree, target_id, path) do
    do_find_ancestors(tree, target_id, path, [])
  end

  defp do_find_ancestors([], _target_id, _path, _ancestors), do: nil

  defp do_find_ancestors([item | rest], target_id, path, ancestors) do
    item_id = Item.get_id(item)

    cond do
      item_id == target_id ->
        # Found it! Return the path
        ancestors

      Item.has_children?(item) ->
        # Search in children, adding this item to the path
        children = Item.get_children(item)

        case do_find_ancestors(children, target_id, [item_id | path], [item_id | ancestors]) do
          nil -> do_find_ancestors(rest, target_id, path, ancestors)
          result -> result
        end

      true ->
        # Not this item, try siblings
        do_find_ancestors(rest, target_id, path, ancestors)
    end
  end
end
