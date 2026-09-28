defmodule ScenicWidgets.Sidebar.BasicStructureSpex do
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
  
  spex "Sidebar Basic Structure" do
    scenario "Component validates input data correctly", context do
      given_ "sidebar with valid data", context do
        items = [
          %{id: :file, label: "File", children: []},
          %{id: :edit, label: "Edit", children: []}
        ]
        
        # Create frame manually to avoid dependency issues
        frame = %{
          __struct__: Widgex.Frame,
          left: 0, 
          top: 0, 
          width: 200, 
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
      
      when_ "we validate the sidebar data", context do
        result = ScenicWidgets.Sidebar.validate(context.sidebar_config)
        
        {:ok, context
        |> Map.put(:validation_result, result)}
      end
      
      then_ "validation should pass", context do
        assert {:ok, _} = context.validation_result
        :ok
      end
    end
    
    scenario "Component validates nested items", context do
      given_ "sidebar with nested items", context do
        items = [
          %{id: :file, label: "File", children: [
            %{id: :new, label: "New", children: []},
            %{id: :open, label: "Open", children: []}
          ]},
          %{id: :edit, label: "Edit", children: []}
        ]
        
        frame = %{
          __struct__: Widgex.Frame,
          left: 0, 
          top: 0, 
          width: 200, 
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
      
      when_ "we validate the nested sidebar data", context do
        result = ScenicWidgets.Sidebar.validate(context.sidebar_config)
        
        {:ok, context
        |> Map.put(:validation_result, result)}
      end
      
      then_ "validation should pass for nested items", context do
        assert {:ok, _} = context.validation_result
        :ok
      end
    end
    
    scenario "Component rejects invalid data", context do
      given_ "sidebar with invalid data", context do
        # Test with missing frame
        invalid_config1 = %{
          items: []
        }
        
        # Test with invalid items
        invalid_config2 = %{
          frame: %{
            __struct__: Widgex.Frame,
            left: 0, top: 0, width: 200, height: 400
          },
          items: "not a list"
        }
        
        {:ok, context
        |> Map.put(:invalid_config1, invalid_config1)
        |> Map.put(:invalid_config2, invalid_config2)}
      end
      
      when_ "we validate invalid data", context do
        result1 = ScenicWidgets.Sidebar.validate(context.invalid_config1)
        result2 = ScenicWidgets.Sidebar.validate(context.invalid_config2)
        
        {:ok, context
        |> Map.put(:result1, result1)
        |> Map.put(:result2, result2)}
      end
      
      then_ "validation should fail appropriately", context do
        assert :invalid_input = context.result1
        assert :invalid_input = context.result2
        :ok
      end
    end
  end
end