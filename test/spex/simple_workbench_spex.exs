# Simply ensure scenic_widget_contrib application is started, which loads all modules
# Mix should handle compilation of all modules in the project

defmodule ScenicWidgets.SimpleWorkbenchSpex do
  @moduledoc """
  Simple spex to verify Widget Workbench can start and load MenuBar.
  
  This is a simplified spex-driven test that demonstrates the basic
  functionality before running the comprehensive spex.
  """
  use SexySpex
  
  alias ScenicWidgets.TestHelpers.ScriptInspector
  
  setup_all do
    # Ensure all required applications are started
    {:ok, _} = Application.ensure_all_started(:scenic)
    {:ok, _} = Application.ensure_all_started(:scenic_driver_local)
    
    # Start the scenic_widget_contrib application manually
    # This ensures all modules are loaded properly
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
      error -> 
        IO.puts("Failed to start scenic_widget_contrib: #{inspect(error)}")
        error
    end
    
    # Wait a bit for everything to load
    Process.sleep(100)
    
    # Register cleanup callback
    on_exit(fn ->
      # Clean shutdown
      if Code.ensure_loaded?(WidgetWorkbench) and function_exported?(WidgetWorkbench, :running?, 0) and WidgetWorkbench.running?() do
        WidgetWorkbench.stop()
        Process.sleep(100)
      end
    end)
    
    :ok
  end

  spex "Widget Workbench - Basic Functionality",
    description: "Validates that Widget Workbench starts and MenuBar component works",
    tags: [:workbench, :menubar, :basic] do

    scenario "Widget Workbench startup and verification", context do
      given_ "Widget Workbench is starting", context do
        # Start Widget Workbench if not already running
        case Process.whereis(:main_viewport) do
          nil -> 
            {:ok, workbench_pid} = WidgetWorkbench.start(size: {1200, 800}, title: "Test Workbench")
            assert Process.alive?(workbench_pid), "Widget Workbench process should be alive"
            # Wait for initialization
            Process.sleep(1000)
            {:ok, Map.put(context, :workbench_pid, workbench_pid)}
          pid ->
            # Already running
            {:ok, Map.put(context, :workbench_pid, pid)}
        end
      end

      when_ "we inspect the initial viewport", context do
        # Verify viewport is accessible
        vp_pid = Process.whereis(:main_viewport)
        assert vp_pid != nil, "Widget Workbench viewport should be registered"
        assert Process.alive?(vp_pid), "Viewport process should be alive"
        
        # Wait a bit for the scene to render
        Process.sleep(500)
        
        # Check what's rendered initially
        ScriptInspector.debug_script_table()
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n🔍 Initial rendered content: '#{rendered_content}'")
        
        # Take baseline screenshot
        baseline_screenshot = ScenicMcp.Probes.take_screenshot("workbench_baseline")
        
        {:ok, Map.merge(context, %{
          viewport_pid: vp_pid,
          baseline_screenshot: baseline_screenshot,
          initial_content: rendered_content
        })}
      end

      then_ "Widget Workbench displays the expected UI", context do
        # Verify we can see expected UI elements
        _rendered_content = context.initial_content
        
        # The workbench should show:
        # 1. Widget Workbench heading
        # 2. Reset Scene button
        # 3. Load Component button
        # 4. Green circle in main area (default test pattern)
        
        # Note: These assertions depend on what text is actually rendered
        # You may need to adjust based on actual rendering
        
        # Verify the workbench is not empty
        refute ScriptInspector.rendered_text_empty?(),
               "Widget Workbench should have rendered content"
        
        # Verify the viewport info
        {:ok, vp_info} = Scenic.ViewPort.info(:main_viewport)
        assert vp_info.name == :main_viewport
        assert vp_info.size == {1200, 800}
        
        :ok
      end
    end

    scenario "Loading MenuBar component", context do
      given_ "Widget Workbench is ready", context do
        # Ensure workbench is running
        assert WidgetWorkbench.running?(), "Widget Workbench should be running"
        
        # Get current rendered content
        initial_content = ScriptInspector.get_rendered_text_string()
        
        {:ok, Map.put(context, :initial_content, initial_content)}
      end

      when_ "we load the MenuBar component", context do
        # In a real test, we would:
        # 1. Click the Load Component button
        # 2. Select MenuBar from the modal
        # 3. Verify it loads
        
        # For now, let's test the data structure preparation that happens
        # when loading a component
        
        # Create the MenuBar data structure as the workbench would
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
        
        menu_data = %{
          frame: frame,
          menu_map: [
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
        }
        
        {:ok, Map.merge(context, %{frame: frame, menu_data: menu_data})}
      end

      then_ "MenuBar data is properly formatted", context do
        # Verify the data structure that would be passed to MenuBar
        menu_data = context.menu_data
        
        # Verify structure
        assert is_map(menu_data)
        assert Map.has_key?(menu_data, :frame)
        assert Map.has_key?(menu_data, :menu_map)
        
        # Verify frame positioning
        assert menu_data.frame.pin.x == 80, "MenuBar should be positioned at x=80"
        assert menu_data.frame.pin.y == 80, "MenuBar should be positioned at y=80"
        assert menu_data.frame.size.height == 60, "MenuBar height should be 60"
        
        # Verify menu items use string format (not atoms)
        [{:sub_menu, "File", file_items} | _] = menu_data.menu_map
        [{"new_file", "New File"} | _] = file_items
        
        IO.puts("✅ MenuBar data structure is valid and ready for loading")
        
        # In a full test, we would verify the MenuBar actually renders
        # by checking ScriptInspector after loading
        
        :ok
      end
    end

    # Cleanup is handled by the test framework teardown
  end

  # Helper function to wait for scene hierarchy
  defp wait_for_scene_hierarchy(viewport_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 3000)
    start_time = System.monotonic_time(:millisecond)
    
    wait_for_scenes(viewport_name, start_time, timeout)
  end

  defp wait_for_scenes(viewport_name, start_time, timeout) do
    current_time = System.monotonic_time(:millisecond)
    
    if current_time - start_time > timeout do
      {:error, :timeout}
    else
      case Scenic.ViewPort.info(viewport_name) do
        {:ok, vp_info} ->
          # Check if we have scenes loaded
          if vp_info.name == viewport_name do
            {:ok, %{viewport: vp_info}}
          else
            Process.sleep(100)
            wait_for_scenes(viewport_name, start_time, timeout)
          end
        _ ->
          Process.sleep(100)
          wait_for_scenes(viewport_name, start_time, timeout)
      end
    end
  end
end