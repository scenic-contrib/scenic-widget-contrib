defmodule ScenicWidgets.TextField.FoldingTest do
  use ExUnit.Case, async: true
  alias ScenicWidgets.TextField.Folding
  alias ScenicWidgets.TextField.{Reducer, Renderer, State}
  alias Scenic.Graph
  alias Widgex.{Frame}
  alias Widgex.Scroll.ScrollState

  @lines ["defmodule A do", "  def x do", "    :ok", "  end", "end", "tail"]

  test "indentation defines a fold and projection retains the header" do
    assert Folding.foldable?(@lines, 1)

    assert Folding.projection(@lines, MapSet.new([1])) == [
             {1, "defmodule A do", 3},
             {5, "end", 0},
             {6, "tail", 0}
           ]
  end

  test "toggle, unfold-all, and fold-to-level are deterministic" do
    assert Folding.toggle(@lines, MapSet.new(), 1) == MapSet.new([1])
    assert Folding.unfold_all() == MapSet.new()
    assert MapSet.member?(Folding.fold_to_level(@lines, 2), 2)
  end

  test "fold levels are exact and one-based so parent headers remain visible" do
    assert Folding.fold_to_level(@lines, 1) == MapSet.new([1])
    assert Folding.fold_to_level(@lines, 2) == MapSet.new([2])
    assert Folding.fold_to_level(@lines, 3) == MapSet.new()
    assert Folding.foldable_lines(@lines) == MapSet.new([1, 2])
  end

  test "tabs and multi-column indentation count as one structural level" do
    tabbed = ["defmodule A do", "\tdef x do", "\t\t:ok", "\tend", "end"]
    four_spaces = ["defmodule A do", "    def x do", "        :ok", "    end", "end"]

    assert Folding.fold_to_level(tabbed, 2) == MapSet.new([2])
    assert Folding.fold_to_level(tabbed, 3) == MapSet.new()
    assert Folding.fold_to_level(four_spaces, 2) == MapSet.new([2])
  end

  test "fold header discovery scales linearly across a large document" do
    lines =
      1..10_000
      |> Enum.flat_map(fn n -> ["def item_#{n} do", "  :ok", "end"] end)

    {microseconds, folds} = :timer.tc(fn -> Folding.fold_to_level(lines, 1) end)
    assert MapSet.size(folds) == 10_000
    assert microseconds < 1_000_000
  end

  test "fold projection stays linear across a large document" do
    lines =
      1..10_000
      |> Enum.flat_map(fn n -> ["def item_#{n} do", "  :ok", "end"] end)

    folds = Folding.fold_to_level(lines, 1)
    {microseconds, projection} = :timer.tc(fn -> Folding.projection(lines, folds) end)

    assert length(projection) == 20_000
    assert microseconds < 250_000
  end

  test "navigation expands containing folds and line-count edits clear them" do
    assert Folding.expand_to_line(@lines, MapSet.new([1]), 3) == MapSet.new()
    assert Folding.reconcile_after_edit(MapSet.new([1]), @lines, @lines) == MapSet.new([1])

    assert Folding.reconcile_after_edit(MapSet.new([1]), @lines, @lines ++ ["new"]) ==
             MapSet.new()
  end

  test "TextField actions and source/display mapping consume fold state" do
    frame = Frame.new(%{pin: {0, 0}, size: {500, 300}})

    state = %State{
      id: :editor,
      frame: frame,
      lines: @lines,
      folds: MapSet.new(),
      wrap_mode: :none,
      scroll: ScrollState.new(frame),
      font: %{size: 16}
    }

    assert {:event, {:folds_changed, :editor, [1]}, folded} =
             Reducer.process_action(state, {:toggle_fold, 1})

    assert Renderer.source_to_display_cursor(folded, {5, 1}) == {3, 1}
    assert Renderer.display_to_source_line(folded, 2) == 1
    assert Renderer.display_to_source_line(folded, 3) == 5

    assert {:event, {:folds_changed, :editor, []}, unfolded} =
             Reducer.process_action(folded, :unfold_all)

    assert unfolded.folds == MapSet.new()

    assert {:noop, ^unfolded} = Reducer.process_action(unfolded, {:toggle_fold, 6})
  end

  test "fold summary rows participate in scroll height and unfolding restores the full extent" do
    frame = Frame.new(%{pin: {0, 0}, size: {500, 40}})

    state =
      State.new(%{
        id: :editor,
        frame: frame,
        initial_text: Enum.join(@lines, "\n"),
        wrap_mode: :none,
        tab_width: 2,
        font: %{
          name: :ibm_plex_mono,
          size: 16,
          path: Path.expand("../../assets/fonts/IBMPlexMono-Regular.ttf", __DIR__)
        }
      })

    assert {:event, _event, folded} = Reducer.process_action(state, {:toggle_fold, 1})
    folded = Reducer.update_scroll_content_size(folded)

    # Header + synthetic summary + the two lines after the folded region.
    assert folded.scroll.content_height == 4 * State.line_height(folded) + 8

    assert {:event, _event, unfolded} = Reducer.process_action(folded, :unfold_all)
    unfolded = Reducer.update_scroll_content_size(unfolded)

    assert unfolded.scroll.content_height == length(@lines) * State.line_height(unfolded) + 8
  end

  test "fold marker and hit row follow wrapped display rows" do
    lines = [
      String.duplicate("a long wrapped prefix ", 10),
      "def nested do",
      "  :ok",
      "end"
    ]

    state =
      State.new(%{
        id: :editor,
        frame: Frame.new(%{pin: {0, 0}, size: {260, 180}}),
        initial_text: Enum.join(lines, "\n"),
        wrap_mode: :word,
        show_line_numbers: true,
        font: %{
          name: :ibm_plex_mono,
          size: 16,
          path: Path.expand("../../assets/fonts/IBMPlexMono-Regular.ttf", __DIR__)
        }
      })
      |> Map.put(:fold_hover_line, 2)
      |> Renderer.prepare_display_cache()

    display_row =
      Enum.find(1..length(state.display_lines), fn row ->
        Renderer.display_to_source_line(state, row) == 2
      end)

    assert display_row > 2
    assert Renderer.display_to_source_line(state, display_row) == 2

    graph = Renderer.initial_render(Graph.build(), state)
    [triangle] = Graph.get(graph, {:fold_toggle, 2})
    {{_x1, y1}, {_x2, y2}, {_x3, y3}} = Scenic.Primitive.get(triangle)
    # The open (downward) triangle's first two points sit two pixels above its
    # anchor. Recover that anchor and prove it uses the wrapped display row.
    triangle_anchor_y = (y1 + y2) / 2 + 2
    expected_anchor_y = display_row * State.line_height(state) - state.font.size * 0.35

    assert y3 > triangle_anchor_y
    assert_in_delta triangle_anchor_y, expected_anchor_y, 0.01
  end

  test "line-number context menu is layered over both panes and opens its select on demand" do
    menu_theme = %{
      dropdown_bg: {31, 32, 33},
      dropdown_border: {41, 42, 43},
      item_text_color: {51, 52, 53},
      item_hover_bg: {61, 62, 63},
      item_hover_text_color: {71, 72, 73},
      font: :ibm_plex_mono,
      dropdown_font_size: 13,
      dropdown_item_height: 28
    }

    state =
      State.new(%{
        id: :editor,
        frame: Frame.new(%{pin: {0, 0}, size: {500, 300}}),
        initial_text: Enum.join(@lines, "\n"),
        show_line_numbers: true,
        fold_level: 2,
        gutter_menu_theme: menu_theme,
        font: %{
          name: :ibm_plex_mono,
          size: 16,
          path: Path.expand("../../assets/fonts/IBMPlexMono-Regular.ttf", __DIR__)
        }
      })
      |> Map.put(:gutter_menu, %{
        x: 24,
        y: 30,
        hovered: :gutter_clear_folds,
        hovered_option: nil,
        select_expanded?: false
      })

    bounds = Renderer.gutter_menu_bounds(state)
    assert bounds.x == state.line_number_width
    assert bounds.y == 30

    graph = Renderer.initial_render(Graph.build(), state)
    assert Graph.get!(graph, :gutter_context_menu_gutter)
    assert Graph.get!(graph, :gutter_context_menu_content)

    assert Scenic.Primitive.get_style(hd(Graph.get(graph, :dropdown_bg)), :fill) ==
             {:color, {:color_rgba, {31, 32, 33, 255}}}

    clear_bg = hd(Graph.get(graph, {:item_bg, :gutter_clear_folds}))
    clear_text = hd(Graph.get(graph, {:item_text, :gutter_clear_folds}))

    assert Scenic.Primitive.get_style(clear_bg, :fill) ==
             {:color, {:color_rgba, {61, 62, 63, 255}}}

    assert Scenic.Primitive.get_style(clear_text, :fill) ==
             {:color, {:color_rgba, {71, 72, 73, 255}}}

    assert Scenic.Primitive.get_style(clear_text, :font_size) == 13
    assert Graph.get(graph, {:select_option, :gutter_fold_level, 1}) == []

    expanded = put_in(state.gutter_menu.select_expanded?, true)
    expanded_graph = Renderer.initial_render(Graph.build(), expanded)
    assert Graph.get(expanded_graph, {:select_option, :gutter_fold_level, 1}) != []
    assert Graph.get(expanded_graph, {:select_option, :gutter_fold_level, 5}) != []
    assert Renderer.gutter_menu_bounds(state).width == 240
    assert Renderer.gutter_menu_bounds(state).x >= state.line_number_width
    assert clear_text.data == "Clear All Folds"

    assert {:event, _event, folded} = Reducer.process_action(state, {:fold_to_level, 1})
    assert folded.fold_level == 1
  end
end
