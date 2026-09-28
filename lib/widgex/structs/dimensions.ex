defmodule Widgex.Structs.Dimensions do
  @moduledoc """
  Struct which holds 2d points.
  """

  defstruct width: nil,
            height: nil,
            box: {nil, nil}

  def new({w, h}) do
    new(%{width: w, height: h})
  end

  def new(%{width: w, height: h}) when w >= 0 and h >= 0 do
    %__MODULE__{
      width: w,
      height: h,
      box: {w, h}
    }
  end
end
