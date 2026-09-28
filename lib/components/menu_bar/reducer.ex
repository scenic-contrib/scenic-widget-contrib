defmodule ScenicWidgets.MenuBar.Reducer do
  @moduledoc """
  State reduction logic for the MenuBar component.
  Handles user input and state transitions.
  """
  
  alias ScenicWidgets.MenuBar.State
  
  @doc """
  Handle cursor position updates.
  """
  def handle_cursor_pos(%State{} = state, coords) do
    require Logger
    # Logger.debug("Reducer.handle_cursor_pos: coords=#{inspect(coords)}, active_menu=#{inspect(state.active_menu)}, active_sub_menus=#{inspect(state.active_sub_menus)}")

    cond do
      # Check if cursor is in menu bar
      State.point_in_menu_bar?(state, coords) ->
        case State.find_hovered_menu(state, coords) do
          nil -> 
            # Logger.debug("No menu hovered")
            %{state | hovered_item: nil}
          menu_id ->
            # Logger.debug("Hovered menu: #{inspect(menu_id)}, current active: #{inspect(state.active_menu)}")
            new_state = %{state | hovered_item: menu_id}
            
            cond do
              # In hover_activate mode, open menu on hover
              state.hover_activate && state.active_menu == nil ->
                # Logger.debug("Hover activate: opening menu #{inspect(menu_id)}")
                %{new_state | active_menu: menu_id, hovered_dropdown: nil, active_sub_menus: %{}}
              
              # If a dropdown is open and we hover a different menu, switch to it
              state.active_menu != nil && state.active_menu != menu_id ->
                # Logger.debug("Switching active menu from #{inspect(state.active_menu)} to #{inspect(menu_id)}")
                %{new_state | active_menu: menu_id, hovered_dropdown: nil, active_sub_menus: %{}}
              
              true ->
                new_state
            end
        end
      
      # Check if cursor is in active dropdown
      state.active_menu != nil ->
        # First check if we're in a sub-menu
        case State.point_in_sub_menu?(state, coords) do
          {:ok, {parent_menu, sub_menu_id, hovered_item}} ->
            # Mouse is in an active sub-menu!
            # Logger.debug("In sub-menu #{inspect(sub_menu_id)}, hovering item: #{inspect(hovered_item)}")

            # Get the currently active child of this sub-menu (if any)
            old_child = Map.get(state.active_sub_menus, sub_menu_id)

            # If the hovered item is itself a sub-menu, open it
            new_sub_menus = if is_sub_menu_item?(state, sub_menu_id, hovered_item) do
              # Check if we're switching to a different sub-sub-menu
              base_menus = if old_child && old_child != hovered_item do
                # Different sub-sub-menu - close the old one and its children
                close_sub_menu_and_children(state.active_sub_menus, old_child)
              else
                state.active_sub_menus
              end

              # Add both the current sub-menu AND the nested one
              base_menus
              |> Map.put(parent_menu, sub_menu_id)
              |> Map.put(sub_menu_id, hovered_item)
            else
              # Just keep the current sub-menu open, close any nested ones
              base_menus = if old_child do
                close_sub_menu_and_children(state.active_sub_menus, old_child)
              else
                state.active_sub_menus
              end

              base_menus
              |> Map.put(parent_menu, sub_menu_id)
            end

            %{state |
              hovered_dropdown: if(hovered_item, do: {sub_menu_id, hovered_item}, else: nil),
              hovered_item: state.active_menu,
              active_sub_menus: new_sub_menus
            }

          :not_in_sub_menu ->
            # Not in sub-menu, check main dropdown
            case State.point_in_dropdown?(state, coords) do
              {true, {item_id, :sub_menu}} ->
                # Hovering over a sub-menu item in main dropdown
                # Logger.debug("Hovering over sub-menu trigger: #{inspect(item_id)}")

                # Get the currently active sub-menu for this dropdown (if any)
                old_sub_menu = Map.get(state.active_sub_menus, state.active_menu)

                # Close any nested sub-menus from the old sub-menu, but keep the new one
                new_sub_menus = if old_sub_menu && old_sub_menu != item_id do
                  # Different sub-menu - close the old one and its children
                  close_sub_menu_and_children(state.active_sub_menus, old_sub_menu)
                  |> Map.put(state.active_menu, item_id)
                else
                  # Same sub-menu or no previous sub-menu - just update
                  Map.put(state.active_sub_menus, state.active_menu, item_id)
                end

                %{state |
                  hovered_dropdown: {state.active_menu, item_id},
                  hovered_item: state.active_menu,
                  active_sub_menus: new_sub_menus
                }
              {true, {item_id, :item}} ->
                # Regular menu item (not a sub-menu)
                # Close any sub-menus for the current active menu AND their children
                # Logger.debug("Hovering over regular item: #{inspect(item_id)}, clearing sub-menus for #{inspect(state.active_menu)}")

                # Get the child sub-menu of the active menu (if any) and close it recursively
                new_sub_menus = case Map.get(state.active_sub_menus, state.active_menu) do
                  nil -> state.active_sub_menus
                  child_sub_menu_id ->
                    # Close this child and all its descendants
                    close_sub_menu_and_children(state.active_sub_menus, child_sub_menu_id)
                    |> Map.delete(state.active_menu)
                end

                %{state |
                  hovered_dropdown: {state.active_menu, item_id},
                  hovered_item: state.active_menu,
                  active_sub_menus: new_sub_menus
                }
              {true, nil} ->
                # In dropdown area but not over a specific item
                # Clear sub-menus for this dropdown AND their children
                new_sub_menus = case Map.get(state.active_sub_menus, state.active_menu) do
                  nil -> state.active_sub_menus
                  child_sub_menu_id ->
                    close_sub_menu_and_children(state.active_sub_menus, child_sub_menu_id)
                    |> Map.delete(state.active_menu)
                end

                %{state |
                  hovered_dropdown: nil,
                  active_sub_menus: new_sub_menus
                }
              {false, _} ->
                # Mouse left dropdown area - check if we should close it
                # IMPORTANT: Don't close if we have active sub-menus (user might be moving to them)
                if outside_menu_area?(state, coords) do
                  # Logger.debug("Outside menu area, active_sub_menus: #{inspect(state.active_sub_menus)}")
                  if map_size(state.active_sub_menus) > 0 do
                    # Keep menus open if sub-menus are active
                    # Logger.debug("Keeping menus open due to active sub-menus")
                    %{state | hovered_dropdown: nil}
                  else
                    # Logger.debug("Closing all menus")
                    %{state | active_menu: nil, hovered_item: nil, hovered_dropdown: nil, active_sub_menus: %{}}
                  end
                else
                  # Mouse might be in grace area between dropdown and sub-menu
                  %{state | hovered_dropdown: nil}
                end
            end
        end
      
      # Cursor is outside menu area
      true ->
        %{state | hovered_item: nil, hovered_dropdown: nil}
    end
  end
  
  @doc """
  Handle click events.
  """
  def handle_click(%State{} = state, coords) do
    require Logger
    # Logger.debug("Reducer.handle_click: coords=#{inspect(coords)}, frame=#{inspect(state.frame)}")
    
    cond do
      # Click on menu header
      State.point_in_menu_bar?(state, coords) ->
        # Logger.debug("Click is in menu bar")
        case State.find_hovered_menu(state, coords) do
          nil -> 
            # Logger.debug("No menu found at click position")
            {:noop, state}
          menu_id ->
            # Logger.debug("Clicked on menu: #{inspect(menu_id)}")
            if state.active_menu == menu_id do
              # Clicking active menu closes it
              # Logger.debug("Closing active menu: #{inspect(menu_id)}")
              new_state = %{state | active_menu: nil, hovered_dropdown: nil}
              {:noop, new_state}
            else
              # Open this menu
              # Logger.debug("Opening menu: #{inspect(menu_id)}")
              new_state = %{state | active_menu: menu_id, hovered_dropdown: nil}
              {:noop, new_state}
            end
        end
      
      # Click in dropdown or sub-menu
      state.active_menu != nil ->
        # First check if click is in a sub-menu
        case State.point_in_sub_menu?(state, coords) do
          {:ok, {_parent_id, _sub_menu_id, item_id}} when not is_nil(item_id) ->
            # Clicked on an item inside a sub-menu
            # Logger.debug("Clicked on sub-menu item: #{inspect(item_id)}")

            # Close menu and notify parent
            new_state = %{state | active_menu: nil, hovered_item: nil, hovered_dropdown: nil, active_sub_menus: %{}}
            {:menu_item_clicked, item_id, new_state}

          _ ->
            # Not in sub-menu, check main dropdown
            case State.point_in_dropdown?(state, coords) do
              {true, {item_id, :sub_menu}} ->
                # Clicked on sub-menu trigger - don't close, just activate it
                # Logger.debug("Clicked on sub-menu: #{inspect(item_id)}")
                new_state = %{state | active_sub_menus: Map.put(state.active_sub_menus, state.active_menu, item_id)}
                {:noop, new_state}
              {true, {item_id, :item}} ->
                # Regular menu item clicked
                # Logger.debug("Clicked on menu item: #{inspect(item_id)}")

                # Check if this item has an action callback
                action = get_item_action(state, item_id)

                # Execute the action if it exists
                if is_function(action, 0) do
                  # Logger.debug("Executing action callback for #{inspect(item_id)}")
                  action.()
                end

                # Close menu and notify parent
                new_state = %{state | active_menu: nil, hovered_item: nil, hovered_dropdown: nil, active_sub_menus: %{}}
                {:menu_item_clicked, item_id, new_state}
              _ ->
                # Click outside - close menu
                new_state = %{state | active_menu: nil, hovered_item: nil, hovered_dropdown: nil, active_sub_menus: %{}}
                {:noop, new_state}
            end
        end
      
      # Click outside menu entirely
      true ->
        {:noop, state}
    end
  end
  
  defp outside_menu_area?(%State{frame: frame, dropdown_bounds: bounds, active_menu: menu_id, active_sub_menus: sub_menus} = state, {x, y}) do
    dropdown = Map.get(bounds, menu_id)

    # Check if outside menu bar (relative to component origin)
    outside_menu_bar = y < 0 || y > 40 ||
                      x < 0 || x > frame.size.width

    # Check if outside dropdown (if one is open)
    outside_dropdown = if dropdown do
      # Base dropdown bounds
      in_dropdown = x >= dropdown.x && x <= dropdown.x + dropdown.width &&
                   y >= dropdown.y && y <= dropdown.y + dropdown.height

      # Check if we're in any active sub-menu area
      # When a sub-menu is active, expand the valid area SIGNIFICANTLY to include nested menus
      in_submenu_area = if map_size(sub_menus) > 0 do
        # Calculate grace area based on nesting depth
        # Each level adds 150px (width of a menu), plus extra room for mouse movement
        nesting_depth = map_size(sub_menus)
        grace_width = nesting_depth * 150 + 200  # Extra padding for safety

        # Expand the valid area to the right to accommodate nested menus
        x >= dropdown.x && x <= dropdown.x + dropdown.width + grace_width &&
        y >= dropdown.y - 50 && y <= dropdown.y + dropdown.height + 50  # Vertical grace too
      else
        false
      end

      not (in_dropdown or in_submenu_area)
    else
      true
    end

    outside_menu_bar && outside_dropdown
  end
  
  def handle_escape(%State{} = state) do
    # Close any open menus on escape key
    if state.active_menu do
      %{state | active_menu: nil, hovered_item: nil, hovered_dropdown: nil, active_sub_menus: %{}}
    else
      state
    end
  end

  @doc """
  Get the action callback for a menu item by traversing the dropdown bounds.
  Returns nil if no action is found.
  """
  defp get_item_action(%State{dropdown_bounds: bounds, active_menu: active_menu}, item_id) do
    case Map.get(bounds, active_menu) do
      nil -> nil
      dropdown ->
        case get_in(dropdown, [:items, item_id, :action]) do
          action when is_function(action, 0) -> action
          _ -> nil
        end
    end
  end

  @doc """
  Check if an item within a sub-menu is itself a sub-menu (for nesting).
  Returns true if the hovered_item is a sub-menu within the parent sub_menu.
  """
  defp is_sub_menu_item?(_state, _sub_menu_id, nil), do: false
  defp is_sub_menu_item?(state, sub_menu_id, hovered_item) do
    require Logger
    # Find the sub-menu's items in dropdown bounds
    case find_sub_menu_items(state, sub_menu_id) do
      nil ->
        # Logger.debug("is_sub_menu_item?: find_sub_menu_items returned nil for sub_menu_id=#{inspect(sub_menu_id)}")
        false
      items ->
        # Check if this item has type :sub_menu or starts with "submenu_"
        result = String.starts_with?(to_string(hovered_item), "submenu_")
        # Logger.debug("is_sub_menu_item?: sub_menu_id=#{inspect(sub_menu_id)}, hovered_item=#{inspect(hovered_item)}, result=#{result}")
        result
    end
  end

  defp find_sub_menu_items(%State{menu_map: menu_map, active_menu: active_menu}, sub_menu_id) do
    require Logger
    # Search recursively through the menu structure starting from active menu
    case Map.get(menu_map, active_menu) do
      nil ->
        # Logger.debug("find_sub_menu_items: active_menu #{inspect(active_menu)} not found in menu_map")
        nil
      {_label, items} ->
        result = search_items_for_sub_menu(items, sub_menu_id)
        # Logger.debug("find_sub_menu_items: searching for #{inspect(sub_menu_id)} in active_menu #{inspect(active_menu)}, result=#{inspect(result != nil)}")
        result
    end
  end

  defp search_items_for_sub_menu(items, target_sub_menu_id) do
    Enum.find_value(items, fn item ->
      case item do
        {:sub_menu, label, sub_items} ->
          sub_menu_id = "submenu_#{String.downcase(String.replace(label, " ", "_"))}"
          if sub_menu_id == target_sub_menu_id do
            # Found it! Return the items
            sub_items
          else
            # Search deeper
            search_items_for_sub_menu(sub_items, target_sub_menu_id)
          end
        _ ->
          nil
      end
    end)
  end

  @doc """
  Recursively close a sub-menu and all its children.
  Removes the sub_menu_id and any entries where sub_menu_id is a key (its children).
  """
  defp close_sub_menu_and_children(active_sub_menus, sub_menu_id) do
    # Find all children of this sub-menu (entries where this sub_menu_id is a key)
    children = Map.get(active_sub_menus, sub_menu_id)

    # Recursively close children first
    active_sub_menus = if children do
      close_sub_menu_and_children(active_sub_menus, children)
    else
      active_sub_menus
    end

    # Remove this sub-menu from the map (both as a value and as a key)
    active_sub_menus
    |> Enum.reject(fn {_k, v} -> v == sub_menu_id end)
    |> Enum.into(%{})
    |> Map.delete(sub_menu_id)
  end
end