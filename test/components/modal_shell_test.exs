defmodule ScenicWidgets.ModalShellTest do
  use ExUnit.Case, async: true

  test "centers modal bounds and builds an input-shielding overlay" do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {800, 600})

    assert %{x: 300.0, y: 225.0, width: 200, height: 150} =
             ScenicWidgets.ModalShell.bounds(frame, {200, 150})

    graph = ScenicWidgets.ModalShell.overlay(Scenic.Graph.build(), frame, :shield)
    assert Scenic.Graph.get!(graph, :shield)
  end
end
