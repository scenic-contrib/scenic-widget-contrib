defmodule ScenicWidgets.Core.Structs.FrameTest do
   use ExUnit.Case

   @testmodule ScenicWidgets.Core.Structs.Frame

   test "construct a basic %Frame{} struct" do
      f = @testmodule.new(%{pin: {7, 12}, size: {80, 207}})
      assert f == %ScenicWidgets.Core.Structs.Frame{
         coords: %ScenicWidgets.Core.Structs.Coordinates{x: 7, y: 12, point: {7, 12}},
         dimens: %ScenicWidgets.Core.Structs.Dimensions{width: 80, height: 207, box: {80, 207}}
      }
   end
end