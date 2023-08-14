defmodule Widgex do
  @moduledoc """
  # A Component Management Framework for Scenic

  The Widgex designed to simplify the development of complex user interfaces using Scenic, the 2D graphics toolkit for Elixir. Instead of dealing directly with individual graphical elements, Widgex allows developers to work with higher-level components, providing a more flexible and streamlined development experience.

  ## The Concept of a Frame

  A core concept in Widgex is the "frame." A frame represents a rectangular region within the application window. It defines both position and dimensions, encapsulating where a component resides and how much space it occupies. Frames can be nested, aligned, resized, and positioned with ease, enabling the creation of intricate layouts without getting lost in the minutiae of individual pixel management.

  ### Key Components of a Frame

  - **Coordinates**: Defines the top-left corner of the frame. Represented by `Widgex.Structs.Coordinates`, it includes `x` and `y` values.
  - **Dimensions**: Specifies the size of the frame. Represented by `Widgex.Structs.Dimensions`, it includes `width` and `height` values.

  ### Example Usage

  Here's how you might create a frame that represents a button within a larger interface:

  ```elixir
  alias Widgex.Structs.{Frame, Coordinates, Dimensions}

  frame = Frame.new(
    pin: Coordinates.new(x: 10, y: 20),
    size: Dimensions.new(width: 100, height: 50)
  )
  ```

  You can then manipulate this frame, align it with other frames, or use it as the basis for rendering your button.

  ### Conclusion

  Widgex offers an abstraction layer that makes working with Scenic simpler and more intuitive. By embracing concepts like frames, coordinates, and dimensions, it offers a powerful toolset for building rich, interactive user interfaces in Elixir.

  For more detailed information on specific structs and functions, please refer to the corresponding module documentation.
  """
end
