defmodule ScenicWidgets.MenuBar.State do
  @moduledoc """
  State management for the MenuBar component.
  """
  
  defstruct [
    :frame,
    :menu_map,
    :active_menu,      # Currently open dropdown menu ID
    :active_sub_menus, # Map where keys are parent IDs and values are child sub-menu IDs
                       # e.g., %{:menu_0_file => "submenu_recent_files", "submenu_recent_files" => "submenu_by_project"}
    :hovered_item,     # Currently hovered menu item
    :hovered_dropdown, # Currently hovered dropdown item
    :dropdown_bounds,  # Pre-calculated bounds for each dropdown
    :theme,
    :hover_activate    # If true, hovering opens menus instead of clicking
  ]
  
  @default_theme %{
    # Colors
    background: :dark_gray,
    text: :white,
    hover_bg: :steel_blue,
    hover_text: :white,
    dropdown_bg: :light_gray,
    dropdown_text: :black,
    dropdown_hover_bg: :dodger_blue,
    dropdown_hover_text: :white,

    # Dimensions
    menu_height: 40,
    item_width: 150,
    sub_menu_width: 150,  # Width of sub-menu dropdowns (can be wider than main menus)
    item_height: 30,
    padding: 5,

    # Typography
    font: :roboto,
    font_size: 16,

    # Text Overflow
    text_overflow: :ellipsis,  # :ellipsis, :truncate, or :none
    max_text_width: 120,  # Max width for text before overflow handling (leaves room for arrows, padding)
    ellipsis_char: "..."
  }
  
  @doc """
  Create a new MenuBar state from initialization data.
  """
  def new(data) do
    # Merge default theme with provided theme
    theme = Map.merge(@default_theme, Map.get(data, :theme, %{}))

    %__MODULE__{
      frame: data.frame,
      menu_map: data.menu_map,
      active_menu: nil,
      active_sub_menus: %{},
      hovered_item: nil,
      hovered_dropdown: nil,
      dropdown_bounds: calculate_dropdown_bounds(data.frame, data.menu_map, theme),
      theme: theme,
      hover_activate: Map.get(data, :hover_activate, false)
    }
  end
  
  @doc """
  Calculate and cache the bounds for all dropdown menus.
  This allows us to pre-render them and just toggle visibility.
  """
  def calculate_dropdown_bounds(_frame, menu_map, theme) do
    menu_height = Map.get(theme, :menu_height, 40)
    item_width = Map.get(theme, :item_width, 150)
    sub_menu_width = Map.get(theme, :sub_menu_width, 150)
    dropdown_item_height = Map.get(theme, :item_height, 30)
    dropdown_padding = Map.get(theme, :padding, 5)

    menu_map
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{menu_id, {_label, items}}, index}, acc ->
      # Calculate dropdown position relative to component origin (0,0)
      x = index * item_width
      y = menu_height

      # Calculate dropdown height based on number of items
      dropdown_height = length(items) * dropdown_item_height + (2 * dropdown_padding)
      dropdown_width = sub_menu_width  # Use sub_menu_width for all dropdowns

      # Store bounds for this dropdown
      bounds = %{
        x: x,
        y: y,
        width: dropdown_width,
        height: dropdown_height,
        items: calculate_item_bounds(items, x, y, dropdown_width, dropdown_item_height, dropdown_padding)
      }

      Map.put(acc, menu_id, bounds)
    end)
  end
  
  defp calculate_item_bounds(items, dropdown_x, dropdown_y, width, item_height, padding) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      # Each item starts at dropdown_y + padding, then offset by index * item_height
      item_y = dropdown_y + padding + (index * item_height)

      case item do
        {item_id, _label} when is_binary(item_id) ->
          # Regular menu item (2-tuple format): {item_id, label}
          {item_id, %{
            x: dropdown_x + padding,  # Add padding for inner items
            y: item_y,
            width: width - (2 * padding),  # Account for padding on both sides
            height: item_height,
            type: :item,
            action: nil  # No action callback
          }}

        {item_id, _label, action} when is_binary(item_id) and is_function(action, 0) ->
          # Regular menu item with action callback (3-tuple format): {item_id, label, action_fn}
          {item_id, %{
            x: dropdown_x + padding,
            y: item_y,
            width: width - (2 * padding),
            height: item_height,
            type: :item,
            action: action  # Store the action function
          }}

        {:sub_menu, label, sub_items} ->
          # Sub-menu item - use label as the ID for now
          sub_menu_id = "submenu_#{String.downcase(String.replace(label, " ", "_"))}"
          {sub_menu_id, %{
            x: dropdown_x + padding,
            y: item_y,
            width: width - (2 * padding),
            height: item_height,
            type: :sub_menu,
            label: label,
            items: sub_items,
            action: nil  # Sub-menus don't have actions
          }}
      end
    end)
    |> Enum.into(%{})
  end
  
  @doc """
  Check if a point is within the menu bar area.
  """
  def point_in_menu_bar?(%{frame: frame, theme: theme}, {x, y}) do
    menu_height = Map.get(theme, :menu_height, 40)
    # Check relative to component origin (0,0)
    x >= 0 &&
    x <= frame.size.width &&
    y >= 0 &&
    y <= menu_height
  end
  
  @doc """
  Check if a point is within any dropdown area.
  """
  def point_in_dropdown?(%{active_menu: nil}, _coords), do: {false, nil}
  def point_in_dropdown?(%{active_menu: menu_id, dropdown_bounds: bounds}, {x, y}) do
    case Map.get(bounds, menu_id) do
      nil -> 
        {false, nil}
      dropdown ->
        if x >= dropdown.x && x <= dropdown.x + dropdown.width &&
           y >= dropdown.y && y <= dropdown.y + dropdown.height do
          # Find which item is hovered
          hovered_item = find_hovered_dropdown_item(dropdown.items, {x, y})
          {true, hovered_item}
        else
          {false, nil}
        end
    end
  end
  
  defp find_hovered_dropdown_item(items, {x, y}) do
    Enum.find_value(items, fn {item_id, bounds} ->
      if x >= bounds.x && x <= bounds.x + bounds.width &&
         y >= bounds.y && y <= bounds.y + bounds.height do
        # Return both the item_id and its type
        {item_id, bounds.type}
      end
    end)
  end

  @doc """
  Check if a point is within any active sub-menu area at any nesting level.
  Returns {:ok, {parent_id, sub_menu_id, item_id}} if hovering over a sub-menu item,
  or :not_in_sub_menu if not in any sub-menu.

  This checks ALL active sub-menus in the active_sub_menus map, supporting deep nesting.
  """
  def point_in_sub_menu?(%{active_sub_menus: sub_menus} = state, {x, y}) when map_size(sub_menus) > 0 do
    require Logger
    # Check each active sub-menu (at any level)
    # The map contains parent_id => sub_menu_id pairs at all levels
    result = Enum.find_value(sub_menus, :not_in_sub_menu, fn {parent_id, sub_menu_id} ->
      case check_point_in_specific_sub_menu(state, parent_id, sub_menu_id, {x, y}, state.theme) do
        {:ok, result} ->
          # Logger.debug("Found point in sub-menu: parent=#{inspect(parent_id)}, sub=#{inspect(sub_menu_id)}, result=#{inspect(result)}")
          {:ok, result}
        :not_in_sub_menu -> nil  # Continue searching
      end
    end)

    if result == :not_in_sub_menu do
      # Logger.debug("Point #{inspect({x, y})} not in any sub-menu. Active sub-menus: #{inspect(Map.keys(sub_menus))}")
    end

    result
  end
  def point_in_sub_menu?(_state, _coords), do: :not_in_sub_menu

  defp check_point_in_specific_sub_menu(state, parent_id, sub_menu_id, {x, y}, theme) do
    require Logger
    # Calculate sub-menu position based on parent position
    # Sub-menus are positioned to the right of their parent item

    sub_menu_width = Map.get(theme, :sub_menu_width, 150)
    dropdown_item_height = Map.get(theme, :item_height, 30)
    dropdown_padding = Map.get(theme, :padding, 5)

    # Find the position of the parent (either a menu or another sub-menu)
    case calculate_sub_menu_position(state, parent_id, sub_menu_id, theme) do
      nil ->
        # Logger.debug("calculate_sub_menu_position returned nil for parent=#{inspect(parent_id)}, sub=#{inspect(sub_menu_id)}")
        :not_in_sub_menu
      {sub_x, sub_y, sub_items} ->
        # Calculate sub-menu bounds
        sub_width = sub_menu_width
        sub_height = length(sub_items) * dropdown_item_height + (2 * dropdown_padding)

        # Logger.debug("Checking sub-menu #{inspect(sub_menu_id)}: bounds=[#{sub_x}, #{sub_y}, #{sub_x + sub_width}, #{sub_y + sub_height}], point=[#{x}, #{y}]")

        # Check if point is within sub-menu bounds
        if x >= sub_x && x <= sub_x + sub_width &&
           y >= sub_y && y <= sub_y + sub_height do
          # Find which item is hovered
          hovered_item = find_hovered_sub_menu_item(sub_items, {x, y}, sub_x, sub_y, dropdown_item_height, dropdown_padding, sub_menu_width)
          # Logger.debug("Point IS in sub-menu #{inspect(sub_menu_id)}, hovered_item=#{inspect(hovered_item)}")
          {:ok, {parent_id, sub_menu_id, hovered_item}}
        else
          # Logger.debug("Point NOT in sub-menu #{inspect(sub_menu_id)}")
          :not_in_sub_menu
        end
    end
  end

  defp calculate_sub_menu_position(%{menu_map: menu_map, dropdown_bounds: bounds, active_menu: active_menu}, parent_id, sub_menu_id, theme) do
    # Check if parent is the main menu dropdown
    if parent_id == active_menu do
      # Find the sub-menu item in the main dropdown
      case Map.get(bounds, active_menu) do
        nil -> nil
        dropdown ->
          # Find the item that matches this sub_menu_id in the dropdown items
          case Map.get(dropdown.items, sub_menu_id) do
            nil -> nil
            item_bounds ->
              if item_bounds.type == :sub_menu do
                # Position is to the right of the parent item
                sub_x = item_bounds.x + item_bounds.width
                sub_y = item_bounds.y
                {sub_x, sub_y, item_bounds.items}
              else
                nil
              end
          end
      end
    else
      # Parent is another sub-menu, need to find it recursively
      # For now, we'll need to traverse the menu structure
      find_nested_sub_menu_position(menu_map, active_menu, parent_id, sub_menu_id, theme)
    end
  end

  defp find_nested_sub_menu_position(menu_map, active_menu, parent_sub_menu_id, target_sub_menu_id, theme) do
    # We need to find where the parent sub-menu is, then find the target within it
    # This is a recursive problem: parent_sub_menu_id could itself be nested multiple levels deep

    item_width = Map.get(theme, :item_width, 150)
    sub_menu_width = Map.get(theme, :sub_menu_width, 150)
    menu_height = Map.get(theme, :menu_height, 40)
    dropdown_item_height = Map.get(theme, :item_height, 30)
    dropdown_padding = Map.get(theme, :padding, 5)

    # First, get the main menu items to start our search
    case Map.get(menu_map, active_menu) do
      nil -> nil
      {_label, main_items} ->
        # Calculate base X position for the active menu
        menu_index = menu_map |> Map.keys() |> Enum.find_index(&(&1 == active_menu)) || 0
        base_x = menu_index * item_width

        # Recursively search for the parent_sub_menu_id starting from main items
        # Once found, we'll know its position
        # Use sub_menu_width for the initial dropdown width (first-level dropdowns)
        case find_sub_menu_in_items(main_items, parent_sub_menu_id, {base_x, menu_height, sub_menu_width}, theme) do
          nil -> nil
          {parent_x, parent_y, parent_items} ->
            # Now find the target sub-menu within the parent's items
            find_item_in_list(parent_items, target_sub_menu_id, parent_x, parent_y, sub_menu_width, dropdown_item_height, dropdown_padding)
        end
    end
  end

  # Recursively search for a sub-menu by ID within a list of items
  # Returns {x, y, items} if found
  defp find_sub_menu_in_items(items, target_id, {base_x, base_y, parent_width}, theme) do
    dropdown_item_height = Map.get(theme, :item_height, 30)
    dropdown_padding = Map.get(theme, :padding, 5)
    sub_menu_width = Map.get(theme, :sub_menu_width, 150)

    items
    |> Enum.with_index()
    |> Enum.find_value(fn {item, index} ->
      item_y = base_y + dropdown_padding + (index * dropdown_item_height)

      case item do
        {:sub_menu, label, sub_items} ->
          sub_menu_id = "submenu_#{String.downcase(String.replace(label, " ", "_"))}"

          if sub_menu_id == target_id do
            # Found it! Return the position where this submenu will appear
            # Sub-menus appear to the right of their parent
            sub_x = base_x + parent_width - dropdown_padding
            {sub_x, item_y, sub_items}
          else
            # Not this one, but maybe it's nested deeper - search recursively
            # Sub-menus appear to the right of their parent
            # Use sub_menu_width for nested positioning
            sub_x = base_x + parent_width - dropdown_padding
            find_sub_menu_in_items(sub_items, target_id, {sub_x, item_y, sub_menu_width}, theme)
          end

        _ ->
          # Not a sub-menu, skip
          nil
      end
    end)
  end

  # Find a specific item in a list and return its position and contents
  defp find_item_in_list(items, target_id, parent_x, parent_y, item_width, item_height, padding) do
    items
    |> Enum.with_index()
    |> Enum.find_value(fn {item, index} ->
      item_y = parent_y + padding + (index * item_height)

      case item do
        {:sub_menu, label, sub_items} ->
          sub_menu_id = "submenu_#{String.downcase(String.replace(label, " ", "_"))}"

          if sub_menu_id == target_id do
            # Found it! Position is to the right of parent
            sub_x = parent_x + item_width - padding
            {sub_x, item_y, sub_items}
          else
            nil
          end

        _ ->
          nil
      end
    end)
  end

  defp find_hovered_sub_menu_item(items, {x, y}, sub_x, sub_y, item_height, padding, sub_menu_width) do
    items
    |> Enum.with_index()
    |> Enum.find_value(fn {item, index} ->
      item_y = sub_y + padding + (index * item_height)

      if x >= sub_x + padding && x <= sub_x + sub_menu_width - padding &&
         y >= item_y && y <= item_y + item_height do
        # Extract item_id based on item format
        case item do
          {item_id, _label} when is_binary(item_id) -> item_id
          {item_id, _label, _action} when is_binary(item_id) -> item_id
          {:sub_menu, label, _sub_items} -> "submenu_#{String.downcase(String.replace(label, " ", "_"))}"
          _ -> nil
        end
      end
    end)
  end

  @doc """
  Find which menu header is being hovered.
  """
  def find_hovered_menu(%{menu_map: menu_map, theme: theme}, {x, _y}) do
    require Logger
    item_width = Map.get(theme, :item_width, 150)

    # Logger.debug("find_hovered_menu: x=#{x}")

    menu_map
    |> Enum.with_index()
    |> Enum.find_value(fn {{menu_id, _}, index} ->
      # Check relative to component origin
      menu_x = index * item_width
      # Logger.debug("Checking menu #{menu_id} at index #{index}: menu_x=#{menu_x}, x=#{x}")
      if x >= menu_x && x <= menu_x + item_width do
        menu_id
      end
    end)
  end
end