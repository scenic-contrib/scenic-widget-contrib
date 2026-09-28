defmodule ScenicWidgets.TextField.ReducerTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.{Reducer, State}

  test "store-backed command codepoints are ignored" do
    state = %State{focused: true}

    for modifier <- [[:ctrl], [:meta], [:super], [:ctrl, :shift]] do
      assert nil == Reducer.input_to_buffer_action(state, {:codepoint, {"s", modifier}})
    end

    assert {:insert, "é", :at_cursor} =
             Reducer.input_to_buffer_action(state, {:codepoint, {"é", [:alt]}})
  end

  test "store-backed unmodified codepoints remain insert actions" do
    state = %State{focused: true}

    assert {:insert, "s", :at_cursor} =
             Reducer.input_to_buffer_action(state, {:codepoint, {"s", []}})
  end

  # A click on the FIRST row used to resolve to the end of the line: the
  # rows "before" it were sliced as 0..-1//1, which is every row.
  test "a click on the first row lands where it was aimed" do
    state = store_backed_field("Hello world")

    assert {1, 3} = ScenicWidgets.TextField.Renderer.display_to_source_cursor(state, {1, 3})
    assert {1, col} = State.click_to_cursor(state, {30, 10})
    assert col in 2..5, "x=30 is inside 'Hello', got column #{col}"
  end

  # Double-click selects the word, cursor at the word's START: the range is
  # sent end-first because the store puts its cursor at the second position.
  test "store-backed double-click selects the word with the cursor at its start" do
    state = store_backed_field("Hello world")
    click = {:cursor_button, {:btn_left, 1, [], {30, 10}}}

    assert {:click_move_cursor, clicked, {:set_cursor, {1, col}}} =
             Reducer.input_to_buffer_action(state, click)

    assert col in 2..5, "the click should land inside 'Hello', got column #{col}"

    assert {:double_click_select, _, {:select_range, {1, 6}, {1, 1}}} =
             Reducer.input_to_buffer_action(clicked, click)
  end

  defp store_backed_field(text) do
    State.new(%{
      id: :editor,
      frame: Widgex.Frame.new(%{pin: {0, 0}, size: {400, 60}}),
      initial_text: text,
      input_mode: :store_backed,
      focused: true,
      font: %{
        name: :ibm_plex_mono,
        size: 16,
        path: Path.expand("../../assets/fonts/IBMPlexMono-Regular.ttf", __DIR__)
      }
    })
  end

  # The search pane's fields run in direct mode. Ctrl+V there used to paste
  # AND type a "v", because the codepoint the driver reports alongside the
  # chord was inserted as text.
  test "direct-mode command codepoints are ignored" do
    state = direct_field("ab")

    for modifier <- [[:ctrl], [:meta], [:super], [:ctrl, :shift]] do
      assert {:noop, ^state} = Reducer.process_input(state, {:codepoint, {"v", modifier}})
    end
  end

  test "direct-mode text codepoints are inserted, shifted or not" do
    state = direct_field("ab")

    assert {:event, {:text_changed, _, "abc"}, _} =
             Reducer.process_input(state, {:codepoint, {"c", []}})

    assert {:event, {:text_changed, _, "abC"}, _} =
             Reducer.process_input(state, {:codepoint, {"C", [:shift]}})

    assert {:event, {:text_changed, _, "abé"}, _} =
             Reducer.process_input(state, {:codepoint, {"é", [:alt]}})
  end

  test "direct-mode Ctrl+V asks the widget for the clipboard" do
    state = direct_field("")

    assert {:event, {:clipboard_paste_requested, :query}, _} =
             Reducer.process_input(state, {:key, {:key_v, 1, [:ctrl]}})
  end

  # A focused single-line field with the cursor at the end of `text`, as the
  # search pane builds its query field.
  defp direct_field(text) do
    state =
      State.new(%{
        id: :query,
        frame: Widgex.Frame.new(%{pin: {0, 0}, size: {300, 30}}),
        initial_text: text,
        mode: :single_line,
        input_mode: :direct,
        focused: true,
        font: %{
          name: :ibm_plex_mono,
          size: 16,
          path: Path.expand("../../assets/fonts/IBMPlexMono-Regular.ttf", __DIR__)
        }
      })

    # Focus is long settled: a fresh focus_time would make the reducer drop
    # EVERY codepoint for a moment, and the ignore test would pass for the
    # wrong reason.
    %{state | cursor: {1, String.length(text) + 1}, focus_time: nil}
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
