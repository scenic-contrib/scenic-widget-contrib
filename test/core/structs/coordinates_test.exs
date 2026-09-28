defmodule Widgex.Structs.CoordinatesTest do
   use ExUnit.Case

   @testmodule Widgex.Structs.Coordinates

   test "construct a basic %Coordinates{} struct" do
      r = @testmodule.new(%{x: 7, y: 12})
      assert r == %Widgex.Structs.Coordinates{x: 7, y: 12, point: {7, 12}}
   end
end