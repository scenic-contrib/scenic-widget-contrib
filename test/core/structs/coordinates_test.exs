defmodule ScenicWidgets.Core.Structs.CoordinatesTest do
   use ExUnit.Case

   @testmodule ScenicWidgets.Core.Structs.Coordinates

   test "construct a basic %Dimensions{} struct" do
      r = @testmodule.new(x: 7, y: 12)
      assert r == %ScenicWidgets.Core.Structs.Coordinates{x: 7, y: 12, point: {7, 12}}
   end
end