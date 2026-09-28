defmodule ScenicWidgets.TextField.MatchingBraceTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.MatchingBrace
  alias ScenicWidgets.TextField.{Renderer, State}
  alias Scenic.{Graph, Primitive}
  alias Widgex.Frame

  test "matches nested braces from either side" do
    lines = ["call(foo[bar])"]
    assert MatchingBrace.find(lines, {1, 5}) == {{1, 5}, {1, 14}}
    assert MatchingBrace.find(lines, {1, 15}) == {{1, 14}, {1, 5}}
    assert MatchingBrace.find(lines, {1, 9}) == {{1, 9}, {1, 13}}
  end

  test "matches across lines" do
    assert MatchingBrace.find(["fn -> {", "  value", "}"], {1, 7}) == {{1, 7}, {3, 1}}
  end

  test "returns nil for an unmatched brace or ordinary text" do
    assert MatchingBrace.find(["(oops"], {1, 1}) == nil
    assert MatchingBrace.find(["plain"], {1, 3}) == nil
  end

  test "renderer keeps stable brace outlines and hides them when disabled" do
    state =
      State.new(%{
        frame: Frame.new(pin: {0, 0}, size: {400, 200}),
        initial_text: "call(foo)",
        initial_cursor: {1, 5},
        show_matching_brace: true,
        font: %{
          name: :ibm_plex_mono,
          size: 16,
          path: Path.expand("../../assets/fonts/IBMPlexMono-Regular.ttf", __DIR__)
        }
      })

    graph = Renderer.initial_render(Graph.build(), state)
    refute Primitive.get_style(Graph.get!(graph, :matching_brace_current), :hidden)
    refute Primitive.get_style(Graph.get!(graph, :matching_brace_partner), :hidden)

    hidden = Renderer.update_render(graph, state, %{state | show_matching_brace: false})
    assert Primitive.get_style(Graph.get!(hidden, :matching_brace_current), :hidden)
    assert Primitive.get_style(Graph.get!(hidden, :matching_brace_partner), :hidden)
  end

  test "current-line and current-column guides are independently configurable" do
    state =
      State.new(%{
        frame: Frame.new(pin: {0, 0}, size: {400, 200}),
        initial_text: "alpha\nbeta",
        initial_cursor: {2, 3},
        highlight_current_line: true,
        highlight_current_column: false,
        font: %{
          name: :ibm_plex_mono,
          size: 16,
          path: Path.expand("../../assets/fonts/IBMPlexMono-Regular.ttf", __DIR__)
        }
      })

    graph = Renderer.initial_render(Graph.build(), state)
    refute Primitive.get_style(Graph.get!(graph, :current_line_highlight), :hidden)
    assert Primitive.get_style(Graph.get!(graph, :current_column_highlight), :hidden)
  end
end
