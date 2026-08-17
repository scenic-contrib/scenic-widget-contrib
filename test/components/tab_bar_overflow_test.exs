defmodule ScenicWidgets.TabBarOverflowTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.TabBar.{Reducer, State}

  test "driver scroll shape moves overflowing tabs horizontally" do
    state = state_with_tabs()
    assert {:noop, moved} = Reducer.process_input(state, {:cursor_scroll, {{0, -1}, {50, 10}}})
    assert moved.scroll_offset > 0
  end

  test "driver scroll shape is ignored outside the tab bar" do
    state = state_with_tabs()

    assert {:noop, unchanged} =
             Reducer.process_input(state, {:cursor_scroll, {{0, -1}, {50, 200}}})

    assert unchanged.scroll_offset == state.scroll_offset
  end

  test "selecting an offscreen tab reveals it" do
    state = state_with_tabs()
    assert {:tab_selected, :c, selected} = Reducer.select_tab(state, :c)
    {x, _y, width, _height} = State.get_tab_bounds(selected, :c)
    assert x >= 0
    assert x + width <= selected.frame.size.width
  end

  test "dragging a tab across its neighbour reorders and commits on release" do
    state = state_with_tabs()
    {x, _y, _w, h} = State.get_tab_bounds(state, :a)

    assert {:noop, pressed} =
             Reducer.process_input(state, {:cursor_button, {:btn_left, 1, [], {x + 20, h / 2}}})

    {_bx, _by, bw, _bh} = State.get_tab_bounds(pressed, :b)

    assert {:tabs_dragged, dragged} =
             Reducer.process_input(pressed, {:cursor_pos, {bw * 1.8, h / 2}})

    assert Enum.map(dragged.tabs, & &1.id) == [:b, :a, :c]

    assert {:tabs_reordered, [:b, :a, :c], released} =
             Reducer.process_input(
               dragged,
               {:cursor_button, {:btn_left, 0, [], {bw * 1.8, h / 2}}}
             )

    assert released.dragging_tab_id == nil
  end

  defp state_with_tabs do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {150, 35})

    State.new(%{
      frame: frame,
      tabs: [
        %{id: :a, label: "alpha", closeable: true},
        %{id: :b, label: "beta", closeable: true},
        %{id: :c, label: "gamma", closeable: true}
      ],
      selected_id: :a
    })
  end
end
