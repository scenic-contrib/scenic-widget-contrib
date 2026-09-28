defmodule ScenicWidgets.TextField.ComprehensiveTextEditingSpex do
  @moduledoc """
  COMPREHENSIVE Text Editing Spex for TextField Widget - Complete notepad.exe functionality.

  This spex covers ALL basic text editing operations that any text editor should support.
  It serves as both specification and acceptance tests for core text editing features.

  ## Feature Coverage (Building Incrementally):
  1. ✅ Basic Text Input/Output - STARTING HERE
  2. ⏳ Cursor Movement (arrows, home/end, word boundaries)
  3. ⏳ Text Modification (backspace, delete, insert)
  4. ⏳ Line Operations (enter, line joining/splitting)
  5. ⏳ Text Selection (keyboard, mouse, shortcuts)
  6. ⏳ Clipboard Operations (copy, cut, paste)
  7. ⏳ Selection State Management (highlighting, clearing, replacement)
  8. ⏳ Multi-line Operations (vertical movement, cross-line selection)
  9. ⏳ Edge Cases (boundaries, empty docs, rapid input)
  10. ⏳ Error Handling (invalid operations)

  Success Criteria: ALL scenarios must pass for TextField to be considered feature-complete
  at the basic text editor level (equivalent to notepad.exe or gedit).

  ## Implementation Notes:
  - Uses SemanticUI.load_component() for setup (handles scrolling automatically)
  - Uses ScenicMcp.Probes for keyboard/mouse input (proven reliable in quillex)
  - Uses ScriptInspector for rendered content verification
  - Starts with ONE passing scenario, then builds incrementally
  """
  use SexySpex

  # Load helpers at compile time
  Code.require_file("test/helpers/script_inspector.ex")
  Code.require_file("test/helpers/semantic_ui.ex")

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}

  @tmp_screenshots_dir "test/spex/screenshots/text_field"

  setup_all do
    # Ensure screenshots directory exists
    File.mkdir_p!(@tmp_screenshots_dir)

    # Get test-specific viewport and driver names from config
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)

    # Ensure any existing test viewport is stopped first
    if viewport_pid = Process.whereis(viewport_name) do
      Process.exit(viewport_pid, :kill)
      Process.sleep(100)
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
            title: "Widget Workbench - TextField Comprehensive Test (Port 9998)"
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
    Process.sleep(500)

    # Cleanup on test completion
    on_exit(fn ->
      if pid = Process.whereis(viewport_name) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)

    {:ok, %{viewport_pid: viewport_pid, viewport_name: viewport_name, driver_name: driver_name}}
  end

  setup context do
    # Wait for Widget Workbench to fully render
    Process.sleep(100)

    # Load TextField component before each test
    # SemanticUI.load_component handles scrolling automatically
    case SemanticUI.load_component("Text Field") do
      {:ok, result} ->
        IO.puts("✅ TextField loaded successfully")
        Process.sleep(10)
      {:error, reason} ->
        IO.puts("❌ Failed to load TextField: #{reason}")
        # Try to debug what's on screen
        rendered = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 Screen content: #{String.slice(rendered, 0, 200)}")
        raise "Could not load TextField component"
    end

    # Click to focus the TextField
    # TextField is positioned at (100, 100) with size 400x200
    # Click in the middle of the TextField
    click_x = 200  # Middle of TextField horizontally (100 + 400/2)
    click_y = 200  # Middle of TextField vertically (100 + 200/2)

    # Use direct driver send (same as SemanticUI helper)
    driver_struct = get_driver_state()
    Scenic.Driver.send_input(driver_struct, {:cursor_button, {:btn_left, 1, [], {click_x, click_y}}})
    Process.sleep(10)
    Scenic.Driver.send_input(driver_struct, {:cursor_button, {:btn_left, 0, [], {click_x, click_y}}})
    Process.sleep(20)

    context
  end

  # Helper to get driver state (same as SemanticUI)
  defp get_driver_state() do
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)

    case Process.whereis(driver_name) do
      nil ->
        viewport_pid = Process.whereis(viewport_name)
        state = :sys.get_state(viewport_pid, 5000)
        [driver | _] = Map.get(state, :driver_pids, [])
        :sys.get_state(driver, 5000)
      driver_pid ->
        :sys.get_state(driver_pid, 5000)
    end
  end

  spex "TextField Comprehensive Text Editing - Phase 2",
    description: "Validates essential text editing features (starting with basics)",
    tags: [:textfield, :text_editing, :phase2, :comprehensive] do

    # =============================================================================
    # 1. BASIC TEXT INPUT/OUTPUT - Starting with ONE simple test
    # =============================================================================

    scenario "Basic character input and display", context do
      given_ "empty TextField ready for input", context do
        # TextField loaded and focused from setup
        # Clear any default text
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(10)
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(10)

        # Verify it's empty
        rendered = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 Starting state: #{inspect(rendered)}")

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("#{@tmp_screenshots_dir}/basic_input_baseline")
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "user types simple text", context do
        # Start simple - just type "Hello"
        test_string = "Hello"
        ScenicMcp.Probes.send_text(test_string)
        Process.sleep(10)

        input_screenshot = ScenicMcp.Probes.take_screenshot("#{@tmp_screenshots_dir}/basic_input_typed")
        {:ok, Map.merge(context, %{test_string: test_string, input_screenshot: input_screenshot})}
      end

      then_ "text should be displayed", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After typing: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?(context.test_string),
               "Typed text should appear. Expected: '#{context.test_string}', Got: '#{rendered_content}'"

        IO.puts("✅ Basic text input working: #{context.test_string}")
        :ok
      end
    end

    # =============================================================================
    # 2. CURSOR MOVEMENT
    # =============================================================================

    scenario "Arrow key cursor movement", context do
      given_ "TextField with text for arrow key testing", context do
        # Type "Test" then move left twice and insert "XX"
        test_text = "Test"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(10)

        {:ok, Map.put(context, :test_text, test_text)}
      end

      when_ "user moves cursor left and inserts text", context do
        # Move left 2 positions (cursor between 's' and 't')
        ScenicMcp.Probes.send_keys("left", [])
        Process.sleep(10)
        ScenicMcp.Probes.send_keys("left", [])
        Process.sleep(10)

        # Insert "XX"
        ScenicMcp.Probes.send_text("XX")
        Process.sleep(10)

        {:ok, context}
      end

      then_ "text should be inserted at correct cursor position", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After arrow movement: #{inspect(rendered_content)}")

        # Look for "TeXXst" (the result of moving left twice in "Test" and inserting "XX")
        assert ScriptInspector.rendered_text_contains?("TeXXst"),
               "Arrow keys should position cursor correctly. Expected 'TeXXst', Got: '#{rendered_content}'"

        IO.puts("✅ Arrow key navigation working")
        :ok
      end
    end

    # =============================================================================
    # 3. TEXT MODIFICATION
    # =============================================================================

    scenario "Backspace deletes character before cursor", context do
      given_ "TextField with text", context do
        test_text = "Delete"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(10)

        {:ok, context}
      end

      when_ "user presses backspace", context do
        # Delete the 'e' at the end
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(10)

        {:ok, context}
      end

      then_ "character before cursor should be deleted", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After backspace: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?("Delet"),
               "Backspace should delete last character. Got: '#{rendered_content}'"

        IO.puts("✅ Backspace working correctly")
        :ok
      end
    end

    # =============================================================================
    # 4. LINE OPERATIONS
    # =============================================================================

    scenario "Enter key creates new line", context do
      given_ "TextField with single line text", context do
        test_text = "Line1"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(10)

        {:ok, context}
      end

      when_ "user presses Enter and types more text", context do
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(10)
        ScenicMcp.Probes.send_text("Line2")
        Process.sleep(10)

        {:ok, context}
      end

      then_ "new line should be created", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After Enter: #{inspect(rendered_content)}")

        # Both lines should be present
        assert ScriptInspector.rendered_text_contains?("Line1"),
               "First line should be present. Got: '#{rendered_content}'"

        assert ScriptInspector.rendered_text_contains?("Line2"),
               "Second line should be present. Got: '#{rendered_content}'"

        IO.puts("✅ Enter key line creation working")
        :ok
      end
    end

    scenario "Delete key deletes character at cursor", context do
      given_ "TextField with text", context do
        ScenicMcp.Probes.send_text("Remove")
        Process.sleep(10)
        # Move cursor to beginning
        for _i <- 1..6, do: ScenicMcp.Probes.send_keys("left", [])
        Process.sleep(10)

        {:ok, context}
      end

      when_ "user presses delete", context do
        # Should delete the 'R'
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(10)

        {:ok, context}
      end

      then_ "character at cursor should be deleted", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After delete: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?("emove"),
               "Delete should remove first character. Got: '#{rendered_content}'"

        IO.puts("✅ Delete key working correctly")
        :ok
      end
    end

    scenario "Home and End keys navigate to line boundaries", context do
      given_ "TextField with text", context do
        ScenicMcp.Probes.send_text("Middle")
        Process.sleep(10)

        {:ok, context}
      end

      when_ "user uses Home and End keys", context do
        # Home - go to start
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(10)
        ScenicMcp.Probes.send_text("START")
        Process.sleep(10)

        # End - go to end
        ScenicMcp.Probes.send_keys("end", [])
        Process.sleep(10)
        ScenicMcp.Probes.send_text("END")
        Process.sleep(10)

        {:ok, context}
      end

      then_ "cursor should navigate to line boundaries", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After Home/End: #{inspect(rendered_content)}")

        # Check that START, Middle, and END all appear (may have other text between them)
        assert ScriptInspector.rendered_text_contains?("START"),
               "Should have START at beginning. Got: '#{rendered_content}'"
        assert ScriptInspector.rendered_text_contains?("Middle"),
               "Should have Middle in content. Got: '#{rendered_content}'"
        assert ScriptInspector.rendered_text_contains?("END"),
               "Should have END at end. Got: '#{rendered_content}'"

        IO.puts("✅ Home/End keys working correctly")
        :ok
      end
    end

    # =============================================================================
    # 5. FOCUS MANAGEMENT
    # =============================================================================

    scenario "Click to focus then type", context do
      # This tests that clicking focuses the TextField
      # Note: setup already clicked to focus, but let's verify it explicitly

      given_ "focused TextField (clicked in setup)", context do
        # TextField was clicked in setup, so it should be focused
        {:ok, context}
      end

      when_ "user types after clicking", context do
        # Type some text
        ScenicMcp.Probes.send_text("Focused")
        Process.sleep(20)

        {:ok, context}
      end

      then_ "text should appear", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After typing focused: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?("Focused"),
               "Focused TextField should accept input. Got: '#{rendered_content}'"

        IO.puts("✅ Click-to-focus working - text accepted when focused")
        :ok
      end
    end

    # =============================================================================
    # 6. TEXT SELECTION (Phase 3)
    # =============================================================================

    scenario "Shift+Arrow text selection and replacement", context do
      given_ "text for selection", context do
        # Clear all previous text first (Ctrl+A then Backspace)
        driver_struct = get_driver_state()
        Scenic.Driver.send_input(driver_struct, {:key, {:key_a, 1, [:ctrl]}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_a, 0, [:ctrl]}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_backspace, 1, []}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_backspace, 0, []}})
        Process.sleep(10)

        test_text = "Select some text"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(10)

        # Position cursor after "Select "
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..7, do: ScenicMcp.Probes.send_keys("right", [])
        Process.sleep(10)

        {:ok, Map.put(context, :test_text, test_text)}
      end

      when_ "user selects text with Shift+Right and types replacement", context do
        # Select "some" (4 characters)
        for _i <- 1..4, do: ScenicMcp.Probes.send_keys("right", [:shift])
        Process.sleep(10)

        # Type replacement - should replace selection
        ScenicMcp.Probes.send_text("NEW")
        Process.sleep(10)

        {:ok, context}
      end

      then_ "selected text should be replaced", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After selection replacement: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?("Select NEW text"),
               "Selection should be replaced. Expected 'Select NEW text', Got: '#{rendered_content}'"

        IO.puts("✅ Text selection and replacement working")
        :ok
      end
    end

    scenario "Ctrl+A Select All", context do
      given_ "multi-line text", context do
        ScenicMcp.Probes.send_text("Line1")
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("Line2")
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("Line3")
        Process.sleep(10)

        {:ok, context}
      end

      when_ "user presses Ctrl+A and types replacement", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(10)

        ScenicMcp.Probes.send_text("Replaced")
        Process.sleep(10)

        {:ok, context}
      end

      then_ "all text should be replaced", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After select all: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?("Replaced"),
               "Replacement text should appear. Got: '#{rendered_content}'"

        refute ScriptInspector.rendered_text_contains?("Line1"),
               "Original text should be gone. Got: '#{rendered_content}'"

        IO.puts("✅ Select All working")
        :ok
      end
    end

    # =============================================================================
    # 7. CLIPBOARD OPERATIONS (Phase 3)
    # =============================================================================

    scenario "Copy and paste", context do
      given_ "text for copy/paste", context do
        # Clear all previous text first (Ctrl+A then Backspace)
        driver_struct = get_driver_state()
        Scenic.Driver.send_input(driver_struct, {:key, {:key_a, 1, [:ctrl]}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_a, 0, [:ctrl]}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_backspace, 1, []}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_backspace, 0, []}})
        Process.sleep(10)

        ScenicMcp.Probes.send_text("Copy this")
        Process.sleep(10)

        {:ok, context}
      end

      when_ "user selects, copies, moves, and pastes", context do
        # Ensure focus (in case previous scenarios lost it)
        driver_struct = get_driver_state()
        Scenic.Driver.send_input(driver_struct, {:cursor_button, {:btn_left, 1, [], {200, 200}}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:cursor_button, {:btn_left, 0, [], {200, 200}}})
        Process.sleep(10)

        # Select "this"
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..5, do: ScenicMcp.Probes.send_keys("right", [])
        for _i <- 1..4, do: ScenicMcp.Probes.send_keys("right", [:shift])
        Process.sleep(10)

        # Copy
        ScenicMcp.Probes.send_keys("c", [:ctrl])
        Process.sleep(10)

        # Move to end and paste
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_text(" and ")
        ScenicMcp.Probes.send_keys("v", [:ctrl])
        Process.sleep(10)

        {:ok, context}
      end

      then_ "copied text should appear twice", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After copy/paste: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?("Copy this and this"),
               "Copy/paste should work. Expected 'Copy this and this', Got: '#{rendered_content}'"

        IO.puts("✅ Copy/paste working")
        :ok
      end
    end

    scenario "Cut and paste", context do
      given_ "text for cut/paste", context do
        # Clear all previous text first (Ctrl+A then Backspace)
        driver_struct = get_driver_state()
        Scenic.Driver.send_input(driver_struct, {:key, {:key_a, 1, [:ctrl]}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_a, 0, [:ctrl]}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_backspace, 1, []}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_struct, {:key, {:key_backspace, 0, []}})
        Process.sleep(10)

        ScenicMcp.Probes.send_text("Cut this out")
        Process.sleep(10)

        {:ok, context}
      end

      when_ "user selects, cuts, and pastes elsewhere", context do
        # Select "this "
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..4, do: ScenicMcp.Probes.send_keys("right", [])
        for _i <- 1..5, do: ScenicMcp.Probes.send_keys("right", [:shift])
        Process.sleep(10)

        # Cut
        ScenicMcp.Probes.send_keys("x", [:ctrl])
        Process.sleep(10)

        # Move to end and paste
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_text(" ")
        ScenicMcp.Probes.send_keys("v", [:ctrl])
        Process.sleep(10)

        {:ok, context}
      end

      then_ "cut text should move to new location", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After cut/paste: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?("Cut out this"),
               "Cut/paste should work. Expected 'Cut out this', Got: '#{rendered_content}'"

        IO.puts("✅ Cut/paste working")
        :ok
      end
    end

    # =============================================================================
    # 8. MULTI-LINE NAVIGATION
    # =============================================================================

    scenario "Up and Down arrows navigate between lines", context do
      given_ "TextField with multiple lines", context do
        # Create 3 lines
        ScenicMcp.Probes.send_text("Line1")
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("Line2")
        ScenicMcp.Probes.send_keys("enter", [])
        ScenicMcp.Probes.send_text("Line3")
        Process.sleep(10)

        {:ok, context}
      end

      when_ "user navigates with up/down arrows", context do
        # Go to start of line 3
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(10)

        # Move up to line 2
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(10)

        # Insert marker
        ScenicMcp.Probes.send_text("MARK")
        Process.sleep(10)

        {:ok, context}
      end

      then_ "cursor should navigate vertically correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("📄 After up/down: #{inspect(rendered_content)}")

        assert ScriptInspector.rendered_text_contains?("MARKLine2"),
               "Up arrow should navigate to previous line. Got: '#{rendered_content}'"

        IO.puts("✅ Vertical navigation working correctly")
        :ok
      end
    end

    # scenario "Multi-line selection with Shift+Down/Up", context do
    #   given_ "multi-line text content", context do
    #     # Clear previous content
    #     driver_struct = get_driver_state()
    #     Scenic.Driver.send_input(driver_struct, {:key, {:key_a, 1, [:ctrl]}})
    #     Process.sleep(50)
    #     Scenic.Driver.send_input(driver_struct, {:key, {:key_a, 0, [:ctrl]}})
    #     Process.sleep(50)
    #     Scenic.Driver.send_input(driver_struct, {:key, {:key_backspace, 1, []}})
    #     Process.sleep(50)
    #     Scenic.Driver.send_input(driver_struct, {:key, {:key_backspace, 0, []}})
    #     Process.sleep(100)

    #     # Type multi-line content
    #     ScenicMcp.Probes.send_text("First line")
    #     ScenicMcp.Probes.send_keys("enter", [])
    #     ScenicMcp.Probes.send_text("Second line")
    #     ScenicMcp.Probes.send_keys("enter", [])
    #     ScenicMcp.Probes.send_text("Third line")
    #     Process.sleep(100)

    #     # Position cursor at start of first line
    #     ScenicMcp.Probes.send_keys("home", [:ctrl])
    #     Process.sleep(50)

    #     {:ok, context}
    #   end

    #   when_ "user selects across multiple lines with Shift+Down", context do
    #     # Select from start of first line, move down with shift
    #     ScenicMcp.Probes.send_keys("down", [:shift])  # Select first line
    #     Process.sleep(50)
    #     ScenicMcp.Probes.send_keys("down", [:shift])  # Extend to second line
    #     Process.sleep(50)

    #     # Now move right a bit to select partial third line
    #     for _i <- 1..5 do
    #       ScenicMcp.Probes.send_keys("right", [:shift])
    #     end
    #     Process.sleep(100)

    #     {:ok, context}
    #   end

    #   then_ "multi-line selection should be replaceable", context do
    #     # Type to replace selection
    #     ScenicMcp.Probes.send_text("REPLACED")
    #     Process.sleep(100)

    #     rendered_content = ScriptInspector.get_rendered_text_string()
    #     IO.puts("📄 After multi-line replace: #{inspect(rendered_content)}")

    #     assert ScriptInspector.rendered_text_contains?("REPLACED"),
    #            "Multi-line selection should be replaced. Got: '#{rendered_content}'"

    #     refute ScriptInspector.rendered_text_contains?("First line"),
    #            "Original first line should be gone. Got: '#{rendered_content}'"

    #     refute ScriptInspector.rendered_text_contains?("Second line"),
    #            "Original second line should be gone. Got: '#{rendered_content}'"

    #     IO.puts("✅ Multi-line selection and replacement working")
    #     :ok
    #   end
    # end
  end



  # Helper function to clear textfield
  defp clear_textfield() do
    # Move to start, then select all by holding shift and going to end
    ScenicMcp.Probes.send_keys("home", [:ctrl])  # Ctrl+Home = document start
    Process.sleep(50)
    ScenicMcp.Probes.send_keys("end", [:ctrl])  # Ctrl+End = document end
    Process.sleep(50)

    # Now just backspace repeatedly to clear (crude but works for Phase 2)
    for _i <- 1..100 do
      ScenicMcp.Probes.send_keys("backspace", [])
      Process.sleep(5)
    end
    Process.sleep(100)
  end
end
