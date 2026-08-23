defmodule ScenicWidgets.TextField.ReducerTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.{Reducer, State}

  test "store-backed command codepoints are ignored" do
    state = %State{focused: true}

    for modifier <- [[:ctrl], [:meta], [:super], [:ctrl, :shift]] do
      assert :ignore = Reducer.input_to_buffer_action(state, {:codepoint, {"s", modifier}})
    end

    assert {:insert, "é", :at_cursor} =
             Reducer.input_to_buffer_action(state, {:codepoint, {"é", [:alt]}})
  end

  test "store-backed unmodified codepoints remain insert actions" do
    state = %State{focused: true}

    assert {:insert, "s", :at_cursor} =
             Reducer.input_to_buffer_action(state, {:codepoint, {"s", []}})
  end

  test "store-backed undo and redo use canonical bindings" do
    state = %State{focused: true}

    assert :undo = Reducer.input_to_buffer_action(state, {:key, {:key_z, 1, [:ctrl]}})
    assert :redo = Reducer.input_to_buffer_action(state, {:key, {:key_z, 1, [:ctrl, :shift]}})
    assert nil == Reducer.input_to_buffer_action(state, {:key, {:key_u, 1, [:ctrl]}})
    assert nil == Reducer.input_to_buffer_action(state, {:key, {:key_r, 1, [:ctrl]}})
  end

  test "Shift+Tab emits unindent using the configured tab stop" do
    state = %State{focused: true, tab_width: 6}
    assert {:unindent, 6} = Reducer.input_to_buffer_action(state, {:key, {:key_tab, 1, [:shift]}})

    assert {:insert, "\t", :at_cursor} =
             Reducer.input_to_buffer_action(state, {:key, {:key_tab, 1, []}})
  end
end
