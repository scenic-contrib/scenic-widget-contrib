defmodule Widgex.Structs.Coordinates do
  @moduledoc """
  Represents a 2D point with non-negative `x` and `y` coordinates.

  The `Coordinates` struct is defined with the following fields:

  - `x`: The X-coordinate of the point, a non-negative float.
  - `y`: The Y-coordinate of the point, a non-negative float.
  - `point`: A tuple containing both `x` and `y`, for convenience.
  """

  @typedoc "The struct for representing a point in 2D space."
  @type t :: %__MODULE__{
          x: float(),
          y: float()
        }

  @typedoc "The type representing the x-coordinate of the point."
  @type x_coordinate :: float()

  @typedoc "The type representing the y-coordinate of the point."
  @type y_coordinate :: float()

  @typedoc "The type representing the point as a tuple of x and y coordinates."
  @type point :: {x_coordinate(), y_coordinate()}

  defstruct x: 0.0,
            y: 0.0

  def point(%__MODULE__{x: x, y: y}), do: {x, y}
end
