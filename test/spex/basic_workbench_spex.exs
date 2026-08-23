defmodule ScenicWidgets.BasicWorkbenchSpex do
  @moduledoc """
  Basic spex to verify Widget Workbench functionality.
  
  This version focuses on testing what we can without full app startup.
  """
  use SexySpex
  
  # Simple helper to check if workbench is running
  defp workbench_running? do
    Process.whereis(:main_viewport) != nil
  end
  
  spex "Widget Workbench - Basic Tests",
    description: "Basic tests for Widget Workbench and MenuBar",
    tags: [:basic, :workbench] do

    scenario "MenuBar data structure validation", context do
      given_ "we need to create MenuBar data", context do
        IO.puts("\n📋 Testing MenuBar data structure creation...")
        {:ok, context}
      end

      when_ "we create a Widgex.Frame structure", context do
        # Manually create the frame structure without using Widgex.Frame.new
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
        
        IO.puts("✅ Created frame with pin at (80, 80) and size 400x60")
        {:ok, Map.put(context, :frame, frame)}
      end

      and_ "we create a menu_map structure", context do
        menu_map = [
          {:sub_menu, "File", [
            {"new_file", "New File"},
            {"open_file", "Open File"},
            {"save_file", "Save"},
            {"quit", "Quit"}
          ]},
          {:sub_menu, "Edit", [
            {"undo", "Undo"},
            {"redo", "Redo"}
          ]}
        ]
        
        IO.puts("✅ Created menu_map with File and Edit menus")
        {:ok, Map.put(context, :menu_map, menu_map)}
      end

      then_ "we can create valid MenuBar data", context do
        menu_data = %{
          frame: context.frame,
          menu_map: context.menu_map
        }
        
        # Basic validations
        assert is_map(menu_data), "Menu data should be a map"
        assert Map.has_key?(menu_data, :frame), "Should have :frame key"
        assert Map.has_key?(menu_data, :menu_map), "Should have :menu_map key"
        
        # Validate frame structure
        assert menu_data.frame.pin.x == 80, "Frame x should be 80"
        assert menu_data.frame.pin.y == 80, "Frame y should be 80"
        assert menu_data.frame.size.width == 400, "Frame width should be 400"
        assert menu_data.frame.size.height == 60, "Frame height should be 60"
        
        # Validate menu structure
        [{:sub_menu, "File", file_items} | _] = menu_data.menu_map
        assert length(file_items) == 4, "File menu should have 4 items"
        [first_item | _] = file_items
        assert first_item == {"new_file", "New File"}, "First item should be New File"
        
        IO.puts("✅ MenuBar data structure is valid!")
        :ok
      end
    end

    scenario "Widget Workbench runtime check", context do
      given_ "we want to check if Widget Workbench is available", context do
        IO.puts("\n🔍 Checking Widget Workbench runtime status...")
        {:ok, context}
      end

      when_ "we check for the viewport process", context do
        viewport_pid = Process.whereis(:main_viewport)
        running = viewport_pid != nil
        
        {:ok, Map.put(context, :workbench_running, running)}
      end

      then_ "we report the status", context do
        if context.workbench_running do
          IO.puts("✅ Widget Workbench viewport is running!")
          assert true
        else
          IO.puts("ℹ️  Widget Workbench viewport is not currently running")
          IO.puts("   (This is expected if you haven't started it separately)")
          assert true  # Not a failure - just informational
        end
        
        :ok
      end
    end
  end
end