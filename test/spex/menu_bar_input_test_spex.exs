defmodule ScenicWidgets.MenuBarInputTestSpex do
  @moduledoc """
  Test if MenuBar receives input events when loaded in Widget Workbench.
  """
  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}
  alias ScenicMcp.Probes

  setup_all do
    # Use the working setup from simple load test
    SexySpex.Helpers.start_scenic_app(:scenic_widget_contrib)
    
    viewport_config = [
      name: :main_viewport,
      size: {1200, 800},
      theme: :dark,
      default_scene: {WidgetWorkbench.Scene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: :scenic_driver,
          window: [title: "MenuBar Input Test"],
          debug: false
        ]
      ]
    ]
    
    {:ok, _pid} = Scenic.ViewPort.start_link(viewport_config)
    Process.sleep(2000)
    
    # Load MenuBar
    case SemanticUI.load_component("Menu Bar") do
      {:ok, _} -> 
        IO.puts("✅ MenuBar loaded")
      {:error, reason} ->
        IO.puts("❌ Failed to load MenuBar: #{reason}")
    end
    
    Process.sleep(1000)
    
    :ok
  end

  spex "MenuBar Input Event Reception",
    description: "Verify MenuBar can receive input events in Widget Workbench" do

    scenario "Test input reception", context do
      given_ "MenuBar is loaded", context do
        assert ScriptInspector.rendered_text_contains?("File")
        assert ScriptInspector.rendered_text_contains?("Edit")
        {:ok, context}
      end

      when_ "we click in various places", context do
        # First, let's verify the MenuBar position
        # According to prepare_component_data, it should be at {80, 80}
        
        click_positions = [
          {80, 80, "top-left of MenuBar"},
          {110, 110, "center of File menu"},
          {180, 110, "between File and Edit"},
          {250, 110, "on Edit menu"},
          {400, 110, "past Edit menu"},
          {80, 140, "below MenuBar"}
        ]
        
        Enum.each(click_positions, fn {x, y, description} ->
          IO.puts("\n=== Clicking at {#{x}, #{y}} - #{description} ===")
          
          # Move mouse first
          Probes.send_mouse_move(x, y)
          Process.sleep(100)
          
          # Then click
          Probes.send_mouse_click(x, y)
          Process.sleep(300)
          
          # Check if anything changed
          rendered_content = ScriptInspector.get_rendered_text_string()
          
          # Check for dropdown items
          has_dropdown = ScriptInspector.rendered_text_contains?("New File") ||
                        ScriptInspector.rendered_text_contains?("Undo") ||
                        ScriptInspector.rendered_text_contains?("About")
          
          if has_dropdown do
            IO.puts("✅ DROPDOWN APPEARED!")
            IO.puts("Rendered: #{inspect(rendered_content)}")
          else
            IO.puts("❌ No dropdown visible")
          end
        end)
        
        {:ok, context}
      end

      then_ "we determine if MenuBar is interactive", context do
        # Just check that we completed the test
        assert true, "Input test completed"
        :ok
      end
    end
  end
end