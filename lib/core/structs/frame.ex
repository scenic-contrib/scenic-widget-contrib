defmodule ScenicWidgets.Core.Structs.Frame do
  @moduledoc """
  A Frame struct defines the rectangular size of a component.
  """
  alias ScenicWidgets.Core.Structs.{Coordinates, Dimensions}


  defstruct [
    # The {x, y} of the top-left of this Frame
    pin: {0, 0},
    # A %Coordinates{} struct, this is essentially the same as the pin, but having it leads to some nice syntax e.g. frame.coords.x
    coords: nil,
    #  # How large in {width, height} this Frame is
    size: nil,
    # a %Dimensions{} struct, specifying the height and width of the frame - this makes for some nice syntax down the road e.g. frame.dimens.width, rather than having to pull out a {width, height} tuple
    dimens: nil
  ]

  # # Make a new frame the same size as the ViewPort
  # def new(%Scenic.ViewPort{size: {w, h}}) do
  #   %__MODULE__{
  #     pin: {0, 0},
  #     top_left: Coordinates.new(x: 0, y: 0),
  #     size: {w, h},
  #     dimensions: Dimensions.new(width: w, height: h)
  #   }
  # end

  # def new(%{size: {w, h}}) do
  #   new(pin: {0, 0}, size: {w, h})
  # end

  # def new(%{coords: %Coordinates{} = c, dimens: %Dimensions{} = d}) do
  #   %__MODULE__{
  #     pin: {x, y},
  #     coords: Coordinates.new(x: x, y: y),
  #     size: {w, h},
  #     dimens: Dimensions.new(width: w, height: h)
  #   }
  # end

  # # Make a new frame, with the top-left corner at point `pin`
  # def new(pin: {x, y}, size: {w, h}) do
  #   IO.puts "DEPRECATE MEEE 88888"
  #   new(%{pin: {x, y}, size: {w, h}})
  # end

  def new(%Scenic.ViewPort{size: {vp_width, vp_height}}) do
    #TODO why do we need this +1?? Without it we get a dark strip on the right hand side
    new(%{pin: {0, 0}, size: {vp_width+1, vp_height}})
  end

  def new(pin: pin, size: size), do: new(%{pin: pin, size: size})

  def new(%{pin: {x, y}, size: {w, h}}) do
    %__MODULE__{
      pin: {x, y},
      coords: Coordinates.new(x: x, y: y),
      size: {w, h},
      dimens: Dimensions.new(width: w, height: h)
    }
  end

  def center(%{coords: c, dimens: d}) do
    Coordinates.new(x: c.x + d.width / 2, y: c.y + d.height / 2)
  end

  # def bottom_left(%{pin: {tl_x, tl_y}, size: {w, h}}) do
  #   Coordinates.new(x: tl_x, y: tl_y + h)
  # end
end
