defmodule ScenicWidgets.MenuBar.SiblingSubmenuCleanupSpex do
  @moduledoc """
  Spex to reproduce and verify the sibling sub-menu cleanup bug.

  Bug: When hovering from one sub-menu to another sibling sub-menu (both at the same level),
  the first sub-menu's children don't disappear.

  Example: View > Appearance (opens sub-sub-menu) > then hover View > Layout
  Expected: Appearance's sub-sub-menu should close
  Actual: Appearance's sub-sub-menu stays open forever
  """

  use ExUnit.Case
  alias ScenicWidgets.MenuBar.State
  alias ScenicWidgets.MenuBar.Reducer

  describe "sibling sub-menu cleanup" do
    setup do
      # Create a menu structure similar to the View menu
      menu_map = %{
        view: {"View", [
          {:sub_menu, "Appearance", [
            {"theme_light", "Light Theme"},
            {"theme_dark", "Dark Theme"},
            {"theme_auto", "Auto"}
          ]},
          {:sub_menu, "Layout", [
            {"layout_single", "Single Pane"},
            {"layout_split", "Split Horizontal"},
            {"layout_split_v", "Split Vertical"}
          ]},
          {"fullscreen", "Toggle Fullscreen"}
        ]}
      }

      frame = %{
        pin: %{x: 0, y: 0},
        size: %{width: 800, height: 600}
      }

      state = State.new(%{
        frame: frame,
        menu_map: menu_map,
        hover_activate: false
      })

      {:ok, state: state}
    end

    test "hovering from Appearance to Layout closes Appearance's sub-sub-menu", %{state: state} do
      # Step 1: Click to open View menu
      view_x = 75  # Middle of first menu (0-150)
      view_y = 20  # Middle of menu bar

      {:noop, state} = Reducer.handle_click(state, {view_x, view_y})
      assert state.active_menu == :view
      assert state.active_sub_menus == %{}

      IO.puts("\n📍 Step 1: Opened View menu")
      IO.puts("   active_menu: #{inspect(state.active_menu)}")
      IO.puts("   active_sub_menus: #{inspect(state.active_sub_menus)}")

      # Step 2: Hover over "Appearance" (first item in dropdown)
      appearance_x = 75   # Same X as menu
      appearance_y = 50   # First item: 40 (menu height) + 5 (padding) + 15 (half item height)

      state = Reducer.handle_cursor_pos(state, {appearance_x, appearance_y})

      IO.puts("\n📍 Step 2: Hovered over Appearance")
      IO.puts("   hovered_dropdown: #{inspect(state.hovered_dropdown)}")
      IO.puts("   active_sub_menus: #{inspect(state.active_sub_menus)}")

      # Should have opened the Appearance sub-menu
      assert state.active_sub_menus[:view] == "submenu_appearance"

      # Step 3: Hover into the Appearance sub-menu area (to make it "active")
      # Appearance sub-menu appears at X = 75 + 150 - 5 = 220
      # We'll hover over the "Light Theme" item which should be the first item
      light_theme_x = 295  # 220 + 5 (padding) + 70 (middle of item)
      light_theme_y = 50   # Same Y as Appearance item (40 + 5 + 15)

      state = Reducer.handle_cursor_pos(state, {light_theme_x, light_theme_y})

      IO.puts("\n📍 Step 3: Hovered into Appearance sub-menu (over Light Theme)")
      IO.puts("   hovered_dropdown: #{inspect(state.hovered_dropdown)}")
      IO.puts("   active_sub_menus: #{inspect(state.active_sub_menus)}")

      # This should register that we're IN the Appearance sub-menu
      # But since "Light Theme" is not a sub-menu itself, no children should be open
      # The key point is that we've "been inside" the Appearance sub-menu

      # Now we should see Appearance sub-menu is still open
      appearance_submenu_before = state.active_sub_menus

      # IMPORTANT: The test scenario might not match reality. Let me check if the bug
      # happens when we have ACTUAL sub-sub-menus opened. In the real View menu,
      # both Appearance and Layout DON'T have sub-sub-menus - they only have regular items!
      # So let me trace what the actual bug scenario is...

      # Step 4: Move back to main dropdown and hover over "Layout" (second item)
      layout_x = 75
      layout_y = 80  # Second item: 40 + 5 + 30 (first item) + 15 (half of second item)

      state = Reducer.handle_cursor_pos(state, {layout_x, layout_y})

      IO.puts("\n📍 Step 4: Hovered over Layout")
      IO.puts("   hovered_dropdown: #{inspect(state.hovered_dropdown)}")
      IO.puts("   active_sub_menus: #{inspect(state.active_sub_menus)}")
      IO.puts("   active_sub_menus BEFORE: #{inspect(appearance_submenu_before)}")

      # BUG CHECK: The submenu_appearance should be CLOSED
      # We should only have: %{view: "submenu_layout"}
      assert state.active_sub_menus[:view] == "submenu_layout",
        "View menu should now point to Layout sub-menu"

      refute Map.has_key?(state.active_sub_menus, "submenu_appearance"),
        "BUG: Appearance sub-menu should be closed but is still in active_sub_menus"

      # Verify the map only has one entry
      assert map_size(state.active_sub_menus) == 1,
        "Should only have 1 active sub-menu (Layout), but have #{map_size(state.active_sub_menus)}: #{inspect(state.active_sub_menus)}"
    end

    test "detailed trace of state transitions", %{state: state} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("DETAILED TRACE: Sibling Sub-menu Cleanup")
      IO.puts(String.duplicate("=", 80))

      # Open View menu
      {:noop, state} = Reducer.handle_click(state, {75, 20})
      IO.puts("\n1️⃣  After opening View menu:")
      print_state(state)

      # Hover Appearance
      state = Reducer.handle_cursor_pos(state, {75, 50})
      IO.puts("\n2️⃣  After hovering Appearance:")
      print_state(state)

      # Hover Layout
      state = Reducer.handle_cursor_pos(state, {75, 80})
      IO.puts("\n3️⃣  After hovering Layout (SHOULD CLOSE APPEARANCE):")
      print_state(state)

      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("EXPECTED: active_sub_menus should be %{view: \"submenu_layout\"}")
      IO.puts("ACTUAL:   active_sub_menus is #{inspect(state.active_sub_menus)}")
      IO.puts(String.duplicate("=", 80) <> "\n")
    end
  end

  defp print_state(state) do
    IO.puts("   active_menu:       #{inspect(state.active_menu)}")
    IO.puts("   hovered_item:      #{inspect(state.hovered_item)}")
    IO.puts("   hovered_dropdown:  #{inspect(state.hovered_dropdown)}")
    IO.puts("   active_sub_menus:  #{inspect(state.active_sub_menus)}")
  end
end
