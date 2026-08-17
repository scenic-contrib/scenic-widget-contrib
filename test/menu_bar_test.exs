defmodule ScenicWidgets.MenuBarTest do
  use ExUnit.Case, async: true
  
  alias ScenicWidgets.MenuBar
  alias Scenic.Graph
  
  describe "MenuBar component" do
    test "add_to_graph/3 creates proper graph structure" do
      menu_data = %{
        frame: %{
          pin: %{x: 100, y: 50},
          size: %{width: 600, height: 40}
        },
        menu_map: %{
          file: {"File", [
            {"new", "New"},
            {"open", "Open..."},
            {"save", "Save"}
          ]},
          edit: {"Edit", [
            {"undo", "Undo"},
            {"copy", "Copy"}
          ]}
        }
      }
      
      graph = Graph.build()
      result_graph = MenuBar.add_to_graph(graph, menu_data, id: :test_menubar)
      
      # The graph should have been modified
      assert result_graph != graph
      
      # The component should be findable by ID
      assert Graph.get(result_graph, :test_menubar) != nil
    end
    
    test "validate/1 accepts valid data" do
      valid_data = %{
        frame: %{
          pin: %{x: 0, y: 0},
          size: %{width: 800, height: 30}
        },
        menu_map: %{
          file: {"File", []},
          edit: {"Edit", []}
        }
      }
      
      assert {:ok, _} = MenuBar.validate(valid_data)
    end
    
    test "validate/1 rejects invalid data" do
      # Missing frame
      invalid_data1 = %{
        menu_map: %{file: {"File", []}}
      }
      assert {:error, _} = MenuBar.validate(invalid_data1)
      
      # Missing menu_map
      invalid_data2 = %{
        frame: %{pin: %{x: 0, y: 0}, size: %{width: 100, height: 30}}
      }
      assert {:error, _} = MenuBar.validate(invalid_data2)
      
      # Invalid frame structure
      invalid_data3 = %{
        frame: %{x: 0, y: 0},  # Wrong structure
        menu_map: %{}
      }
      assert {:error, _} = MenuBar.validate(invalid_data3)
    end
    
  end
end