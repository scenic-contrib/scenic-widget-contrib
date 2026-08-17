defmodule Widgex.Scroll.ScrollControllerTest do
  use ExUnit.Case, async: true

  alias Widgex.Scroll.ScrollController

  test "drag maps the complete available thumb travel to complete content travel" do
    track = 100
    thumb = 25

    assert ScrollController.drag_offset(0, 0, track, thumb, 300) == 0
    assert ScrollController.drag_offset(0, 37.5, track, thumb, 300) == 150
    assert ScrollController.drag_offset(0, 75, track, thumb, 300) == 300
  end

  test "drag clamps at both ends and handles unscrollable content" do
    assert ScrollController.drag_offset(20, -100, 100, 20, 300) == 0
    assert ScrollController.drag_offset(280, 100, 100, 20, 300) == 300
    assert ScrollController.drag_offset(0, 50, 100, 100, 0) == 0
  end

  test "thumb extent is proportional and usable" do
    assert ScrollController.thumb_length(100, 400, 100) == 25
    assert ScrollController.thumb_length(100, 10_000, 100) == 20
    assert ScrollController.thumb_length(100, 100, 100) == 100
  end

  test "track clicks page by one viewport and clamp at both ends" do
    assert ScrollController.page_offset(300, 10, 40, 20, 100, 500) == 200
    assert ScrollController.page_offset(300, 90, 40, 20, 100, 500) == 400
    assert ScrollController.page_offset(300, 50, 40, 20, 100, 500) == 300
    assert ScrollController.page_offset(20, 0, 40, 20, 100, 500) == 0
    assert ScrollController.page_offset(480, 90, 40, 20, 100, 500) == 500
  end
end
