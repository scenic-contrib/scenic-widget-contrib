defmodule ScenicWidgets.WidgetWorkbenchManualDemoSpex do
  @moduledoc """
  Widget Workbench Manual Demo Spex
  
  This spex demonstrates step-by-step testing with manual mode.
  Perfect for following along with the test execution.
  """
  use SexySpex
  
  spex "Widget Workbench - Manual Demo for Development",
    description: "Step-by-step demonstration of Widget Workbench testing",
    tags: [:manual_demo, :workbench, :educational] do

    scenario "Understanding the workbench layout", context do
      given_ "we examine the Widget Workbench structure", context do
        IO.puts("\n🎯 Widget Workbench Layout Overview:")
        IO.puts("   - Left 2/3: Main canvas (white background with grid)")
        IO.puts("   - Right 1/3: Constructor pane")
        IO.puts("   - Constructor has: Heading, Reset Scene (red), Load Component")
        {:ok, context}
      end

      when_ "we inspect the current state", context do
        IO.puts("\n🔍 Current state check:")
        viewport_running = Process.whereis(:main_viewport) != nil
        
        if viewport_running do
          IO.puts("   ✅ Widget Workbench viewport is running")
        else
          IO.puts("   ⚠️  Widget Workbench viewport is not running")
          IO.puts("   💡 Start it with: WidgetWorkbench.start()")
        end
        
        {:ok, Map.put(context, :viewport_running, viewport_running)}
      end

      then_ "we understand the workbench capabilities", context do
        IO.puts("\n📚 Workbench capabilities:")
        IO.puts("   1. Component isolation - test components independently")
        IO.puts("   2. Hot reload - changes auto-update (if FileSystem available)")
        IO.puts("   3. Dynamic discovery - finds components in /lib/components")
        IO.puts("   4. Visual testing - see components render in real-time")
        
        assert true, "Understanding complete"
        :ok
      end
    end

    scenario "Component loading workflow", context do
      given_ "Widget Workbench is ready", context do
        IO.puts("\n🎮 Component Loading Process:")
        IO.puts("   Step 1: Click 'Load Component' button")
        IO.puts("   Step 2: Modal appears with component list")
        IO.puts("   Step 3: Click desired component (e.g., MenuBar)")
        IO.puts("   Step 4: Component renders in main canvas")
        {:ok, context}
      end

      when_ "we prepare to test MenuBar", context do
        IO.puts("\n📋 MenuBar testing checklist:")
        IO.puts("   □ Position: Should be at (80, 80), not (0, 0)")
        IO.puts("   □ Height: Should be 60 pixels")
        IO.puts("   □ Hover: Immediate visual feedback")
        IO.puts("   □ Dropdowns: Click File → see submenu")
        IO.puts("   □ Z-order: No click-through to components below")
        
        {:ok, Map.put(context, :test_checklist, :ready)}
      end

      then_ "we know what to look for", context do
        IO.puts("\n🎯 Key things to verify:")
        IO.puts("   1. Data format: menu items use strings {\"id\", \"label\"}")
        IO.puts("   2. Translation: Coordinates struct → tuple conversion")
        IO.puts("   3. Isolation: Component errors don't crash workbench")
        IO.puts("   4. Hot reload: Window size persists via ETS table")
        
        assert context.test_checklist == :ready
        :ok
      end
    end

    scenario "MenuBar data structure creation", context do
      given_ "we need proper MenuBar data", context do
        IO.puts("\n🔧 Creating MenuBar data structure...")
        {:ok, context}
      end

      when_ "we build the Widgex.Frame", context do
        # Create frame structure
        frame = %{
          __struct__: Widgex.Frame,
          pin: %{
            __struct__: Widgex.Structs.Coordinates,
            x: 80,
            y: 80,
            point: {80, 80}
          },
          size: %{
            __struct__: Widgex.Structs.Dimensions,
            width: 400,
            height: 60,
            box: {400, 60}
          }
        }
        
        IO.puts("   ✅ Frame: pin=(80,80), size=400x60")
        {:ok, Map.put(context, :frame, frame)}
      end

      and_ "we create the menu_map", context do
        menu_map = [
          {:sub_menu, "File", [
            {"new_file", "New File"},
            {"open_file", "Open File"},
            {"save_file", "Save"},
            {"quit", "Quit"}
          ]},
          {:sub_menu, "Edit", [
            {"undo", "Undo"},
            {"redo", "Redo"},
            {"cut", "Cut"},
            {"copy", "Copy"},
            {"paste", "Paste"}
          ]},
          {:sub_menu, "View", [
            {"zoom_in", "Zoom In"},
            {"zoom_out", "Zoom Out"},
            {"fullscreen", "Toggle Fullscreen"}
          ]}
        ]
        
        IO.puts("   ✅ Menu map: File, Edit, View menus")
        IO.puts("   ✅ Items use string tuples: {\"id\", \"label\"}")
        {:ok, Map.put(context, :menu_map, menu_map)}
      end

      then_ "MenuBar data is ready", context do
        menu_data = %{
          frame: context.frame,
          menu_map: context.menu_map
        }
        
        IO.puts("\n✅ Complete MenuBar data structure created!")
        IO.puts("   - Frame with proper Coordinates/Dimensions structs")
        IO.puts("   - Menu items using string format (not atoms)")
        IO.puts("   - Ready for Widget Workbench testing")
        
        assert is_map(menu_data)
        assert menu_data.frame.pin.x == 80
        assert menu_data.frame.size.height == 60
        
        # Verify string format
        [{:sub_menu, "File", file_items} | _] = menu_data.menu_map
        [{"new_file", "New File"} | _] = file_items
        
        :ok
      end
    end

    scenario "Common issues and solutions", context do
      given_ "we review common problems", context do
        IO.puts("\n⚠️  Common Issues:")
        {:ok, context}
      end

      when_ "we list the issues", context do
        issues = [
          {"Window resize", "Fixed with ETS table persistence"},
          {"Translation error", "Convert Coordinates struct to tuple"},
          {"Menu data format", "Use strings not atoms for items"},
          {"Click-through", "Check z-order and event handling"},
          {"Module loading", "Ensure all deps are started"}
        ]
        
        for {issue, solution} <- issues do
          IO.puts("   ❌ #{issue}")
          IO.puts("   ✅ Solution: #{solution}")
          IO.puts("")
        end
        
        {:ok, Map.put(context, :issues_reviewed, true)}
      end

      then_ "we're prepared for testing", context do
        IO.puts("🎯 Ready for comprehensive testing!")
        IO.puts("   - Use manual_menubar_test_guide.md for UI testing")
        IO.puts("   - Run menu_bar_comprehensive_spex.exs when ready")
        
        assert context.issues_reviewed
        :ok
      end
    end
  end
end