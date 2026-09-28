defmodule ScenicWidgets.MenuBarSubmenuTestSpex do
  @moduledoc """
  Tests sub-menu and nested menu functionality in MenuBar.
  """
  use SexySpex
  
  alias ScenicWidgets.TestHelpers.ScriptInspector
  
  setup_all do
    # Start the application
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end
    
    # Create a test scene with sub-menus
    defmodule TestSubmenuScene do
      use Scenic.Scene
      alias Scenic.Graph
      alias ScenicWidgets.MenuBar
      alias Widgex.Frame
      
      def init(scene, _params, _opts) do
        # Create MenuBar with sub-menus
        menu_bar_data = %{
          frame: Frame.new(%{
            pin: {100, 50},
            size: {800, 40}
          }),
          menu_map: [
            {:sub_menu, "File", [
              {"new", "New"},
              {"open", "Open..."},
              {:sub_menu, "Recent Files", [
                {"file1", "document1.txt"},
                {"file2", "project.ex"},
                {"file3", "config.yml"},
                {:sub_menu, "More Recent", [
                  {"file4", "old_file1.txt"},
                  {"file5", "old_file2.txt"}
                ]}
              ]},
              {"save", "Save"},
              {"quit", "Quit"}
            ]},
            {:sub_menu, "Edit", [
              {"undo", "Undo"},
              {"redo", "Redo"},
              {:sub_menu, "Transform", [
                {"upper", "Uppercase"},
                {"lower", "Lowercase"},
                {:sub_menu, "Advanced", [
                  {"camel", "CamelCase"},
                  {"snake", "snake_case"}
                ]}
              ]},
              {"cut", "Cut"},
              {"copy", "Copy"},
              {"paste", "Paste"}
            ]},
            {:sub_menu, "View", [
              {"zoom_in", "Zoom In"},
              {"zoom_out", "Zoom Out"},
              {:sub_menu, "Panels", [
                {"sidebar", "Toggle Sidebar"},
                {"terminal", "Toggle Terminal"},
                {:sub_menu, "Tools", [
                  {"explorer", "File Explorer"},
                  {"search", "Search Panel"},
                  {"debug", "Debug Console"}
                ]}
              ]}
            ]}
          ]
        }
        
        # Build graph with MenuBar
        graph = Graph.build()
        |> MenuBar.add_to_graph(menu_bar_data, id: :test_submenu_bar)
        
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
      name: :test_submenu_viewport,
      size: {1200, 800},
      theme: :dark,
      default_scene: {TestSubmenuScene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :scenic_driver,
          window: [
            resizeable: false,
            title: "MenuBar Submenu Test"
          ],
          debug: false
        ]
      ]
    ]
    
    {:ok, _pid} = Scenic.ViewPort.start_link(viewport_config)
    Process.sleep(1000)  # Wait for viewport to initialize
    
    on_exit(fn ->
      if pid = Process.whereis(:test_submenu_viewport) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)
    
    :ok
  end

  spex "MenuBar Sub-menu Functionality",
    description: "Tests that sub-menus and nested menus work properly",
    tags: [:menubar, :submenu, :nested] do

    scenario "Sub-menus are indicated with visual cues", context do
      given_ "MenuBar with sub-menus is loaded", context do
        {:ok, context}
      end

      when_ "File menu is opened", context do
        viewport_pid = Process.whereis(:test_submenu_viewport)
        
        # Click on File menu
        file_menu_x = 100 + 30  # frame.x + padding
        file_menu_y = 50 + 20   # frame.y + center
        
        send(viewport_pid, {:cursor_button, {:btn_left, 1, [], {file_menu_x, file_menu_y}}})
        Process.sleep(10)
        send(viewport_pid, {:cursor_button, {:btn_left, 0, [], {file_menu_x, file_menu_y}}})
        Process.sleep(200)
        
        {:ok, context}
      end

      then_ "sub-menu items show arrow indicators", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Regular items should be visible
        assert ScriptInspector.rendered_text_contains?("New"),
               "New item should be visible"
        assert ScriptInspector.rendered_text_contains?("Save"),
               "Save item should be visible"
        
        # Sub-menu item should be visible
        assert ScriptInspector.rendered_text_contains?("Recent Files"),
               "Recent Files sub-menu should be visible"
        
        # TODO: Check for arrow indicator (►) if implemented
        
        :ok
      end
    end

    scenario "Hovering over sub-menu opens nested menu", context do
      given_ "File menu is already open", context do
        # Ensure File menu is open from previous test
        assert ScriptInspector.rendered_text_contains?("Recent Files"),
               "File dropdown should be open"
        {:ok, context}
      end

      when_ "user hovers over Recent Files sub-menu", context do
        viewport_pid = Process.whereis(:test_submenu_viewport)
        
        # Hover over Recent Files (should be 3rd item in File menu)
        recent_files_x = 100 + 10  # Menu x + padding
        recent_files_y = 50 + 40 + 5 + (30 * 2) + 15  # Below menubar + 2 items + half height
        
        send(viewport_pid, {:cursor_pos, {recent_files_x, recent_files_y}})
        Process.sleep(300)  # Allow time for sub-menu to open
        
        {:ok, context}
      end

      then_ "Recent Files sub-menu opens to the side", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Recent files should be visible
        assert ScriptInspector.rendered_text_contains?("document1.txt"),
               "Recent file 1 should be visible"
        assert ScriptInspector.rendered_text_contains?("project.ex"),
               "Recent file 2 should be visible"
        assert ScriptInspector.rendered_text_contains?("config.yml"),
               "Recent file 3 should be visible"
        
        # Should also see nested sub-menu
        assert ScriptInspector.rendered_text_contains?("More Recent"),
               "Nested sub-menu should be visible"
        
        :ok
      end
    end

    scenario "Deep nesting - third level sub-menus", context do
      given_ "Recent Files sub-menu is open", context do
        # From previous scenario
        assert ScriptInspector.rendered_text_contains?("More Recent"),
               "Recent Files sub-menu should be open"
        {:ok, context}
      end

      when_ "user hovers over More Recent nested sub-menu", context do
        viewport_pid = Process.whereis(:test_submenu_viewport)
        
        # Hover over More Recent (should be last item in Recent Files sub-menu)
        more_recent_x = 100 + 150 + 10  # Offset to right for sub-menu
        more_recent_y = 50 + 40 + 5 + (30 * 5) + 15  # Position of More Recent item
        
        send(viewport_pid, {:cursor_pos, {more_recent_x, more_recent_y}})
        Process.sleep(300)  # Allow time for nested sub-menu
        
        {:ok, context}
      end

      then_ "third level menu opens correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Third level items should be visible
        assert ScriptInspector.rendered_text_contains?("old_file1.txt"),
               "Third level item 1 should be visible"
        assert ScriptInspector.rendered_text_contains?("old_file2.txt"),
               "Third level item 2 should be visible"
        
        :ok
      end
    end

    scenario "Clicking sub-menu item in nested menu", context do
      given_ "deep nested menu is open", context do
        # From previous scenario
        assert ScriptInspector.rendered_text_contains?("old_file1.txt"),
               "Nested menu should be open"
        {:ok, context}
      end

      when_ "user clicks on old_file1.txt", context do
        viewport_pid = Process.whereis(:test_submenu_viewport)
        
        # Click on old_file1.txt
        item_x = 100 + 300 + 10  # Two levels of offset
        item_y = 50 + 40 + 5 + (30 * 6) + 15  # Position of item
        
        send(viewport_pid, {:cursor_button, {:btn_left, 1, [], {item_x, item_y}}})
        Process.sleep(10)
        send(viewport_pid, {:cursor_button, {:btn_left, 0, [], {item_x, item_y}}})
        Process.sleep(200)
        
        {:ok, context}
      end

      then_ "all menus close after selection", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # All dropdowns should be closed
        refute ScriptInspector.rendered_text_contains?("old_file1.txt"),
               "Nested menu should be closed"
        refute ScriptInspector.rendered_text_contains?("Recent Files"),
               "Sub-menu should be closed"
        refute ScriptInspector.rendered_text_contains?("New"),
               "Main menu should be closed"
        
        # But menu bar headers should still be visible
        assert ScriptInspector.rendered_text_contains?("File"),
               "Menu headers should remain visible"
        assert ScriptInspector.rendered_text_contains?("Edit"),
               "Menu headers should remain visible"
        
        :ok
      end
    end

    scenario "Moving away from sub-menu closes it", context do
      given_ "Edit menu with Transform sub-menu is open", context do
        viewport_pid = Process.whereis(:test_submenu_viewport)
        
        # Open Edit menu
        edit_menu_x = 100 + 150 + 30  # Second menu
        edit_menu_y = 50 + 20
        
        send(viewport_pid, {:cursor_button, {:btn_left, 1, [], {edit_menu_x, edit_menu_y}}})
        Process.sleep(10)
        send(viewport_pid, {:cursor_button, {:btn_left, 0, [], {edit_menu_x, edit_menu_y}}})
        Process.sleep(200)
        
        # Hover over Transform sub-menu
        transform_x = 100 + 150 + 10
        transform_y = 50 + 40 + 5 + (30 * 2) + 15  # Third item
        
        send(viewport_pid, {:cursor_pos, {transform_x, transform_y}})
        Process.sleep(300)
        
        assert ScriptInspector.rendered_text_contains?("Uppercase"),
               "Transform sub-menu should be open"
        
        {:ok, context}
      end

      when_ "user moves cursor back to main Edit menu", context do
        viewport_pid = Process.whereis(:test_submenu_viewport)
        
        # Move to Undo item
        undo_x = 100 + 150 + 10
        undo_y = 50 + 40 + 5 + 15  # First item
        
        send(viewport_pid, {:cursor_pos, {undo_x, undo_y}})
        Process.sleep(300)
        
        {:ok, context}
      end

      then_ "Transform sub-menu closes", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        # Transform sub-menu should be closed
        refute ScriptInspector.rendered_text_contains?("Uppercase"),
               "Transform sub-menu should be closed"
        
        # But Edit menu should still be open
        assert ScriptInspector.rendered_text_contains?("Undo"),
               "Edit menu should remain open"
        assert ScriptInspector.rendered_text_contains?("Cut"),
               "Edit menu items should be visible"
        
        :ok
      end
    end
  end
end