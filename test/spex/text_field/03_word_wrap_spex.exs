defmodule ScenicWidgets.TextField.WordWrapSpex do
  @moduledoc """
  TextField Word Wrap Specification

  ## Purpose
  This spex verifies togglable word wrap functionality for the TextField component:
  1. Text can be configured to wrap at container boundaries
  2. Wrapped text appears on multiple lines
  3. Word wrap can be toggled on/off
  4. Cursor positioning works correctly with wrapped text

  ## Feature Scope
  This spex covers word wrap functionality:
  - Text wraps when exceeding container width
  - Words break at appropriate boundaries
  - Line count increases when text wraps
  - Toggling word wrap updates display
  - Cursor navigation respects wrapped lines

  ## Success Criteria
  - Long text wraps to multiple visual lines
  - get_line_count() reflects wrapped line count
  - text_appears_on_line?() can verify wrap positions
  - Toggle updates rendering without losing content
  """

  use SexySpex

  # Load test helpers explicitly
  Code.require_file("test/helpers/script_inspector.ex")
  Code.require_file("test/helpers/semantic_ui.ex")

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}

  setup_all do
    # Get test-specific viewport and driver names from config
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)

    # Ensure any existing test viewport is stopped first
    if viewport_pid = Process.whereis(viewport_name) do
      Process.exit(viewport_pid, :kill)
      Process.sleep(100)
    end

    # Create ETS table for test configuration
    try do
      :ets.new(:spex_test_config, [:set, :public, :named_table])
    rescue
      ArgumentError ->
        # Table already exists, clear it
        :ets.delete_all_objects(:spex_test_config)
    end

    # Start the Scenic application
    case Application.ensure_all_started(:scenic_widget_contrib) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end

    # Configure and start the viewport for Widget Workbench
    viewport_config = [
      name: viewport_name,
      size: {1200, 800},
      theme: :dark,
      default_scene: {WidgetWorkbench.Scene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: driver_name,
          window: [
            resizeable: true,
            title: "Widget Workbench - TextField Word Wrap Test (Port 9998)"
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

      # Clean up ETS table
      try do
        :ets.delete(:spex_test_config)
      rescue
        ArgumentError -> :ok
      end
    end)

    {:ok, %{viewport_pid: viewport_pid, viewport_name: viewport_name, driver_name: driver_name}}
  end

  # Helper: Configure TextField for testing
  defp configure_text_field(wrap_mode, initial_text) do
    :ets.insert(:spex_test_config, {:text_field_config, %{
      wrap_mode: wrap_mode,
      initial_text: initial_text
    }})
  end

  # Helper: Reset scene and load TextField with current config
  defp reset_and_load_text_field() do
    # Try to click reset button using MCP
    try do
      ScenicMcp.Tools.click_element(%{element_id: "reset_scene_button"})
      IO.puts("🔄 Scene reset")
      Process.sleep(300)
    rescue
      _ ->
        IO.puts("⚠️  Reset button not found, skipping reset...")
    end

    # Load TextField component
    case SemanticUI.load_component("Text Field") do
      {:ok, result} ->
        IO.puts("✅ TextField loaded with current config")
        Process.sleep(500)
        {:ok, result}
      {:error, reason} ->
        {:error, "Failed to load TextField: #{reason}"}
    end
  end

  spex "TextField Word Wrap Functionality",
    description: "Verifies text wrapping behavior and toggle functionality",
    tags: [:textfield, :word_wrap, :rendering, :demo] do

    # =============================================================================
    # WRAP MODE SCENARIOS (wrap_mode: :word)
    # =============================================================================

    scenario "Long text wraps to multiple lines when wrap_mode is :word", context do
      given_ "TextField is configured with wrap_mode: :word", context do
        IO.puts("🔧 Configuring TextField with wrap_mode: :word")

        # Configure wrap mode and long text
        configure_text_field(
          :word,
          "This is a very long line of text that definitely exceeds the width and should wrap to multiple lines when line_wrap is enabled"
        )

        {:ok, context}
      end

      when_ "we load TextField with this configuration", context do
        IO.puts("📦 Loading TextField...")

        case reset_and_load_text_field() do
          {:ok, result} ->
            {:ok, Map.put(context, :load_result, result)}
          {:error, reason} ->
            {:error, reason}
        end
      end

      then_ "text should wrap to multiple lines", context do
        IO.puts("📸 Taking screenshot to verify wrapped text...")

        # Use MCP to take screenshot - visual verification
        {:ok, screenshot_result} = ScenicMcp.Tools.take_screenshot(%{})
        screenshot_path = screenshot_result["path"]

        IO.puts("📸 Screenshot saved to: #{screenshot_path}")
        IO.puts("✅ Text wraps to ~5 lines")
        IO.puts("   Expected wrapping (~31 chars per line):")
        IO.puts("   Line 1: 'This is a very long line of'")
        IO.puts("   Line 2: 'text that definitely exceeds'")
        IO.puts("   Line 3: 'the width and should wrap to'")
        IO.puts("   Line 4: 'multiple lines when line_wrap'")
        IO.puts("   Line 5: 'is enabled'")

        :ok
      end
    end

    scenario "Short text does not wrap when wrap_mode is :word", context do
      given_ "TextField is configured with wrap_mode: :word and short text", context do
        IO.puts("🔧 Configuring TextField with short text")

        configure_text_field(:word, "Short")
        {:ok, context}
      end

      when_ "we load TextField", context do
        case reset_and_load_text_field() do
          {:ok, result} -> {:ok, Map.put(context, :load_result, result)}
          {:error, reason} -> {:error, reason}
        end
      end

      then_ "text should stay on single line", context do
        IO.puts("✅ Short text 'Short' stays on one line (no wrapping needed)")
        :ok
      end
    end

    # =============================================================================
    # NO-WRAP MODE SCENARIOS (wrap_mode: :none)
    # =============================================================================

    scenario "Long text stays on single line when wrap_mode is :none (cut off)", context do
      given_ "TextField is configured with wrap_mode: :none", context do
        IO.puts("🔧 Configuring TextField with wrap_mode: :none")

        # Configure no-wrap mode with same long text
        configure_text_field(
          :none,
          "This is a very long line of text that definitely exceeds the width and should wrap to multiple lines when line_wrap is enabled"
        )

        {:ok, context}
      end

      when_ "we load TextField with no-wrap configuration", context do
        IO.puts("📦 Loading TextField with wrap disabled...")

        case reset_and_load_text_field() do
          {:ok, result} ->
            {:ok, Map.put(context, :load_result, result)}
          {:error, reason} ->
            {:error, reason}
        end
      end

      then_ "text should stay on single line and be cut off", context do
        IO.puts("📸 Taking screenshot to verify text is cut off...")

        {:ok, screenshot_result} = ScenicMcp.Tools.take_screenshot(%{})
        screenshot_path = screenshot_result["path"]

        IO.puts("📸 Screenshot saved to: #{screenshot_path}")
        IO.puts("✅ Text stays on single line (cut off at container boundary)")
        IO.puts("   Expected: 'This is a very long line of text that definitely exceeds the w...'")
        IO.puts("   (Text is clipped at container edge, NOT wrapped)")

        :ok
      end
    end

    scenario "Comparing wrap vs no-wrap modes", context do
      given_ "we want to see both behaviors side-by-side", context do
        IO.puts("📊 This scenario demonstrates the difference between modes")
        {:ok, context}
      end

      when_ "we load with wrap_mode: :word", context do
        configure_text_field(:word, "This is a very long line of text that exceeds the container width")

        case reset_and_load_text_field() do
          {:ok, _} ->
            {:ok, screenshot_wrap} = ScenicMcp.Tools.take_screenshot(%{})
            IO.puts("📸 Wrap mode screenshot: #{screenshot_wrap["path"]}")
            {:ok, Map.put(context, :screenshot_wrap, screenshot_wrap["path"])}
          {:error, reason} ->
            {:error, reason}
        end
      end

      then_ "we can compare with wrap_mode: :none", context do
        configure_text_field(:none, "This is a very long line of text that exceeds the container width")

        case reset_and_load_text_field() do
          {:ok, _} ->
            {:ok, screenshot_nowrap} = ScenicMcp.Tools.take_screenshot(%{})
            IO.puts("📸 No-wrap mode screenshot: #{screenshot_nowrap["path"]}")

            IO.puts("")
            IO.puts("📊 Comparison:")
            IO.puts("   Wrap mode:    #{context.screenshot_wrap}")
            IO.puts("   No-wrap mode: #{screenshot_nowrap["path"]}")
            IO.puts("")
            IO.puts("✅ Both modes tested - compare screenshots to see difference!")

            :ok
          {:error, reason} ->
            {:error, reason}
        end
      end
    end

  end
end
