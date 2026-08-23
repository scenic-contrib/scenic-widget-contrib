defmodule Widgex.Structs.DimensionsTest do
   use ExUnit.Case

   @testmodule Widgex.Structs.Dimensions

   test "construct a basic %Dimensions{} struct" do
      r = @testmodule.new(%{width: 10, height: 10})
      assert r == %Widgex.Structs.Dimensions{width: 10, height: 10, box: {10, 10}}
   end
end