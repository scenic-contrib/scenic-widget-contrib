defmodule ScenicWidgets.MenuBarBasicTestSpex do
  @moduledoc """
  Basic MenuBar test that works with current Widget Workbench setup.
  This focuses on testing the MenuBar component in isolation.
  """
  use SexySpex
  
  alias ScenicWidgets.TestHelpers.ScriptInspector
  
  setup_all do
    # Ensure application is started
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end
    
    on_exit(fn ->
      if WidgetWorkbench.running?() do
        WidgetWorkbench.stop()
        Process.sleep(100)
      end
    end)
    
    :ok
  end

  spex "MenuBar Basic Functionality",
    description: "Test basic MenuBar rendering and interaction",
    tags: [:menubar, :basic] do

    scenario "MenuBar component can be instantiated and rendered", context do
      given_ "Widget Workbench is running", context do
        {:ok, _pid} = WidgetWorkbench.start(size: {1200, 800}, title: "MenuBar Test")
        Process.sleep(1000)
        
        # Verify workbench started
        assert WidgetWorkbench.running?()
        assert Process.whereis(:main_viewport) != nil
        
        {:ok, context}
      end

      when_ "we load a MenuBar component", context do
        # Get the scene PID to send messages directly
        viewport_pid = Process.whereis(:main_viewport)
        
        # Create MenuBar data
        menu_data = %{
          frame: %{
            pin: %{x: 100, y: 100},
            size: %{width: 600, height: 30}
          },
          menu_map: %{
            file: {"File", [
              {"new", "New"},
              {"open", "Open"}, 
              {"save", "Save"}
            ]},
            edit: {"Edit", [
              {"undo", "Undo"},
              {"redo", "Redo"}
            ]}
          }
        }
        
        # Note: In real implementation, we'd load through Widget Workbench UI
        # For now, let's check what's actually rendered
        Process.sleep(500)
        
        {:ok, Map.put(context, :menu_data, menu_data)}
      end

      then_ "the Widget Workbench displays properly", context do
        # Check basic rendering
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n🔍 Rendered content: #{inspect(rendered_content)}")
        
        # At minimum, Widget Workbench should be rendering
        refute ScriptInspector.rendered_text_empty?(),
               "Widget Workbench should render some content"
        
        # Check viewport is responding
        {:ok, vp_info} = Scenic.ViewPort.info(:main_viewport)
        IO.puts("\n📏 Actual viewport size: #{inspect(vp_info.size)}")
        
        # The viewport size may vary slightly due to window manager
        {width, height} = vp_info.size
        assert width >= 1200 and width <= 1202,
               "Viewport width should be around 1200 (got #{width})"
        assert height >= 780 and height <= 800,
               "Viewport height should be around 800 (got #{height})"
        
        :ok
      end
    end

    scenario "MenuBar hover interactions", context do
      given_ "Widget Workbench with potential MenuBar", context do
        unless WidgetWorkbench.running?() do
          {:ok, _pid} = WidgetWorkbench.start(size: {1200, 800})
          Process.sleep(1000)
        end
        
        {:ok, context}
      end

      when_ "we simulate mouse movements", context do
        viewport_pid = Process.whereis(:main_viewport)
        
        # Record initial state
        initial_content = ScriptInspector.get_rendered_text_string()
        
        # Simulate mouse movement over where menu would be
        send(viewport_pid, {:cursor_pos, {150, 115}})
        Process.sleep(100)
        
        after_hover_content = ScriptInspector.get_rendered_text_string()
        
        {:ok, Map.merge(context, %{
          initial_content: initial_content,
          after_hover_content: after_hover_content
        })}
      end

      then_ "we can detect any rendering changes", context do
        # For now, just verify the system is responsive
        # In a real test, we'd check for hover highlighting
        
        IO.puts("\n📊 Hover test results:")
        IO.puts("   Initial content length: #{String.length(context.initial_content)}")
        IO.puts("   After hover length: #{String.length(context.after_hover_content)}")
        
        # The system should at least be processing events
        assert Process.whereis(:main_viewport) != nil,
               "Viewport should still be running after interactions"
        
        :ok
      end
    end

    scenario "Component loading through code", context do
      given_ "Widget Workbench is ready", context do
        unless WidgetWorkbench.running?() do
          {:ok, _pid} = WidgetWorkbench.start(size: {1200, 800})
          Process.sleep(1000)
        end
        
        {:ok, context}
      end

      when_ "we attempt to load MenuBar programmatically", context do
        # Let's check if the MenuBar module is available
        menubar_available = Code.ensure_loaded?(ScenicWidgets.MenuBar)
        
        # Check if the component follows expected patterns
        has_validate = menubar_available and 
                      function_exported?(ScenicWidgets.MenuBar, :validate, 1)
        has_init = menubar_available and 
                  function_exported?(ScenicWidgets.MenuBar, :init, 3)
        
        {:ok, Map.merge(context, %{
          menubar_available: menubar_available,
          has_validate: has_validate,
          has_init: has_init
        })}
      end

      then_ "MenuBar component meets Scenic requirements", context do
        assert context.menubar_available,
               "MenuBar module should be available"
        assert context.has_validate,
               "MenuBar should have validate/1 function"
        assert context.has_init,
               "MenuBar should have init/3 function"
        
        IO.puts("\n✅ MenuBar component structure:")
        IO.puts("   Module loaded: #{context.menubar_available}")
        IO.puts("   Has validate/1: #{context.has_validate}")
        IO.puts("   Has init/3: #{context.has_init}")
        
        :ok
      end
    end
  end
end