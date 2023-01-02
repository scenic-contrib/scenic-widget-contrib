defmodule ScenicWidgets.Core.Structs.DimensionsTest do
   use ExUnit.Case

   @testmodule ScenicWidgets.Core.Structs.Dimensions

   test "construct a basic %Dimensions{} struct" do
      r = @testmodule.new(%{width: 10, height: 10})
      assert r == %ScenicWidgets.Core.Structs.Dimensions{width: 10, height: 10, box: {10, 10}}
   end
end