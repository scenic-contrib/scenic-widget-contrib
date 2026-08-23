defmodule ScenicWidgets.FloatingPanelTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.FloatingPanel
  alias Widgex.Frame

  test "anchors a bounded panel to the top right" do
    container = Frame.new(pin: {10, 20}, size: {800, 600})
    panel = FloatingPanel.frame(container, placement: :top_right, margin: 12, size: {480, 72})

    assert panel.pin.point == {318, 32}
    assert panel.size.width == 480
    assert panel.size.height == 72
    assert FloatingPanel.contains?(panel, {798, 104})
    refute FloatingPanel.contains?(panel, {317, 32})
  end

  test "shrinks oversized panels inside their container" do
    container = Frame.new(pin: {0, 0}, size: {300, 100})
    panel = FloatingPanel.frame(container, margin: 10, size: {480, 200})

    assert panel.pin.point == {10, 10}
    assert panel.size.width == 280
    assert panel.size.height == 80
  end
end
