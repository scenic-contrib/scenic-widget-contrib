defmodule ScenicWidgets.SideNav.Api do
  @moduledoc """
  Public API for the SideNav component.
  Provides functions to control the sidebar programmatically.

  ## Usage

      # Set active item (auto-expands ancestors)
      SideNav.Api.set_active(state, "my_item_id")

      # Toggle expansion
      SideNav.Api.toggle_expand(state, "parent_id")

      # Update tree data
      SideNav.Api.update_tree(state, new_tree)

      # Filter/search
      SideNav.Api.set_filter(state, "search term")
  """

  use Widgex.Scrollable, direction: :vertical

  alias ScenicWidgets.SideNav.{State, Item}

  @doc """
  Set the active (selected) item.
  Automatically expands ancestors to make it visible.
  """
  def set_active(%State{} = state, item_id) do
    State.set_active(state, item_id)
  end

  @doc """
  Toggle expansion state of a node.
  """
  def toggle_expand(%State{} = state, item_id) do
    State.toggle_expanded(state, item_id)
  end

  @doc """
  Expand a node (if not already expanded).
  """
  def expand(%State{} = state, item_id) do
    State.expand(state, item_id)
  end

  @doc """
  Collapse a node (if expanded).
  """
  def collapse(%State{} = state, item_id) do
    State.collapse(state, item_id)
  end

  @doc """
  Expand all nodes in the tree.
  """
  def expand_all(%State{} = state) do
    all_ids =
      Item.flatten(state.tree)
      |> Enum.filter(&Item.has_children?/1)
      |> Enum.map(&Item.get_id/1)

    new_expanded = MapSet.new(all_ids)
    new_bounds = State.calculate_item_bounds(state.tree, state.theme, new_expanded)

    %{state | expanded: new_expanded, item_bounds: new_bounds}
  end

  @doc """
  Collapse all nodes in the tree.
  """
  def collapse_all(%State{} = state) do
    new_bounds = State.calculate_item_bounds(state.tree, state.theme, MapSet.new())
    %{state | expanded: MapSet.new(), item_bounds: new_bounds}
  end

  @doc """
  Update the tree structure.
  Preserves expansion state for items that still exist.
  """
  def update_tree(%State{} = state, new_tree) do
    # Get IDs from new tree
    new_ids =
      Item.flatten(new_tree)
      |> Enum.map(&Item.get_id/1)
      |> MapSet.new()

    # Keep only expanded IDs that still exist. Items the caller did not have
    # before arrive with their own `expanded:` preference (a search-results
    # tree wants each file open); items the user already collapsed stay so.
    remap = fn id -> remap_path(id, state.pending_path_moves) end
    remapped_expanded = MapSet.new(state.expanded, remap)
    old_ids = state.tree |> Item.flatten() |> Enum.map(&Item.get_id/1) |> MapSet.new()

    newly_expanded =
      new_tree
      |> Item.flatten()
      |> Enum.filter(&(Item.is_expanded?(&1) and not MapSet.member?(old_ids, Item.get_id(&1))))
      |> Enum.map(&Item.get_id/1)
      |> MapSet.new()

    new_expanded =
      remapped_expanded
      |> MapSet.intersection(new_ids)
      |> MapSet.union(newly_expanded)

    # Recalculate bounds
    new_bounds = State.calculate_item_bounds(new_tree, state.theme, new_expanded)

    content_width =
      new_tree
      |> State.calculate_content_width(state.theme, new_expanded)
      |> State.scroll_content_width(new_bounds, state.frame)

    content_height = State.scroll_content_height(new_bounds, content_width, state.frame)

    new_scroll =
      state.scroll
      |> update_content_size(content_width, content_height)
      |> State.sync_scrollbar_visibility()

    active_id = remap.(state.active_id)
    active_id = if MapSet.member?(new_ids, active_id), do: active_id
    focused_id = remap.(state.focused_id)
    focused_id = if MapSet.member?(new_ids, focused_id), do: focused_id
    selected_ids = state.selected_ids |> MapSet.new(remap) |> MapSet.intersection(new_ids)

    selection_anchor =
      anchor = remap.(state.selection_anchor)

    if MapSet.member?(new_ids, anchor), do: anchor

    %{
      state
      | tree: new_tree,
        expanded: new_expanded,
        item_bounds: new_bounds,
        scroll: new_scroll,
        active_id: active_id,
        focused_id: focused_id,
        selected_ids: selected_ids,
        selection_anchor: selection_anchor,
        pending_path_moves: []
    }
  end

  defp remap_path(nil, _moves), do: nil

  defp remap_path(path, moves) when is_binary(path) do
    Enum.find_value(moves, path, fn {source, destination} ->
      cond do
        path == source ->
          destination

        descendant_path?(path, source) ->
          Path.join(destination, Path.relative_to(path, source))

        true ->
          nil
      end
    end)
  end

  defp descendant_path?(candidate, directory) do
    relative = Path.relative_to(candidate, directory)
    relative != candidate and relative != "." and not String.starts_with?(relative, "..")
  end

  @doc """
  Set a filter/search term.
  Returns updated state with filtered tree.

  Only items matching the filter (or their ancestors/descendants) are visible.
  """
  def set_filter(%State{} = state, filter_term) when is_binary(filter_term) do
    if String.trim(filter_term) == "" do
      # Empty filter - show original tree
      %{state | tree: state.tree}
    else
      # Filter tree and auto-expand matches
      filtered_tree = filter_tree(state.tree, filter_term)

      # Auto-expand all items in filtered view
      all_ids =
        Item.flatten(filtered_tree)
        |> Enum.filter(&Item.has_children?/1)
        |> Enum.map(&Item.get_id/1)

      new_expanded = MapSet.new(all_ids)
      new_bounds = State.calculate_item_bounds(filtered_tree, state.theme, new_expanded)

      %{state | tree: filtered_tree, expanded: new_expanded, item_bounds: new_bounds}
    end
  end

  @doc """
  Clear any active filter.
  """
  def clear_filter(%State{} = state) do
    set_filter(state, "")
  end

  @doc """
  Update the theme.
  Recalculates bounds if dimensions changed.
  """
  def update_theme(%State{} = state, theme_updates) do
    new_theme = Map.merge(state.theme, theme_updates)

    # Check if dimension-related properties changed
    dimension_keys = [:item_height, :indent]
    dimensions_changed? = Enum.any?(dimension_keys, &Map.has_key?(theme_updates, &1))

    if dimensions_changed? do
      # Recalculate bounds with new dimensions
      new_bounds = State.calculate_item_bounds(state.tree, new_theme, state.expanded)
      %{state | theme: new_theme, item_bounds: new_bounds}
    else
      # Just update colors, no need to recalculate bounds
      %{state | theme: new_theme}
    end
  end

  @doc """
  Scroll to make a specific item visible.
  """
  def scroll_to_item(%State{} = state, item_id) do
    case Map.get(state.item_bounds, item_id) do
      nil ->
        state

      bounds ->
        # Use scroll_to_show to make item visible with small margin
        rect = {bounds.x, bounds.y, bounds.width, bounds.height}
        new_scroll = scroll_to_show(state.scroll, rect, 4)
        %{state | scroll: new_scroll}
    end
  end

  @doc """
  Get list of all item IDs in the tree (flat list).
  """
  def all_item_ids(%State{} = state) do
    Item.flatten(state.tree)
    |> Enum.map(&Item.get_id/1)
  end

  @doc """
  Get list of visible item IDs (respecting collapsed parents).
  """
  def visible_item_ids(%State{} = state) do
    State.visible_items(state)
  end

  @doc """
  Find an item by ID.
  """
  def find_item(%State{} = state, item_id) do
    Item.find_by_id(state.tree, item_id)
  end

  @doc """
  Check if an item is expanded.
  """
  def expanded?(%State{} = state, item_id) do
    MapSet.member?(state.expanded, item_id)
  end

  @doc """
  Check if an item is the active item.
  """
  def active?(%State{} = state, item_id) do
    state.active_id == item_id
  end

  @doc """
  Check if an item is focused (keyboard navigation).
  """
  def focused?(%State{} = state, item_id) do
    state.focused_id == item_id
  end

  # Private helpers

  defp filter_tree(tree, filter_term) when is_list(tree) do
    normalized_filter = String.downcase(filter_term)

    tree
    |> Enum.map(fn item ->
      filter_item(item, normalized_filter)
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp filter_item(item, filter_term) do
    title_matches =
      String.downcase(Item.get_title(item))
      |> String.contains?(filter_term)

    has_children = Item.has_children?(item)

    cond do
      # Title matches - include item and all children
      title_matches ->
        item

      # Has children - check if any children match
      has_children ->
        filtered_children = filter_tree(Item.get_children(item), filter_term)

        if length(filtered_children) > 0 do
          # Include this item with filtered children
          %{item | children: filtered_children}
        else
          nil
        end

      # Leaf item that doesn't match
      true ->
        nil
    end
  end
end
