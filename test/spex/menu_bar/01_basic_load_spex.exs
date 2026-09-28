defmodule ScenicWidgets.MenuBar.BasicLoadSpex do
  @moduledoc """
  Basic MenuBar Loading Specification

  ## Purpose
  This is the foundational spex for the MenuBar component. It verifies that:
  1. Widget Workbench can boot successfully
  2. MenuBar component can be loaded into the workbench
  3. Basic menu headers render correctly

  ## Why This Spex Exists
  This spex establishes the baseline functionality - if this fails, all other
  MenuBar features cannot work. It's the first test to run when debugging issues.

  ## Test Approach
  Uses semantic UI helpers to interact with Widget Workbench as a user would:
  - Verifies workbench is running
  - Clicks "Load Component" button
  - Selects "Menu Bar" from the component list
  - Verifies menu headers appear

  ## Success Criteria
  - Widget Workbench boots without errors
  - Component selection modal opens when requested
  - MenuBar component loads and initializes
  - At least 2 menu headers are visible (File, Edit, View, or Help)
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
            title: "Widget Workbench - MenuBar Test (Port 9998)"
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

  spex "MenuBar Basic Loading",
    description: "Verifies MenuBar can be loaded and displays menu headers",
    tags: [:menubar, :basic, :loading] do

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

    scenario "MenuBar component can be loaded", context do
      given_ "Widget Workbench is ready for component loading", context do
        case SemanticUI.verify_widget_workbench_loaded() do
          {:ok, _} -> {:ok, context}
          {:error, reason} -> {:error, "Widget Workbench not ready: #{reason}"}
        end
      end

      when_ "we load the MenuBar component", context do
        IO.puts("🎯 Attempting to load MenuBar component...")

        case SemanticUI.load_component("Menu Bar") do
          {:ok, load_result} ->
            IO.puts("✅ MenuBar loaded successfully")
            IO.puts("   Menu items found: #{inspect(load_result.menu_items)}")
            {:ok, Map.put(context, :load_result, load_result)}

          {:error, reason} ->
            IO.puts("❌ Failed to load MenuBar: #{reason}")
            # Capture current UI state for debugging
            rendered = ScriptInspector.get_rendered_text_string()
            IO.puts("📄 Current UI state:")
            IO.puts("   #{String.slice(rendered, 0, 200)}...")
            {:error, reason}
        end
      end

      then_ "MenuBar should be visible with menu headers", context do
        load_result = context.load_result

        # Verify component loaded successfully
        assert load_result.loaded == true,
               "MenuBar should be marked as loaded"

        # Verify we have at least 2 menu items (basic sanity check)
        assert length(load_result.menu_items) >= 2,
               "MenuBar should have at least 2 menu headers, found: #{inspect(load_result.menu_items)}"

        IO.puts("✅ MenuBar is visible with #{length(load_result.menu_items)} menu headers")
        :ok
      end
    end

    scenario "MenuBar displays expected menu structure", context do
      given_ "MenuBar has been loaded", context do
        # Give the component time to fully render
        Process.sleep(500)
        {:ok, context}
      end

      when_ "we inspect the rendered menu structure", context do
        rendered = ScriptInspector.get_rendered_text_string()
        {:ok, Map.put(context, :rendered_content, rendered)}
      end

      then_ "standard menu headers should be present", context do
        rendered = context.rendered_content

        # Expected menu headers based on MenuBar implementation
        expected_headers = ["File", "Edit", "View", "Help"]

        found_headers = Enum.filter(expected_headers, fn header ->
          String.contains?(rendered, header)
        end)

        IO.puts("📋 Menu headers found: #{inspect(found_headers)}")
        IO.puts("   (#{length(found_headers)} out of #{length(expected_headers)} expected headers)")

        # We expect to find at least 2 of the standard headers
        assert length(found_headers) >= 2,
               "Should find at least 2 menu headers, found: #{inspect(found_headers)}"

        IO.puts("✅ MenuBar structure verified")
        :ok
      end
    end
  end
end
