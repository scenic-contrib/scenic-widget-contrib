defmodule ScenicWidgets.MenuBarComprehensiveFixedSpex do
  @moduledoc """
  FIXED MenuBar Comprehensive Spex - Complete desktop menubar functionality.
  
  This version directly loads the MenuBar component without relying on UI interaction.
  """
  use SexySpex
  
  alias ScenicWidgets.TestHelpers.ScriptInspector
  
  setup_all do
    # Start the application
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end
    
    # Create a custom scene that directly loads MenuBar
    defmodule TestMenuBarScene do
      use Scenic.Scene
      alias Scenic.Graph
      alias ScenicWidgets.MenuBar
      alias Widgex.Frame
      
      def init(scene, _params, _opts) do
        # Create MenuBar data
        menu_bar_data = %{
          frame: Frame.new(%{
            pin: {100, 50},
            size: {600, 40}
          }),
          menu_map: [
            {:sub_menu, "File", [
              {"new", "New"},
              {"open", "Open..."},
              {"save", "Save"},
              {"save_as", "Save As..."},
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
              {"reset_zoom", "Reset Zoom"},
              {"full_screen", "Full Screen"},
              {"toggle_sidebar", "Toggle Sidebar"}
            ]},
            {:sub_menu, "Help", [
              {"documentation", "Documentation"},
              {"about", "About"}
            ]}
          ]
        }
        
        # Build graph with MenuBar
        graph = Graph.build()
        |> MenuBar.add_to_graph(menu_bar_data, id: :test_menu_bar)
        
        scene = scene
        |> assign(graph: graph)
        |> push_graph(graph)
        
        {:ok, scene}
      end
      
      def handle_event({:menu_item_clicked, item_id}, _from, scene) do
        IO.puts("Menu item clicked: #{inspect(item_id)}")
        {:noreply, scene}
      end
    end
    
    # Start viewport with our test scene
    viewport_config = [
      name: :test_viewport,
      size: {1200, 800},
      theme: :dark,
      default_scene: {TestMenuBarScene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :scenic_driver,
          window: [
            resizeable: false,
            title: "MenuBar Comprehensive Test"
          ],
          debug: false
        ]
      ]
    ]
    
    {:ok, _pid} = Scenic.ViewPort.start_link(viewport_config)
    Process.sleep(1000)  # Wait for viewport to initialize
    
    on_exit(fn ->
      if pid = Process.whereis(:test_viewport) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)
    
    :ok
  end

  spex "Fixed MenuBar Comprehensive Functionality",
    description: "Tests MenuBar directly without Widget Workbench",
    tags: [:menubar, :comprehensive, :fixed] do

    scenario "MenuBar renders correctly", context do
      given_ "MenuBar is loaded in test scene", context do
        # MenuBar should already be loaded from setup_all
        {:ok, context}
      end

      when_ "we inspect the rendered content", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        {:ok, Map.put(context, :rendered_content, rendered_content)}
      end

      then_ "all menu headers are visible", context do
        IO.puts("Rendered content: #{inspect(context.rendered_content)}")
        
        assert ScriptInspector.rendered_text_contains?("File"), 
               "File menu should be visible"
        assert ScriptInspector.rendered_text_contains?("Edit"),
               "Edit menu should be visible"
        assert ScriptInspector.rendered_text_contains?("View"),
               "View menu should be visible" 
        assert ScriptInspector.rendered_text_contains?("Help"),
               "Help menu should be visible"
        
        :ok
      end
    end

    scenario "Click-to-open dropdown behavior", context do
      given_ "MenuBar in default state", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        refute ScriptInspector.rendered_text_contains?("New"),
               "Dropdown items should not be visible initially"
        {:ok, context}
      end

      when_ "user clicks on File menu", context do
        # Get viewport pid
        viewport_pid = Process.whereis(:test_viewport)
        
        # Click on File menu position
        file_menu_x = 100 + 30  # frame.x + some padding
        file_menu_y = 50 + 20   # frame.y + vertical center
        
        # Send click event
        send(viewport_pid, {:cursor_button, {:btn_left, 1, [], {file_menu_x, file_menu_y}}})
        Process.sleep(10)
        send(viewport_pid, {:cursor_button, {:btn_left, 0, [], {file_menu_x, file_menu_y}}})
        Process.sleep(100)
        
        {:ok, context}
      end

      then_ "File dropdown opens", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        assert ScriptInspector.rendered_text_contains?("New"),
               "New option should be visible in dropdown"
        assert ScriptInspector.rendered_text_contains?("Open..."),
               "Open option should be visible"
        assert ScriptInspector.rendered_text_contains?("Save"),
               "Save option should be visible"
        assert ScriptInspector.rendered_text_contains?("Quit"),
               "Quit option should be visible"
        
        :ok
      end
    end

    scenario "Hover navigation when active", context do
      given_ "File menu is already open", context do
        # Ensure File menu is open from previous test
        assert ScriptInspector.rendered_text_contains?("New"),
               "File dropdown should be open"
        {:ok, context}
      end

      when_ "user hovers over Edit menu", context do
        viewport_pid = Process.whereis(:test_viewport)
        
        # Move mouse to Edit menu
        edit_menu_x = 100 + 30 + 150  # Move right to Edit
        edit_menu_y = 50 + 20
        
        send(viewport_pid, {:cursor_pos, {edit_menu_x, edit_menu_y}})
        Process.sleep(100)
        
        {:ok, context}
      end

      then_ "Edit dropdown opens and File closes", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # File items should be hidden
        refute ScriptInspector.rendered_text_contains?("New"),
               "File dropdown should be closed"
        
        # Edit items should be visible
        assert ScriptInspector.rendered_text_contains?("Undo"),
               "Edit dropdown should be open"
        assert ScriptInspector.rendered_text_contains?("Copy"),
               "Copy option should be visible"
        
        :ok
      end
    end

    scenario "Click outside closes dropdowns", context do
      given_ "Edit menu is open", context do
        assert ScriptInspector.rendered_text_contains?("Undo"),
               "Edit dropdown should be open"
        {:ok, context}
      end

      when_ "user clicks outside menubar", context do
        viewport_pid = Process.whereis(:test_viewport)
        
        # Click far outside
        outside_x = 500
        outside_y = 300
        
        send(viewport_pid, {:cursor_button, {:btn_left, 1, [], {outside_x, outside_y}}})
        Process.sleep(10)
        send(viewport_pid, {:cursor_button, {:btn_left, 0, [], {outside_x, outside_y}}})
        Process.sleep(100)
        
        {:ok, context}
      end

      then_ "all dropdowns close", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        refute ScriptInspector.rendered_text_contains?("Undo"),
               "Edit dropdown should be closed"
        refute ScriptInspector.rendered_text_contains?("New"),
               "No dropdown items should be visible"
        
        # But headers should still be there
        assert ScriptInspector.rendered_text_contains?("File"),
               "Menu headers should remain visible"
        assert ScriptInspector.rendered_text_contains?("Edit"),
               "Menu headers should remain visible"
        
        :ok
      end
    end
  end
end