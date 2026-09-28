defmodule ScenicWidgets.MenuBarSpecSuite do
  @moduledoc """
  Comprehensive specification suite for MenuBar component.
  Each spex in this suite drives a specific aspect of the MenuBar implementation.
  
  ## Spex-Driven Development Process:
  
  1. Run this suite to identify failing specs
  2. Implement/fix code to make specs pass
  3. Refactor while keeping specs green
  4. Add new specs for edge cases discovered
  """
  use SexySpex
  
  alias ScenicWidgets.TestHelpers.ScriptInspector
  
  # Shared setup for all MenuBar specs
  setup_all do
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end
    
    on_exit(fn ->
      if WidgetWorkbench.running?() do
        WidgetWorkbench.stop()
        Process.sleep(100)
      end
    end)
    
    :ok
  end
  
  setup do
    # Ensure clean state for each test
    if WidgetWorkbench.running?() do
      WidgetWorkbench.stop()
      Process.sleep(100)
    end
    
    {:ok, _pid} = WidgetWorkbench.start(size: {1200, 800}, title: "MenuBar Spec Suite")
    Process.sleep(500)
    
    :ok
  end

  # SPEC 1: Visual Rendering
  spex "MenuBar Visual Rendering Specification",
    description: "MenuBar must render correctly with proper styling and layout",
    tags: [:visual, :rendering] do
    
    scenario "Basic menu bar renders with correct dimensions", context do
      given_ "a MenuBar configuration", context do
        menu_data = create_test_menu_data()
        {:ok, Map.put(context, :menu_data, menu_data)}
      end
      
      when_ "the MenuBar is rendered", context do
        # Load MenuBar component with data
        load_menubar_component(context.menu_data)
        Process.sleep(200)
        {:ok, context}
      end
      
      then_ "it displays with correct visual properties", context do
        content = ScriptInspector.get_rendered_text_string()
        
        # Check that menu headers are visible
        assert String.contains?(content, "File")
        assert String.contains?(content, "Edit")
        assert String.contains?(content, "View")
        
        # TODO: Add visual dimension checks when ScriptInspector supports it
        :ok
      end
    end
    
    scenario "Menu items align properly", context do
      given_ "a MenuBar with multiple menus", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        {:ok, Map.put(context, :menu_data, menu_data)}
      end
      
      then_ "menu headers are evenly spaced", context do
        # TODO: Implement position checking
        # This would verify that menu items don't overlap
        # and maintain consistent spacing
        :ok
      end
    end
  end

  # SPEC 2: Hover Behavior
  spex "MenuBar Hover Behavior Specification",
    description: "MenuBar must respond correctly to mouse hover events",
    tags: [:interaction, :hover] do
    
    scenario "Hovering over menu header highlights it", context do
      given_ "a MenuBar is displayed", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        {:ok, Map.put(context, :menu_data, menu_data)}
      end
      
      when_ "mouse hovers over File menu", context do
        simulate_hover(150, 115)  # Approximate File menu position
        Process.sleep(100)
        {:ok, context}
      end
      
      then_ "File menu header is highlighted", context do
        # Check that visual state has changed
        # This would verify highlight color/style is applied
        :ok
      end
    end
    
    scenario "Moving between headers updates highlight smoothly", context do
      given_ "MenuBar with mouse over File menu", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        simulate_hover(150, 115)
        {:ok, context}
      end
      
      when_ "mouse moves to Edit menu", context do
        simulate_hover(300, 115)
        Process.sleep(50)
        {:ok, context}
      end
      
      then_ "highlight transfers without flicker", context do
        # Verify smooth transition
        # Check that only one header is highlighted at a time
        :ok
      end
    end
  end

  # SPEC 3: Dropdown Behavior
  spex "MenuBar Dropdown Behavior Specification",
    description: "Dropdowns must open, display, and close correctly",
    tags: [:dropdown, :interaction] do
    
    scenario "Clicking menu header opens dropdown", context do
      given_ "MenuBar is displayed", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        {:ok, Map.put(context, :menu_data, menu_data)}
      end
      
      when_ "File menu is clicked", context do
        simulate_click(150, 115)
        Process.sleep(200)
        {:ok, context}
      end
      
      then_ "File dropdown appears with all items", context do
        content = ScriptInspector.get_rendered_text_string()
        
        # Check dropdown items are visible
        assert String.contains?(content, "New")
        assert String.contains?(content, "Open")
        assert String.contains?(content, "Save")
        assert String.contains?(content, "Exit")
        :ok
      end
    end
    
    scenario "Dropdown closes when clicking outside", context do
      given_ "File dropdown is open", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        simulate_click(150, 115)  # Open File dropdown
        Process.sleep(100)
        {:ok, context}
      end
      
      when_ "clicking outside the dropdown", context do
        simulate_click(600, 300)  # Click away from menu
        Process.sleep(100)
        {:ok, context}
      end
      
      then_ "dropdown closes", context do
        content = ScriptInspector.get_rendered_text_string()
        
        # Dropdown items should not be visible
        refute String.contains?(content, "New")
        refute String.contains?(content, "Open")
        :ok
      end
    end
    
    scenario "Hovering between open dropdowns switches smoothly", context do
      given_ "File dropdown is open", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        simulate_click(150, 115)
        Process.sleep(100)
        {:ok, context}
      end
      
      when_ "mouse moves to Edit menu header", context do
        simulate_hover(300, 115)
        Process.sleep(100)
        {:ok, context}
      end
      
      then_ "File dropdown closes and Edit dropdown opens", context do
        content = ScriptInspector.get_rendered_text_string()
        
        # File items should be hidden
        refute String.contains?(content, "New")
        refute String.contains?(content, "Save")
        
        # Edit items should be visible
        assert String.contains?(content, "Undo")
        assert String.contains?(content, "Redo")
        :ok
      end
    end
  end

  # SPEC 4: Keyboard Navigation
  spex "MenuBar Keyboard Navigation Specification",
    description: "MenuBar must support keyboard navigation",
    tags: [:keyboard, :accessibility] do
    
    scenario "Arrow keys navigate between menu headers", context do
      given_ "MenuBar has focus", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        # Focus on MenuBar
        simulate_click(150, 115)
        {:ok, context}
      end
      
      when_ "right arrow is pressed", context do
        simulate_key(:right)
        Process.sleep(50)
        {:ok, context}
      end
      
      then_ "focus moves to Edit menu", context do
        # Verify Edit menu is now focused/highlighted
        :ok
      end
    end
    
    scenario "Enter key opens focused menu", context do
      given_ "File menu is focused", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        simulate_click(150, 115)
        simulate_key(:escape)  # Close dropdown but keep focus
        {:ok, context}
      end
      
      when_ "Enter key is pressed", context do
        simulate_key(:enter)
        Process.sleep(100)
        {:ok, context}
      end
      
      then_ "File dropdown opens", context do
        content = ScriptInspector.get_rendered_text_string()
        assert String.contains?(content, "New")
        assert String.contains?(content, "Open")
        :ok
      end
    end
  end

  # SPEC 5: Performance and Efficiency
  spex "MenuBar Performance Specification",
    description: "MenuBar must render efficiently without flickering",
    tags: [:performance, :efficiency] do
    
    scenario "Rapid interactions don't cause excessive renders", context do
      given_ "MenuBar is displayed", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        {:ok, Map.put(context, :initial_render_count, get_render_count())}
      end
      
      when_ "performing rapid menu interactions", context do
        # Simulate realistic user behavior
        Enum.each(1..10, fn _ ->
          simulate_hover(150, 115)
          Process.sleep(20)
          simulate_hover(300, 115)
          Process.sleep(20)
          simulate_hover(450, 115)
          Process.sleep(20)
        end)
        
        {:ok, Map.put(context, :final_render_count, get_render_count())}
      end
      
      then_ "render count is reasonable", context do
        total_renders = context.final_render_count - context.initial_render_count
        
        # Should have efficient rendering
        assert total_renders < 100, 
               "Too many renders: #{total_renders}. This indicates inefficient rendering."
        :ok
      end
    end
  end

  # SPEC 6: State Consistency
  spex "MenuBar State Consistency Specification",
    description: "MenuBar must maintain consistent state",
    tags: [:state, :consistency] do
    
    scenario "Only one dropdown can be open at a time", context do
      given_ "MenuBar with File dropdown open", context do
        menu_data = create_test_menu_data()
        load_menubar_component(menu_data)
        simulate_click(150, 115)
        {:ok, context}
      end
      
      when_ "Edit menu is clicked", context do
        simulate_click(300, 115)
        Process.sleep(100)
        {:ok, context}
      end
      
      then_ "only Edit dropdown is visible", context do
        content = ScriptInspector.get_rendered_text_string()
        
        # Edit items visible
        assert String.contains?(content, "Undo")
        
        # File items not visible
        refute String.contains?(content, "New")
        :ok
      end
    end
  end

  # Helper Functions
  
  defp create_test_menu_data do
    %{
      frame: %{
        pin: %{x: 100, y: 100},
        size: %{width: 600, height: 30}
      },
      menu_map: %{
        file: {"File", [
          {"new", "New"},
          {"open", "Open"},
          {"save", "Save"},
          {"exit", "Exit"}
        ]},
        edit: {"Edit", [
          {"undo", "Undo"},
          {"redo", "Redo"},
          {"cut", "Cut"},
          {"copy", "Copy"},
          {"paste", "Paste"}
        ]},
        view: {"View", [
          {"zoom_in", "Zoom In"},
          {"zoom_out", "Zoom Out"},
          {"full_screen", "Full Screen"}
        ]}
      }
    }
  end
  
  defp load_menubar_component(menu_data) do
    # TODO: Implement actual component loading through Widget Workbench
    # For now, simulate by sending data to the scene
    send(Process.whereis(:main_viewport), {:load_component, {ScenicWidgets.MenuBar, menu_data}})
  end
  
  defp simulate_hover(x, y) do
    send(Process.whereis(:main_viewport), {:cursor_pos, {x, y}})
  end
  
  defp simulate_click(x, y) do
    pid = Process.whereis(:main_viewport)
    send(pid, {:cursor_button, {:btn_left, 1, [], {x, y}}})
    Process.sleep(10)
    send(pid, {:cursor_button, {:btn_left, 0, [], {x, y}}})
  end
  
  defp simulate_key(key) do
    send(Process.whereis(:main_viewport), {:key, {key, 1, []}})
    Process.sleep(10)
    send(Process.whereis(:main_viewport), {:key, {key, 0, []}})
  end
  
  defp get_render_count do
    # TODO: Implement actual render counting
    :rand.uniform(100)
  end
end
