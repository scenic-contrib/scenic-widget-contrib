defmodule ScenicWidgets.FloatingPanel do
  @moduledoc """
  Shared layout and chrome for small overlay panels anchored within a frame.

  A floating panel does not own its contents. Components such as find/replace,
  command palettes, diagnostics and inspectors use `frame/2` to choose stable
  overlay geometry and `add_card/3` to draw the common elevated surface.

  Keeping anchoring here prevents host scenes from accumulating one-off
  top-right coordinate arithmetic, and ensures floating UI never participates
  in the underlying document layout.
  """

  alias Scenic.Graph
  alias Scenic.Primitives
  alias Widgex.Frame

  @type placement :: :top_left | :top_right | :bottom_left | :bottom_right

  @doc "Returns a bounded floating frame inside `container`."
  @spec frame(Frame.t(), keyword()) :: Frame.t()
  def frame(%Frame{} = container, opts) do
    {requested_width, requested_height} = Keyword.fetch!(opts, :size)
    margin = Keyword.get(opts, :margin, 12)
    placement = Keyword.get(opts, :placement, :top_right)
    width = min(requested_width, max(container.size.width - margin * 2, 1))
    height = min(requested_height, max(container.size.height - margin * 2, 1))

    x =
      case placement do
        side when side in [:top_right, :bottom_right] ->
          container.pin.x + container.size.width - width - margin

        _ ->
          container.pin.x + margin
      end

    y =
      case placement do
        side when side in [:bottom_left, :bottom_right] ->
          container.pin.y + container.size.height - height - margin

        _ ->
          container.pin.y + margin
      end

    Frame.new(pin: {x, y}, size: {width, height})
  end

  @doc "Returns whether a point lies within a floating frame."
  @spec contains?(Frame.t(), {number(), number()}) :: boolean()
  def contains?(%Frame{} = frame, {x, y}) do
    x >= frame.pin.x and x <= frame.pin.x + frame.size.width and
      y >= frame.pin.y and y <= frame.pin.y + frame.size.height
  end

  @doc "Adds a reusable rounded card, border and subtle drop shadow."
  @spec add_card(Graph.t(), {number(), number()}, keyword()) :: Graph.t()
  def add_card(%Graph{} = graph, {width, height}, opts \\ []) do
    radius = Keyword.get(opts, :radius, 7)
    fill = Keyword.get(opts, :fill, {42, 45, 54})
    border = Keyword.get(opts, :border, {92, 98, 116})
    shadow = Keyword.get(opts, :shadow, {0, 0, 0, 145})

    graph
    |> Primitives.rounded_rectangle({width, height, radius},
      id: Keyword.get(opts, :shadow_id, :floating_panel_shadow),
      fill: shadow,
      translate: {3, 4}
    )
    |> Primitives.rounded_rectangle({width, height, radius},
      id: Keyword.get(opts, :id, :floating_panel),
      fill: fill,
      stroke: {1, border}
    )
  end
end
