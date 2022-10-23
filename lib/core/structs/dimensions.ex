defmodule ScenicWidgets.Core.Structs.Dimensions do
   @moduledoc """
   Struct which holds 2d points.
   """
   use ScenicWidgets.Core.Utils.CustomGuards

   defstruct [
      width:  nil,
      height: nil,
      box: {nil, nil} # the cross-product, width (-->) then height
   ]

   def new(width: w, height: h), do: new(%{width: w, height: h})

   def new(%{width: w, height: h}) when w >= 0 and h >= 0 do
      %__MODULE__{
         width:  w,
         height: h,
         box: {w, h}
      }
   end

  #  def new(:viewport_size) do
  #     vp = Scenic.ViewPort.info()
  #     # #TODO this is actually just getting us the *default* viewport,
  #     # #     not necessarily the current one
  #     # dimensions = Flamelex.GUI.ScenicInitialize.viewport_config() #TODO remove this!!
  #     #              |> Keyword.get(:size)
  #     # new(dimensions)
  #   end

  #   def find_center(dimensions) do
#     Coordinates.new(
#         x: dimensions.width  / 2,
#         y: dimensions.height / 2)
#   

   # def centerpoint(dimensions) do
   #    ScenicWidgets.Core.Structs.Coordinates
   # end
end