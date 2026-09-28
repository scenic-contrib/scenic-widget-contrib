defmodule ScenicWidgets.MenuBarDebugSpex do
  @moduledoc """
  Debug spex to understand MenuBar input handling.
  """
  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}
  alias ScenicMcp.Probes

  setup_all do
    Application.start(:scenic_widget_contrib)
    
    viewport_config = [
      name: :main_viewport,
      size: {1200, 800},
      theme: :dark,
      default_scene: {WidgetWorkbench.Scene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :scenic_driver,
          window: [title: "MenuBar Debug Test"],
          debug: false
        ]
      ]
    ]
    
    {:ok, _pid} = Scenic.ViewPort.start_link(viewport_config)
    Process.sleep(2000)
    
    # Load MenuBar
    SemanticUI.load_component("Menu Bar")
    Process.sleep(1000)
    
    on_exit(fn ->
      if pid = Process.whereis(:main_viewport) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)
    
    :ok
  end

  spex "Debug MenuBar Click Handling",
    description: "Understand why clicks aren't opening dropdown" do

    scenario "Click on MenuBar", context do
      given_ "MenuBar is loaded", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("Initial render: #{inspect(rendered_content)}")
        
        assert ScriptInspector.rendered_text_contains?("File")
        {:ok, context}
      end

      when_ "we click on File menu", context do
        # Try different coordinates
        coordinates = [
          {110, 110},  # Original
          {90, 100},   # Slightly left
          {100, 95},   # Slightly up
          {120, 110},  # Slightly right
        ]
        
        Enum.each(coordinates, fn {x, y} ->
          IO.puts("\n=== Clicking at {#{x}, #{y}} ===")
          Probes.send_mouse_click(x, y)
          Process.sleep(500)
          
          rendered_content = ScriptInspector.get_rendered_text_string()
          IO.puts("After click: #{inspect(rendered_content)}")
          
          if ScriptInspector.rendered_text_contains?("New File") do
            IO.puts("✅ DROPDOWN OPENED at {#{x}, #{y}}!")
          else
            IO.puts("❌ No dropdown at {#{x}, #{y}}")
          end
        end)
        
        {:ok, context}
      end

      then_ "we should see debug output", context do
        # Just check that we tried
        assert true
        :ok
      end
    end
  end
end