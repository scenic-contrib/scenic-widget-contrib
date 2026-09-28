defmodule ScenicWidgets.Menu.ModelTest do
  use ExUnit.Case, async: true
  alias ScenicWidgets.Menu.Model
  alias ScenicWidgets.Menu.Model.{Item, Section, Slider, Submenu, Toggle}
  alias ScenicWidgets.IconMenu.{Reducer, State}

  test "IconMenu exposes optional tooltips for icon buttons and typed rows" do
    menu = %{id: :file, icon: :file, tooltip: "File commands", items: []}

    item = %ScenicWidgets.Menu.Model.Item{
      id: "save",
      label: "Save",
      tooltip: "Write changes to disk"
    }

    assert State.menu_tooltip(menu) == "File commands"
    assert State.item_tooltip(item) == "Write changes to disk"
    assert State.item_tooltip({"plain", "Plain item"}) == nil
  end

  test "validates nested typed rows and emits semantic events" do
    item = %Item{id: :save, label: "Save"}
    slider = %Slider{id: :size, label: "Text size", value: 16, min: 12, max: 32}

    model = %Model{
      id: :file,
      rows: [
        item,
        %Section{id: :view_section, label: "View"},
        %Toggle{id: :wrap, label: "Wrap", checked?: true},
        %Submenu{id: :more, label: "More", rows: [slider]}
      ]
    }

    assert {:ok, ^model} = Model.validate(model)
    assert Model.event(model, item) == {:menu_action, :file, :save, :activate}
  end

  test "IconMenu consumes typed rows and disabled rows cannot activate" do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {200, 35})

    rows = [
      %Item{id: :open, label: "Open"},
      %Item{id: :disabled, label: "Disabled", enabled?: false}
    ]

    state =
      State.new(%{frame: frame, align: :left, menus: [%{id: :file, icon: :file, items: rows}]})

    state = %{state | active_menu: :file}
    disabled_bounds = state.dropdown_bounds.file.items.disabled
    coords = {disabled_bounds.x + 1, disabled_bounds.y + 1}
    assert {:noop, ^state} = Reducer.handle_click(state, coords)
  end

  test "rejects duplicate ids and out-of-range sliders" do
    assert {:error, :duplicate_id} =
             Model.validate(%Model{
               id: :x,
               rows: [%Item{id: :same, label: "A"}, %Item{id: :same, label: "B"}]
             })

    assert {:error, :invalid_row} =
             Model.validate(%Model{
               id: :x,
               rows: [%Slider{id: :s, label: "S", value: 40, min: 12, max: 32}]
             })
  end

  test "IconMenu slider maps pointer position to a stepped live value" do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {200, 35})
    slider = %Slider{id: :size, label: "Size", value: 12, min: 12, max: 32, step: 2}

    state =
      State.new(%{
        frame: frame,
        align: :left,
        menus: [%{id: :view, icon: :view, items: [slider]}]
      })

    state = %{state | active_menu: :view}
    bounds = state.dropdown_bounds.view.items.size

    assert {:menu_value_changed, :size, 22, updated} =
             Reducer.handle_click(state, {bounds.x + bounds.width / 2, bounds.y + 1})

    assert %Slider{value: 22} = State.find_item(updated, :size)
  end
end
