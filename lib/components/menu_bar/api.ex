defmodule ScenicWidgets.MenuBar.Api do
  @moduledoc """
  Public API for the MenuBar component.
  Provides functions to control the menu bar programmatically.
  """
  
  alias ScenicWidgets.MenuBar.State
  
  @doc """
  Set the active (open) menu programmatically.
  """
  def set_active_menu(%State{} = state, menu_id) do
    if has_menu?(state, menu_id) do
      %{state | active_menu: menu_id, hovered_item: menu_id, hovered_dropdown: nil}
    else
      state
    end
  end
  
  @doc """
  Close all open menus.
  """
  def close_all_menus(%State{} = state) do
    %{state | active_menu: nil, hovered_item: nil, hovered_dropdown: nil}
  end
  
  @doc """
  Check if a menu exists.
  """
  def has_menu?(%State{menu_map: menu_map}, menu_id) do
    Map.has_key?(menu_map, menu_id)
  end
  
  @doc """
  Get the list of all menu IDs.
  """
  def menu_ids(%State{menu_map: menu_map}) do
    Map.keys(menu_map)
  end
  
  @doc """
  Get the list of item IDs for a specific menu.
  """
  def menu_item_ids(%State{menu_map: menu_map}, menu_id) do
    case Map.get(menu_map, menu_id) do
      {_label, items} ->
        Enum.map(items, fn {item_id, _label} -> item_id end)
      nil ->
        []
    end
  end
  
  @doc """
  Update the menu map (add/remove menus or items).
  """
  def update_menu_map(%State{} = state, new_menu_map) do
    %{state |
      menu_map: new_menu_map,
      dropdown_bounds: State.calculate_dropdown_bounds(state.frame, new_menu_map, state.theme),
      active_menu: nil,
      hovered_item: nil,
      hovered_dropdown: nil
    }
  end
  
  @doc """
  Update the theme.

  When theme dimensions change (menu_height, item_width, sub_menu_width, item_height, padding),
  dropdown bounds are recalculated to reflect the new dimensions.
  """
  def update_theme(%State{} = state, theme_updates) do
    new_theme = Map.merge(state.theme, theme_updates)

    # Check if any dimension-related theme properties changed
    dimension_keys = [:menu_height, :item_width, :sub_menu_width, :item_height, :padding]
    dimensions_changed? = Enum.any?(dimension_keys, &Map.has_key?(theme_updates, &1))

    if dimensions_changed? do
      # Recalculate dropdown bounds with new dimensions
      %{state |
        theme: new_theme,
        dropdown_bounds: State.calculate_dropdown_bounds(state.frame, state.menu_map, new_theme)
      }
    else
      # Just update colors, no need to recalculate bounds
      %{state | theme: new_theme}
    end
  end
end