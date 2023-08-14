defmodule Widgex.Structs.Dimensions do
  @moduledoc """
  Represents 2D dimensions with non-negative `width` and `height`.

  The `Dimensions` struct is defined with the following fields:

  - `width`: The width of the dimensions, a non-negative float.
  - `height`: The height of the dimensions, a non-negative float.
  - `box`: A tuple containing both `width` and `height`, for convenience.
  """

  @typedoc "The struct for representing dimensions in 2D space."
  @type t :: %__MODULE__{
          width: width_dimension(),
          height: height_dimension()
        }

  @typedoc "The type representing the width dimension."
  @type width_dimension :: float()

  @typedoc "The type representing the height dimension."
  @type height_dimension :: float()

  @typedoc "The type representing the dimensions as a tuple of width and height."
  @type box :: {width_dimension(), height_dimension()}

  defstruct width: 0.0,
            height: 0.0

  def box(%__MODULE__{width: w, height: h}), do: {w, h}
end
