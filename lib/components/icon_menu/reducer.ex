defmodule ScenicWidgets.IconMenu.Reducer do
  @moduledoc """
  Pure state transition functions for IconMenu.

  Handles cursor movements, clicks, and keyboard input.
  """

  alias ScenicWidgets.IconMenu.State
  alias ScenicWidgets.Menu.Dropdown

  @doc """
  Process user input and return state transitions.

  Returns:
  - `{:noop, state}` - State unchanged or only visual state changed
  - `{:menu_item_clicked, item_id, state}` - Menu item was clicked
  """
  def process_input(%State{} = state, {:cursor_pos, coords}) do
    handle_cursor_pos(state, coords)
  end

  def process_input(
        %State{} = state,
        {:cursor_scroll, {{_dx, dy}, coords}}
      ) do
    scroll_open_select(state, dy, coords)
  end

  def process_input(%State{} = state, {:cursor_scroll, {_dx, dy, x, y}}) do
    scroll_open_select(state, dy, {x, y})
  end

  # Any click ends the typing of a stepper's value, uncommitted — a click on
  # the value box itself starts it afresh, and a click on its plus or minus
  # is a step from the value the field opened on.
  def process_input(%State{} = state, {:cursor_button, {:btn_left, 1, _mods, coords}}) do
    handle_click(%{state | editing: nil}, coords)
  end

  def process_input(
        %State{dragging_slider: slider_id} = state,
        {:cursor_button, {:btn_left, 0, _mods, _coords}}
      )
      when not is_nil(slider_id) do
    {:noop, %{state | dragging_slider: nil}}
  end

  # The button came up: whichever drag was on is over. The scrollbar is checked
  # after the slider only because a slider drag cannot start on the bar.
  def process_input(
        %State{dropdown_drag: drag} = state,
        {:cursor_button, {:btn_left, 0, _mods, _coords}}
      )
      when not is_nil(drag) do
    {:noop, %{state | dropdown_drag: nil}}
  end

  # ── A stepper's value being typed ─────────────────────────────────────────
  #
  # Digits only, and four of them at most: the box is sized for a percentage,
  # and a stepper's range is clamped on commit anyway. A "%" typed out of
  # habit is simply not a digit, so it never lands in the field.
  def process_input(
        %State{editing: %{text: text, pristine?: pristine?} = editing} = state,
        {:codepoint, {char, _mods}}
      )
      when char in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    text = if pristine?, do: "", else: text

    if String.length(text) >= 4 do
      {:noop, state}
    else
      {:noop, %{state | editing: %{editing | text: text <> char, pristine?: false}}}
    end
  end

  def process_input(
        %State{editing: %{text: text, pristine?: pristine?} = editing} = state,
        {:key, {:key_backspace, key_state, _mods}}
      )
      when key_state > 0 do
    text = if pristine?, do: "", else: String.slice(text, 0..-2//1)
    {:noop, %{state | editing: %{editing | text: text, pristine?: false}}}
  end

  def process_input(%State{editing: %{}} = state, {:key, {key, 1, _mods}})
      when key in [:key_enter, :key_kp_enter] do
    commit_edit(state)
  end

  # Escape while typing puts the field away and nothing else: the menu the
  # person is looking at stays open.
  def process_input(%State{editing: %{}} = state, {:key, {:key_esc, 1, _mods}}) do
    {:noop, %{state | editing: nil}}
  end

  def process_input(%State{} = state, {:key, {:key_esc, key_state, _mods}})
      when key_state > 0 do
    handle_escape(state)
  end

  def process_input(state, _input) do
    {:noop, state}
  end

  @doc """
  Handle cursor position for hover effects.
  """
  def handle_cursor_pos(%State{} = state, coords) do
    cond do
      state.dragging_slider ->
        update_slider(state, state.dragging_slider, coords, true)

      state.dropdown_drag ->
        {:noop, drag_dropdown(state, coords)}

      true ->
        do_handle_cursor_pos(state, coords)
    end
  end

  # Mid-drag the pointer belongs to the bar and to nothing else: no hover, no
  # row under it, however far it has wandered from the panel.
  defp drag_dropdown(%State{dropdown_drag: {start_y, start_offset}} = state, {_x, y}) do
    bounds = active_dropdown(state)
    scrolled = Dropdown.drag(bounds, start_offset, y - start_y)
    recalculate(%{state | dropdown_scroll: scrolled})
  end

  defp do_handle_cursor_pos(%State{} = state, coords) do
    cond do
      # Check if cursor is over icon buttons
      State.point_in_icon_bar?(state, coords) ->
        hovered_icon = State.find_hovered_icon(state, coords)

        new_state = %{
          state
          | hovered_menu: hovered_icon,
            hovered_item: nil,
            hovered_select_option: nil
        }

        # If a dropdown is open and we hover a different icon, switch to it
        new_state =
          if state.active_menu && hovered_icon && state.active_menu != hovered_icon do
            %{new_state | active_menu: hovered_icon}
          else
            new_state
          end

        {:noop, new_state}

      # Check if cursor is in dropdown
      state.active_menu != nil ->
        case State.point_in_dropdown?(state, coords) do
          {true, item_id} ->
            # Inside dropdown, possibly over an item
            option = hovered_select_option(state, item_id, coords)

            {:noop,
             %{
               state
               | hovered_item: item_id,
                 hovered_select_option: option,
                 hovered_menu: state.active_menu
             }}

          {false, _} ->
            # Pointer motion alone never dismisses an open menu. This avoids
            # stale/out-of-order cursor samples closing a menu immediately
            # after a semantic or real click; click-away and Escape remain the
            # authoritative dismissal gestures.
            {:noop, %{state | hovered_item: nil, hovered_select_option: nil}}
        end

      # Cursor outside menu area
      true ->
        if state.hovered_menu do
          {:noop, %{state | hovered_menu: nil, hovered_item: nil, hovered_select_option: nil}}
        else
          {:noop, state}
        end
    end
  end

  defp hovered_select_option(state, item_id, {x, y}) do
    item = State.find_item(state, item_id)
    bounds = get_in(state.dropdown_bounds, [state.active_menu, :items, item_id])

    if match?(%ScenicWidgets.Menu.Model.Select{expanded?: true}, item) and bounds do
      row_height = state.theme.dropdown_item_height

      {box_left, box_width} =
        if item.options_full_width?,
          do: {bounds.x, bounds.width},
          else: {bounds.x + bounds.width - (item.option_width || 76) - 8, item.option_width || 76}

      index = floor((y - bounds.y - row_height) / row_height)
      options = ScenicWidgets.Menu.Model.select_options(item)

      if x >= box_left and x <= box_left + box_width and index >= 0,
        do: options |> Enum.at(index) |> then(&if(&1, do: elem(&1, 0))),
        else: nil
    end
  end

  @doc """
  Handle click events.
  """
  # The scrollbar first. It is drawn over the right-hand end of the panel, so
  # every point on it is also a point on a row — and a press there means the
  # bar. `Dropdown.scrollbar_hit/2` answers nil for a panel with no bar on it,
  # which is most of them.
  def handle_click(%State{} = state, {_x, y} = coords) do
    case scrollbar_hit(state, coords) do
      :thumb ->
        {:noop, %{state | dropdown_drag: {y, state.dropdown_scroll}}}

      {:track, along} ->
        {:noop,
         recalculate(%{state | dropdown_scroll: Dropdown.page(active_dropdown(state), along)})}

      nil ->
        click_rows(state, coords)
    end
  end

  defp scrollbar_hit(%State{active_menu: nil}, _coords), do: nil

  defp scrollbar_hit(%State{} = state, coords) do
    case active_dropdown(state) do
      nil -> nil
      bounds -> Dropdown.scrollbar_hit(bounds, coords)
    end
  end

  defp active_dropdown(%State{active_menu: menu_id, dropdown_bounds: bounds}),
    do: Map.get(bounds, menu_id)

  defp click_rows(%State{} = state, coords) do
    cond do
      # Click on icon button
      State.point_in_icon_bar?(state, coords) ->
        case State.find_hovered_icon(state, coords) do
          nil ->
            {:noop, state}

          menu_id ->
            if state.active_menu == menu_id do
              # Click on active menu - close it
              {:noop,
               recalculate(%{
                 state
                 | active_menu: nil,
                   hovered_menu: nil,
                   hovered_item: nil,
                   dropdown_scroll: 0,
                   dropdown_drag: nil
               })}
            else
              # Open this menu. A dropdown always opens at its top: reopening
              # one where the last visit left it would hide the first rows.
              {:noop,
               recalculate(%{
                 state
                 | active_menu: menu_id,
                   hovered_item: nil,
                   dropdown_scroll: 0,
                   dropdown_drag: nil
               })}
            end
        end

      # Click in dropdown
      state.active_menu != nil ->
        case State.point_in_dropdown?(state, coords) do
          {true, nil} ->
            # Click in dropdown but not on an item
            {:noop, state}

          {true, item_id} ->
            # Click on menu item
            item = State.find_item(state, item_id)

            if item && not State.item_enabled?(item) do
              {:noop, state}
            else
              activate_item(state, item, item_id, coords)
            end

          {false, _} ->
            # Click outside dropdown - close menu
            {:noop, %{state | active_menu: nil, hovered_menu: nil, hovered_item: nil}}
        end

      # Click outside menu area
      true ->
        {:noop, state}
    end
  end

  defp activate_item(state, %ScenicWidgets.Menu.Model.Slider{}, item_id, {x, _y}) do
    update_slider(state, item_id, {x, 0}, true)
  end

  # A tree row: the header opens and shuts it, and inside it the TRIANGLE
  # expands a branch while the rest of the row ticks it. Two intentions, two
  # targets — one rectangle carrying both means the commonest thing you want
  # from a tree ("not that one") cannot be done to anything with children.
  defp activate_item(state, %ScenicWidgets.Menu.Model.Tree{} = tree, item_id, {x, y}) do
    bounds = state.dropdown_bounds[state.active_menu].items[item_id]
    row_height = state.theme.dropdown_item_height

    if tree.expanded? and y >= bounds.y + row_height do
      index = floor((y - bounds.y - row_height) / row_height)

      case Enum.at(ScenicWidgets.Menu.Model.visible_tree_nodes(tree), index) do
        nil ->
          {:noop, state}

        {node, depth} ->
          gutter = 8 + depth * ScenicWidgets.Menu.Model.tree_indent()

          cond do
            node.children != [] and x >= gutter and
                x < gutter + ScenicWidgets.Menu.Model.tree_indent() ->
              {:noop,
               replace_and_recalculate(
                 state,
                 item_id,
                 ScenicWidgets.Menu.Model.toggle_tree_expanded(tree, node.id)
               )}

            true ->
              updated = ScenicWidgets.Menu.Model.toggle_tree_node(tree, node.id)

              {:menu_tree_changed, item_id, {node.id, not node.checked?},
               replace_and_recalculate(state, item_id, updated)}
          end
      end
    else
      {:noop, replace_and_recalculate(state, item_id, %{tree | expanded?: not tree.expanded?})}
    end
  end

  defp activate_item(state, %ScenicWidgets.Menu.Model.Select{} = select, item_id, {_x, y}) do
    bounds = state.dropdown_bounds[state.active_menu].items[item_id]
    row_height = state.theme.dropdown_item_height

    if select.expanded? and y >= bounds.y + row_height do
      option =
        select
        |> ScenicWidgets.Menu.Model.select_options()
        |> Enum.at(floor((y - bounds.y - row_height) / row_height))

      if is_nil(option) do
        {:noop, state}
      else
        {value, _label} = option
        updated = %{select | value: value, expanded?: false}
        {:menu_value_changed, item_id, value, replace_and_recalculate(state, item_id, updated)}
      end
    else
      updated = %{select | expanded?: not select.expanded?}
      {:noop, replace_and_recalculate(state, item_id, updated)}
    end
  end

  # The wheel inside an open dropdown scrolls the DROPDOWN, whatever it is
  # over. It used to ask first whether the pointer was on an expanded Tree or
  # Select and wind that row's own offset instead — which meant the same
  # gesture did two different things depending on which row you happened to be
  # over, and only one of them moved the bar now drawn down the side. Rows do
  # not scroll any more; panels do.
  defp scroll_open_select(state, dy, coords) do
    case State.point_in_dropdown?(state, coords) do
      {true, _item_id} ->
        {:noop, scroll_dropdown(state, dy)}

      # The wheel somewhere else: the person has finished with the menu and
      # started reading what is behind it. A dropdown left hanging over that
      # is in the way.
      _ ->
        {:noop, %{state | active_menu: nil, hovered_item: nil}}
    end
  end

  defp scroll_dropdown(state, dy) do
    bounds = active_dropdown(state)

    if bounds && Dropdown.scrollable?(bounds) do
      recalculate(%{state | dropdown_scroll: Dropdown.wheel(bounds, state.dropdown_scroll, dy)})
    else
      state
    end
  end

  # The three hit zones are the three things drawn, from the one layout the
  # renderer draws them with — hard-coded pixel offsets here were only right
  # at 100%, and at any other zoom the buttons had moved out from under them.
  defp activate_item(state, %ScenicWidgets.Menu.Model.Stepper{} = stepper, item_id, {x, _y}) do
    bounds = state.dropdown_bounds[state.active_menu].items[item_id]
    local_x = x - bounds.x
    layout = ScenicWidgets.Menu.Dropdown.stepper_layout(state.theme, bounds.width)

    cond do
      within?(local_x, layout.plus) ->
        set_stepper(state, stepper, item_id, stepper.value + stepper.step)

      within?(local_x, layout.minus) ->
        set_stepper(state, stepper, item_id, stepper.value - stepper.step)

      within?(local_x, layout.value) ->
        edit = %{item_id: item_id, text: Integer.to_string(stepper.value), pristine?: true}
        {:noop, %{state | editing: edit}}

      true ->
        {:noop, state}
    end
  end

  defp activate_item(
         state,
         %ScenicWidgets.Menu.Model.Toggle{checked?: checked} = toggle,
         item_id,
         _coords
       ) do
    updated = %{toggle | checked?: not checked}
    menus = replace_active_item(state, item_id, updated)

    {:menu_value_changed, item_id, updated.checked?,
     %{state | menus: menus, hovered_item: item_id}}
  end

  defp activate_item(state, _item, item_id, _coords) do
    # Execute action callback if present
    action = State.get_item_action(state, item_id)
    if is_function(action, 0), do: action.()

    # Close menu and notify parent
    new_state = %{
      state
      | active_menu: nil,
        hovered_menu: nil,
        hovered_item: nil,
        dragging_slider: nil
    }

    {:menu_item_clicked, item_id, new_state}
  end

  defp update_slider(state, item_id, {x, _y}, dragging?) do
    slider = State.find_item(state, item_id)
    bounds = state.dropdown_bounds[state.active_menu].items[item_id]
    track_inset = ScenicWidgets.Menu.Dropdown.slider_track_inset(state.theme)
    ratio = (x - bounds.x - track_inset) / max(bounds.width - 2 * track_inset, 1)
    raw = slider.min + min(1.0, max(0.0, ratio)) * (slider.max - slider.min)
    steps = round((raw - slider.min) / slider.step)
    value = min(slider.max, max(slider.min, slider.min + steps * slider.step))
    updated = %{slider | value: value}

    menus = replace_active_item(state, item_id, updated)

    new_state = %{
      state
      | menus: menus,
        hovered_item: item_id,
        dragging_slider: if(dragging?, do: item_id, else: state.dragging_slider)
    }

    {:menu_value_changed, item_id, value, new_state}
  end

  defp replace_active_item(state, item_id, updated) do
    Enum.map(state.menus, fn
      %{id: id, items: items} = menu when id == state.active_menu ->
        %{
          menu
          | items: Enum.map(items, &if(State.get_item_id(&1) == item_id, do: updated, else: &1))
        }

      menu ->
        menu
    end)
  end

  defp recalculate(state), do: %{state | dropdown_bounds: State.calculate_dropdown_bounds(state)}

  defp within?(x, {left, width}), do: x >= left and x <= left + width

  # Clamp to the stepper's range and tell the host — unless it is the value
  # the stepper already shows, in which case there is nothing to tell.
  defp set_stepper(state, %ScenicWidgets.Menu.Model.Stepper{} = stepper, item_id, wanted) do
    value = min(stepper.max, max(stepper.min, wanted))

    if value == stepper.value do
      {:noop, state}
    else
      updated = %{stepper | value: value}
      {:menu_value_changed, item_id, value, replace_and_recalculate(state, item_id, updated)}
    end
  end

  # Enter on a typed value. Empty or unparseable means "never mind", the same
  # as Escape; anything else is clamped into range and applied.
  defp commit_edit(%State{editing: %{item_id: item_id, text: text}} = state) do
    state = %{state | editing: nil}

    case {Integer.parse(text), State.find_item(state, item_id)} do
      {{wanted, ""}, %ScenicWidgets.Menu.Model.Stepper{} = stepper} ->
        set_stepper(state, stepper, item_id, wanted)

      _ ->
        {:noop, state}
    end
  end

  defp replace_and_recalculate(state, item_id, updated) do
    state = %{state | menus: replace_active_item(state, item_id, updated), hovered_item: item_id}
    %{state | dropdown_bounds: State.calculate_dropdown_bounds(state)}
  end

  @doc """
  Handle escape key to close menus.
  """
  def handle_escape(%State{active_menu: nil} = state) do
    {:noop, state}
  end

  def handle_escape(%State{} = state) do
    {:noop,
     %{
       state
       | active_menu: nil,
         hovered_menu: nil,
         hovered_item: nil,
         dragging_slider: nil,
         dropdown_drag: nil,
         editing: nil
     }}
  end
end
