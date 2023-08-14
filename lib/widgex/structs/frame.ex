defmodule Widgex.Structs.Frame do
  @moduledoc """
  Represents a rectangular component, bound by a 2D box.

  A `Frame` in Widgex defines the spatial dimensions and location of a rectangular area in a 2D space.
  It is characterized by the coordinates of its top-left corner (`pin`) and its size (`size`), including the
  width (x dimension) and height (y dimension).

  ## Example

      iex> alias Widgex.Structs.{Frame, Coordinates, Dimensions}
      iex> frame = Frame.new(%Coordinates{x: 5, y: 10}, %Dimensions{width: 100, height: 200})
      iex> frame.pin.x
      5
  """

  alias Widgex.Structs.Coordinates
  alias Widgex.Structs.Dimensions

  @typedoc """
  The struct for representing a Frame.

  - `pin`: The coordinates of the top-left corner of the frame.
  - `size`: The dimensions of the frame, specifying the width (x-axis) and height (y-axis).
  """
  @type t :: %__MODULE__{
          pin: Coordinates.t(),
          size: Dimensions.t()
        }

  defstruct [
    # Default top-left coordinates at the origin.
    pin: %Coordinates{x: 0, y: 0},
    # Default size not set.
    size: %Dimensions{width: nil, height: nil}
  ]

  @doc """
  Constructs a new `Frame` struct.

  The `new/2` function takes in the coordinates for the top-left corner (`pin`) and the size (`size`) of the frame.
  Both parameters are optional, and if not provided, they will be initialized to default values.

  ## Params

  - `pin`: Coordinates for the top-left corner of the frame. Defaults to `{0, 0}`.
  - `size`: Dimensions of the frame, specifying the width (x) and height (y). Defaults to `{nil, nil}`.

  ## Examples


      iex> Widgex.Structs.Frame.new()
      %Widgex.Structs.Frame{pin: %Widgex.Structs.Coordinates{x: 0, y: 0}, size: %Widgex.Structs.Dimensions{width: nil, height: nil}}

      iex> Widgex.Structs.Frame.new(%Widgex.Structs.Coordinates{x: 5, y: 10}, %Widgex.Structs.Dimensions{width: 100, height: 200})
      %Widgex.Structs.Frame{pin: %Widgex.Structs.Coordinates{x: 5, y: 10}, size: %Widgex.Structs.Dimensions{width: 100, height: 200}}

  """
  @spec new(Coordinates.t(), Dimensions.t()) :: t()
  def new(
        %Coordinates{} = pin \\ %Coordinates{x: 0, y: 0},
        %Dimensions{} = size \\ %Dimensions{width: nil, height: nil}
      ) do
    %__MODULE__{
      pin: pin,
      size: size
    }
  end

  def new({x, y}, {w, h}) do
    new(%Coordinates{x: x, y: y}, %Dimensions{width: w, height: h})
  end

  @doc """
  Constructs a new `Frame` struct that corresponds to the entire `Scenic.ViewPort`.

  Given a `Scenic.ViewPort`, this function will create a `Frame` that represents the entire viewport by utilizing the `size` attribute of the `ViewPort`.

  ## Params

  - `view_port`: The `Scenic.ViewPort` from which the frame is to be constructed.

  ## Examples

      iex> alias Scenic.ViewPort
      iex> alias Widgex.Structs.{Frame, Coordinates, Dimensions}
      iex> view_port = %ViewPort{size: {800, 600}}
      iex> Frame.from_viewport(view_port)
      %Frame{pin: %Coordinates{x: 0, y: 0}, size: %Dimensions{width: 800, height: 600}}
  """

  @spec from_viewport(Scenic.ViewPort.t()) :: t()
  def from_viewport(%Scenic.ViewPort{size: {vp_width, vp_height}}) do
    # Uncomment the line below to include the hack* (without it we get a dark strip on the right hand side)
    # width = vp_width + 1

    # Uncomment the line below for the intended behavior
    width = vp_width

    new(%Coordinates{x: 0, y: 0}, %Dimensions{width: width, height: vp_height})
  end

  @doc """
  Computes the centroid of the given frame.

  The centroid is calculated as the mid-point of both dimensions of the frame.

  ## Params

  - `frame`: The `Frame` whose centroid is to be computed.

  ## Examples

      iex> alias Widgex.Structs.{Frame, Coordinates, Dimensions}
      iex> frame = %Frame{pin: %Coordinates{x: 10, y: 10}, size: %Dimensions{width: 100, height: 50}}
      iex> Frame.center(frame)
      %Coordinates{x: 60.0, y: 35.0}

  """
  @spec center(t()) :: Coordinates.t()
  def center(%__MODULE__{
        pin: %Coordinates{x: pin_x, y: pin_y},
        size: %Dimensions{width: size_x, height: size_y}
      }) do
    %Coordinates{
      x: pin_x + size_x / 2,
      y: pin_y + size_y / 2
    }
  end

  def center_tuple(%__MODULE__{} = frame) do
    Coordinates.point(center(frame))
  end

  @doc """
  Computes the coordinates of the bottom-left corner of the given frame.

  ## Params

  - `frame`: The `Frame` whose bottom-left corner coordinates are to be computed.

  ## Examples

      iex> alias Widgex.Structs.{Frame, Coordinates, Dimensions}
      iex> frame = %Frame{pin: %Coordinates{x: 10, y: 10}, size: %Dimensions{width: 100, height: 50}}
      iex> Frame.bottom_left(frame)
      %Coordinates{x: 10, y: 60}

  """
  @spec bottom_left(t()) :: Coordinates.t()
  def bottom_left(%__MODULE__{pin: %Coordinates{x: tl_x, y: tl_y}, size: %Dimensions{height: h}}) do
    # add the height dimension to the y-coordinate of the pin (top-left corner).
    %Coordinates{
      x: tl_x,
      y: tl_y + h
    }
  end
end
