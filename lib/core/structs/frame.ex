defmodule ScenicWidgets.Core.Structs.Frame do
  @moduledoc """
  A Frame struct defines the rectangular size of a component.
  """

  defmodule Coordinates do
    defstruct x: 0, y: 0

    def new(x: x, y: y), do: %__MODULE__{x: x, y: y}
    def new(%{x: x, y: y}), do: %__MODULE__{x: x, y: y}
    def new({x, y}), do: %__MODULE__{x: x, y: y}
  end

  defmodule Dimensions do
    defstruct width: 0, height: 0

    def new(width: w, height: h), do: %__MODULE__{width: w, height: h}
    def new(%{width: w, height: h}), do: %__MODULE__{width: w, height: h}
    def new({w, h}), do: %__MODULE__{width: w, height: h}
  end

  defstruct [
    # The {x, y} of the top-left of this Frame
    pin: {0, 0},
    # A %Coordinates{} struct, this is essentially the same as the pin, but having it leads to some nice syntax e.g. frame.top_left.x
    top_left: nil,
    # In Scenic, the pin is always in the top-left corner of the Graph - as x increases, we go _down_ the screen, and as y increases we go to the right
    orientation: :top_left,
    # How large in {width, height} this Frame is
    size: nil,
    # a %Dimensions{} struct, specifying the height and width of the frame - this makes for some nice syntax down the road e.g. frame.dimensions.width, rather than having to pull out a {width, height} tuple
    dimensions: nil
  ]

  # Make a new frame the same size as the ViewPort
  def new(%Scenic.ViewPort{size: {w, h}}) do
    %__MODULE__{
      pin: {0, 0},
      top_left: Coordinates.new(x: 0, y: 0),
      size: {w, h},
      dimensions: Dimensions.new(width: w, height: h)
    }
  end

  def new(size: {w, h}) do
    new(pin: {0, 0}, size: {w, h})
  end

  def new(width: w, height: h) do
    new(pin: {0, 0}, size: {w, h})
  end

  # Make a new frame, with the top-left corner at point `pin`
  def new(pin: {x, y}, size: {w, h}) do
    IO.puts "DEPRECATE MEEE 88888"
    new(%{pin: {x, y}, size: {w, h}})
  end

  def new(%{pin: {x, y}, size: {w, h}}) do
    %__MODULE__{
      pin: {x, y},
      top_left: Coordinates.new(x: x, y: y),
      size: {w, h},
      dimensions: Dimensions.new(width: w, height: h)
    }
  end

  # def new(top_left: {_x, _y} = top_left, dimensions: {_w, _h} = size) do
  #   new(pin: top_left, size: size)
  # end

  def new(%Scenic.ViewPort{size: {w, h}}, menubar_height: mh) do
    IO.puts "DEPRECATED MEEEEE 99999"
    %__MODULE__{
      pin: {0, mh},
      top_left: Coordinates.new(x: 0, y: mh),
      size: {w, h - mh},
      dimensions: Dimensions.new(width: w, height: h - mh)
    }
  end

  def center(%{top_left: c, dimensions: d}) do
    Coordinates.new(x: c.x + d.width / 2, y: c.y + d.height / 2)
  end

  def bottom_left(%{pin: {tl_x, tl_y}, size: {w, h}}) do
    Coordinates.new(x: tl_x, y: tl_y + h)
  end
end
