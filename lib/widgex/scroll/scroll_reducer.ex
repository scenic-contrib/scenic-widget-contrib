defmodule Widgex.Scroll.ScrollReducer do
  @moduledoc """
  Pure scroll calculation functions.

  All functions are pure - they take scroll state + input and return updated scroll state.
  No side effects or mutations.

  ## Example

      def process_input(state, {:cursor_scroll, {_dx, dy, _x, _y}}) do
        new_scroll = ScrollReducer.handle_wheel(state.scroll, dy)
        {:noop, %{state | scroll: new_scroll}}
      end
  """

  alias Widgex.Scroll.ScrollState

  @doc """
  Handle mouse wheel/trackpad scroll input.

  The delta is typically from Scenic's `:cursor_scroll` event.
  Positive delta = scroll down/right, negative = scroll up/left.

  Returns updated scroll state with visibility toggled on.
  """
  @spec handle_wheel(ScrollState.t(), number()) :: ScrollState.t()
  def handle_wheel(%ScrollState{} = scroll, delta_y) do
    scroll
    |> scroll_by(0, delta_y * scroll.scroll_speed)
    |> show_scrollbars()
  end

  @doc """
  Handle horizontal wheel scroll (shift+scroll or horizontal trackpad).
  """
  @spec handle_wheel_x(ScrollState.t(), number()) :: ScrollState.t()
  def handle_wheel_x(%ScrollState{} = scroll, delta_x) do
    scroll
    |> scroll_by(delta_x * scroll.scroll_speed, 0)
    |> show_scrollbars()
  end

  @doc """
  Handle both axes at once (for 2D trackpad scrolling).
  """
  @spec handle_wheel_2d(ScrollState.t(), number(), number()) :: ScrollState.t()
  def handle_wheel_2d(%ScrollState{} = scroll, delta_x, delta_y) do
    scroll
    |> scroll_by(delta_x * scroll.scroll_speed, delta_y * scroll.scroll_speed)
    |> show_scrollbars()
  end

  @doc """
  Smart scroll handling that respects shift_held state.

  When shift is held and direction supports horizontal scrolling,
  vertical scroll input is converted to horizontal scrolling.
  """
  @spec handle_wheel_smart(ScrollState.t(), number(), number()) :: ScrollState.t()
  def handle_wheel_smart(%ScrollState{shift_held: true, direction: dir} = scroll, delta_x, delta_y)
      when dir in [:horizontal, :both] do
    # Shift held - swap axes (vertical becomes horizontal)
    scroll_amount = (delta_y + delta_x) * scroll.scroll_speed
    scroll
    |> scroll_by(scroll_amount, 0)
    |> show_scrollbars()
  end

  def handle_wheel_smart(%ScrollState{} = scroll, delta_x, delta_y) do
    # Normal scrolling
    handle_wheel_2d(scroll, delta_x, delta_y)
  end

  @doc """
  Set the shift key held state.
  Call this when shift key is pressed/released.
  """
  @spec set_shift_held(ScrollState.t(), boolean()) :: ScrollState.t()
  def set_shift_held(%ScrollState{} = scroll, held) do
    %{scroll | shift_held: held}
  end

  @doc """
  Scroll by a specific pixel amount.

  Respects the scroll direction setting - if direction is `:vertical`,
  horizontal scrolling is ignored, and vice versa.
  """
  @spec scroll_by(ScrollState.t(), number(), number()) :: ScrollState.t()
  def scroll_by(%ScrollState{direction: :vertical} = scroll, _dx, dy) do
    new_offset_y = scroll.offset_y + dy
    %{scroll | offset_y: new_offset_y} |> ScrollState.clamp()
  end

  def scroll_by(%ScrollState{direction: :horizontal} = scroll, dx, _dy) do
    new_offset_x = scroll.offset_x + dx
    %{scroll | offset_x: new_offset_x} |> ScrollState.clamp()
  end

  def scroll_by(%ScrollState{direction: :both} = scroll, dx, dy) do
    %{scroll |
      offset_x: scroll.offset_x + dx,
      offset_y: scroll.offset_y + dy
    }
    |> ScrollState.clamp()
  end

  @doc """
  Scroll to make a rectangle visible within the viewport.

  Useful for ensuring a selected item, cursor, or element is visible.
  The margin adds extra padding around the target.

  ## Parameters

    * `scroll` - Current scroll state
    * `rect` - `{x, y, width, height}` of the target rectangle (in content coordinates)
    * `margin` - Extra padding around the target (default: 0)

  ## Example

      # Ensure cursor line is visible with 20px padding
      scroll_to_show(scroll, {0, cursor_y, viewport_width, line_height}, 20)
  """
  @spec scroll_to_show(ScrollState.t(), {number(), number(), number(), number()}, number()) ::
          ScrollState.t()
  def scroll_to_show(%ScrollState{} = scroll, {x, y, w, h}, margin \\ 0) do
    scroll
    |> scroll_to_show_x(x, w, margin)
    |> scroll_to_show_y(y, h, margin)
  end

  @doc """
  Scroll to a specific offset position.
  """
  @spec scroll_to(ScrollState.t(), number(), number()) :: ScrollState.t()
  def scroll_to(%ScrollState{} = scroll, x, y) do
    %{scroll | offset_x: x, offset_y: y}
    |> ScrollState.clamp()
  end

  @doc """
  Scroll to the top (y = 0).
  """
  @spec scroll_to_top(ScrollState.t()) :: ScrollState.t()
  def scroll_to_top(%ScrollState{} = scroll) do
    %{scroll | offset_y: 0}
  end

  @doc """
  Scroll to the bottom (y = max).
  """
  @spec scroll_to_bottom(ScrollState.t()) :: ScrollState.t()
  def scroll_to_bottom(%ScrollState{} = scroll) do
    %{scroll | offset_y: ScrollState.max_offset_y(scroll)}
  end

  @doc """
  Scroll to the left (x = 0).
  """
  @spec scroll_to_left(ScrollState.t()) :: ScrollState.t()
  def scroll_to_left(%ScrollState{} = scroll) do
    %{scroll | offset_x: 0}
  end

  @doc """
  Scroll to the right (x = max).
  """
  @spec scroll_to_right(ScrollState.t()) :: ScrollState.t()
  def scroll_to_right(%ScrollState{} = scroll) do
    %{scroll | offset_x: ScrollState.max_offset_x(scroll)}
  end

  @doc """
  Check if scroll state has changed (for determining if re-render needed).
  """
  @spec changed?(ScrollState.t(), ScrollState.t()) :: boolean()
  def changed?(%ScrollState{} = old, %ScrollState{} = new) do
    old.offset_x != new.offset_x ||
      old.offset_y != new.offset_y ||
      old.scrollbar_visible != new.scrollbar_visible ||
      old.scrollbar_opacity != new.scrollbar_opacity
  end

  @doc """
  Check if only the scroll offset changed (not visibility).
  """
  @spec offset_changed?(ScrollState.t(), ScrollState.t()) :: boolean()
  def offset_changed?(%ScrollState{} = old, %ScrollState{} = new) do
    old.offset_x != new.offset_x || old.offset_y != new.offset_y
  end

  @doc """
  Show scrollbars (set visible, full opacity).
  """
  @spec show_scrollbars(ScrollState.t()) :: ScrollState.t()
  def show_scrollbars(%ScrollState{} = scroll) do
    %{scroll | scrollbar_visible: true, scrollbar_opacity: 255}
  end

  @doc """
  Hide scrollbars (set invisible, zero opacity).
  """
  @spec hide_scrollbars(ScrollState.t()) :: ScrollState.t()
  def hide_scrollbars(%ScrollState{} = scroll) do
    %{scroll | scrollbar_visible: false, scrollbar_opacity: 0}
  end

  @doc """
  Set scrollbar opacity for fade animation (0-255).
  """
  @spec set_scrollbar_opacity(ScrollState.t(), integer()) :: ScrollState.t()
  def set_scrollbar_opacity(%ScrollState{} = scroll, opacity) when opacity in 0..255 do
    visible = opacity > 0
    %{scroll | scrollbar_opacity: opacity, scrollbar_visible: visible}
  end

  @doc """
  Normalize various Scenic scroll input formats.

  Scenic can send scroll events in different formats depending on the driver.
  This function normalizes them to `{delta_x, delta_y}`.
  """
  @spec normalize_input(term()) :: {number(), number()} | nil
  def normalize_input({:cursor_scroll, {dx, dy, _x, _y}}), do: {dx, dy}
  def normalize_input({:cursor_scroll, {{dx, dy}, _coords}}), do: {dx, dy}
  def normalize_input({:cursor_scroll, {dx, dy}}), do: {dx, dy}
  def normalize_input(_), do: nil

  # Scroll to make X coordinate visible
  defp scroll_to_show_x(%ScrollState{direction: :vertical} = scroll, _x, _w, _margin) do
    # Vertical-only scrolling, ignore X
    scroll
  end

  defp scroll_to_show_x(%ScrollState{} = scroll, x, w, margin) do
    left = x - margin
    right = x + w + margin

    cond do
      # Target is to the left of visible area
      left < scroll.offset_x ->
        %{scroll | offset_x: left} |> ScrollState.clamp()

      # Target is to the right of visible area
      right > scroll.offset_x + scroll.viewport_width ->
        new_offset = right - scroll.viewport_width
        %{scroll | offset_x: new_offset} |> ScrollState.clamp()

      # Already visible
      true ->
        scroll
    end
  end

  # Scroll to make Y coordinate visible
  defp scroll_to_show_y(%ScrollState{direction: :horizontal} = scroll, _y, _h, _margin) do
    # Horizontal-only scrolling, ignore Y
    scroll
  end

  defp scroll_to_show_y(%ScrollState{} = scroll, y, h, margin) do
    top = y - margin
    bottom = y + h + margin

    cond do
      # Target is above visible area
      top < scroll.offset_y ->
        %{scroll | offset_y: top} |> ScrollState.clamp()

      # Target is below visible area
      bottom > scroll.offset_y + scroll.viewport_height ->
        new_offset = bottom - scroll.viewport_height
        %{scroll | offset_y: new_offset} |> ScrollState.clamp()

      # Already visible
      true ->
        scroll
    end
  end
end
