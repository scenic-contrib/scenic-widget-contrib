defmodule ScenicWidgets.ConfirmDialogTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.ConfirmDialog

  describe "button_color/1" do
    test ":save is green, :discard is orange, other is grey" do
      assert ConfirmDialog.button_color(:save) == {60, 130, 70}
      assert ConfirmDialog.button_color(:discard) == {170, 100, 30}
      assert ConfirmDialog.button_color(:cancel) == {80, 80, 85}
      assert ConfirmDialog.button_color(:whatever) == {80, 80, 85}
    end
  end

  describe "button_bounds/1" do
    test "centers a single button horizontally in the 420px dialog" do
      [{action, x, y, w, h}] = ConfirmDialog.button_bounds([{:ok, "OK"}])
      assert action == :ok
      assert w == 100
      assert h == 32
      assert y == 140
      # (420 - 100) / 2 = 160
      assert x == 160
    end

    test "returns correct tuples for three buttons laid out in a row" do
      bounds = ConfirmDialog.button_bounds([{:save, "Save"}, {:discard, "Discard"}, {:cancel, "Cancel"}])
      assert length(bounds) == 3
      [{:save, sx, _, _, _}, {:discard, dx, _, _, _}, {:cancel, cx, _, _, _}] = bounds
      # Each button is 100 wide + 16 spacing. Row width = 3*100 + 2*16 = 332. start_x = (420-332)/2 = 44.
      assert sx == 44.0
      assert dx == 44.0 + 100 + 16
      assert cx == 44.0 + 2 * (100 + 16)
    end
  end

  describe "source: emit_response uses send_parent_event/2" do
    # Regression: an earlier version called Scenic.Scene.send_event/2 with the
    # scene struct (instead of a pid), producing an ArgumentError with the
    # message "invalid destination" at runtime. The dialog was crashing on
    # every keyboard/mouse response, so the parent scene never received the
    # {:confirm_dialog_response, ...} event. The correct call is
    # Scenic.Scene.send_parent_event/2, which pattern-matches a %Scene{} and
    # sends to the parent pid.
    test "source file calls send_parent_event, not send_event" do
      path = Application.app_dir(:scenic_widget_contrib, "ebin")
              |> Path.join("../lib/components/confirm_dialog/confirm_dialog.ex")
              |> Path.expand()

      path =
        if File.exists?(path) do
          path
        else
          # Fallback to workspace-relative path when running from the repo
          Path.expand("lib/components/confirm_dialog/confirm_dialog.ex", File.cwd!())
        end

      source = File.read!(path)
      refute source =~ "Scenic.Scene.send_event(scene,",
             "ConfirmDialog.emit_response/2 must not call Scenic.Scene.send_event/2 " <>
               "with a scene struct — Process.send raises 'invalid destination'. " <>
               "Use Scenic.Scene.send_parent_event/2 instead."

      assert source =~ "Scenic.Scene.send_parent_event(scene,"
    end
  end
end
