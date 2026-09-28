defmodule Widgex.Scroll.ScrollController do
  @moduledoc """
  Shared, pure scrollbar interaction math.

  Hosts retain pointer capture while `drag_offset/5` maps pointer travel over
  the thumb's available travel—not the full track—to content offset.
  """

  @minimum_thumb 20

  @spec thumb_length(number(), number(), number()) :: number()
  def thumb_length(track_length, content_size, viewport_size)
      when track_length > 0 and content_size > viewport_size do
    min(track_length, max(track_length * viewport_size / content_size, @minimum_thumb))
  end

  def thumb_length(track_length, _content_size, _viewport_size), do: max(track_length, 0)

  @spec drag_offset(number(), number(), number(), number(), number()) :: number()
  def drag_offset(start_offset, pointer_delta, track_length, thumb_length, max_offset) do
    travel = max(track_length - thumb_length, 0)

    if travel == 0 or max_offset <= 0 do
      0
    else
      start_offset
      |> Kernel.+(pointer_delta / travel * max_offset)
      |> max(0)
      |> min(max_offset)
    end
  end

  @doc """
  Pages one viewport toward a click in the unoccupied scrollbar track.

  A click inside the thumb is a no-op; the thumb primitive normally wins that
  hit test, but keeping the math defensive makes it safe for every host.
  """
  @spec page_offset(number(), number(), number(), number(), number(), number()) :: number()
  def page_offset(current_offset, pointer, thumb_start, thumb_length, viewport_size, max_offset) do
    next_offset =
      cond do
        pointer < thumb_start -> current_offset - viewport_size
        pointer > thumb_start + thumb_length -> current_offset + viewport_size
        true -> current_offset
      end

    next_offset
    |> max(0)
    |> min(max_offset)
  end
end
