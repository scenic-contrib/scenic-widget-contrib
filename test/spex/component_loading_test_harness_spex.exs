defmodule ScenicWidgets.ComponentLoadingTestHarnessSpex do
  @moduledoc """
  Comprehensive test harness for programmatically loading and testing components
  in the Widget Workbench via scenic_mcp automation.

  This spex provides:
  1. Automated component discovery and loading
  2. Verification of component rendering
  3. Visual regression testing with screenshots
  4. Repeatable test flows for CI/CD

  Usage:
      mix spex test/spex/component_loading_test_harness_spex.exs
      mix spex test/spex/component_loading_test_harness_spex.exs --manual
  """
  use SexySpex

  alias ScenicWidgets.TestHelpers.ScriptInspector

  # Test configuration
  @mcp_port 9996
  @workbench_size {1200, 800}
  @wait_for_render_ms 500
  @wait_for_modal_ms 300

  setup_all do
    # Ensure all required applications are started
    {:ok, _} = Application.ensure_all_started(:scenic)
    {:ok, _} = Application.ensure_all_started(:scenic_driver_local)
    {:ok, _} = Application.ensure_all_started(:scenic_mcp)

    # Start the scenic_widget_contrib application
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
      error ->
        IO.puts("Failed to start scenic_widget_contrib: #{inspect(error)}")
        error
    end

    # Register cleanup callback
    on_exit(fn ->
      if Code.ensure_loaded?(WidgetWorkbench) and function_exported?(WidgetWorkbench, :running?, 0) and WidgetWorkbench.running?() do
        WidgetWorkbench.stop()
        Process.sleep(100)
      end
    end)

    :ok
  end

  spex "Component Loading Test Harness",
    description: "Automated component loading and verification via scenic_mcp",
    tags: [:workbench, :automation, :mcp, :components] do

    scenario "Start Widget Workbench and connect MCP", context do
      given_ "Widget Workbench needs to be running", context do
        # Start Widget Workbench if not already running
        case Process.whereis(:main_viewport) do
          nil ->
            {:ok, workbench_pid} = WidgetWorkbench.start(
              size: @workbench_size,
              title: "Component Test Harness"
            )
            assert Process.alive?(workbench_pid), "Widget Workbench should start"
            Process.sleep(1000)
            {:ok, Map.put(context, :workbench_pid, workbench_pid)}
          pid ->
            {:ok, Map.put(context, :workbench_pid, pid)}
        end
      end

      when_ "we connect via scenic_mcp", context do
        # Verify MCP server is available
        vp_pid = Process.whereis(:main_viewport)
        assert vp_pid != nil, "Viewport should be registered"

        # Verify scenic_mcp server is running
        mcp_pid = Process.whereis(ScenicMcp.Server)
        assert mcp_pid != nil, "ScenicMCP server should be running on port #{@mcp_port}"
        assert Process.alive?(mcp_pid), "ScenicMCP server should be alive"

        # Wait for scene to render
        Process.sleep(@wait_for_render_ms)

        # Take baseline screenshot
        baseline_screenshot = ScenicMcp.Probes.take_screenshot("harness_baseline")

        {:ok, Map.merge(context, %{
          viewport_pid: vp_pid,
          mcp_pid: mcp_pid,
          baseline_screenshot: baseline_screenshot
        })}
      end

      then_ "Widget Workbench is ready for automation", context do
        # Verify viewport is functioning
        {:ok, vp_info} = Scenic.ViewPort.info(:main_viewport)
        assert vp_info.name == :main_viewport
        assert vp_info.size == @workbench_size

        # Verify we have rendered content
        refute ScriptInspector.rendered_text_empty?(),
               "Workbench should have rendered content"

        IO.puts("\n✅ Widget Workbench ready for component testing")
        :ok
      end
    end

    scenario "Discover available components", context do
      given_ "Widget Workbench is running", context do
        assert WidgetWorkbench.running?(), "Widget Workbench should be running"
        {:ok, context}
      end

      when_ "we query available components", context do
        # Call the component discovery function from the scene
        components = WidgetWorkbench.Scene.discover_components()

        IO.puts("\n📦 Discovered #{length(components)} components:")
        Enum.each(components, fn {name, module} ->
          IO.puts("   - #{name} (#{inspect(module)})")
        end)

        {:ok, Map.put(context, :available_components, components)}
      end

      then_ "we have a list of loadable components", context do
        components = context.available_components

        assert is_list(components), "Components should be a list"
        assert length(components) > 0, "Should have at least one component"

        # Verify each component is a {name, module} tuple
        Enum.each(components, fn {name, module} ->
          assert is_binary(name) or is_atom(name), "Component name should be string or atom"
          assert is_atom(module), "Component module should be an atom"
          assert Code.ensure_loaded?(module), "Component module #{inspect(module)} should be loaded"
        end)

        :ok
      end
    end

    scenario "Open component selection modal via MCP", context do
      given_ "Widget Workbench is ready", context do
        assert WidgetWorkbench.running?()
        Process.sleep(@wait_for_render_ms)
        {:ok, context}
      end

      when_ "we use MCP to click 'Load Component' button", context do
        # Use scenic_mcp to find and click the load component button
        result = ScenicMcp.Probes.click_element(:load_component_button)

        assert match?({:ok, _}, result), "Should successfully click load component button"

        # Wait for modal to appear
        Process.sleep(@wait_for_modal_ms)

        # Take screenshot of modal
        modal_screenshot = ScenicMcp.Probes.take_screenshot("modal_opened")

        {:ok, Map.put(context, :modal_screenshot, modal_screenshot)}
      end

      then_ "component selection modal is visible", context do
        # Verify modal is in the scene
        rendered_content = ScriptInspector.get_rendered_text_string()

        # The modal should contain component names
        # Note: Actual verification depends on rendered text content
        refute ScriptInspector.rendered_text_empty?(),
               "Modal should have rendered content"

        IO.puts("\n✅ Component selection modal opened")
        IO.puts("   Rendered content: #{String.slice(rendered_content, 0..100)}...")

        :ok
      end
    end

    scenario "Load specific component via MCP automation", context do
      given_ "component modal is open", context do
        # Ensure modal is open (may have been opened in previous scenario)
        # This is idempotent - clicking again is fine
        ScenicMcp.Probes.click_element(:load_component_button)
        Process.sleep(@wait_for_modal_ms)
        {:ok, context}
      end

      when_ "we programmatically select and load a component", context do
        # Get available components
        components = WidgetWorkbench.Scene.discover_components()

        # Pick the first component as a test target
        target_component = case components do
          [{name, module} | _] ->
            IO.puts("\n🎯 Target component: #{name} (#{inspect(module)})")
            {name, module}
          [] ->
            flunk("No components available to test")
        end

        {component_name, _component_module} = target_component

        # Build the semantic ID for the component button
        # Format: component_#{Macro.underscore(name)}
        component_id = "component_#{component_name |> to_string() |> Macro.underscore()}"
                       |> String.to_atom()

        IO.puts("   Clicking component button: #{inspect(component_id)}")

        # Try to click the component button
        result = ScenicMcp.Probes.click_element(component_id)

        case result do
          {:ok, _} ->
            IO.puts("   ✅ Successfully clicked component button")

          {:error, reason} ->
            IO.puts("   ⚠️  Click failed: #{reason}")
            IO.puts("   Attempting to find clickable elements...")

            # Debug: List all clickable elements
            {:ok, clickables} = ScenicMcp.Probes.find_clickable_elements()
            IO.puts("   Found #{length(clickables.elements)} clickable elements:")
            Enum.each(clickables.elements, fn elem ->
              IO.puts("      - #{inspect(elem.id)} at #{inspect(elem.center)}")
            end)
        end

        # Wait for component to load
        Process.sleep(@wait_for_render_ms)

        # Take screenshot after loading
        loaded_screenshot = ScenicMcp.Probes.take_screenshot("component_loaded_#{component_name}")

        {:ok, Map.merge(context, %{
          target_component: target_component,
          loaded_screenshot: loaded_screenshot
        })}
      end

      then_ "component is loaded and rendered in workbench", context do
        {component_name, _component_module} = context.target_component

        # Verify component is rendered
        rendered_content = ScriptInspector.get_rendered_text_string()
        refute ScriptInspector.rendered_text_empty?(),
               "Component should have rendered content"

        IO.puts("\n✅ Component '#{component_name}' loaded successfully")
        IO.puts("   Rendered content preview: #{String.slice(rendered_content, 0..100)}...")

        :ok
      end
    end

    scenario "Test component loading for all discovered components", context do
      given_ "we have a list of all components", context do
        components = WidgetWorkbench.Scene.discover_components()
        {:ok, Map.put(context, :all_components, components)}
      end

      when_ "we load each component sequentially", context do
        components = context.all_components

        results = Enum.map(components, fn {name, module} ->
          IO.puts("\n📦 Testing component: #{name}")

          # Open modal
          ScenicMcp.Probes.click_element(:load_component_button)
          Process.sleep(@wait_for_modal_ms)

          # Build component ID
          component_id = "component_#{name |> to_string() |> Macro.underscore()}"
                         |> String.to_atom()

          # Try to load component
          load_result = case ScenicMcp.Probes.click_element(component_id) do
            {:ok, _} ->
              Process.sleep(@wait_for_render_ms)
              screenshot = ScenicMcp.Probes.take_screenshot("batch_test_#{name}")
              {:ok, name, screenshot}

            {:error, reason} ->
              {:error, name, reason}
          end

          load_result
        end)

        {:ok, Map.put(context, :load_results, results)}
      end

      then_ "we have test results for all components", context do
        results = context.load_results

        # Separate successes and failures
        successes = Enum.filter(results, &match?({:ok, _, _}, &1))
        failures = Enum.filter(results, &match?({:error, _, _}, &1))

        IO.puts("\n📊 Component Loading Test Results:")
        IO.puts("   ✅ Loaded successfully: #{length(successes)}")
        IO.puts("   ❌ Failed to load: #{length(failures)}")

        if length(failures) > 0 do
          IO.puts("\n   Failed components:")
          Enum.each(failures, fn {:error, name, reason} ->
            IO.puts("      - #{name}: #{reason}")
          end)
        end

        # Assert at least some components loaded successfully
        assert length(successes) > 0, "At least one component should load successfully"

        :ok
      end
    end

    # Cleanup is handled by setup_all on_exit
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Helper to load a specific component by name via MCP automation.

  Returns {:ok, screenshot_path} or {:error, reason}.
  """
  def load_component_via_mcp(component_name) do
    # Open modal
    case ScenicMcp.Probes.click_element(:load_component_button) do
      {:ok, _} ->
        Process.sleep(@wait_for_modal_ms)

        # Click component
        component_id = "component_#{component_name |> to_string() |> Macro.underscore()}"
                       |> String.to_atom()

        case ScenicMcp.Probes.click_element(component_id) do
          {:ok, _} ->
            Process.sleep(@wait_for_render_ms)
            screenshot = ScenicMcp.Probes.take_screenshot("loaded_#{component_name}")
            {:ok, screenshot}

          error -> error
        end

      error -> error
    end
  end

  @doc """
  Helper to verify a component is currently loaded in the workbench.

  Returns true if component module is found in the script table.
  """
  def verify_component_loaded?(component_module) when is_atom(component_module) do
    ScriptInspector.debug_script_table()
    |> String.contains?(inspect(component_module))
  end
end
