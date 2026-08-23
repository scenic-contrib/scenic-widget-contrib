defmodule ScenicWidgets.TextFieldScrollPerformanceTest do
  use ExUnit.Case, async: false

  alias Scenic.Graph
  alias ScenicWidgets.TextField.{Reducer, Renderer, State}
  alias Widgex.Frame

  @scroll_events 1_000

  defp ethics_sized_text do
    paragraph =
      "However, whatsoever perfection is possessed by substance is due to no external cause; " <>
        "wherefore existence must arise solely from its own nature and necessity."

    1..1_200
    |> Enum.map_join("\n", fn line -> "#{line}. #{paragraph}" end)
  end

  defp state(wrap_mode) do
    State.new(%{
      id: :scroll_perf,
      frame: Frame.new(pin: {0, 0}, size: {1100, 720}),
      initial_text: ethics_sized_text(),
      mode: :multi_line,
      wrap_mode: wrap_mode,
      show_line_numbers: true,
      viewport_buffer_lines: 96,
      font: %{
        name: :ibm_plex_mono,
        size: 16,
        path: Path.expand("../assets/fonts/IBMPlexMono-Regular.ttf", __DIR__)
      }
    })
    |> Renderer.prepare_display_cache()
  end

  defp scroll_workload(wrap_mode) do
    initial = state(wrap_mode)
    graph = Renderer.initial_render(Graph.build(), initial)

    {micros, {_graph, _state, rebuilds}} =
      :timer.tc(fn ->
        Enum.reduce(1..@scroll_events, {graph, initial, 0}, fn _, {graph, old_state, rebuilds} ->
          {:noop, new_state} =
            Reducer.process_input(old_state, {:cursor_scroll, {{0, -12}, {500, 300}}})

          graph = Renderer.update_render(graph, old_state, new_state)
          changed = if old_state.render_window == new_state.render_window, do: 0, else: 1
          {graph, new_state, rebuilds + changed}
        end)
      end)

    {micros, rebuilds}
  end

  test "large unwrapped documents retain their render window across wheel events" do
    {micros, rebuilds} = scroll_workload(:none)

    assert rebuilds <= 12
    assert micros < 1_500_000
  end

  test "large word-wrapped documents do not rewrap on every wheel event" do
    {micros, rebuilds} = scroll_workload(:word)

    assert rebuilds <= 24
    assert micros < 3_000_000
  end

  test "wheel scrolling reuses the exact wrapped projection" do
    initial = state(:word)

    final =
      Enum.reduce(1..@scroll_events, initial, fn _, current ->
        {:noop, next} =
          Reducer.process_input(current, {:cursor_scroll, {{0, -12}, {500, 300}}})

        Renderer.prepare_display_cache(next)
      end)

    assert final.display_lines === initial.display_lines
    assert final.display_line_mapping === initial.display_line_mapping
    assert final.display_cache_key === initial.display_cache_key
  end

  test "a buffer switch resets a retained off-screen render window" do
    scrolled =
      state(:word)
      |> Map.put(:scroll, %{state(:word).scroll | offset_y: 12_000})
      |> State.reset_render_window()

    {old_first, _old_last} = scrolled.render_window
    assert old_first > 1

    switched =
      scrolled
      |> Map.put(:scroll, %{scrolled.scroll | offset_y: 0})
      |> State.reset_render_window()

    assert {1, _last} = switched.render_window
    assert {1, _last} = State.visible_display_range(switched, 2_000)
  end
end
