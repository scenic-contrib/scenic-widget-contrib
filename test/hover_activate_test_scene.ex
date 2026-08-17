defmodule ScenicWidgets.HoverActivateTestScene do
  @moduledoc """
  Test scene for MenuBar hover activation mode
  """
  use Scenic.Scene
  alias Scenic.Graph
  alias ScenicWidgets.MenuBar
  import Scenic.Primitives
  
  @impl true
  def init(scene, _opts, _supervisor_opts) do
    # Create a MenuBar with hover activation enabled
    menu_bar_data = %{
      menu_map: %{
        file: {"File", [
          {"new", "New File"},
          {"open", "Open File"},
          {:sub_menu, "Recent Files", [
            {"doc1", "Document 1.txt"},
            {"doc2", "Document 2.txt"},
            {"doc3", "Document 3.txt"}
          ]},
          {"save", "Save"},
          {"exit", "Exit"}
        ]},
        edit: {"Edit", [
          {"undo", "Undo"},
          {"redo", "Redo"},
          {"cut", "Cut"},
          {"copy", "Copy"},
          {"paste", "Paste"},
          {:sub_menu, "Find", [
            {"find_replace", "Find and Replace"},
            {"find_files", "Find in Files"},
            {:sub_menu, "Advanced", [
              {"regex", "Regular Expression"},
              {"case", "Case Sensitive"},
              {"whole", "Whole Word"}
            ]}
          ]}
        ]},
        view: {"View", [
          {"zoom_in", "Zoom In"},
          {"zoom_out", "Zoom Out"},
          {"fullscreen", "Fullscreen"}
        ]}
      },
      hover_activate: true  # Enable hover activation
    }
    
    graph =
      Graph.build()
      |> text("MenuBar Hover Activation Test", translate: {20, 30})
      |> text("Hover over menu headers to open them automatically", translate: {20, 60}, font_size: 14)
      |> MenuBar.add_to_graph(menu_bar_data, id: :menu_bar, translate: {0, 100})
      |> text("Click outside the menu to close it", translate: {20, 200}, font_size: 14)
    
    scene = push_graph(scene, graph)
    
    {:ok, scene}
  end
  
  @impl true
  def handle_event({:menu_item_clicked, item_id}, _context, scene) do
    IO.puts("Menu item clicked: #{inspect(item_id)}")
    {:noreply, scene}
  end
  
  # Handle click outside to close menu
  @impl true
  def handle_input({:cursor_button, {:btn_left, 1, [], coords}}, _context, scene) do
    # Check if click is outside menu bar area
    {x, y} = coords
    if y < 100 || y > 300 || x < 0 || x > 600 do
      # Click is outside menu bar - send close message
      put_child(scene, :menu_bar, :close_all_menus)
    end
    
    {:noreply, scene}
  end
  
  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end
end