defmodule Widgex.Structs.Coordinates do
  @moduledoc """
  Struct which holds 2d points.
  """

  defstruct x: nil,
            y: nil,
            point: {nil, nil}

  def new({x, y}) do
    new(%{x: x, y: y})
  end

  def new(%{x: x, y: y}) when x >= 0 and y >= 0 do
    %__MODULE__{
      x: x,
      y: y,
      point: {x, y}
    }
  end
end
