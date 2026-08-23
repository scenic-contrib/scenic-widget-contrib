defmodule ScenicWidgets.MenuBarBasicSpex do
  @moduledoc """
  Bare bones MenuBar spex - just establishes the test loop.

  This is the starting point for spex-driven development.
  Tests will be added incrementally as we build up the component.
  """

  use SexySpex
  alias ScenicWidgets.TestHelpers.ScriptInspector

  setup_all do
    # Ensure all required applications are started
    {:ok, _} = Application.ensure_all_started(:scenic)
    {:ok, _} = Application.ensure_all_started(:scenic_driver_local)

    # Start the scenic_widget_contrib application
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end

    # Wait for modules to load
    Process.sleep(100)

    # Cleanup on exit
    on_exit(fn ->
      if Code.ensure_loaded?(WidgetWorkbench) and
         function_exported?(WidgetWorkbench, :running?, 0) and
         WidgetWorkbench.running?() do
        IO.puts("🛑 Stopping Widget Workbench...")
        WidgetWorkbench.stop()
        Process.sleep(100)
      end
    end)

    :ok
  end

  spex "MenuBar Basic Test",
    description: "Minimal test to establish dev/test loop with Widget Workbench",
    tags: [:menubar, :basic] do

    scenario "Widget Workbench can be started", context do
      given_ "Widget Workbench is not yet running", context do
        # Verify workbench isn't already running
        case Process.whereis(:main_viewport) do
          nil ->
            IO.puts("✓ Viewport not running yet, will start fresh")
            {:ok, context}
          _pid ->
            IO.puts("✓ Viewport already running from previous test")
            {:ok, context}
        end
      end

      when_ "we start Widget Workbench" do
        IO.puts("🚀 Starting Widget Workbench...")

        case Process.whereis(:main_viewport) do
          nil ->
            {:ok, workbench_pid} = WidgetWorkbench.start(size: {1200, 800}, title: "MenuBar Test")
            assert Process.alive?(workbench_pid), "Widget Workbench process should be alive"
            Process.sleep(1000)  # Wait for initialization
            IO.puts("✅ Widget Workbench started successfully")
            :ok
          _pid ->
            IO.puts("✅ Widget Workbench already running")
            :ok
        end
      end

      then_ "Widget Workbench is visible and running" do
        # Verify viewport is registered and alive
        vp_pid = Process.whereis(:main_viewport)
        assert vp_pid != nil, "Viewport should be registered"
        assert Process.alive?(vp_pid), "Viewport should be alive"

        # Check viewport info
        {:ok, vp_info} = Scenic.ViewPort.info(:main_viewport)
        assert vp_info.name == :main_viewport
        assert vp_info.size == {1200, 800}

        IO.puts("✅ Widget Workbench viewport is running on port 9998")
        IO.puts("   You should see a window titled 'MenuBar Test'")

        # Give it a moment to render
        Process.sleep(500)

        # Try to get rendered content (may be empty initially)
        rendered = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Rendered content:\n#{rendered}\n")

        :ok
      end
    end
  end
end
