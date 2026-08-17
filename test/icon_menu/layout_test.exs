defmodule ScenicWidgets.IconMenu.LayoutTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.IconMenu.State
  alias ScenicWidgets.IconMenu.Renderer
  alias ScenicWidgets.Menu.Model.{Divider, Item, Select, Slider, Stepper}
  alias ScenicWidgets.IconMenu.Reducer
  alias Scenic.{Graph, Primitive}
  alias Widgex.Frame

  defp state(items, theme \\ %{}) do
    State.new(%{
      frame: Frame.new(pin: {0, 0}, size: {800, 35}),
      align: :left,
      menus: [%{id: :file, icon: :file, items: items}],
      theme: theme
    })
  end

  test "dropdown width grows to fit independent label and shortcut columns" do
    short = state([%Item{id: :save, label: "Save", shortcut: "Ctrl+S"}])

    long =
      state([
        %Item{
          id: :save_as,
          label: "Save a Copy in Another Location",
          shortcut: "Ctrl+Shift+Alt+S"
        }
      ])

    assert long.dropdown_bounds.file.width > short.dropdown_bounds.file.width
    assert short.dropdown_bounds.file.width >= short.theme.dropdown_width
  end

  test "content sizing is capped by dropdown_max_width" do
    state =
      state(
        [
          %Item{
            id: :long,
            label: String.duplicate("very long label ", 20),
            shortcut: "Ctrl+Shift+S"
          }
        ],
        %{dropdown_max_width: 240}
      )

    assert state.dropdown_bounds.file.width == 240
  end

  test "shortcut remains separate from the display label" do
    item = %Item{id: :save, label: "Save As…", shortcut: "Ctrl+Shift+S"}

    assert State.display_label(item) == "Save As…"
    assert State.item_shortcut(item) == "Ctrl+Shift+S"
  end

  test "renderer right-aligns every shortcut on the same column" do
    state =
      state([
        %Item{id: :save, label: "Save", shortcut: "Ctrl+S"},
        %Item{id: :save_as, label: "Save As…", shortcut: "Ctrl+Shift+S"}
      ])

    graph = Renderer.initial_render(Graph.build(), %{state | active_menu: :file})
    first = Graph.get!(graph, {:item_shortcut, :save})
    second = Graph.get!(graph, {:item_shortcut, :save_as})

    assert Primitive.get_style(first, :text_align) == :right
    assert Primitive.get_style(second, :text_align) == :right

    assert Primitive.get_transform(first, :translate) ==
             Primitive.get_transform(second, :translate)
  end

  test "renderer truncates an extreme shortcut at the configured width cap" do
    shortcut = String.duplicate("Ctrl+Shift+", 12) <> "S"

    state =
      state(
        [%Item{id: :extreme, label: "Run", shortcut: shortcut}],
        %{dropdown_max_width: 220}
      )

    graph = Renderer.initial_render(Graph.build(), %{state | active_menu: :file})
    primitive = Graph.get!(graph, {:item_shortcut, :extreme})

    assert primitive.data != shortcut
    assert String.ends_with?(primitive.data, "…")
    assert Primitive.get_style(primitive, :text_align) == :right
  end

  test "slider rows are taller and render a label, value, track, and thumb" do
    slider = %Slider{id: :tab_width, label: "Tab Width", value: 4, min: 2, max: 12}
    state = state([slider, %Item{id: :after, label: "After"}])
    bounds = state.dropdown_bounds.file.items

    assert bounds.tab_width.height == state.theme.dropdown_slider_height
    assert bounds.after.y == bounds.tab_width.y + bounds.tab_width.height

    graph = Renderer.initial_render(Graph.build(), %{state | active_menu: :file})
    assert Graph.get!(graph, {:slider_label, :tab_width}).data == "Tab Width"
    assert Graph.get!(graph, {:slider_value, :tab_width}).data == "4"
    assert Graph.get!(graph, {:slider_track, :tab_width})
    assert Graph.get!(graph, {:slider_thumb, :tab_width})
  end

  test "divider rows are compact, non-interactive separators" do
    divider = %Divider{id: :display_divider}

    state =
      state([%Item{id: :before, label: "Before"}, divider, %Item{id: :after, label: "After"}])

    bounds = state.dropdown_bounds.file.items

    assert bounds.display_divider.height == 13
    assert bounds.after.y == bounds.display_divider.y + bounds.display_divider.height
    refute State.item_enabled?(divider)

    graph = Renderer.initial_render(Graph.build(), %{state | active_menu: :file})
    assert Graph.get!(graph, {:menu_divider, :display_divider})
    assert Graph.get(graph, {:item_text, :display_divider}) == []
  end

  test "select rows expand and emit the chosen value" do
    select = %Select{id: :fold_level, label: "Set Fold Level", value: 1, options: [1, 2, 3, 4]}
    state = %{state([select]) | active_menu: :file}
    bounds = state.dropdown_bounds.file.items.fold_level

    assert {:noop, expanded} = Reducer.handle_click(state, {bounds.x + 20, bounds.y + 10})
    assert State.find_item(expanded, :fold_level).expanded?
    expanded_bounds = expanded.dropdown_bounds.file.items.fold_level

    assert {:menu_value_changed, :fold_level, 3, collapsed} =
             Reducer.handle_click(expanded, {
               expanded_bounds.x + 20,
               expanded_bounds.y + expanded.theme.dropdown_item_height * 3 + 1
             })

    assert State.find_item(collapsed, :fold_level).value == 3
    refute State.find_item(collapsed, :fold_level).expanded?
  end

  test "stepper buttons clamp and emit numeric changes" do
    stepper = %Stepper{id: :zoom, label: "Zoom", value: 100, min: 50, max: 200, step: 10}
    state = %{state([stepper]) | active_menu: :file}
    bounds = state.dropdown_bounds.file.items.zoom

    assert {:menu_value_changed, :zoom, 110, updated} =
             Reducer.handle_click(state, {bounds.x + bounds.width - 5, bounds.y + 10})

    assert State.find_item(updated, :zoom).value == 110

    graph = Renderer.initial_render(Graph.build(), state)
    minus_bg = Graph.get!(graph, {:stepper_minus_bg, :zoom})
    plus = Graph.get!(graph, {:stepper_plus, :zoom})
    value = Graph.get!(graph, {:stepper_value, :zoom})
    refute Primitive.get_style(minus_bg, :fill) == {:color, {:color_rgba, {0, 0, 0, 0}}}
    assert Primitive.get_style(plus, :text_base) == :middle
    assert Primitive.get_style(value, :text_base) == :middle
  end

  test "select popovers show four options and scroll longer choice lists" do
    select = %Select{id: :level, label: "Level", value: 1, options: Enum.to_list(1..8)}
    state = %{state([select]) | active_menu: :file}
    bounds = state.dropdown_bounds.file.items.level
    {:noop, expanded} = Reducer.handle_click(state, {bounds.x + 10, bounds.y + 10})

    assert expanded.dropdown_bounds.file.items.level.height ==
             expanded.theme.dropdown_item_height * 5

    graph = Renderer.initial_render(Graph.build(), expanded)
    assert Graph.get!(graph, {:select_option, :level, 1})
    assert Graph.get!(graph, {:select_option, :level, 4})
    assert Graph.get(graph, {:select_option, :level, 5}) == []

    assert {:noop, scrolled} =
             Reducer.process_input(expanded, {
               :cursor_scroll,
               {{0, 1}, {bounds.x + 10, bounds.y + expanded.theme.dropdown_item_height * 2}}
             })

    assert State.find_item(scrolled, :level).scroll_offset == 1
  end

  test "hovered sliders invert their controls against the blue row highlight" do
    slider = %Slider{id: :tab_width, label: "Tab Stops", value: 4, min: 2, max: 12}
    state = state([slider])

    normal = Renderer.initial_render(Graph.build(), %{state | active_menu: :file})

    hovered =
      Renderer.initial_render(Graph.build(), %{
        state
        | active_menu: :file,
          hovered_item: :tab_width
      })

    normal_fill = Graph.get!(normal, {:slider_fill, :tab_width})
    hovered_fill = Graph.get!(hovered, {:slider_fill, :tab_width})
    hovered_track = Graph.get!(hovered, {:slider_track, :tab_width})

    refute Primitive.get_style(normal_fill, :fill) == Primitive.get_style(hovered_fill, :fill)
    assert Primitive.get_style(hovered_fill, :fill) == {:color, {:color_rgba, {50, 50, 50, 255}}}

    assert Primitive.get_style(hovered_track, :fill) ==
             {:color, {:color_rgba, {255, 255, 255, 255}}}

    restored =
      Renderer.update_render(
        hovered,
        %{state | active_menu: :file, hovered_item: :tab_width},
        %{state | active_menu: :file}
      )

    assert Primitive.get_style(Graph.get!(restored, {:slider_fill, :tab_width}), :fill) ==
             Primitive.get_style(normal_fill, :fill)

    assert Primitive.get_style(Graph.get!(restored, {:slider_label, :tab_width}), :fill) ==
             {:color, {:color_rgba, {220, 220, 220, 255}}}
  end

  test "shortcut columns can be hidden in place and dropdown bounds are recalculated" do
    item = %Item{id: :save_as, label: "Save As…", shortcut: "Ctrl+Shift+S"}
    shown = state([item], %{dropdown_width: 100})
    hidden = %{shown | show_shortcuts: false}
    hidden = %{hidden | dropdown_bounds: State.calculate_dropdown_bounds(hidden)}

    assert hidden.dropdown_bounds.file.width < shown.dropdown_bounds.file.width

    shown_graph = Renderer.initial_render(Graph.build(), %{shown | active_menu: :file})
    hidden_graph = Renderer.initial_render(Graph.build(), %{hidden | active_menu: :file})
    assert Graph.get(shown_graph, {:item_shortcut, :save_as}) != []
    assert Graph.get(hidden_graph, {:item_shortcut, :save_as}) == []
  end

  test "a tooltip near the right edge flips left instead of overflowing" do
    x = Renderer.fit_tooltip_x(130, 180, 140)
    assert x + 180 <= 136
    assert x < 0
  end

  test "tooltip width uses measured text plus symmetric padding" do
    width = Renderer.tooltip_width("File commands", :roboto_mono, 12, 7)
    assert width > 14
    assert width < 120
  end
end
