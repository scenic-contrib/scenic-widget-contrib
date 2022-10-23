defmodule ScenicWidgets.Core.Structs.Coordinates do
   @moduledoc """
   Struct which holds 2d points.
   """
   use ScenicWidgets.Core.Utils.CustomGuards

   defstruct [
      # guid: nil,
      x: nil,
      y: nil,
      point: {nil, nil}
   ]

   def new(x: x, y: y), do: new(%{x: x, y: y})

   def new(%{x: x, y: y}) when x >= 0 and y >= 0 do
         %__MODULE__{
         x: x,
         y: y,
         point: {x, y}
      }
   end

   def modify(%__MODULE__{} = struct, %{x: new_x, y: new_y})
      when all_positive_floats(new_x, new_y) do
         %{struct|x: new_x, y: new_y}
   end

end
