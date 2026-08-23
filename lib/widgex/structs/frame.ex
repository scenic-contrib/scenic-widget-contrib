defmodule Widgex.Frame do
  @moduledoc """
  Represents a rectangular component, bound by a 2D box.

  A `Frame` in Widgex defines the spatial dimensions and location
  of a rectangular area in a 2D space. It is characterized by the
  coordinates of its top-left corner (`pin`) and its size (`size`),
  including the width (x dimension) and height (y dimension).
  """

  alias Widgex.Structs.Coordinates
  alias Widgex.Structs.Dimensions

  defstruct [
    # The Coordinates for the top-left point of this Frame
    pin: nil,
    # How large in {width, height} this Frame is
    size: nil
  ]

  defdelegate v_split(frame, args), to: Widgex.Frame.Utils

  defdelegate h_split(frame), to: Widgex.Frame.Utils
  defdelegate h_split(frame, args), to: Widgex.Frame.Utils

  defdelegate col_split(frame, n), to: Widgex.Frame.Utils

  defdelegate shrink(frame, factor, args), to: Widgex.Frame.Utils

  # Make a new frame the same size as the ViewPort
  def new(%Scenic.ViewPort{size: {vp_width, vp_height}}) do
    # TODO why do we need this +1?? Without it we get a dark strip on the right hand side
    new(%{pin: {0, 0}, size: {vp_width + 1, vp_height}})
  end

  def new(pin: p, size: s) do
    new(%{pin: p, size: s})
  end

  def new(%{pin: %{x: x, y: y}, size: {w, h}}) do
    new(%{pin: {x, y}, size: {w, h}})
  end

  def new(%{pin: {x, y}, size: %{width: w, height: h}}) do
    new(%{pin: {x, y}, size: {w, h}})
  end

  def new(%{pin: %{x: x, y: y}, size: %{width: w, height: h}}) do
    new(%{pin: {x, y}, size: {w, h}})
  end

  def new(%{pin: {x, y}, size: {w, h}}) do
    %__MODULE__{
      pin: Coordinates.new({x, y}),
      size: Dimensions.new({w, h})
    }
  end

  # # return a frame the size of the entire viewport
  # def stack(
  #       %Scenic.ViewPort{} = vp,
  #       # %Scenic.ViewPort{size: {vp_width, vp_height}},
  #       # :full_screen
  #       layout
  #     ) do
  #   IO.puts("DEPRECATED ONLY USED BY QUILLEX #{inspect(layout)}")

  #   [
  #     %__MODULE__{
  #       pin: Coordinates.new({10, 10}),
  #       size: Dimensions.new({100, 100})
  #     }
  #     # new(%{pin: {0, 0}, size: {vp_width, vp_height}})
  #   ]
  # end

  @doc """
  Computes the centroid of the given frame.

  The centroid is calculated as the mid-point of both dimensions of the frame.

  ## Params

  - `frame`: The `Frame` whose centroid is to be computed.

  ## Examples

      iex> alias Widgex.{Frame, Structs.Coordinates, Structs.Dimensions}
      iex> frame = %Frame{pin: %Coordinates{x: 10, y: 10}, size: %Dimensions{width: 100, height: 50}}
      iex> Frame.center(frame)
      %Coordinates{x: 60.0, y: 35.0, point: {60.0, 35.0}}

  """
  def center(%__MODULE__{
        pin: %Coordinates{x: pin_x, y: pin_y},
        size: %Dimensions{width: size_x, height: size_y}
      }) do
    x = pin_x + size_x / 2
    y = pin_y + size_y / 2

    %Coordinates{
      x: x,
      y: y,
      point: {x, y}
    }
  end

  # def center(%{coords: c, dimens: d}) do
  #   Coordinates.new(x: c.x + d.width / 2, y: c.y + d.height / 2)
  # end

  # def center_tuple(%__MODULE__{} = frame) do
  #   Coordinates.point(center(frame))
  # end

  @doc """
  Computes the coordinates of the bottom-left corner of the given frame.

  ## Params

  - `frame`: The `Frame` whose bottom-left corner coordinates are to be computed.

  ## Examples

      iex> alias Widgex.{Frame, Structs.Coordinates, Structs.Dimensions}
      iex> frame = %Frame{pin: %Coordinates{x: 10, y: 10}, size: %Dimensions{width: 100, height: 50}}
      iex> Frame.bottom_left(frame)
      %Coordinates{x: 10, y: 60, point: {10, 60}}

  """
  def top_left(%__MODULE__{pin: %Coordinates{x: tl_x, y: tl_y}}) do
    %Coordinates{
      x: tl_x,
      y: tl_y,
      point: {tl_x, tl_y}
    }
  end

  # @spec bottom_left(t()) :: Coordinates.t()
  def bottom_left(%__MODULE__{pin: %Coordinates{x: tl_x, y: tl_y}, size: %Dimensions{height: h}}) do
    # add the height dimension to the y-coordinate of the pin (top-left corner).
    %Coordinates{
      x: tl_x,
      y: tl_y + h,
      point: {tl_x, tl_y + h}
    }
  end

  def top_right(%__MODULE__{pin: %Coordinates{x: tl_x, y: tl_y}, size: %Dimensions{width: w}}) do
    # Add the width to the x-coordinate of the pin (top-left corner) to get the top-right corner.
    %Coordinates{
      x: tl_x + w,
      y: tl_y,
      point: {tl_x + w, tl_y}
    }
  end

  def bottom_right(%__MODULE__{
        pin: %Coordinates{x: tl_x, y: tl_y},
        size: %Dimensions{width: w, height: h}
      }) do
    # Add the width to the x-coordinate and the height to the y-coordinate of the pin (top-left corner).
    %Coordinates{
      x: tl_x + w,
      y: tl_y + h,
      point: {tl_x + w, tl_y + h}
    }
  end

  def draw_x_box(graph, %Widgex.Frame{} = frame, color: c) do
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect(frame.size.box, stroke: {10, c})
        |> Scenic.Primitives.line({{0, 0}, {frame.size.width, frame.size.height}},
          stroke: {4, c}
        )
        |> Scenic.Primitives.line({{0, frame.size.height}, {frame.size.width, 0}},
          stroke: {4, c}
        )
      end
      # NOTE don't translate this group, translate in the higher component
      # translate: frame.pin.point
    )
  end

  # def draw_guidewires(graph, frame, background: background_color) do
  #   graph
  #   |> Scenic.Primitives.rect(frame.size.box, fill: background_color)
  #   |> Scenic.Primitives.rect(frame.size.box, stroke: {10, :white})
  #   |> Scenic.Primitives.line({top_left(frame).point, bottom_right(frame).point},
  #     stroke: {4, :black}
  #   )
  #   |> Scenic.Primitives.line({bottom_left(frame).point, top_right(frame).point},
  #     stroke: {4, :black}
  #   )
  # end

  def draw_guides(graph, frame) do
    graph
    |> draw_x_box(frame, color: :white)
  end

  def draw_guidewires(graph, frame) do
    graph
    |> draw_x_box(frame, color: :white)
  end

  def draw_guidewires(graph, frame, color: background_color) do
    draw_guidewires(graph, frame, background: background_color)
  end

  def draw_guidewires(graph, frame, background: background_color) do
    graph
    |> Scenic.Primitives.rect(frame.size.box, fill: background_color)
    |> draw_x_box(frame, color: :black)
  end
end
