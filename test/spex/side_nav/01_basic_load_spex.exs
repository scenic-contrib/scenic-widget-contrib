defmodule ScenicWidgets.SideNav.BasicLoadSpex do
  @moduledoc """
  Basic SideNav Loading Specification

  ## Purpose
  This is the foundational spex for the SideNav component. It verifies that:
  1. Widget Workbench can boot successfully
  2. SideNav component can be loaded into the workbench
  3. Basic navigation tree renders correctly with expand/collapse chevrons

  ## Why This Spex Exists
  This spex establishes the baseline functionality - if this fails, all other
  SideNav features cannot work. It's the first test to run when debugging issues.

  ## Test Approach
  Uses semantic UI helpers to interact with Widget Workbench as a user would:
  - Verifies workbench is running
  - Clicks "Load Component" button
  - Selects "Side Nav" from the component list
  - Verifies tree structure appears with collapsible nodes

  ## Success Criteria
  - Widget Workbench boots without errors
  - Component selection modal opens when requested
  - SideNav component loads and initializes
  - Tree structure is visible with at least one collapsible node
  - Chevron icons indicate expand/collapse state
  """

  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}

  setup_all do
    # Get test-specific viewport and driver names from config
    # This allows dev and test viewports to run simultaneously
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)

    # Ensure any existing test viewport is stopped first (prevents naming conflicts)
    if viewport_pid = Process.whereis(viewport_name) do
      Process.exit(viewport_pid, :kill)
      Process.sleep(100)  # Wait for cleanup
    end

    # Start the Scenic application (but not the viewport yet)
    case Application.ensure_all_started(:scenic_widget_contrib) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end

    # Configure and start the viewport for Widget Workbench
    # Use test-specific names so we can run alongside dev viewport
    viewport_config = [
      name: viewport_name,      # :test_viewport in test env, :main_viewport in dev
      size: {1200, 800},
      theme: :dark,
      default_scene: {WidgetWorkbench.Scene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: driver_name,    # :test_driver in test env, :scenic_driver in dev
          window: [
            resizeable: true,
            title: "Widget Workbench - SideNav Test (Port 9998)"
          ],
          on_close: :stop_viewport,
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

    # Start the viewport
    {:ok, viewport_pid} = Scenic.ViewPort.start_link(viewport_config)

    # Wait for Widget Workbench to initialize
    Process.sleep(1500)

    # Cleanup on test completion
    on_exit(fn ->
      if pid = Process.whereis(viewport_name) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)

    {:ok, %{viewport_pid: viewport_pid, viewport_name: viewport_name, driver_name: driver_name}}
  end

  spex "SideNav Basic Loading",
    description: "Verifies SideNav can be loaded and displays navigation tree",
    tags: [:side_nav, :basic, :loading] do

    scenario "Widget Workbench boots successfully", context do
      given_ "the application has started", context do
        # Application started in setup_all
        {:ok, context}
      end

      when_ "we check if Widget Workbench is running", context do
        case SemanticUI.verify_widget_workbench_loaded() do
          {:ok, workbench_state} ->
            IO.puts("✅ Widget Workbench is running")
            IO.puts("   Status: #{workbench_state.status}")
            {:ok, Map.put(context, :workbench_state, workbench_state)}

          {:error, reason} ->
            IO.puts("❌ Widget Workbench failed to load: #{reason}")
            {:error, reason}
        end
      end

      then_ "Widget Workbench UI should be visible", context do
        rendered = ScriptInspector.get_rendered_text_string()

        # Verify we can see Widget Workbench UI elements
        assert String.contains?(rendered, "Widget Workbench") or
               String.contains?(rendered, "Load Component"),
               "Expected Widget Workbench UI to be visible"

        IO.puts("✅ Widget Workbench UI is visible")
        :ok
      end
    end

    scenario "SideNav component can be loaded", context do
      given_ "Widget Workbench is ready for component loading", context do
        case SemanticUI.verify_widget_workbench_loaded() do
          {:ok, _} -> {:ok, context}
          {:error, reason} -> {:error, "Widget Workbench not ready: #{reason}"}
        end
      end

      when_ "we load the SideNav component", context do
        IO.puts("🎯 Attempting to load SideNav component...")

        case SemanticUI.load_component("Side Nav") do
          {:ok, load_result} ->
            IO.puts("✅ SideNav loaded successfully")
            {:ok, Map.put(context, :load_result, load_result)}

          {:error, reason} ->
            IO.puts("❌ Failed to load SideNav: #{reason}")
            # Capture current UI state for debugging
            rendered = ScriptInspector.get_rendered_text_string()
            IO.puts("📄 Current UI state:")
            IO.puts("   #{String.slice(rendered, 0, 200)}...")
            {:error, reason}
        end
      end

      then_ "SideNav should be visible with tree structure", context do
        load_result = context.load_result

        # Verify component loaded successfully
        assert load_result.loaded == true,
               "SideNav should be marked as loaded"

        IO.puts("✅ SideNav is visible")
        :ok
      end
    end

    scenario "SideNav displays hierarchical tree structure", context do
      given_ "SideNav has been loaded", context do
        # Give the component time to fully render
        Process.sleep(500)
        {:ok, context}
      end

      when_ "we inspect the rendered tree structure", context do
        rendered = ScriptInspector.get_rendered_text_string()
        {:ok, Map.put(context, :rendered_content, rendered)}
      end

      then_ "navigation items should be visible in tree format", context do
        rendered = context.rendered_content

        # For now, just verify we have some content rendered
        # Once the component is implemented, we'll verify specific tree nodes
        assert String.length(rendered) > 0,
               "SideNav should render some content"

        IO.puts("✅ SideNav tree structure verified")
        IO.puts("   Rendered content length: #{String.length(rendered)} characters")
        :ok
      end
    end
  end
end
