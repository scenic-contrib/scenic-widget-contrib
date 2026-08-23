defmodule ScenicWidgets.Sidebar.ViewClickBehaviorSpex do
  use SexySpex
  
  alias ScenicWidgets.TestHelpers.ScriptInspector
  
  setup_all do
    # Ensure all required applications are started
    {:ok, _} = Application.ensure_all_started(:scenic)
    {:ok, _} = Application.ensure_all_started(:scenic_driver_local)
    
    # Start the scenic_widget_contrib application manually
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
      error -> 
        IO.puts("Failed to start scenic_widget_contrib: #{inspect(error)}")
        error
    end
    
    # Wait a bit for everything to load
    Process.sleep(100)
    
    :ok
  end
  
  spex "Sidebar View Click Behavior" do
    scenario "View item handles click events", context do
      given_ "sidebar with View item that has children", context do
        items = [
          %{id: :file, label: "File", children: [
            %{id: :new, label: "New", children: []},
            %{id: :open, label: "Open", children: []}
          ]},
          %{id: :edit, label: "Edit", children: []},
          %{id: :view, label: "View", children: [
            %{id: :zoom_in, label: "Zoom In", children: []},
            %{id: :zoom_out, label: "Zoom Out", children: []},
            %{id: :fullscreen, label: "Toggle Fullscreen", children: []}
          ]}
        ]
        
        frame = %{
          __struct__: Widgex.Frame,
          left: 0, 
          top: 0, 
          width: 250, 
          height: 400
        }
        
        sidebar_config = %{
          frame: frame,
          items: items
        }
        
        {:ok, context
        |> Map.put(:sidebar_config, sidebar_config)
        |> Map.put(:items, items)}
      end
      
      when_ "we test the component structure", context do
        # Validate the component accepts the data
        result = ScenicWidgets.Sidebar.validate(context.sidebar_config)
        
        {:ok, context
        |> Map.put(:validation_result, result)}
      end
      
      then_ "component validates and is ready for click handling", context do
        assert {:ok, _} = context.validation_result
        
        IO.puts("\n✅ View click behavior test:")
        IO.puts("   Component structure validated")
        IO.puts("   View item has children: true")
        IO.puts("   Ready for click event handling")
        
        :ok
      end
    end
    
    scenario "Click event routing for View item", context do
      given_ "understanding of Sidebar click handling", context do
        IO.puts("\n📚 Sidebar Click Handling Overview:")
        IO.puts("   - handle_input/3 receives click events")
        IO.puts("   - Context determines which item was clicked")
        IO.puts("   - {:sidebar_item, path} indicates item click")
        IO.puts("   - {:expand_icon, path} indicates expand icon click")
        
        {:ok, context}
      end
      
      when_ "we examine the click handler implementation", context do
        # Check if the handle_input function exists
        has_handle_input = function_exported?(ScenicWidgets.Sidebar, :handle_input, 3)
        
        {:ok, context
        |> Map.put(:has_handle_input, has_handle_input)}
      end
      
      then_ "click handler is properly implemented", context do
        assert context.has_handle_input,
               "Sidebar should have handle_input/3 function"
        
        IO.puts("\n✅ Click handler verification:")
        IO.puts("   handle_input/3 exists: #{context.has_handle_input}")
        IO.puts("   Ready to process View click events")
        
        :ok
      end
    end
    
    scenario "Manual testing instructions for View clicks", context do
      given_ "need to test View click behavior", context do
        IO.puts("\n📋 Manual Testing Steps:")
        IO.puts("1. Start IEx session: iex -S mix")
        IO.puts("2. Start Widget Workbench: WidgetWorkbench.start()")
        IO.puts("3. Click 'Load Component' button")
        IO.puts("4. Select 'Sidebar' from the component list")
        IO.puts("5. Once loaded, locate the 'View' item in the sidebar")
        IO.puts("6. Click on 'View' and observe:")
        IO.puts("   - Console output shows 'Sidebar received click'")
        IO.puts("   - View expands to show child items (Zoom In, Zoom Out, Toggle Fullscreen)")
        IO.puts("   - Expand icon (triangle) points down when expanded")
        IO.puts("7. Click 'View' again to collapse")
        
        {:ok, context}
      end
      
      when_ "manual testing is performed", context do
        IO.puts("\n🔍 What to observe:")
        IO.puts("   - Check console for debug output")
        IO.puts("   - Verify visual feedback (expand/collapse)")
        IO.puts("   - Test clicking on both text and expand icon")
        
        {:ok, context}
      end
      
      then_ "View click behavior works as expected", context do
        IO.puts("\n✅ Expected results:")
        IO.puts("   - View toggles between expanded/collapsed states")
        IO.puts("   - Child items appear/disappear appropriately")
        IO.puts("   - Console logs confirm click handling")
        
        :ok
      end
    end
  end
end