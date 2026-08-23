defmodule Widgex.Scroll.ScrollState do
  @moduledoc """
  Embeddable scroll state struct for components.

  Contains all information needed to track scroll position, content bounds,
  and scrollbar visibility. Designed to be embedded in component state structs.

  ## Example

      defmodule MyComponent.State do
        alias Widgex.Scroll.ScrollState

        defstruct [:frame, :items, :scroll]

        def new(%{frame: frame, items: items}) do
          content_height = length(items) * 60

          %__MODULE__{
            frame: frame,
            items: items,
            scroll: ScrollState.new(frame, content_height: content_height)
          }
        end
      end
  """

  alias Widgex.Frame

  @default_scroll_speed 40
  @scrollbar_fade_delay 1500

  defstruct [
    # Current scroll position (positive values = scrolled down/right)
    offset_x: 0,
    offset_y: 0,
    # Content dimensions (the full size of scrollable content)
    content_width: 0,
    content_height: 0,
    # Viewport dimensions (visible area)
    viewport_width: 0,
    viewport_height: 0,
    # Scroll behavior
    direction: :vertical,
    scroll_speed: @default_scroll_speed,
    # Scrollbar visibility
    scrollbar_visible: false,
    scrollbar_opacity: 0,
    scrollbar_fade_timer: nil,
    # Modifier key tracking for Shift+scroll horizontal scrolling
    shift_held: false
  ]

  @type direction :: :vertical | :horizontal | :both
  @type t :: %__MODULE__{
          offset_x: number(),
          offset_y: number(),
          content_width: number(),
          content_height: number(),
          viewport_width: number(),
          viewport_height: number(),
          direction: direction(),
          scroll_speed: number(),
          scrollbar_visible: boolean(),
          scrollbar_opacity: number(),
          scrollbar_fade_timer: reference() | nil
        }

  @doc """
  Create a new ScrollState from a frame and options.

  ## Options

    * `:content_width` - Width of scrollable content (default: frame width)
    * `:content_height` - Height of scrollable content (default: frame height)
    * `:direction` - `:vertical`, `:horizontal`, or `:both` (default: `:vertical`)
    * `:scroll_speed` - Pixels per scroll tick (default: #{@default_scroll_speed})

  ## Examples

      # Vertical scrolling with content taller than viewport
      ScrollState.new(frame, content_height: 1000)

      # Horizontal scrolling
      ScrollState.new(frame, content_width: 2000, direction: :horizontal)

      # Both directions
      ScrollState.new(frame, content_width: 2000, content_height: 1000, direction: :both)
  """
  @spec new(Frame.t(), keyword()) :: t()
  def new(%Frame{} = frame, opts \\ []) do
    {viewport_width, viewport_height} = frame.size.box

    content_width = Keyword.get(opts, :content_width, viewport_width)
    content_height = Keyword.get(opts, :content_height, viewport_height)
    direction = Keyword.get(opts, :direction, :vertical)

    # Check if content is scrollable and if we should show scrollbars immediately
    initially_visible = Keyword.get(opts, :initially_visible, false)
    is_scrollable = case direction do
      :vertical -> content_height > viewport_height
      :horizontal -> content_width > viewport_width
      :both -> content_height > viewport_height or content_width > viewport_width
    end

    {visible, opacity} = if initially_visible and is_scrollable do
      {true, 255}
    else
      {false, 0}
    end

    %__MODULE__{
      offset_x: 0,
      offset_y: 0,
      content_width: content_width,
      content_height: content_height,
      viewport_width: viewport_width,
      viewport_height: viewport_height,
      direction: direction,
      scroll_speed: Keyword.get(opts, :scroll_speed, @default_scroll_speed),
      scrollbar_visible: visible,
      scrollbar_opacity: opacity,
      scrollbar_fade_timer: nil
    }
  end

  @doc """
  Update the content size. Clamps scroll offset if content shrinks.

  Called when content changes (items added/removed, text reflowed, etc.)
  """
  @spec update_content_size(t(), number(), number()) :: t()
  def update_content_size(%__MODULE__{} = scroll, width, height) do
    %{scroll | content_width: width, content_height: height}
    |> clamp()
  end

  @doc """
  Update viewport size (when frame resizes).
  """
  @spec update_viewport_size(t(), Frame.t()) :: t()
  def update_viewport_size(%__MODULE__{} = scroll, %Frame{} = frame) do
    {width, height} = frame.size.box

    %{scroll | viewport_width: width, viewport_height: height}
    |> clamp()
  end

  @doc """
  Maximum scroll offset for X axis.
  Returns 0 if content fits within viewport.
  """
  @spec max_offset_x(t()) :: number()
  def max_offset_x(%__MODULE__{content_width: cw, viewport_width: vw}) do
    max(0, cw - vw)
  end

  @doc """
  Maximum scroll offset for Y axis.
  Returns 0 if content fits within viewport.
  """
  @spec max_offset_y(t()) :: number()
  def max_offset_y(%__MODULE__{content_height: ch, viewport_height: vh}) do
    max(0, ch - vh)
  end

  @doc """
  Get the translate offset for rendering (negated scroll position).

  Use this value with Scenic's `translate:` option.
  """
  @spec translate_offset(t()) :: {number(), number()}
  def translate_offset(%__MODULE__{offset_x: ox, offset_y: oy}) do
    {-ox, -oy}
  end

  @doc """
  Check if scrolling is needed (content larger than viewport).
  """
  @spec scrollable?(t()) :: boolean()
  def scrollable?(%__MODULE__{} = scroll) do
    scrollable_x?(scroll) || scrollable_y?(scroll)
  end

  @doc """
  Check if horizontal scrolling is needed.
  """
  @spec scrollable_x?(t()) :: boolean()
  def scrollable_x?(%__MODULE__{content_width: cw, viewport_width: vw, direction: dir}) do
    dir in [:horizontal, :both] && cw > vw
  end

  @doc """
  Check if vertical scrolling is needed.
  """
  @spec scrollable_y?(t()) :: boolean()
  def scrollable_y?(%__MODULE__{content_height: ch, viewport_height: vh, direction: dir}) do
    dir in [:vertical, :both] && ch > vh
  end

  @doc """
  Ensure scroll offset is within valid bounds.
  """
  @spec clamp(t()) :: t()
  def clamp(%__MODULE__{} = scroll) do
    %{scroll |
      offset_x: clamp_value(scroll.offset_x, 0, max_offset_x(scroll)),
      offset_y: clamp_value(scroll.offset_y, 0, max_offset_y(scroll))
    }
  end

  @doc """
  Calculate scrollbar thumb bounds for rendering.

  Returns `{position, size}` where:
  - `position` is the offset from track start
  - `size` is the thumb length

  ## Example

      {thumb_y, thumb_height} = ScrollState.scrollbar_thumb(:y, scroll)
  """
  @spec scrollbar_thumb(t(), :x | :y) :: {number(), number()}
  def scrollbar_thumb(%__MODULE__{} = scroll, :x) do
    calculate_thumb(
      scroll.offset_x,
      scroll.content_width,
      scroll.viewport_width
    )
  end

  def scrollbar_thumb(%__MODULE__{} = scroll, :y) do
    calculate_thumb(
      scroll.offset_y,
      scroll.content_height,
      scroll.viewport_height
    )
  end

  @doc """
  Get the scrollbar fade delay in milliseconds.
  """
  @spec fade_delay() :: non_neg_integer()
  def fade_delay, do: @scrollbar_fade_delay

  # Calculate thumb position and size
  defp calculate_thumb(offset, content_size, viewport_size) when content_size > viewport_size do
    # Thumb size is proportional to visible area
    thumb_size = viewport_size * (viewport_size / content_size)
    # Minimum thumb size for usability
    thumb_size = max(thumb_size, 30)

    # Position proportional to scroll offset
    max_offset = content_size - viewport_size
    track_length = viewport_size - thumb_size
    thumb_pos = if max_offset > 0, do: (offset / max_offset) * track_length, else: 0

    {thumb_pos, thumb_size}
  end

  defp calculate_thumb(_offset, _content_size, viewport_size) do
    # Content fits in viewport, no scrollbar needed
    {0, viewport_size}
  end

  defp clamp_value(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end
end
