defmodule ScenicWidgets.IconMenu.ReducerTest do
  @moduledoc """
  TDD gate for Bug 002 — menubar deselect.

  See `quillex/docs/bugs/002_menubar_deselect.md`. Two PRD-confirmed
  pure-state-transition failures live in `IconMenu.Reducer`:

    V1 (PRIMARY) — Escape key never closes an open dropdown. The clause
    at `reducer.ex:25` matches `{:key, {"escape", _mods, _action}}` but
    Scenic delivers `{:key, {:key_esc, key_state, mods}}` (cf.
    `text_field/reducer.ex:101`). Input falls through to the catch-all
    noop at `reducer.ex:29`.

    V2 (SECONDARY) — Click on the already-active icon (toggle-close)
    clears `active_menu`/`hovered_item` at `reducer.ex:91-93` but leaves
    `hovered_menu` set, so the icon retains hover styling visually until
    the cursor leaves the bar.

  These tests MUST fail on HEAD (`fb15316`) — they are the failing-test
  gate that authorises the fix commit.
  """

  use ExUnit.Case, async: true

  alias ScenicWidgets.IconMenu.{Reducer, State}
  alias ScenicWidgets.Menu.Dropdown
  alias ScenicWidgets.Menu.Model.{Slider, Stepper, Toggle}
  alias Widgex.Frame

  defp build_state do
    frame = %Frame{
      pin: %{point: {0, 0}},
      size: %{width: 800, height: 35}
    }

    State.new(%{frame: frame, align: :left})
  end

  describe "menubar hover/deselect — Bug 002" do
    test "Escape with active dropdown closes it (V1 — primary)" do
      state = %{
        build_state()
        | active_menu: :file,
          hovered_menu: :file,
          hovered_item: "new"
      }

      escape_input = {:key, {:key_esc, 1, []}}

      assert {:noop, new_state} = Reducer.process_input(state, escape_input)

      assert new_state.active_menu == nil,
             "Escape must clear active_menu; got #{inspect(new_state.active_menu)}"

      assert new_state.hovered_menu == nil,
             "Escape must clear hovered_menu; got #{inspect(new_state.hovered_menu)}"

      assert new_state.hovered_item == nil,
             "Escape must clear hovered_item; got #{inspect(new_state.hovered_item)}"
    end

    test "Toggle-close (click on active icon) clears hovered_menu (V2 — secondary)" do
      # File icon spans x = 0..35 with align: :left and default button_size 35.
      # Click at (17, 17) lands inside the File icon button.
      state = %{
        build_state()
        | active_menu: :file,
          hovered_menu: :file,
          hovered_item: nil
      }

      click_input = {:cursor_button, {:btn_left, 1, [], {17, 17}}}

      assert {:noop, new_state} = Reducer.process_input(state, click_input)

      assert new_state.active_menu == nil,
             "Toggle-close must clear active_menu; got #{inspect(new_state.active_menu)}"

      assert new_state.hovered_menu == nil, """
      Toggle-close must clear hovered_menu, but it was #{inspect(new_state.hovered_menu)}.
      Bug 002 V2: reducer.ex:91-93 only clears active_menu/hovered_item.
      """
    end
  end

  describe "reusable slider rows" do
    test "pressing and dragging continuously changes the stepped value" do
      slider = %Slider{id: :tab_width, label: "Tab Width", value: 2, min: 2, max: 12, step: 1}

      state =
        State.new(%{
          frame: Frame.new(pin: {0, 0}, size: {300, 35}),
          align: :left,
          menus: [%{id: :view, icon: :view, items: [slider]}]
        })

      state = %{state | active_menu: :view}
      bounds = state.dropdown_bounds.view.items.tab_width
      middle = {bounds.x + bounds.width / 2, bounds.y + bounds.height / 2}

      assert {:menu_value_changed, :tab_width, 7, dragging} =
               Reducer.process_input(state, {:cursor_button, {:btn_left, 1, [], middle}})

      assert dragging.dragging_slider == :tab_width

      assert {:menu_value_changed, :tab_width, 12, dragged} =
               Reducer.process_input(dragging, {:cursor_pos, {bounds.x + bounds.width, bounds.y}})

      assert {:noop, released} =
               Reducer.process_input(
                 dragged,
                 {:cursor_button, {:btn_left, 0, [], {bounds.x + bounds.width, bounds.y}}}
               )

      assert released.dragging_slider == nil
      assert State.find_item(released, :tab_width).value == 12
    end
  end

  describe "reusable toggle rows" do
    test "toggle changes value without closing its dropdown" do
      toggle = %Toggle{id: :shortcuts, label: "Shortcuts", checked?: true}

      state =
        State.new(%{
          frame: Frame.new(pin: {0, 0}, size: {300, 35}),
          align: :left,
          menus: [%{id: :view, icon: :view, items: [toggle]}]
        })

      state = %{state | active_menu: :view}
      bounds = state.dropdown_bounds.view.items.shortcuts
      coords = {bounds.x + bounds.width / 2, bounds.y + bounds.height / 2}

      assert {:menu_value_changed, :shortcuts, false, updated} =
               Reducer.process_input(state, {:cursor_button, {:btn_left, 1, [], coords}})

      assert updated.active_menu == :view
      refute State.find_item(updated, :shortcuts).checked?
    end
  end
  describe "stepper rows" do
    # A View menu holding only the zoom stepper, open, at a given chrome size.
    defp zoom_menu(font_size) do
      stepper = %Stepper{id: :zoom, label: "Zoom", value: 100, min: 50, max: 400, step: 10}

      state =
        State.new(%{
          frame: Frame.new(pin: {0, 0}, size: {600, 35}),
          align: :left,
          menus: [%{id: :view, icon: :view, items: [stepper]}],
          theme: %{
            dropdown_font_size: font_size,
            dropdown_item_height: round(font_size * 2.15)
          }
        })

      %{state | active_menu: :view}
    end

    defp click(state, {left, width}) do
      bounds = state.dropdown_bounds.view.items.zoom
      at = {bounds.x + left + width / 2, bounds.y + bounds.height / 2}
      Reducer.process_input(state, {:cursor_button, {:btn_left, 1, [], at}})
    end

    defp layout(state) do
      bounds = state.dropdown_bounds.view.items.zoom
      Dropdown.stepper_layout(state.theme, bounds.width)
    end

    # The buttons used to be hit-tested at fixed pixel offsets, which were
    # only where the buttons were drawn at 100%.
    test "plus and minus are where they are drawn, at any chrome size" do
      for font_size <- [13, 26, 52] do
        state = zoom_menu(font_size)
        layout = layout(state)

        assert {:menu_value_changed, :zoom, 110, _} = click(state, layout.plus)
        assert {:menu_value_changed, :zoom, 90, _} = click(state, layout.minus)

        # The controls grow with the type, and the row is still wide enough.
        {plus_x, plus_w} = layout.plus
        assert layout.button_height > font_size
        assert plus_x + plus_w <= state.dropdown_bounds.view.items.zoom.width
      end
    end

    test "a click on the value opens it for typing, showing the current value selected" do
      state = zoom_menu(13)

      assert {:noop, editing} = click(state, layout(state).value)
      assert editing.editing == %{item_id: :zoom, text: "100", pristine?: true}
      assert editing.active_menu == :view
    end

    test "typing replaces the selected value, Enter applies it clamped" do
      {:noop, state} = click(zoom_menu(13), layout(zoom_menu(13)).value)

      typed =
        Enum.reduce(["4", "0", "0", "%"], state, fn char, acc ->
          {:noop, acc} = Reducer.process_input(acc, {:codepoint, {char, []}})
          acc
        end)

      assert typed.editing.text == "400", "digits land, a typed % does not"

      assert {:menu_value_changed, :zoom, 400, applied} =
               Reducer.process_input(typed, {:key, {:key_enter, 1, []}})

      assert applied.editing == nil
      assert applied.active_menu == :view
      assert State.find_item(applied, :zoom).value == 400

      # Past the top of the range is the top of the range.
      {:noop, again} = click(applied, layout(applied).value)

      big =
        Enum.reduce(["9", "9", "9", "9"], again, fn char, acc ->
          {:noop, acc} = Reducer.process_input(acc, {:codepoint, {char, []}})
          acc
        end)

      assert {:menu_value_changed, :zoom, 400, _} =
               Reducer.process_input(%{big | menus: state.menus}, {:key, {:key_enter, 1, []}})
    end

    test "Backspace on the fresh field clears it, and an empty Enter is a cancel" do
      {:noop, state} = click(zoom_menu(13), layout(zoom_menu(13)).value)

      {:noop, cleared} = Reducer.process_input(state, {:key, {:key_backspace, 1, []}})
      assert cleared.editing.text == ""

      assert {:noop, cancelled} = Reducer.process_input(cleared, {:key, {:key_enter, 1, []}})
      assert cancelled.editing == nil
      assert State.find_item(cancelled, :zoom).value == 100
    end

    test "Escape while typing closes the field and leaves the menu open" do
      {:noop, state} = click(zoom_menu(13), layout(zoom_menu(13)).value)

      assert {:noop, after_esc} = Reducer.process_input(state, {:key, {:key_esc, 1, []}})
      assert after_esc.editing == nil
      assert after_esc.active_menu == :view
    end

    test "a click anywhere ends the typing uncommitted" do
      {:noop, state} = click(zoom_menu(13), layout(zoom_menu(13)).value)
      {:noop, typed} = Reducer.process_input(state, {:codepoint, {"3", []}})

      assert {:menu_value_changed, :zoom, 110, stepped} = click(typed, layout(typed).plus)
      assert stepped.editing == nil
    end
  end
end
