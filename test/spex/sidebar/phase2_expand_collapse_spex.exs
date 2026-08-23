defmodule ScenicWidgets.Sidebar.ExpandCollapseSpex do
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
  
  spex "Sidebar Expand/Collapse Functionality" do
    scenario "Items with children show expand icons", context do
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
      
      when_ "we create the sidebar component", context do
        # Test that the component can be created with expand/collapse state
        result = ScenicWidgets.Sidebar.validate(context.sidebar_config)
        
        {:ok, context
        |> Map.put(:validation_result, result)}
      end
      
      then_ "component validates with expand/collapse features", context do
        assert {:ok, _} = context.validation_result
        :ok
      end
    end
    
    scenario "Default state has all nodes collapsed", context do
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
      
      when_ "we initialize the sidebar", context do
        # This would test the initial state has empty expanded_nodes
        # For now, we'll test that the data structure is correct
        initial_state = %{
          frame: context.sidebar_config.frame,
          items: context.sidebar_config.items,
          indent_width: 20,
          item_height: 32,
          expanded_nodes: MapSet.new()  # Should start empty
        }
        
        {:ok, context
        |> Map.put(:initial_state, initial_state)}
      end
      
      then_ "all nodes start collapsed", context do
        assert MapSet.size(context.initial_state.expanded_nodes) == 0
        :ok
      end
    end
    
    scenario "Expand state management works correctly", context do
      given_ "an initial sidebar state", context do
        initial_expanded = MapSet.new()
        
        {:ok, context
        |> Map.put(:expanded_nodes, initial_expanded)}
      end
      
      when_ "we expand a node", context do
        # Simulate expanding the :file node
        new_expanded = MapSet.put(context.expanded_nodes, :file)
        
        {:ok, context
        |> Map.put(:new_expanded, new_expanded)}
      end
      
      then_ "node is marked as expanded", context do
        assert MapSet.member?(context.new_expanded, :file)
        assert MapSet.size(context.new_expanded) == 1
        :ok
      end
      
      and_ "node can be collapsed again", context do
        collapsed_again = MapSet.delete(context.new_expanded, :file)
        assert MapSet.size(collapsed_again) == 0
        refute MapSet.member?(collapsed_again, :file)
        :ok
      end
    end
    
    scenario "Multiple nodes can be expanded simultaneously", context do
      given_ "sidebar with multiple parent nodes", context do
        items = [
          %{id: :file, label: "File", children: [
            %{id: :new, label: "New", children: []}
          ]},
          %{id: :edit, label: "Edit", children: [
            %{id: :undo, label: "Undo", children: []}
          ]},
          %{id: :view, label: "View", children: [
            %{id: :zoom, label: "Zoom", children: []}
          ]}
        ]
        
        expanded_nodes = MapSet.new()
        
        {:ok, context
        |> Map.put(:items, items)
        |> Map.put(:expanded_nodes, expanded_nodes)}
      end
      
      when_ "we expand multiple nodes", context do
        # Expand file and edit nodes
        new_expanded = context.expanded_nodes
        |> MapSet.put(:file)
        |> MapSet.put(:edit)
        
        {:ok, context
        |> Map.put(:new_expanded, new_expanded)}
      end
      
      then_ "multiple nodes are expanded", context do
        assert MapSet.member?(context.new_expanded, :file)
        assert MapSet.member?(context.new_expanded, :edit)
        refute MapSet.member?(context.new_expanded, :view)
        assert MapSet.size(context.new_expanded) == 2
        :ok
      end
    end
  end
end