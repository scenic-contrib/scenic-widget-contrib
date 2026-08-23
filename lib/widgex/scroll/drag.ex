defmodule Widgex.Scroll.Drag do
  @moduledoc """
  Dragging a scrollbar — the part of scrolling every host was writing for
  itself.

  `Widgex.Scrollable` hands a component its scroll state, its wheel handling
  and its scrollbars. It never handed it the ability to *drag* one, which is
  the first thing a person reaches for once there is more content than
  viewport. So each host wrote its own, around the one genuinely shared piece
  (`ScrollController.drag_offset/5`):

    * `SideNav` grew `scrollbar_drag_geometry/3` and `horizontal_track_length/1`;
    * `TextField` grew `State.scrollbar_track_info/2` and a `drag_offset/5`
      wrapper of its own;
    * `SearchPane` grew the three `scrollbar_drag*` state fields and **no code
      at all**, so its bar could be looked at and not moved. Its clicks landed
      in the catch-all clause and were dropped.

  What is host-specific is only the input routing — Scenic delivers positional
  input to the scene that drew the primitive, so the `handle_input` clauses
  have to live in the component. Everything under those clauses is the same
  everywhere, and is here.

  ## Using it

  The scrollbar primitives already ask for input (`ScrollRenderer` gives the
  track and thumb `input: [:cursor_button, :cursor_pos]`), and they are keyed
  `{:scrollbar_y_thumb, group_id}` and so on, so a host routes on the id:

      def handle_input({:cursor_button, {:btn_left, 1, _, at}}, {:scrollbar_y_thumb, _}, scene) do
        :ok = capture_input(scene, [:cursor_pos, :cursor_button])
        {:noreply, redraw(scene, Drag.start(scene.assigns.state, :y, at))}
      end

      def handle_input({:cursor_pos, at}, _ctx, scene) when Drag.dragging?(scene) do
        {:noreply, redraw(scene, Drag.move(scene.assigns.state, bar_frame, at))}
      end

  Works on any state with `:scroll`, `:scrollbar_drag`, `:scrollbar_drag_start`
  and `:scrollbar_drag_offset`. The FRAME is passed in rather than read off the
  state, because it is not always the component's own: `SideNav` draws its bars
  in its whole frame, `SearchPane` draws them in the scrolling body below its
  header, and a track measured against the wrong one moves the content at the
  wrong speed.
  """

  alias Widgex.Scroll.{ScrollController, ScrollState}

  # ScrollRenderer's own layout, and the reason these are here rather than
  # guessed at by each caller: the bar is inset by @padding at both ends, and
  # the horizontal track stops short when the vertical bar is occupying the
  # corner.
  @padding 2
  @bar_width 12

  @doc "Is a scrollbar drag in progress?"
  def dragging?(%{scrollbar_drag: axis}), do: axis in [:x, :y]
  def dragging?(_state), do: false

  @doc "Which axis is being dragged, or `nil`."
  def axis(%{scrollbar_drag: axis}), do: axis

  @doc """
  Begin a drag on `axis`, from wherever the pointer went down.

  The offset is remembered as it was at the start, so the whole drag is
  measured from one place — accumulating deltas frame by frame drifts.
  """
  def start(state, axis, coords) when axis in [:x, :y] do
    %{
      state
      | scrollbar_drag: axis,
        scrollbar_drag_start: coords,
        scrollbar_drag_offset: offset(state.scroll, axis)
    }
  end

  @doc "The button came up: the drag is over."
  def stop(state) do
    %{state | scrollbar_drag: nil, scrollbar_drag_start: nil, scrollbar_drag_offset: nil}
  end

  @doc """
  The pointer moved mid-drag — where the content sits now.

  Only the DISTANCE from where the drag began is used, so it does not matter
  which coordinate space the host's input arrives in.
  """
  def move(%{scrollbar_drag: axis} = state, frame, {x, y}) when axis in [:x, :y] do
    {start_x, start_y} = state.scrollbar_drag_start
    delta = if axis == :x, do: x - start_x, else: y - start_y

    track = track_length(frame, state.scroll, axis)

    thumb =
      ScrollController.thumb_length(track, content(state.scroll, axis), viewport(state.scroll, axis))

    put_offset(
      state,
      axis,
      ScrollController.drag_offset(
        state.scrollbar_drag_offset,
        delta,
        track,
        thumb,
        max_offset(state.scroll, axis)
      )
    )
  end

  @doc """
  A click on the TRACK rather than the thumb: a page in that direction.

  `pointer` is measured along the track, from its start.
  """
  def page(state, frame, axis, pointer) when axis in [:x, :y] do
    track = track_length(frame, state.scroll, axis)

    thumb =
      ScrollController.thumb_length(track, content(state.scroll, axis), viewport(state.scroll, axis))

    current = offset(state.scroll, axis)
    max = max_offset(state.scroll, axis)
    thumb_start = if max > 0, do: current / max * max(track - thumb, 0), else: 0

    put_offset(
      state,
      axis,
      ScrollController.page_offset(
        current,
        pointer,
        thumb_start,
        thumb,
        viewport(state.scroll, axis),
        max
      )
    )
  end

  @doc "How long the track is, in the frame the scrollbars were drawn in."
  def track_length(frame, _scroll, :y), do: frame.size.height - 2 * @padding

  def track_length(frame, scroll, :x) do
    if ScrollState.scrollable_y?(scroll),
      do: frame.size.width - @bar_width - 3 * @padding,
      else: frame.size.width - 2 * @padding
  end

  defp offset(scroll, :x), do: scroll.offset_x
  defp offset(scroll, :y), do: scroll.offset_y

  defp content(scroll, :x), do: scroll.content_width
  defp content(scroll, :y), do: scroll.content_height

  defp viewport(scroll, :x), do: scroll.viewport_width
  defp viewport(scroll, :y), do: scroll.viewport_height

  defp max_offset(scroll, :x), do: ScrollState.max_offset_x(scroll)
  defp max_offset(scroll, :y), do: ScrollState.max_offset_y(scroll)

  # Dragging a bar is also the clearest possible statement that you want to
  # see it, so it stays up while it is being used.
  defp put_offset(state, axis, offset) do
    scroll = %{state.scroll | scrollbar_visible: true, scrollbar_opacity: 255}
    scroll = if axis == :x, do: %{scroll | offset_x: offset}, else: %{scroll | offset_y: offset}
    %{state | scroll: scroll}
  end
end
