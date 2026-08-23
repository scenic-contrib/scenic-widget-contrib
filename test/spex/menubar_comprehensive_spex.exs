defmodule ScenicWidgets.MenuBarComprehensiveSpex do
  @moduledoc """
  COMPREHENSIVE MenuBar Spex for ScenicWidgets - Complete desktop menubar functionality.

  This spex covers ALL essential menubar operations that any desktop application should support.
  It serves as both specification and acceptance tests for production-ready MenuBar features.

  ## Feature Coverage:
  1. Basic Menu Operations (click-to-open, close behaviors)
  2. Hover Navigation (post-activation hover switching)
  3. Keyboard Navigation (Alt activation, arrow keys, mnemonics)
  4. Menu Item Types (standard, toggle, radio, separators, submenus)
  5. Visual Feedback (highlights, active states, disabled states)
  6. Selection & Action Execution (callbacks, state changes)
  7. Z-Order & Modal Behavior (layering, click-outside-to-close)
  8. Multi-Menu Navigation (seamless switching between menus)
  9. Edge Cases (rapid interactions, boundary conditions)
  10. Accessibility Features (screen reader support, high contrast)
  11. Error Handling (malformed data, missing callbacks)
  12. Performance (large menus, deep nesting)

  Success Criteria: ALL scenarios must pass for MenuBar to be considered feature-complete
  at the desktop application level (equivalent to Windows/macOS/Linux native menubars).
  """
  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}
  alias ScenicMcp.Probes

  @tmp_screenshots_dir "test/spex/screenshots/menubar"

  setup_all do
    # Start Widget Workbench with proper viewport
    SexySpex.Helpers.start_scenic_app(:scenic_widget_contrib)
    
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
    
    # Create screenshots directory
    File.mkdir_p!(@tmp_screenshots_dir)
    
    :ok
  end

  spex "Comprehensive MenuBar Operations - Complete Desktop Menubar Functionality",
    description: "Validates ALL essential menubar features for production-ready desktop applications",
    tags: [:comprehensive, :menubar, :core_functionality, :ai_driven] do

    # =============================================================================
    # 1. BASIC MENU OPERATIONS
    # =============================================================================

    scenario "Basic menu click-to-open pattern", context do
      given_ "MenuBar is loaded in Widget Workbench", context do
        case SemanticUI.load_component("Menu Bar") do
          {:ok, load_result} ->
            Process.sleep(500)  # Let animations settle
            baseline_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/basic_menu_baseline.png")
            {:ok, Map.merge(context, %{
              load_result: load_result,
              baseline_screenshot: baseline_screenshot
            })}
          {:error, reason} ->
            {:error, "Failed to load MenuBar: #{reason}"}
        end
      end

      when_ "user clicks on File menu", context do
        # Find and click the File menu
        case SemanticUI.click_menu_item("File") do
          {:ok, click_result} ->
            Process.sleep(200)  # Allow dropdown animation
            menu_open_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/file_menu_open.png")
            {:ok, Map.merge(context, %{
              click_result: click_result,
              menu_open_screenshot: menu_open_screenshot
            })}
          {:error, reason} ->
            {:error, "Failed to click File menu: #{reason}"}
        end
      end

      then_ "File menu dropdown should be visible with menu items", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Verify dropdown is open
        assert ScriptInspector.rendered_text_contains?("New"),
               "File menu should show 'New' option"
        assert ScriptInspector.rendered_text_contains?("Open"),
               "File menu should show 'Open' option"
        assert ScriptInspector.rendered_text_contains?("Save"),
               "File menu should show 'Save' option"
        
        # Verify menu structure from SemanticUI
        menu_state = SemanticUI.get_menu_state()
        assert menu_state.active_menu == "File",
               "File menu should be marked as active"
        assert menu_state.dropdown_visible == true,
               "Dropdown should be visible"
        
        :ok
      end
    end

    scenario "Click outside to close menu", context do
      given_ "File menu is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        
        assert SemanticUI.get_menu_state().dropdown_visible == true,
               "Precondition: File menu should be open"
        
        {:ok, context}
      end

      when_ "user clicks outside the menu area", context do
        # Click in empty space well away from menu
        Probes.send_mouse_click(600, 400)
        Process.sleep(200)
        
        outside_click_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/click_outside.png")
        {:ok, Map.put(context, :outside_click_screenshot, outside_click_screenshot)}
      end

      then_ "menu should close and no dropdown visible", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.dropdown_visible == false,
               "Dropdown should be closed after clicking outside"
        assert menu_state.active_menu == nil,
               "No menu should be active"
        
        # Verify visually
        refute ScriptInspector.rendered_text_contains?("New"),
               "Menu items should not be visible"
        
        :ok
      end
    end

    scenario "Menu stays open until interaction", context do
      given_ "Edit menu is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("Edit")
        Process.sleep(200)
        
        {:ok, Map.put(context, :menu_open_time, System.monotonic_time(:millisecond))}
      end

      when_ "user waits without any interaction for 3 seconds", context do
        Process.sleep(3000)
        still_open_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/menu_still_open.png")
        {:ok, Map.put(context, :still_open_screenshot, still_open_screenshot)}
      end

      then_ "menu should still be open", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.dropdown_visible == true,
               "Menu should remain open without user interaction"
        assert menu_state.active_menu == "Edit",
               "Edit menu should still be active"
        
        # Verify menu items still visible
        assert ScriptInspector.rendered_text_contains?("Cut"),
               "Edit menu items should still be visible"
        
        :ok
      end
    end

    # =============================================================================
    # 2. HOVER NAVIGATION (POST-ACTIVATION)
    # =============================================================================

    scenario "Hover switching between menus after activation", context do
      given_ "File menu is already open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        
        assert SemanticUI.get_menu_state().active_menu == "File",
               "File menu should be active"
        
        {:ok, context}
      end

      when_ "user hovers over Edit menu", context do
        # Move mouse to Edit menu position
        edit_pos = SemanticUI.get_menu_item_position("Edit")
        Probes.send_mouse_move(edit_pos.x, edit_pos.y)
        Process.sleep(300)  # Allow hover delay
        
        hover_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/hover_switch.png")
        {:ok, Map.put(context, :hover_screenshot, hover_screenshot)}
      end

      then_ "Edit menu should open and File menu should close", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.active_menu == "Edit",
               "Edit menu should now be active"
        assert menu_state.dropdown_visible == true,
               "Dropdown should still be visible"
        
        # Verify correct menu items
        assert ScriptInspector.rendered_text_contains?("Cut"),
               "Edit menu items should be visible"
        refute ScriptInspector.rendered_text_contains?("New"),
               "File menu items should not be visible"
        
        :ok
      end
    end

    scenario "No hover activation when menubar is inactive", context do
      given_ "MenuBar is loaded but no menu is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        
        assert SemanticUI.get_menu_state().dropdown_visible == false,
               "No menu should be open initially"
        
        {:ok, context}
      end

      when_ "user hovers over View menu without clicking", context do
        view_pos = SemanticUI.get_menu_item_position("View")
        Probes.send_mouse_move(view_pos.x, view_pos.y)
        Process.sleep(500)  # Wait longer than hover delay
        
        hover_no_activation_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/hover_no_activation.png")
        {:ok, Map.put(context, :screenshot, hover_no_activation_screenshot)}
      end

      then_ "menu should not open, only show hover highlight", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.dropdown_visible == false,
               "Dropdown should not open on hover when menubar inactive"
        assert menu_state.active_menu == nil,
               "No menu should be active"
        assert menu_state.hovered_item == "View",
               "View should be highlighted on hover"
        
        :ok
      end
    end

    scenario "Moving cursor away from menubar closes all menus", context do
      given_ "View menu is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        {:ok, context}
      end

      when_ "user moves cursor far from menubar", context do
        # Move to bottom of screen, away from menubar
        Probes.send_mouse_move(600, 700)
        Process.sleep(500)  # Allow close animation
        
        moved_away_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/moved_away.png")
        {:ok, Map.put(context, :screenshot, moved_away_screenshot)}
      end

      then_ "all menus should close", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.dropdown_visible == false,
               "Dropdown should close when cursor moves away"
        assert menu_state.active_menu == nil,
               "No menu should be active"
        assert menu_state.hovered_item == nil,
               "No item should be hovered"
        
        :ok
      end
    end

    # =============================================================================
    # 3. KEYBOARD NAVIGATION
    # =============================================================================

    scenario "Alt key activation and navigation", context do
      given_ "MenuBar is loaded with no active menu", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "user presses Alt key", context do
        Probes.send_keys("alt", [:alt])
        Process.sleep(100)
        
        alt_activated_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/alt_activated.png")
        {:ok, Map.put(context, :screenshot, alt_activated_screenshot)}
      end

      then_ "menubar should be activated with underlined accelerators", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.keyboard_active == true,
               "Menubar should be keyboard activated"
        assert menu_state.show_accelerators == true,
               "Accelerator underlines should be visible"
        
        # Verify accelerator keys are shown (usually underlined letters)
        rendered = ScriptInspector.get_rendered_content()
        assert Enum.any?(rendered.text_decorations, &(&1.type == :underline)),
               "Accelerator underlines should be rendered"
        
        :ok
      end
    end

    scenario "Arrow key navigation between menu items", context do
      given_ "File menu is open with keyboard activation", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        Probes.send_keys("alt", [:alt])
        Process.sleep(100)
        Probes.send_keys("f", [])  # Alt+F to open File menu
        Process.sleep(200)
        
        {:ok, context}
      end

      when_ "user presses right arrow key", context do
        Probes.send_keys("right", [])
        Process.sleep(200)
        
        right_arrow_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/arrow_right.png")
        {:ok, Map.put(context, :screenshot, right_arrow_screenshot)}
      end

      then_ "Edit menu should open instead", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.active_menu == "Edit",
               "Edit menu should be active after right arrow"
        assert ScriptInspector.rendered_text_contains?("Cut"),
               "Edit menu items should be visible"
        refute ScriptInspector.rendered_text_contains?("New"),
               "File menu items should not be visible"
        
        :ok
      end
    end

    scenario "Escape key closes dropdown and deactivates menubar", context do
      given_ "Edit menu is open via keyboard", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        Probes.send_keys("alt", [:alt])
        Probes.send_keys("e", [])  # Alt+E for Edit
        Process.sleep(200)
        
        {:ok, context}
      end

      when_ "user presses Escape twice", context do
        # First escape closes dropdown
        Probes.send_keys("escape", [])
        Process.sleep(200)
        first_escape_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/first_escape.png")
        
        # Second escape deactivates menubar
        Probes.send_keys("escape", [])
        Process.sleep(200)
        second_escape_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/second_escape.png")
        
        {:ok, Map.merge(context, %{
          first_escape: first_escape_screenshot,
          second_escape: second_escape_screenshot
        })}
      end

      then_ "dropdown closes first, then menubar deactivates", context do
        # After first escape
        state_after_first = SemanticUI.get_menu_state_at_screenshot(context.first_escape)
        assert state_after_first.dropdown_visible == false,
               "Dropdown should close after first Escape"
        assert state_after_first.keyboard_active == true,
               "Menubar should still be keyboard active"
        
        # After second escape
        final_state = SemanticUI.get_menu_state()
        assert final_state.keyboard_active == false,
               "Menubar should be deactivated after second Escape"
        assert final_state.show_accelerators == false,
               "Accelerators should no longer be visible"
        
        :ok
      end
    end

    scenario "Enter key selects menu items", context do
      given_ "File menu is open with New item highlighted", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        
        # Ensure New is highlighted (first item)
        menu_state = SemanticUI.get_menu_state()
        assert menu_state.highlighted_item == "New",
               "New should be highlighted by default"
        
        {:ok, context}
      end

      when_ "user presses Enter", context do
        Probes.send_keys("return", [])  # Enter key
        Process.sleep(200)
        
        enter_pressed_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/enter_pressed.png")
        {:ok, Map.put(context, :screenshot, enter_pressed_screenshot)}
      end

      then_ "New action should be triggered and menu closed", context do
        # Verify action was triggered
        action_log = SemanticUI.get_action_log()
        assert Enum.any?(action_log, &(&1.action == "file_new")),
               "File > New action should be triggered"
        
        # Verify menu closed
        menu_state = SemanticUI.get_menu_state()
        assert menu_state.dropdown_visible == false,
               "Menu should close after selection"
        
        :ok
      end
    end

    # =============================================================================
    # 4. MENU ITEM TYPES
    # =============================================================================

    scenario "Standard action menu items", context do
      given_ "File menu with standard action items is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "user clicks on Save item", context do
        SemanticUI.click_dropdown_item("Save")
        Process.sleep(200)
        
        save_clicked_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/save_clicked.png")
        {:ok, Map.put(context, :screenshot, save_clicked_screenshot)}
      end

      then_ "Save action executes and menu closes", context do
        action_log = SemanticUI.get_action_log()
        last_action = List.last(action_log)
        
        assert last_action.action == "file_save",
               "Save action should be executed"
        assert last_action.type == :standard,
               "Should be a standard action item"
        
        assert SemanticUI.get_menu_state().dropdown_visible == false,
               "Menu should close after action"
        
        :ok
      end
    end

    scenario "Toggle menu items with checkmarks", context do
      given_ "View menu with toggle items is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        # Get initial state of toggle item
        initial_state = SemanticUI.get_menu_item_state("Show Toolbar")
        {:ok, Map.put(context, :initial_checked, initial_state.checked)}
      end

      when_ "user clicks on Show Toolbar toggle item", context do
        SemanticUI.click_dropdown_item("Show Toolbar")
        Process.sleep(200)
        
        # Reopen menu to see new state
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        toggle_clicked_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/toggle_clicked.png")
        {:ok, Map.put(context, :screenshot, toggle_clicked_screenshot)}
      end

      then_ "toggle state should change and show checkmark", context do
        current_state = SemanticUI.get_menu_item_state("Show Toolbar")
        
        assert current_state.checked != context.initial_checked,
               "Toggle state should change"
        assert current_state.type == :toggle,
               "Should be a toggle menu item"
        
        if current_state.checked do
          assert ScriptInspector.rendered_text_contains?("✓"),
               "Checkmark should be visible when checked"
        else
          refute ScriptInspector.rendered_text_contains?("✓"),
               "Checkmark should not be visible when unchecked"
        end
        
        :ok
      end
    end

    scenario "Radio menu items with mutual exclusion", context do
      given_ "View menu with zoom level radio group is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        # Find which zoom level is currently selected
        zoom_items = SemanticUI.get_radio_group_state("zoom_level")
        {:ok, Map.put(context, :initial_zoom, zoom_items)}
      end

      when_ "user selects 150% zoom level", context do
        SemanticUI.click_dropdown_item("150%")
        Process.sleep(200)
        
        # Reopen to verify state
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        radio_selected_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/radio_selected.png")
        {:ok, Map.put(context, :screenshot, radio_selected_screenshot)}
      end

      then_ "only 150% should be selected in the radio group", context do
        zoom_items = SemanticUI.get_radio_group_state("zoom_level")
        
        # Verify only one item is selected
        selected_items = Enum.filter(zoom_items, & &1.selected)
        assert length(selected_items) == 1,
               "Exactly one radio item should be selected"
        
        # Verify it's the right one
        assert hd(selected_items).label == "150%",
               "150% should be the selected item"
        
        # Verify visual indicator
        assert ScriptInspector.rendered_text_contains?("● 150%") or
               ScriptInspector.rendered_text_contains?("◉ 150%"),
               "Radio button indicator should be shown for 150%"
        
        :ok
      end
    end

    scenario "Separator items for logical grouping", context do
      given_ "File menu with separators is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "examining menu structure", context do
        menu_structure = SemanticUI.get_menu_structure("File")
        separator_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/separators.png")
        {:ok, Map.merge(context, %{
          menu_structure: menu_structure,
          screenshot: separator_screenshot
        })}
      end

      then_ "separators should divide menu into logical groups", context do
        structure = context.menu_structure
        
        # Find separator positions
        separator_indices = structure
        |> Enum.with_index()
        |> Enum.filter(fn {item, _} -> item.type == :separator end)
        |> Enum.map(fn {_, idx} -> idx end)
        
        assert length(separator_indices) >= 2,
               "Should have at least 2 separators for grouping"
        
        # Verify separators create logical groups
        # Group 1: New, Open, Save operations
        # Group 2: Print operations  
        # Group 3: Exit
        first_sep = hd(separator_indices)
        assert first_sep > 2,
               "First separator should come after basic file operations"
        
        # Verify separator rendering
        rendered = ScriptInspector.get_rendered_graphics()
        horizontal_lines = Enum.filter(rendered, fn graphic ->
          graphic.type == :line and graphic.orientation == :horizontal
        end)
        
        assert length(horizontal_lines) >= length(separator_indices),
               "Separators should be rendered as horizontal lines"
        
        :ok
      end
    end

    scenario "Submenu items with nested menus", context do
      given_ "File menu with Recent Files submenu is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "user hovers over Recent Files submenu item", context do
        item_pos = SemanticUI.get_dropdown_item_position("Recent Files")
        Probes.send_mouse_move(item_pos.x, item_pos.y)
        Process.sleep(300)  # Allow submenu to open
        
        submenu_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/submenu_open.png")
        {:ok, Map.put(context, :screenshot, submenu_screenshot)}
      end

      then_ "submenu should open to the side with arrow indicator", context do
        # Verify submenu indicator
        item_state = SemanticUI.get_menu_item_state("Recent Files")
        assert item_state.type == :submenu,
               "Should be identified as submenu item"
        assert item_state.has_arrow == true,
               "Submenu items should have arrow indicator"
        
        # Verify submenu is open
        submenu_state = SemanticUI.get_submenu_state("Recent Files")
        assert submenu_state.visible == true,
               "Submenu should be visible"
        assert submenu_state.position == :right,
               "Submenu should open to the right of parent"
        
        # Verify submenu items
        assert ScriptInspector.rendered_text_contains?("document1.txt"),
               "Recent files should be shown in submenu"
        
        :ok
      end
    end

    # =============================================================================
    # 5. VISUAL FEEDBACK
    # =============================================================================

    scenario "Menu item hover highlighting", context do
      given_ "Edit menu is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("Edit")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "user hovers over different menu items", context do
        screenshots = []
        
        # Hover over Cut
        cut_pos = SemanticUI.get_dropdown_item_position("Cut")
        Probes.send_mouse_move(cut_pos.x, cut_pos.y)
        Process.sleep(100)
        screenshots = screenshots ++ [Probes.take_screenshot("#{@tmp_screenshots_dir}/hover_cut.png")]
        
        # Hover over Copy
        copy_pos = SemanticUI.get_dropdown_item_position("Copy")
        Probes.send_mouse_move(copy_pos.x, copy_pos.y)
        Process.sleep(100)
        screenshots = screenshots ++ [Probes.take_screenshot("#{@tmp_screenshots_dir}/hover_copy.png")]
        
        {:ok, Map.put(context, :screenshots, screenshots)}
      end

      then_ "hovered items should be visually highlighted", context do
        # Check Cut hover state
        cut_style = SemanticUI.get_item_style_at_screenshot(hd(context.screenshots), "Cut")
        assert cut_style.background != cut_style.default_background,
               "Cut should have different background when hovered"
        assert cut_style.has_highlight == true,
               "Cut should be highlighted"
        
        # Verify only one item highlighted at a time
        all_items = SemanticUI.get_all_menu_items_state()
        highlighted_items = Enum.filter(all_items, & &1.highlighted)
        assert length(highlighted_items) == 1,
               "Only one item should be highlighted at a time"
        
        :ok
      end
    end

    scenario "Active menu visual distinction", context do
      given_ "MenuBar with multiple menus loaded", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "File menu is activated", context do
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        
        active_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/menu_active.png")
        {:ok, Map.put(context, :screenshot, active_screenshot)}
      end

      then_ "File menu should have distinct active styling", context do
        menu_styles = SemanticUI.get_menubar_item_styles()
        file_style = Enum.find(menu_styles, &(&1.label == "File"))
        edit_style = Enum.find(menu_styles, &(&1.label == "Edit"))
        
        assert file_style.is_active == true,
               "File should be marked as active"
        assert edit_style.is_active == false,
               "Edit should not be active"
        
        # Verify visual differences
        assert file_style.background != edit_style.background,
               "Active menu should have different background"
        assert file_style.border_visible == true,
               "Active menu might have visible border"
        
        :ok
      end
    end

    scenario "Disabled menu items appearance and behavior", context do
      given_ "Edit menu with some disabled items is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        
        # Configure menu to have disabled items
        SemanticUI.set_menu_item_enabled("Edit", "Cut", false)
        SemanticUI.set_menu_item_enabled("Edit", "Copy", false)
        
        SemanticUI.click_menu_item("Edit")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "user attempts to click disabled Cut item", context do
        SemanticUI.click_dropdown_item("Cut")
        Process.sleep(200)
        
        disabled_click_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/disabled_click.png")
        {:ok, Map.put(context, :screenshot, disabled_click_screenshot)}
      end

      then_ "disabled items should be visually distinct and non-interactive", context do
        cut_state = SemanticUI.get_menu_item_state("Cut")
        
        assert cut_state.enabled == false,
               "Cut should be disabled"
        assert cut_state.clickable == false,
               "Disabled items should not be clickable"
        
        # Verify visual styling
        cut_style = SemanticUI.get_item_current_style("Cut")
        assert cut_style.opacity < 1.0,
               "Disabled items should have reduced opacity"
        assert cut_style.text_color != cut_style.normal_text_color,
               "Disabled items should have different text color"
        
        # Verify no action was triggered
        action_log = SemanticUI.get_action_log()
        refute Enum.any?(action_log, &(&1.action == "edit_cut")),
               "Cut action should not be triggered when disabled"
        
        # Verify menu stays open
        assert SemanticUI.get_menu_state().dropdown_visible == true,
               "Menu should stay open after clicking disabled item"
        
        :ok
      end
    end

    # =============================================================================
    # 6. SELECTION & ACTION EXECUTION
    # =============================================================================

    scenario "Menu item callbacks and state changes", context do
      given_ "MenuBar with configured callbacks", context do
        # Set up action callbacks
        SemanticUI.configure_menu_callbacks(%{
          "file_new" => fn -> {:ok, :new_document_created} end,
          "file_save" => fn -> {:ok, :document_saved} end,
          "edit_undo" => fn -> {:ok, :action_undone} end
        })
        
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "user selects File > New", context do
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        SemanticUI.click_dropdown_item("New")
        Process.sleep(200)
        
        callback_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/callback_executed.png")
        {:ok, Map.put(context, :screenshot, callback_screenshot)}
      end

      then_ "callback should execute with correct return value", context do
        callback_results = SemanticUI.get_callback_results()
        last_result = List.last(callback_results)
        
        assert last_result.action == "file_new",
               "File New action should be recorded"
        assert last_result.result == {:ok, :new_document_created},
               "Callback should return expected value"
        assert last_result.timestamp != nil,
               "Callback execution should be timestamped"
        
        :ok
      end
    end

    scenario "Toggle state persistence across menu opens", context do
      given_ "View menu with Show Grid toggle checked", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        
        # Set initial toggle state
        SemanticUI.set_toggle_state("View", "Show Grid", true)
        
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        initial_state = SemanticUI.get_menu_item_state("Show Grid")
        assert initial_state.checked == true
        
        # Close menu
        Probes.send_keys("escape", [])
        Process.sleep(200)
        
        {:ok, Map.put(context, :initial_state, initial_state)}
      end

      when_ "menu is reopened after toggle change", context do
        # Reopen menu
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        # Toggle the item
        SemanticUI.click_dropdown_item("Show Grid")
        Process.sleep(200)
        
        # Open menu again to check state
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        persistence_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/toggle_persistence.png")
        {:ok, Map.put(context, :screenshot, persistence_screenshot)}
      end

      then_ "toggle state should persist correctly", context do
        current_state = SemanticUI.get_menu_item_state("Show Grid")
        
        assert current_state.checked == false,
               "Toggle should be unchecked after clicking"
        assert current_state.checked != context.initial_state.checked,
               "Toggle state should have changed"
        
        # Close and reopen once more to verify persistence
        Probes.send_keys("escape", [])
        Process.sleep(200)
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        final_state = SemanticUI.get_menu_item_state("Show Grid")
        assert final_state.checked == current_state.checked,
               "Toggle state should persist across menu opens"
        
        :ok
      end
    end

    # =============================================================================
    # 7. Z-ORDER & MODAL BEHAVIOR
    # =============================================================================

    scenario "Menu dropdowns appear above all content", context do
      given_ "Complex UI with overlapping elements loaded", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        
        # Add some overlapping content
        SemanticUI.add_overlay_content([
          %{type: :dialog, z_index: 100, position: {100, 50}},
          %{type: :tooltip, z_index: 200, position: {150, 100}}
        ])
        
        {:ok, context}
      end

      when_ "File menu dropdown opens", context do
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        
        z_order_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/z_order.png")
        {:ok, Map.put(context, :screenshot, z_order_screenshot)}
      end

      then_ "menu dropdown should render above all other elements", context do
        render_layers = SemanticUI.get_render_layers()
        menu_layer = Enum.find(render_layers, &(&1.type == :menu_dropdown))
        
        assert menu_layer != nil,
               "Menu dropdown layer should exist"
        
        # Verify z-index
        other_layers = Enum.reject(render_layers, &(&1.type == :menu_dropdown))
        max_other_z = other_layers |> Enum.map(& &1.z_index) |> Enum.max()
        
        assert menu_layer.z_index > max_other_z,
               "Menu dropdown should have highest z-index"
        
        # Verify visual overlap
        overlap_test = SemanticUI.test_visual_overlap(menu_layer, other_layers)
        assert overlap_test.menu_on_top == true,
               "Menu should visually appear above other elements"
        
        :ok
      end
    end

    scenario "Modal input capture while menu is open", context do
      given_ "Edit menu is open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("Edit")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "user tries to interact with content behind menu", context do
        # Try to click on a button that's behind the dropdown
        background_button_pos = SemanticUI.get_element_position("background_button")
        Probes.send_mouse_click(background_button_pos.x, background_button_pos.y)
        Process.sleep(200)
        
        # Also try keyboard input
        Probes.send_text("test")
        Process.sleep(100)
        
        modal_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/modal_behavior.png")
        {:ok, Map.put(context, :screenshot, modal_screenshot)}
      end

      then_ "menu should capture all input, background stays inactive", context do
        # Verify menu is still open
        assert SemanticUI.get_menu_state().dropdown_visible == true,
               "Menu should remain open"
        
        # Verify background button wasn't clicked
        button_state = SemanticUI.get_element_state("background_button")
        assert button_state.clicked == false,
               "Background button should not receive click"
        
        # Verify text input wasn't processed by background
        background_text = SemanticUI.get_background_text_input()
        assert background_text == "",
               "Background should not receive text input"
        
        # Verify input event log
        input_log = SemanticUI.get_input_event_log()
        menu_events = Enum.filter(input_log, &(&1.target == :menu))
        assert length(menu_events) > 0,
               "Menu should have captured input events"
        
        :ok
      end
    end

    # =============================================================================
    # 8. MULTI-MENU NAVIGATION
    # =============================================================================

    scenario "Seamless navigation across multiple menus", context do
      given_ "MenuBar with File menu open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        {:ok, context}
      end

      when_ "user navigates through all menus using hover", context do
        navigation_screenshots = []
        
        # Hover through each menu
        menus = ["Edit", "View", "Tools", "Help", "File"]
        
        Enum.each(menus, fn menu ->
          menu_pos = SemanticUI.get_menu_item_position(menu)
          Probes.send_mouse_move(menu_pos.x, menu_pos.y)
          Process.sleep(150)  # Quick navigation
          
          screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/nav_#{menu}.png")
          navigation_screenshots = navigation_screenshots ++ [{menu, screenshot}]
        end)
        
        {:ok, Map.put(context, :navigation_screenshots, navigation_screenshots)}
      end

      then_ "each menu should open smoothly without flicker", context do
        # Verify each menu opened correctly
        Enum.each(context.navigation_screenshots, fn {menu, screenshot} ->
          state = SemanticUI.get_menu_state_at_screenshot(screenshot)
          assert state.active_menu == menu,
                 "#{menu} should be active during navigation"
          assert state.dropdown_visible == true,
                 "Dropdown should remain visible during navigation"
        end)
        
        # Verify smooth transitions
        transition_analysis = SemanticUI.analyze_transitions(context.navigation_screenshots)
        assert transition_analysis.max_flicker_frames == 0,
               "No flicker frames should occur during navigation"
        assert transition_analysis.all_smooth == true,
               "All transitions should be smooth"
        
        :ok
      end
    end

    scenario "Keyboard navigation wrapping at menu ends", context do
      given_ "Help menu (last menu) is active via keyboard", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        Probes.send_keys("alt", [:alt])
        Probes.send_keys("h", [])  # Alt+H for Help
        Process.sleep(200)
        {:ok, context}
      end

      when_ "user presses right arrow to go past last menu", context do
        Probes.send_keys("right", [])
        Process.sleep(200)
        
        wrap_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/menu_wrap.png")
        {:ok, Map.put(context, :screenshot, wrap_screenshot)}
      end

      then_ "navigation should wrap to File menu (first menu)", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.active_menu == "File",
               "Should wrap from Help to File menu"
        assert menu_state.dropdown_visible == true,
               "Dropdown should remain open during wrap"
        assert ScriptInspector.rendered_text_contains?("New"),
               "File menu items should be visible"
        
        :ok
      end
    end

    # =============================================================================
    # 9. EDGE CASES
    # =============================================================================

    scenario "Rapid clicking between menus", context do
      given_ "MenuBar is loaded and ready", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "user rapidly clicks between different menus", context do
        click_sequence = [
          {"File", 50},
          {"Edit", 50},
          {"View", 50},
          {"File", 50},
          {"Help", 50}
        ]
        
        Enum.each(click_sequence, fn {menu, delay} ->
          SemanticUI.click_menu_item(menu)
          Process.sleep(delay)  # Very short delay
        end)
        
        rapid_click_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/rapid_clicks.png")
        {:ok, Map.put(context, :screenshot, rapid_click_screenshot)}
      end

      then_ "menu should handle rapid changes gracefully", context do
        final_state = SemanticUI.get_menu_state()
        
        # Should end up with Help menu open
        assert final_state.active_menu == "Help",
               "Last clicked menu should be active"
        assert final_state.dropdown_visible == true,
               "Menu should still be functional"
        
        # Check for animation issues
        animation_state = SemanticUI.get_animation_state()
        assert animation_state.pending_animations == 0,
               "No animations should be stuck pending"
        assert animation_state.has_visual_artifacts == false,
               "No visual artifacts from rapid clicking"
        
        :ok
      end
    end

    scenario "Clicking menu while dropdown is animating", context do
      given_ "File menu is starting to open", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        
        # Click File and immediately prepare for next action
        SemanticUI.click_menu_item("File")
        Process.sleep(25)  # Mid-animation
        
        {:ok, context}
      end

      when_ "user clicks Edit menu during File animation", context do
        SemanticUI.click_menu_item("Edit")
        Process.sleep(300)  # Let new animation complete
        
        mid_animation_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/mid_animation.png")
        {:ok, Map.put(context, :screenshot, mid_animation_screenshot)}
      end

      then_ "File animation should cancel and Edit should open cleanly", context do
        menu_state = SemanticUI.get_menu_state()
        
        assert menu_state.active_menu == "Edit",
               "Edit menu should be active"
        assert menu_state.dropdown_visible == true,
               "Dropdown should be visible"
        
        # Verify no File menu items visible
        refute ScriptInspector.rendered_text_contains?("New"),
               "File menu items should not be visible"
        assert ScriptInspector.rendered_text_contains?("Cut"),
               "Edit menu items should be visible"
        
        # Check animation state
        animation_state = SemanticUI.get_animation_state()
        assert animation_state.cancelled_animations == ["file_dropdown"],
               "File dropdown animation should be cancelled"
        
        :ok
      end
    end

    scenario "Menu interaction at screen edges", context do
      given_ "MenuBar near right edge of screen", context do
        # Resize window to force edge case
        SemanticUI.resize_window(400, 800)
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "user opens Help menu (rightmost)", context do
        SemanticUI.click_menu_item("Help")
        Process.sleep(200)
        
        edge_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/screen_edge.png")
        {:ok, Map.put(context, :screenshot, edge_screenshot)}
      end

      then_ "dropdown should adjust position to stay on screen", context do
        dropdown_bounds = SemanticUI.get_dropdown_bounds("Help")
        screen_bounds = SemanticUI.get_screen_bounds()
        
        assert dropdown_bounds.right <= screen_bounds.width,
               "Dropdown should not extend past screen edge"
        assert dropdown_bounds.left >= 0,
               "Dropdown should not extend past left edge"
        
        # Verify it opened to the left instead of right
        menu_pos = SemanticUI.get_menu_item_position("Help")
        assert dropdown_bounds.right <= menu_pos.x + 10,
               "Dropdown should open to the left at screen edge"
        
        :ok
      end
    end

    scenario "Empty menu handling", context do
      given_ "MenuBar with an empty Tools menu", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        
        # Configure Tools menu to be empty
        SemanticUI.set_menu_items("Tools", [])
        
        {:ok, context}
      end

      when_ "user clicks on empty Tools menu", context do
        SemanticUI.click_menu_item("Tools")
        Process.sleep(200)
        
        empty_menu_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/empty_menu.png")
        {:ok, Map.put(context, :screenshot, empty_menu_screenshot)}
      end

      then_ "empty menu should show placeholder or minimum height", context do
        menu_state = SemanticUI.get_menu_state()
        dropdown_bounds = SemanticUI.get_dropdown_bounds("Tools")
        
        assert menu_state.active_menu == "Tools",
               "Tools menu should be active"
        assert menu_state.dropdown_visible == true,
               "Empty dropdown should still be visible"
        
        # Should have minimum height
        assert dropdown_bounds.height >= 20,
               "Empty menu should have minimum height"
        
        # Might show placeholder
        rendered_text = ScriptInspector.get_rendered_text_string()
        assert rendered_text =~ "(empty)" or dropdown_bounds.height >= 20,
               "Empty menu should show placeholder or have minimum size"
        
        :ok
      end
    end

    # =============================================================================
    # 10. ACCESSIBILITY FEATURES
    # =============================================================================

    scenario "Screen reader announcements for menu navigation", context do
      given_ "MenuBar with screen reader enabled", context do
        SemanticUI.enable_screen_reader_mode()
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "user navigates through menus with keyboard", context do
        announcements = SemanticUI.start_recording_announcements()
        
        # Activate menubar
        Probes.send_keys("alt", [:alt])
        Process.sleep(100)
        
        # Navigate to File
        Probes.send_keys("f", [])
        Process.sleep(200)
        
        # Arrow down through items
        Probes.send_keys("down", [])
        Process.sleep(100)
        Probes.send_keys("down", [])
        Process.sleep(100)
        
        recorded = SemanticUI.stop_recording_announcements()
        {:ok, Map.put(context, :announcements, recorded)}
      end

      then_ "appropriate announcements should be made", context do
        announcements = context.announcements
        
        # Verify menubar activation announced
        assert Enum.any?(announcements, &(&1.text =~ "Menu bar activated")),
               "Menubar activation should be announced"
        
        # Verify menu opening announced
        assert Enum.any?(announcements, &(&1.text =~ "File menu opened")),
               "Menu opening should be announced"
        
        # Verify item navigation announced
        assert Enum.any?(announcements, &(&1.text =~ "New, menu item")),
               "Menu items should be announced during navigation"
        
        # Verify position information
        assert Enum.any?(announcements, &(&1.text =~ "2 of")),
               "Position within menu should be announced"
        
        :ok
      end
    end

    scenario "High contrast mode support", context do
      given_ "MenuBar in high contrast mode", context do
        SemanticUI.enable_high_contrast_mode()
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "user opens View menu", context do
        SemanticUI.click_menu_item("View")
        Process.sleep(200)
        
        high_contrast_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/high_contrast.png")
        {:ok, Map.put(context, :screenshot, high_contrast_screenshot)}
      end

      then_ "menu should have appropriate high contrast styling", context do
        contrast_analysis = SemanticUI.analyze_contrast(context.screenshot)
        
        # Verify contrast ratios meet WCAG AAA standards
        assert contrast_analysis.text_contrast_ratio >= 7.0,
               "Text contrast should meet WCAG AAA standard"
        
        # Verify focus indicators are visible
        assert contrast_analysis.focus_indicator_contrast >= 3.0,
               "Focus indicators should have sufficient contrast"
        
        # Verify borders are visible
        assert contrast_analysis.border_visibility == true,
               "Menu borders should be clearly visible"
        
        # Verify disabled items are still distinguishable
        disabled_item_contrast = contrast_analysis.disabled_item_contrast
        assert disabled_item_contrast >= 3.0,
               "Disabled items should still be readable"
        
        :ok
      end
    end

    # =============================================================================
    # 11. ERROR HANDLING
    # =============================================================================

    scenario "Graceful handling of malformed menu data", context do
      given_ "MenuBar with invalid menu configuration", context do
        malformed_config = %{
          menus: [
            %{label: "File", items: nil},  # nil items
            %{label: nil, items: []},       # nil label
            %{label: "Edit", items: [
              %{label: "Cut", action: nil}, # nil action
              %{type: :invalid_type}         # invalid type
            ]}
          ]
        }
        
        SemanticUI.load_component_with_config("Menu Bar", malformed_config)
        Process.sleep(500)
        {:ok, Map.put(context, :config, malformed_config)}
      end

      when_ "user interacts with malformed menus", context do
        # Try to open menu with nil items
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        file_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/malformed_file.png")
        
        # Try to interact with nil label menu
        SemanticUI.click_menu_at_index(1)
        Process.sleep(200)
        nil_label_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/malformed_nil_label.png")
        
        {:ok, Map.merge(context, %{
          file_screenshot: file_screenshot,
          nil_label_screenshot: nil_label_screenshot
        })}
      end

      then_ "MenuBar should handle errors gracefully", context do
        # Verify MenuBar is still functional
        assert SemanticUI.is_component_responsive?("Menu Bar"),
               "MenuBar should remain responsive despite errors"
        
        # Check error handling
        error_log = SemanticUI.get_error_log()
        assert length(error_log) > 0,
               "Errors should be logged"
        
        # Verify specific error handling
        assert Enum.any?(error_log, &(&1.type == :nil_items)),
               "Nil items should be handled"
        assert Enum.any?(error_log, &(&1.type == :nil_label)),
               "Nil label should be handled"
        
        # Verify fallback behavior
        menu_state = SemanticUI.get_menu_state()
        assert menu_state.functional == true,
               "MenuBar should remain functional with fallbacks"
        
        :ok
      end
    end

    scenario "Recovery from missing action callbacks", context do
      given_ "MenuBar with items missing callbacks", context do
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        
        # Don't register callback for file_save
        SemanticUI.configure_menu_callbacks(%{
          "file_new" => fn -> {:ok, :created} end
          # file_save callback missing
        })
        
        {:ok, context}
      end

      when_ "user clicks item with missing callback", context do
        SemanticUI.click_menu_item("File")
        Process.sleep(200)
        SemanticUI.click_dropdown_item("Save")
        Process.sleep(200)
        
        missing_callback_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/missing_callback.png")
        {:ok, Map.put(context, :screenshot, missing_callback_screenshot)}
      end

      then_ "menu should handle missing callback gracefully", context do
        # Menu should close normally
        assert SemanticUI.get_menu_state().dropdown_visible == false,
               "Menu should still close after click"
        
        # Check error was logged
        error_log = SemanticUI.get_error_log()
        callback_errors = Enum.filter(error_log, &(&1.type == :missing_callback))
        
        assert length(callback_errors) == 1,
               "Missing callback should be logged as error"
        assert hd(callback_errors).action == "file_save",
               "Error should identify the missing callback"
        
        # Verify app didn't crash
        assert SemanticUI.is_component_responsive?("Menu Bar"),
               "MenuBar should remain functional"
        
        :ok
      end
    end

    # =============================================================================
    # 12. PERFORMANCE
    # =============================================================================

    scenario "Large menu performance", context do
      given_ "MenuBar with very large Tools menu (100+ items)", context do
        # Generate large menu
        large_menu_items = Enum.map(1..120, fn i ->
          %{
            label: "Tool Option #{i}",
            action: "tool_#{i}",
            enabled: rem(i, 5) != 0  # Every 5th item disabled
          }
        end)
        
        SemanticUI.configure_menu_items("Tools", large_menu_items)
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        
        {:ok, Map.put(context, :item_count, 120)}
      end

      when_ "user opens large Tools menu", context do
        start_time = System.monotonic_time(:millisecond)
        
        SemanticUI.click_menu_item("Tools")
        
        # Wait for menu to fully render
        Process.sleep(500)
        end_time = System.monotonic_time(:millisecond)
        
        large_menu_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/large_menu.png")
        
        {:ok, Map.merge(context, %{
          screenshot: large_menu_screenshot,
          open_time: end_time - start_time
        })}
      end

      then_ "menu should open quickly and scroll smoothly", context do
        # Verify open time is reasonable
        assert context.open_time < 300,
               "Large menu should open in under 300ms, took #{context.open_time}ms"
        
        # Verify menu is scrollable
        menu_bounds = SemanticUI.get_dropdown_bounds("Tools")
        assert menu_bounds.scrollable == true,
               "Large menu should be scrollable"
        
        # Test scroll performance
        scroll_start = System.monotonic_time(:millisecond)
        Probes.send_keys("page_down", [])
        Process.sleep(100)
        scroll_end = System.monotonic_time(:millisecond)
        
        scroll_time = scroll_end - scroll_start
        assert scroll_time < 150,
               "Scrolling should be smooth, took #{scroll_time}ms"
        
        # Verify all items are accessible
        SemanticUI.scroll_menu_to_bottom("Tools")
        assert ScriptInspector.rendered_text_contains?("Tool Option 120"),
               "Last item should be accessible via scroll"
        
        :ok
      end
    end

    scenario "Deep submenu nesting performance", context do
      given_ "MenuBar with deeply nested submenus (5 levels)", context do
        # Create nested menu structure
        nested_menu = %{
          label: "Nested",
          items: [
            %{
              label: "Level 1",
              type: :submenu,
              items: [
                %{
                  label: "Level 2", 
                  type: :submenu,
                  items: [
                    %{
                      label: "Level 3",
                      type: :submenu,
                      items: [
                        %{
                          label: "Level 4",
                          type: :submenu,
                          items: [
                            %{label: "Level 5 Action", action: "deep_action"}
                          ]
                        }
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
        
        SemanticUI.add_menu("Nested", nested_menu.items)
        SemanticUI.load_component("Menu Bar")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "user navigates through all nesting levels", context do
        navigation_times = []
        
        # Open each level
        SemanticUI.click_menu_item("Nested")
        Process.sleep(200)
        
        # Navigate through each submenu level
        ["Level 1", "Level 2", "Level 3", "Level 4"].each do |level|
          start = System.monotonic_time(:millisecond)
          
          item_pos = SemanticUI.get_dropdown_item_position(level)
          Probes.send_mouse_move(item_pos.x, item_pos.y)
          Process.sleep(200)
          
          elapsed = System.monotonic_time(:millisecond) - start
          navigation_times = navigation_times ++ [{level, elapsed}]
        end
        
        deep_nesting_screenshot = Probes.take_screenshot("#{@tmp_screenshots_dir}/deep_nesting.png")
        
        {:ok, Map.merge(context, %{
          screenshot: deep_nesting_screenshot,
          navigation_times: navigation_times
        })}
      end

      then_ "all submenu levels should open responsively", context do
        # Verify each level opened quickly
        Enum.each(context.navigation_times, fn {level, time} ->
          assert time < 250,
                 "#{level} should open in under 250ms, took #{time}ms"
        end)
        
        # Verify all levels are visible
        ["Level 1", "Level 2", "Level 3", "Level 4", "Level 5 Action"]
        |> Enum.each(fn level ->
          assert ScriptInspector.rendered_text_contains?(level),
                 "#{level} should be visible"
        end)
        
        # Verify z-ordering is correct
        render_layers = SemanticUI.get_render_layers()
        submenu_layers = render_layers
        |> Enum.filter(&(&1.type == :submenu))
        |> Enum.sort_by(& &1.z_index)
        
        assert length(submenu_layers) >= 4,
               "All submenu layers should be rendered"
        
        # Each submenu should have higher z-index than parent
        submenu_layers
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [lower, higher] ->
          assert higher.z_index > lower.z_index,
                 "Nested submenus should have increasing z-indices"
        end)
        
        :ok
      end
    end
  end
end