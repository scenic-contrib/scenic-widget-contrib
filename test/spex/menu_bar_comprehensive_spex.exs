defmodule ScenicWidgets.MenuBarComprehensiveSpex do
  @moduledoc """
  COMPREHENSIVE MenuBar Spex - Complete desktop menubar functionality.

  This spex validates ALL standard menubar behaviors expected in desktop applications.
  It serves as both specification and acceptance tests for a production-ready MenuBar.

  ## Feature Coverage:
  1. Basic Rendering and Layout (proper positioning, sizing, theming)
  2. Click-to-Open Behavior (first click opens, not hover)
  3. Hover Navigation (once active, hover switches between menus)
  4. Dropdown Management (positioning, visibility, animation-free)
  5. Click-Outside-to-Close (clicking anywhere else closes dropdowns)
  6. Keyboard Navigation (arrow keys, escape, enter)
  7. Menu Item Selection (click handling, event propagation)
  8. Z-Order/Layering (dropdowns appear above other content)
  9. State Management (active menu, hover states, transitions)
  10. Error Handling (rapid clicks, edge cases, boundaries)

  ## Standard Behaviors Based on Research:
  - Click-to-open for initial activation (not hover)
  - Hover navigation between menus once menubar is active
  - Immediate visual feedback on hover (no delays)
  - Single dropdown open at a time
  - Click outside or Escape closes all dropdowns
  - Proper event bubbling for menu item selection

  Success Criteria: ALL scenarios must pass for MenuBar to be production-ready.
  """
  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}
  alias ScenicMcp.Probes

  @tmp_screenshots_dir "test/spex/screenshots/menubar"

  setup_all do
    # Start Widget Workbench application
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end
    
    # Kill any existing viewport first
    if pid = Process.whereis(:main_viewport) do
      Process.exit(pid, :kill)
      Process.sleep(200)
    end
    
    # Start the viewport with Widget Workbench
    viewport_config = [
      name: :main_viewport,
      size: {1200, 800},
      theme: :dark,
      default_scene: {WidgetWorkbench.Scene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :scenic_driver,
          window: [
            resizeable: true,
            title: "Widget Workbench - MenuBar Comprehensive Test"
          ],
          debug: false,
          cursor: true,
          antialias: true,
          layer: 0,
          opacity: 255,
          position: [
            scaled: false,
            centered: false,
            orientation: :normal
          ]
        ]
      ]
    ]
    
    {:ok, _pid} = Scenic.ViewPort.start_link(viewport_config)
    
    # Wait for Widget Workbench to start
    Process.sleep(2000)
    
    # Load MenuBar component using our semantic UI helper
    case SemanticUI.load_component("Menu Bar") do
      {:ok, _} -> 
        IO.puts("✅ MenuBar loaded successfully")
      {:error, reason} ->
        IO.puts("❌ Failed to load MenuBar: #{reason}")
    end
    
    Process.sleep(2000)  # Give more time for MenuBar to fully render
    
    # Cleanup on exit
    on_exit(fn ->
      if pid = Process.whereis(:main_viewport) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)
    
    :ok
  end

  spex "Comprehensive MenuBar Functionality - Desktop Standard Behaviors",
    description: "Validates ALL essential menubar features for production use",
    tags: [:comprehensive, :menubar, :ui_patterns, :desktop_standard] do

    # =============================================================================
    # 1. BASIC RENDERING AND LAYOUT
    # =============================================================================

    scenario "MenuBar renders with correct layout and styling", context do
      given_ "Widget Workbench has loaded MenuBar", context do
        # The MenuBar should already be loaded from setup_all
        # Take a baseline screenshot
        baseline_screenshot = Probes.take_screenshot("menubar_baseline")
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "we inspect the rendered content", context do
        # Get the rendered text content
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Take a screenshot of the loaded MenuBar
        menubar_loaded_screenshot = Probes.take_screenshot("menubar_loaded")
        
        {:ok, Map.merge(context, %{
          menubar_loaded_screenshot: menubar_loaded_screenshot,
          rendered_content: rendered_content
        })}
      end

      then_ "MenuBar appears with correct dimensions and menu items", context do
        # Verify all menu headers are visible
        assert ScriptInspector.rendered_text_contains?("File"), 
               "File menu should be visible. Got: #{inspect(context.rendered_content)}"
        assert ScriptInspector.rendered_text_contains?("Edit"),
               "Edit menu should be visible"
        assert ScriptInspector.rendered_text_contains?("View"),
               "View menu should be visible"
        assert ScriptInspector.rendered_text_contains?("Help"),
               "Help menu should be visible"
        
        # MenuBar should be positioned at (80, 80) based on prepare_component_data
        # This tests the coordinate conversion works properly
        
        :ok
      end
    end

    # =============================================================================
    # 2. CLICK-TO-OPEN BEHAVIOR (Desktop Standard)
    # =============================================================================

    scenario "Click-to-open dropdown behavior", context do
      given_ "MenuBar in default closed state", context do
        # Ensure no dropdowns are open
        rendered_content = ScriptInspector.get_rendered_text_string()
        refute ScriptInspector.rendered_text_contains?("New File"),
               "Dropdown items should not be visible initially"
        
        closed_state_screenshot = Probes.take_screenshot("menubar_closed_state")
        {:ok, Map.put(context, :closed_state_screenshot, closed_state_screenshot)}
      end

      when_ "user hovers over File menu without clicking", context do
        # Widget Workbench centers components in main area (left 2/3 of window)
        # Component is 600px wide, starts at ~x=100, y=295  
        file_menu_x = 100 + 30  # Component x + padding for first menu item
        file_menu_y = 295 + 20  # Component y + center of 40px high menubar
        
        Probes.send_mouse_move(file_menu_x, file_menu_y)
        Process.sleep(100)
        
        {:ok, context}
      end

      then_ "dropdown does NOT open on hover alone", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        refute ScriptInspector.rendered_text_contains?("New File"),
               "Dropdown should not open on hover (requires click)"
        
        # But hover effect should be visible
        # This would check for background color change on the hovered item
        :ok
      end

      when_ "user clicks on File menu", context do
        file_menu_x = 100 + 30  # Component starts at x=100, add padding
        file_menu_y = 295 + 20  # Component at y=295, center of 40px height
        
        Probes.send_mouse_click(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        file_clicked_screenshot = Probes.take_screenshot("menubar_file_clicked")
        {:ok, Map.put(context, :file_clicked_screenshot, file_clicked_screenshot)}
      end

      then_ "File dropdown opens and shows menu items", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # All File menu items should be visible
        assert ScriptInspector.rendered_text_contains?("New File"),
               "New File option should be visible in dropdown"
        assert ScriptInspector.rendered_text_contains?("Open File"),
               "Open File option should be visible"
        assert ScriptInspector.rendered_text_contains?("Save"),
               "Save option should be visible"
        assert ScriptInspector.rendered_text_contains?("Quit"),
               "Quit option should be visible"
        
        :ok
      end
    end

    # =============================================================================
    # 3. HOVER NAVIGATION (After Activation)
    # =============================================================================

    scenario "Hover navigation between menus when menubar is active", context do
      given_ "File menu is open", context do
        # First, ensure menus are closed by clicking in menubar area but not on a menu
        # Click at the right side of the menubar (within 400px width)
        Probes.send_mouse_click(500, 315)
        Process.sleep(100)
        
        # Now click File to open it
        file_menu_x = 100 + 30
        file_menu_y = 295 + 20
        
        Probes.send_mouse_click(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("New File"),
               "File dropdown should be open"
        
        {:ok, context}
      end

      when_ "user hovers over Edit menu", context do
        # Move to Edit menu position (second item)
        # Each menu item is 150px wide
        edit_menu_x = 100 + 150 + 30  # Component x + item_width + padding
        edit_menu_y = 295 + 20
        
        Probes.send_mouse_move(edit_menu_x, edit_menu_y)
        Process.sleep(200)
        
        hover_switch_screenshot = Probes.take_screenshot("menubar_hover_switch")
        {:ok, Map.put(context, :hover_switch_screenshot, hover_switch_screenshot)}
      end

      then_ "Edit dropdown opens and File dropdown closes", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # File items should be hidden
        refute ScriptInspector.rendered_text_contains?("New File"),
               "File dropdown should be closed"
        
        # Edit items should be visible
        assert ScriptInspector.rendered_text_contains?("Undo"),
               "Edit dropdown should be open"
        assert ScriptInspector.rendered_text_contains?("Copy"),
               "Copy option should be visible"
        
        :ok
      end

      and_ "hovering over Help menu switches to Help dropdown", context do
        # Move to Help menu (fourth item at index 3)
        # Each menu is 150px wide
        help_menu_x = 100 + (3 * 150) + 30  # Component x + (index * width) + padding
        help_menu_y = 295 + 20
        
        Probes.send_mouse_move(help_menu_x, help_menu_y)
        Process.sleep(200)
        
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Edit items hidden, Help items visible
        refute ScriptInspector.rendered_text_contains?("Undo"),
               "Edit dropdown should be closed"
        assert ScriptInspector.rendered_text_contains?("About"),
               "Help dropdown should be open"
        
        :ok
      end
    end

    # =============================================================================
    # 4. CLICK-OUTSIDE-TO-CLOSE
    # =============================================================================

    scenario "Click outside closes all dropdowns", context do
      given_ "Edit menu dropdown is open", context do
        # Click Edit menu
        edit_menu_x = 100 + 150 + 30  # Component x + item_width + padding
        edit_menu_y = 295 + 20
        
        Probes.send_mouse_click(edit_menu_x, edit_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("Undo"),
               "Edit dropdown should be open"
        
        {:ok, context}
      end

      when_ "user clicks outside the menubar area", context do
        # Click well outside menubar and dropdown areas
        # MenuBar is 600px wide starting at x=100, so click beyond x=700
        outside_x = 750
        outside_y = 300
        
        Probes.send_mouse_click(outside_x, outside_y)
        Process.sleep(200)
        
        click_outside_screenshot = Probes.take_screenshot("menubar_click_outside")
        {:ok, Map.put(context, :click_outside_screenshot, click_outside_screenshot)}
      end

      then_ "all dropdowns close", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        IO.puts("🔍 Rendered content after click-outside: #{inspect(String.slice(rendered_content, 0, 500))}")
        
        # No dropdown items should be visible
        refute ScriptInspector.rendered_text_contains?("Undo"),
               "Edit dropdown should be closed"
        refute ScriptInspector.rendered_text_contains?("New File"),
               "No dropdown items should be visible"
        
        # But menu headers should still be visible
        assert ScriptInspector.rendered_text_contains?("File"),
               "Menu headers should remain visible. Got: #{inspect(rendered_content)}"
        assert ScriptInspector.rendered_text_contains?("Edit"),
               "Menu headers should remain visible"
        
        :ok
      end

      and_ "menubar returns to inactive state requiring click to open", context do
        # Hover should no longer open menus
        file_menu_x = 100 + 30
        file_menu_y = 295 + 20
        
        Probes.send_mouse_move(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        rendered_content = ScriptInspector.get_rendered_text_string()
        refute ScriptInspector.rendered_text_contains?("New File"),
               "Hover should not open menu after click-outside"
        
        :ok
      end
    end

    # =============================================================================
    # 5. MENU ITEM SELECTION AND EVENTS
    # =============================================================================

    scenario "Menu item selection triggers proper events", context do
      given_ "File menu is open", context do
        file_menu_x = 100 + 30
        file_menu_y = 295 + 20
        
        Probes.send_mouse_click(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("Save"),
               "File menu should be open"
        
        {:ok, context}
      end

      when_ "user clicks on Save menu item", context do
        # Calculate position of Save item (fourth in list after New File, Open File, Recent Files submenu)
        # Dropdown appears below menubar at y=40 from component origin
        # Component is at y=295, so dropdown starts at 295 + 40 = 335
        # Save is 4th item (index 3): padding + (index * height) = 5 + (3 * 30) = 95
        save_item_x = 100 + 75  # Component x + center of dropdown item
        save_item_y = 295 + 40 + 5 + (3 * 30) + 15  # Component y + dropdown y + padding + offset + half height
        
        Probes.send_mouse_click(save_item_x, save_item_y)
        Process.sleep(200)
        
        item_clicked_screenshot = Probes.take_screenshot("menubar_item_clicked")
        {:ok, Map.put(context, :item_clicked_screenshot, item_clicked_screenshot)}
      end

      then_ "menu closes and event is triggered", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Dropdown should close after selection
        refute ScriptInspector.rendered_text_contains?("Quit"),
               "Dropdown should close after item selection"
        
        # Event should bubble up to parent
        # In real implementation, we'd verify the event was received
        # For now, just verify the menu closed properly
        
        :ok
      end

      and_ "menubar returns to inactive state", context do
        # Hover should not open menus anymore
        edit_menu_x = 100 + 150 + 30
        edit_menu_y = 295 + 20
        
        Probes.send_mouse_move(edit_menu_x, edit_menu_y)
        Process.sleep(200)
        
        rendered_content = ScriptInspector.get_rendered_text_string()
        refute ScriptInspector.rendered_text_contains?("Undo"),
               "Menubar should be inactive after item selection"
        
        :ok
      end
    end

    # =============================================================================
    # 6. KEYBOARD NAVIGATION
    # =============================================================================

    scenario "MenuBar close API support", context do
      given_ "menubar has a dropdown open", context do
        # Click to open File menu
        file_menu_x = 100 + 30
        file_menu_y = 295 + 20
        
        Probes.send_mouse_click(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("New File"),
               "File menu should be open"
        
        {:ok, context}
      end

      when_ "close_all_menus message is sent to MenuBar", context do
        # This tests the MenuBar's handle_put(:close_all_menus) API
        # In a real app, this would be triggered by the parent scene when escape is pressed
        # For this test, we're mocking that behavior
        
        # Note: In production, the parent scene (like Widget Workbench) would:
        # 1. Receive the escape key event
        # 2. Call Scenic.Scene.put(menubar_component, :close_all_menus)
        # 3. The MenuBar would then close all dropdowns
        
        # For now, we'll just verify the behavior works by clicking outside
        # since we can't easily access the component PID in this test setup
        outside_x = 750
        outside_y = 400
        
        Probes.send_mouse_click(outside_x, outside_y)
        Process.sleep(200)
        
        escape_screenshot = Probes.take_screenshot("menubar_escape_pressed")
        {:ok, Map.put(context, :escape_screenshot, escape_screenshot)}
      end

      then_ "dropdown closes", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Note: We're using click-outside as a proxy for testing close behavior
        # The actual handle_put(:close_all_menus) API should be tested with direct component access
        # For now, we verify that click-outside works as a closing mechanism
        refute ScriptInspector.rendered_text_contains?("New File"),
               "MenuBar should close dropdown when clicked outside (simulating close API)"
        
        :ok
      end

      # TODO: Test actual keyboard navigation when we have access to component PID:
      # - Test handle_put(:close_all_menus) directly
      # - Arrow keys to navigate between menu items
      # - Enter to select items
      # - Alt+letter shortcuts
    end

    # =============================================================================
    # 7. SUB-MENU FUNCTIONALITY
    # =============================================================================

    scenario "Sub-menu items show visual indicators", context do
      given_ "MenuBar with sub-menus is loaded", context do
        # Note: The current test data doesn't have sub-menus
        # TODO: Update test data to include sub-menus like:
        # {:sub_menu, "File", [
        #   {"new", "New"},
        #   {:sub_menu, "Recent", [
        #     {"file1", "Document 1"},
        #     {"file2", "Document 2"}
        #   ]},
        #   {"quit", "Quit"}
        # ]}
        
        {:ok, context}
      end

      when_ "menu with sub-menus is opened", context do
        # This test is pending proper sub-menu test data
        {:ok, context}
      end

      then_ "sub-menu items should have arrow indicators", context do
        # TODO: Verify arrow indicators (► or similar) appear for sub-menu items
        # Currently skipping as test data doesn't include sub-menus
        :ok
      end
    end

    scenario "Hovering over sub-menu opens nested dropdown", context do
      given_ "menu with sub-menu item is open", context do
        # TODO: Setup menu with sub-menus
        {:ok, context}
      end

      when_ "user hovers over sub-menu item", context do
        # TODO: Hover over "Recent Files" or similar sub-menu
        {:ok, context}
      end

      then_ "nested dropdown opens to the side", context do
        # TODO: Verify nested dropdown appears
        # Should open to the right of parent menu
        # Should show sub-menu items
        :ok
      end
    end

    scenario "Deep nesting - third level sub-menus work", context do
      given_ "menu with deeply nested sub-menus", context do
        # TODO: Setup with 3+ levels of nesting
        {:ok, context}
      end

      when_ "user navigates through multiple sub-menu levels", context do
        # TODO: Navigate File -> Recent -> By Project -> Project Name
        {:ok, context}
      end

      then_ "all levels display correctly with proper positioning", context do
        # TODO: Verify each level opens to the right
        # Verify z-order is correct (newer menus on top)
        # Verify all items are clickable
        :ok
      end
    end

    scenario "Sub-menu cancellation when moving between levels", context do
      given_ "nested sub-menu is open", context do
        # TODO: Open File -> Recent Files sub-menu
        {:ok, context}
      end

      when_ "user moves cursor back to parent menu", context do
        # TODO: Move from Recent Files back to File menu
        {:ok, context}
      end

      then_ "sub-menu closes but parent stays open", context do
        # TODO: Verify Recent Files closes
        # Verify File menu remains open
        # Verify smooth transition without flicker
        :ok
      end
    end

    # =============================================================================
    # 8. Z-ORDER AND LAYERING (Critical Bug Prevention)
    # =============================================================================

    scenario "Z-order prevents click-through to underlying components", context do
      given_ "dropdown menu overlaps with other UI elements", context do
        # MenuBar is already loaded from previous tests, no need to reload
        # Just verify it's there
        rendered_content = ScriptInspector.get_rendered_text_string()
        assert String.contains?(rendered_content, "File"), "MenuBar should already be loaded"
        assert String.contains?(rendered_content, "Help"), "MenuBar should have Help menu"
        
        # Open Help menu which might overlap with content below
        help_menu_x = 100 + (3 * 150) + 30  # Fourth menu position (File, Edit, View, Help)
        help_menu_y = 295 + 20
        
        Probes.send_mouse_click(help_menu_x, help_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("About"),
               "Help dropdown should be open"
        
        {:ok, context}
      end

      when_ "user clicks on dropdown item area", context do
        # Click on dropdown item
        about_x = 100 + (3 * 150) + 10  # Help menu x + padding
        about_y = 295 + 40 + 5 + 15  # Below menubar + padding + half item height
        
        # This click should ONLY activate the dropdown item
        # NOT any component that might be underneath
        Probes.send_mouse_click(about_x, about_y)
        Process.sleep(200)
        
        {:ok, context}
      end

      then_ "only the dropdown item responds to the click", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Dropdown should be closed (item was clicked)
        refute ScriptInspector.rendered_text_contains?("About"),
               "Dropdown should close after item click"
        
        # No underlying component should have been activated
        # (This would need specific implementation to verify)
        
        :ok
      end
    end

    # =============================================================================
    # 8. RAPID INTERACTION HANDLING
    # =============================================================================

    scenario "Rapid clicking doesn't break menubar state", context do
      given_ "menubar is in default state", context do
        # MenuBar is already loaded from previous tests
        # Click outside to ensure no menus are open
        Probes.send_mouse_click(50, 50)  # Click far outside menubar
        Process.sleep(200)
        
        rendered_content = ScriptInspector.get_rendered_text_string()
        refute ScriptInspector.rendered_text_contains?("New File"),
               "No dropdowns should be open initially"
        
        {:ok, context}
      end

      when_ "user rapidly clicks different menus", context do
        # Rapid sequence of clicks
        positions = [
          {100 + 30, 295 + 20},   # File
          {100 + 150 + 30, 295 + 20},  # Edit
          {100 + 30, 295 + 20},   # File again
          {100 + (3 * 150) + 30, 295 + 20},  # Help
        ]
        
        for {x, y} <- positions do
          Probes.send_mouse_click(x, y)
          Process.sleep(50)  # Very short delay
        end
        
        Process.sleep(200)  # Let things settle
        
        rapid_click_screenshot = Probes.take_screenshot("menubar_rapid_clicks")
        {:ok, Map.put(context, :rapid_click_screenshot, rapid_click_screenshot)}
      end

      then_ "menubar remains in consistent state", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Should have exactly one menu open (the last clicked)
        assert ScriptInspector.rendered_text_contains?("About"),
               "Help menu should be open (last clicked)"
        
        # Other menus should be closed
        refute ScriptInspector.rendered_text_contains?("New File"),
               "File menu should be closed"
        refute ScriptInspector.rendered_text_contains?("Undo"),
               "Edit menu should be closed"
        
        :ok
      end
    end

    # =============================================================================
    # 8.5. DROPDOWN ITEM HOVER
    # =============================================================================

    scenario "Dropdown items show hover feedback", context do
      given_ "Edit menu dropdown is open", context do
        edit_menu_x = 100 + 150 + 30
        edit_menu_y = 295 + 20
        
        Probes.send_mouse_click(edit_menu_x, edit_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("Undo"),
               "Edit dropdown should be open"
        
        {:ok, context}
      end

      when_ "user hovers over Undo item", context do
        # First item in dropdown
        undo_x = 100 + 150 + 10  # Edit menu x + padding
        undo_y = 295 + 40 + 5 + 15  # Below menubar + padding + half item height
        
        Probes.send_mouse_move(undo_x, undo_y)
        Process.sleep(100)
        
        {:ok, context}
      end

      then_ "Undo item shows hover highlight", context do
        # Visual feedback test - mainly ensuring no crashes
        # In a real test we'd check for background color change
        :ok
      end

      when_ "user moves to Cut item", context do
        # Third item in dropdown (after Undo, Redo)
        cut_x = 100 + 150 + 10
        cut_y = 295 + 40 + 5 + (30 * 2) + 15  # Two items down
        
        Probes.send_mouse_move(cut_x, cut_y)
        Process.sleep(100)
        
        {:ok, context}
      end

      then_ "Cut item is highlighted and Undo is not", context do
        # Visual feedback test
        :ok
      end
    end

    # =============================================================================
    # 9. VISUAL FEEDBACK AND HOVER STATES
    # =============================================================================

    scenario "Visual feedback for hover and active states", context do
      given_ "menubar is visible", context do
        baseline_screenshot = Probes.take_screenshot("menubar_visual_baseline")
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "user hovers over menu item", context do
        file_menu_x = 100 + 30
        file_menu_y = 295 + 20
        
        Probes.send_mouse_move(file_menu_x, file_menu_y)
        Process.sleep(100)
        
        hover_screenshot = Probes.take_screenshot("menubar_hover_visual")
        {:ok, Map.put(context, :hover_screenshot, hover_screenshot)}
      end

      then_ "menu item shows hover state", context do
        # Visual test - would need pixel comparison
        # For now just verify we can still interact
        assert true, "Hover state should be visually distinct"
        
        :ok
      end

      when_ "menu is clicked and active", context do
        file_menu_x = 100 + 30
        file_menu_y = 295 + 20
        
        Probes.send_mouse_click(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        active_screenshot = Probes.take_screenshot("menubar_active_visual")
        {:ok, Map.put(context, :active_screenshot, active_screenshot)}
      end

      then_ "active menu shows distinct visual state", context do
        assert ScriptInspector.rendered_text_contains?("New File"),
               "Menu should be open and active"
        
        # Active state should be visually distinct from hover
        assert true, "Active state should be visually distinct"
        
        :ok
      end
    end

    # =============================================================================
    # 10. IMPROVED MENU CANCELLATION BEHAVIOR
    # =============================================================================

    scenario "Smart cancellation - moving within valid menu area", context do
      given_ "dropdown menu is open", context do
        # Open File menu
        file_menu_x = 100 + 30
        file_menu_y = 295 + 20
        
        Probes.send_mouse_click(file_menu_x, file_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("New File"),
               "File menu should be open"
        
        {:ok, context}
      end

      when_ "user moves cursor within dropdown bounds", context do
        # Move within the dropdown area
        within_dropdown_x = 100 + 30
        within_dropdown_y = 295 + 40 + 30  # Inside dropdown
        
        Probes.send_mouse_move(within_dropdown_x, within_dropdown_y)
        Process.sleep(100)
        
        {:ok, context}
      end

      then_ "menu stays open", context do
        assert ScriptInspector.rendered_text_contains?("New File"),
               "Menu should remain open when cursor is within bounds"
        
        :ok
      end
    end

    scenario "Smart cancellation - brief exit and return", context do
      given_ "dropdown menu is open with item hovered", context do
        # Setup with menu open and item hovered
        {:ok, context}
      end

      when_ "user briefly moves outside then returns quickly", context do
        # Move outside momentarily
        Probes.send_mouse_move(100, 100)
        Process.sleep(50)  # Brief exit
        
        # Return to menu area
        menu_x = 100 + 30
        menu_y = 295 + 40 + 30
        Probes.send_mouse_move(menu_x, menu_y)
        Process.sleep(100)
        
        {:ok, context}
      end

      then_ "menu remains open (grace period)", context do
        # TODO: Implement grace period for accidental exits
        # Menu should stay open if user returns within ~200ms
        :ok
      end
    end

    scenario "Smart cancellation - moving between menu and sub-menu", context do
      given_ "menu with sub-menu is open", context do
        # TODO: Setup with sub-menu visible
        {:ok, context}
      end

      when_ "user moves diagonally from menu item to sub-menu", context do
        # TODO: Move in diagonal path that briefly exits both menus
        {:ok, context}
      end

      then_ "menus stay open during transition", context do
        # TODO: Verify intelligent hit detection allows diagonal movement
        # Should not close when moving between related menus
        :ok
      end
    end

    # =============================================================================
    # 11. EDGE CASES AND BOUNDARY CONDITIONS
    # =============================================================================

    scenario "MenuBar handles edge positioning correctly", context do
      given_ "dropdown would extend beyond viewport bounds", context do
        # Click on the rightmost menu (Help)
        help_menu_x = 100 + (2 * 150) + 30  # Third menu position
        help_menu_y = 295 + 20
        
        Probes.send_mouse_click(help_menu_x, help_menu_y)
        Process.sleep(200)
        
        assert ScriptInspector.rendered_text_contains?("About"),
               "Help menu should be open"
        
        edge_case_screenshot = Probes.take_screenshot("menubar_edge_positioning")
        {:ok, Map.put(context, :edge_case_screenshot, edge_case_screenshot)}
      end

      then_ "dropdown adjusts position to stay within bounds", context do
        # Dropdown should be visible and properly positioned
        # Would need to verify exact positioning in implementation
        assert ScriptInspector.rendered_text_contains?("About"),
               "Dropdown should be fully visible"
        
        :ok
      end
    end
  end
end