defmodule ScenicWidgets.MenuBarSimpleTest.TestScene do
  use Scenic.Scene
  alias ScenicWidgets.MenuBar
  alias Scenic.Graph
  
  @impl true
  def init(scene, _params, _opts) do
    menu_data = %{
      frame: %{
        pin: %{x: 100, y: 50},
        size: %{width: 600, height: 40}
      },
      menu_map: %{
        file: {"File", [
          {"new", "New"},
          {"open", "Open..."},
          {"save", "Save"},
          {"quit", "Quit"}
        ]},
        edit: {"Edit", [
          {"undo", "Undo"},
          {"copy", "Copy"},
          {"paste", "Paste"}
        ]},
        view: {"View", [
          {"zoom_in", "Zoom In"},
          {"zoom_out", "Zoom Out"}
        ]},
        help: {"Help", [
          {"about", "About"}
        ]}
      }
    }
    
    graph =
      Graph.build()
      |> MenuBar.add_to_graph(menu_data, id: :test_menubar)
    
    scene = push_graph(scene, graph)
    {:ok, scene}
  end
  
  @impl true
  def handle_event({:menu_item_clicked, item_id}, _from, scene) do
    send(:test_process, {:menu_clicked, item_id})
    {:noreply, scene}
  end
end

defmodule ScenicWidgets.MenuBarSimpleTest do
  @moduledoc """
  Simple test for MenuBar that loads it directly without Widget Workbench UI navigation.
  This allows us to test the MenuBar functionality without the complexity of clicking through UI.
  """
  use ExUnit.Case
  
  alias ScenicWidgets.MenuBar
  alias Scenic.{Graph, ViewPort}
  alias ScenicMcp.Probes
  
  setup do
    # Start scenic and scenic_widget_contrib apps
    {:ok, _} = Application.ensure_all_started(:scenic)
    {:ok, _} = Application.ensure_all_started(:scenic_widget_contrib)
    
    # Start viewport with our test scene
    viewport_config = [
      name: :main_viewport,
      size: {1200, 800},
      theme: :dark,
      default_scene: {ScenicWidgets.MenuBarSimpleTest.TestScene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :scenic_driver,
          window: [
            resizeable: false,
            title: "MenuBar Test"
          ],
          on_close: :stop_system,
          debug: false,
          cursor: true,
          antialias: true,
          layer: 0,
          opacity: 255,
          position: [
            scaled: false,
            centered: false,
            orientation: :normal
          ]
        ]
      ]
    ]
    
    {:ok, viewport} = ViewPort.start_link(viewport_config)
    
    # Register test process to receive menu events
    Process.register(self(), :test_process)
    
    # Wait for scene to start
    Process.sleep(500)
    
    on_exit(fn ->
      Process.unregister(:test_process)
      ViewPort.stop(viewport)
      Process.sleep(100)
    end)
    
    {:ok, %{viewport: viewport}}
  end
  
  test "MenuBar renders with all menu items", _context do
    # Get rendered text
    script_data = Probes.script_table()
    text_ops = Enum.filter(script_data, fn {_id, ops} ->
      Enum.any?(ops, fn op -> match?({:draw_text, _, _, _}, op) end)
    end)
    
    # Extract text
    rendered_text = Enum.flat_map(text_ops, fn {_id, ops} ->
      Enum.filter_map(
        ops,
        fn op -> match?({:draw_text, _, text, _}, op) end,
        fn {:draw_text, _, text, _} -> text end
      )
    end)
    |> Enum.join(" ")
    
    # Verify all menu headers are visible
    assert String.contains?(rendered_text, "File")
    assert String.contains?(rendered_text, "Edit")
    assert String.contains?(rendered_text, "View")
    assert String.contains?(rendered_text, "Help")
  end
  
  test "Click on File menu opens dropdown", _context do
    # Click on File menu (at position 100 + padding, 50 + height/2)
    Probes.send_mouse_click(120, 70)
    Process.sleep(100)
    
    # Get rendered text
    script_data = Probes.script_table()
    text_ops = Enum.filter(script_data, fn {_id, ops} ->
      Enum.any?(ops, fn op -> match?({:draw_text, _, _, _}, op) end)
    end)
    
    rendered_text = Enum.flat_map(text_ops, fn {_id, ops} ->
      Enum.filter_map(
        ops,
        fn op -> match?({:draw_text, _, text, _}, op) end,
        fn {:draw_text, _, text, _} -> text end
      )
    end)
    |> Enum.join(" ")
    
    # Verify dropdown items are visible
    assert String.contains?(rendered_text, "New")
    assert String.contains?(rendered_text, "Open...")
    assert String.contains?(rendered_text, "Save")
    assert String.contains?(rendered_text, "Quit")
  end
  
  test "Click on menu item sends event", _context do
    # Open File menu
    Probes.send_mouse_click(120, 70)
    Process.sleep(100)
    
    # Click on "New" item (first item in dropdown)
    Probes.send_mouse_click(130, 110)
    Process.sleep(100)
    
    # Should receive menu event
    assert_receive {:menu_clicked, "new"}, 500
  end
  
  test "Click outside closes dropdown", _context do
    # Open File menu
    Probes.send_mouse_click(120, 70)
    Process.sleep(100)
    
    # Click outside
    Probes.send_mouse_click(500, 300)
    Process.sleep(100)
    
    # Get rendered text
    script_data = Probes.script_table()
    text_ops = Enum.filter(script_data, fn {_id, ops} ->
      Enum.any?(ops, fn op -> match?({:draw_text, _, _, _}, op) end)
    end)
    
    rendered_text = Enum.flat_map(text_ops, fn {_id, ops} ->
      Enum.filter_map(
        ops,
        fn op -> match?({:draw_text, _, text, _}, op) end,
        fn {:draw_text, _, text, _} -> text end
      )
    end)
    |> Enum.join(" ")
    
    # Dropdown items should not be visible
    refute String.contains?(rendered_text, "New")
    refute String.contains?(rendered_text, "Open...")
  end
end