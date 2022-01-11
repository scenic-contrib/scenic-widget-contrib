
defmodule ScenicWidgets.Core.Structs.Frame do
    @moduledoc """
    A Frame struct defines the rectangular size of a component.
    """
  

    defmodule Coordinates do
      defstruct [x: 0, y: 0]
  
      def new(x: x, y: y), do: %__MODULE__{x: x, y: y}
      def new(%{x: x, y: y}), do: %__MODULE__{x: x, y: y}
      def new({x, y}), do: %__MODULE__{x: x, y: y}
    end
  
    defmodule Dimensions do
      defstruct [width: 0, height: 0]
  
      def new(width: w, height: h), do: %__MODULE__{width: w, height: h}
      def new(%{width: w, height: h}), do: %__MODULE__{width: w, height: h}
      def new({w, h}), do: %__MODULE__{width: w, height: h}
    end
  
  
    defstruct [
      pin:          {0, 0},         # The {x, y} of the top-left of this Frame
      top_left:     nil,            # A %Coordinates{} struct, this is essentially the same as the pin, but having it leads to some nice syntax e.g. frame.top_left.x
      orientation:  :top_left,      # In Scenic, the pin is always in the top-left corner of the Graph - as x increases, we go _down_ the screen, and as y increases we go to the right
      size:         nil,            # How large in {width, height} this Frame is
      dimensions:   nil,            # a %Dimensions{} struct, specifying the height and width of the frame - this makes for some nice syntax down the road e.g. frame.dimensions.width, rather than having to pull out a {width, height} tuple
      margin: %{
          top: 0,
          right: 0,
          bottom: 0,
          left: 0 },
      label:        nil,            # an optional label, usually used to render a footer bar
      opts:         %{}             # A map to hold options, e.g. %{render_footer?: true}
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
  
    # Make a new frame, with the top-left corner at point `pin`
    def new([pin: {x, y}, size: {w, h}]) do
      %__MODULE__{
        pin: {x, y},
        top_left: Coordinates.new(x: x, y: y),
        size: {w, h},
        dimensions: Dimensions.new(width: w, height: h)
      }
    end
  end
