defmodule ScenicWidgets.MenuBarIssuesSpex do
  @moduledoc """
  Tests for specific MenuBar issues identified:
  1. Sub-menu indicator (carat) not rendering properly
  2. Sub-menu navigation causing menubar to disappear
  3. Orphaned sub-sub-menu visibility bug
  4. Mouseover activation option
  """
  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}
  alias ScenicMcp.Probes

  @tmp_screenshots_dir "test/spex/screenshots/menubar_issues"

  setup_all do
    # This test assumes the comprehensive test has already run and MenuBar is loaded
    # If running standalone, start the app first with:
    # mix run -e "Application.ensure_all_started(:scenic_widget_contrib)" --no-halt
    
    :ok
  end

  spex "Sub-menu indicator rendering" do
    scenario "Sub-menu items show visible indicator", context do
      given_ "MenuBar with sub-menus is loaded", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        assert String.contains?(rendered_content, "File"), "MenuBar should be loaded"
        {:ok, context}
      end

      when_ "Edit menu is opened", context do
        # Click on Edit menu which has sub-menus
        edit_menu_x = 100 + 150 + 75  # Component x + menu offset + center
        edit_menu_y = 295 + 20
        
        Probes.send_mouse_click(edit_menu_x, edit_menu_y)
        Process.sleep(200)
        
        {:ok, context}
      end

      then_ "sub-menu items show visual indicator", context do
        # The "Find" item should have a sub-menu indicator
        rendered_content = ScriptInspector.get_rendered_text_string()
        assert String.contains?(rendered_content, "Find"), "Find sub-menu should be visible"
        
        # Take screenshot to verify visual indicator
        screenshot = Probes.take_screenshot("submenu_indicator")
        
        # TODO: Once we implement the fix, we should verify the indicator is visible
        # For now, we just document the issue
        IO.puts("🐛 Sub-menu indicator (▶ or >) not visible with current font")
        
        {:ok, Map.put(context, :screenshot, screenshot)}
      end
    end
  end

  spex "Sub-menu navigation bounds" do
    scenario "Moving cursor to sub-menu doesn't close parent menu", context do
      given_ "Edit menu with Find sub-menu is open", context do
        # Click on Edit menu
        edit_menu_x = 100 + 150 + 75
        edit_menu_y = 295 + 20
        
        Probes.send_mouse_click(edit_menu_x, edit_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("Find"), "Edit menu should be open"
        {:ok, context}
      end

      when_ "cursor hovers over Find to open sub-menu", context do
        # Hover over Find item (should be 6th item in Edit menu)
        find_x = 100 + 150 + 75  # Same x as Edit menu
        find_y = 295 + 40 + 5 + (5 * 30) + 15  # 6th item position
        
        Probes.send_mouse_move(find_x, find_y)
        Process.sleep(200)
        
        {:ok, context}
      end

      and_ "cursor moves right towards sub-menu", context do
        # Move cursor to the right where sub-menu should appear
        submenu_x = 100 + 150 + 150 + 30  # Parent x + parent width + offset
        submenu_y = 295 + 40 + 5 + (5 * 30) + 15  # Same y as Find item
        
        Probes.send_mouse_move(submenu_x, submenu_y)
        Process.sleep(200)
        
        {:ok, context}
      end

      then_ "both Edit menu and Find sub-menu remain open", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Parent menu should still be open
        assert ScriptInspector.rendered_text_contains?("Undo"), 
               "Edit menu should remain open"
        
        # Sub-menu should be open
        assert ScriptInspector.rendered_text_contains?("Find and Replace"), 
               "Find sub-menu should be open"
        
        IO.puts("🐛 Currently, moving to sub-menu causes parent to close")
        
        :ok
      end
    end

    scenario "Grace period allows diagonal mouse movement", context do
      given_ "nested sub-menu is open", context do
        # Open File > Recent Files > By Project
        file_menu_x = 100 + 75
        file_menu_y = 295 + 20
        
        Probes.send_mouse_click(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        # Hover over Recent Files (3rd item)
        recent_x = 100 + 75
        recent_y = 295 + 40 + 5 + (2 * 30) + 15
        
        Probes.send_mouse_move(recent_x, recent_y)
        Process.sleep(200)
        
        {:ok, context}
      end

      when_ "cursor moves diagonally towards sub-menu", context do
        # Simulate diagonal movement that temporarily exits bounds
        positions = [
          {150, 380},  # Start position
          {200, 385},  # Diagonal - might exit dropdown bounds
          {250, 390},  # Continue diagonal
          {300, 395},  # Reach sub-menu area
        ]
        
        for {x, y} <- positions do
          Probes.send_mouse_move(x, y)
          Process.sleep(50)
        end
        
        {:ok, context}
      end

      then_ "menus remain open during transition", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Menus should still be open
        assert ScriptInspector.rendered_text_contains?("Recent Files") ||
               ScriptInspector.rendered_text_contains?("Document 1.txt"),
               "Menus should remain open during diagonal movement"
        
        :ok
      end
    end
  end

  spex "Orphaned sub-menu visibility" do
    scenario "Sub-menus close when parent closes", context do
      given_ "deeply nested sub-menu is open", context do
        # Open File > Recent Files > By Project
        file_menu_x = 100 + 75
        file_menu_y = 295 + 20
        
        Probes.send_mouse_click(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        # Hover over Recent Files
        recent_x = 100 + 75
        recent_y = 295 + 40 + 5 + (2 * 30) + 15
        Probes.send_mouse_move(recent_x, recent_y)
        Process.sleep(200)
        
        # Hover over By Project sub-sub-menu
        by_project_x = 100 + 150 + 75
        by_project_y = 295 + 40 + 5 + (2 * 30) + 15
        Probes.send_mouse_move(by_project_x, by_project_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("Project A"),
               "Sub-sub-menu should be open"
        
        {:ok, context}
      end

      when_ "user clicks outside menubar", context do
        # Click far outside
        Probes.send_mouse_click(50, 50)
        Process.sleep(200)
        
        {:ok, context}
      end

      then_ "all menus and sub-menus are closed", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # No dropdown content should be visible
        refute ScriptInspector.rendered_text_contains?("New File"),
               "File menu should be closed"
        refute ScriptInspector.rendered_text_contains?("Recent Files"),
               "Sub-menu should be closed"
        refute ScriptInspector.rendered_text_contains?("Project A"),
               "Sub-sub-menu should be closed"
        
        # But menu bar itself should still be there
        assert ScriptInspector.rendered_text_contains?("File"),
               "Menu bar headers should remain visible"
        
        IO.puts("🐛 Currently, sub-menus can remain orphaned")
        
        :ok
      end
    end

    scenario "Escape key closes all nested menus", context do
      given_ "nested menus are open", context do
        # Open Edit > Find
        edit_menu_x = 100 + 150 + 75
        edit_menu_y = 295 + 20
        
        Probes.send_mouse_click(edit_menu_x, edit_menu_y)
        Process.sleep(200)
        
        # Hover over Find
        find_x = 100 + 150 + 75
        find_y = 295 + 40 + 5 + (5 * 30) + 15
        Probes.send_mouse_move(find_x, find_y)
        Process.sleep(200)
        
        {:ok, context}
      end

      when_ "escape key is pressed", context do
        # Send escape key
        Probes.send_keys(key: "escape")
        Process.sleep(200)
        
        {:ok, context}
      end

      then_ "all menus close", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        refute ScriptInspector.rendered_text_contains?("Undo"),
               "Edit menu should be closed"
        refute ScriptInspector.rendered_text_contains?("Find and Replace"),
               "Find sub-menu should be closed"
        
        :ok
      end
    end
  end

  spex "Mouseover activation option" do
    scenario "MenuBar can be configured for mouseover activation", context do
      given_ "MenuBar is configured with mouseover mode", context do
        # For this test, we'll need to reload MenuBar with mouseover config
        # TODO: Implement configuration option first
        IO.puts("📝 TODO: Implement mouseover activation configuration")
        
        {:ok, context}
      end

      when_ "cursor hovers over File menu without clicking", context do
        file_menu_x = 100 + 75
        file_menu_y = 295 + 20
        
        Probes.send_mouse_move(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        {:ok, context}
      end

      then_ "File menu opens automatically", context do
        # Once implemented, this should work
        # assert ScriptInspector.rendered_text_contains?("New File"),
        #        "File menu should open on hover in mouseover mode"
        
        IO.puts("📝 Feature not yet implemented: mouseover activation")
        
        :ok
      end
    end
  end
end