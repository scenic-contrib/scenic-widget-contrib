# Prompt for Oracle Opus 4: Generate Comprehensive MenuBar Spex

## Context: Spex-Driven Development

Spex-driven development is a methodology where we write executable specifications (spex) that serve as both tests and living documentation. These spex files:
1. Define expected behavior through curated examples that capture the essence of features
2. Guide automated implementation and debugging by AI agents
3. Serve as comprehensive test coverage including happy paths, edge cases, and failure modes
4. Use a BDD-style Given-When-Then format with the SexySpex framework

The development workflow is:
1. Write comprehensive spex covering desired functionality
2. Run spex to identify failures: `mix spex path/to/spex.exs`
3. Implement/fix code to make spex pass
4. Add edge cases to spex as discovered
5. Iterate until complete specification achieved

## Working Example: MenuBar Simple Load Spex

Here's our foundational spex that successfully loads a MenuBar in Widget Workbench:

```elixir
defmodule ScenicWidgets.MenuBarSimpleLoadSpex do
  @moduledoc """
  Simple MenuBar loading test using semantic UI helpers.
  
  This focuses on one core scenario: boot Widget Workbench -> load MenuBar -> verify it works.
  """
  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}

  setup_all do
    # Start Widget Workbench with proper viewport
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
          window: [
            resizeable: true,
            title: "Widget Workbench - MenuBar Simple Test"
          ],
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
    
    {:ok, _pid} = Scenic.ViewPort.start_link(viewport_config)
    
    # Wait for Widget Workbench to start
    Process.sleep(2000)
    
    :ok
  end

  spex "Simple MenuBar Loading Test",
    description: "Loads MenuBar in Widget Workbench using semantic UI helpers",
    tags: [:simple, :menubar, :load_test] do

    scenario "Load MenuBar component in Widget Workbench", context do
      given_ "Widget Workbench is running", context do
        case SemanticUI.verify_widget_workbench_loaded() do
          {:ok, workbench_state} ->
            IO.puts("✅ Widget Workbench loaded: #{inspect(workbench_state.status)}")
            {:ok, Map.put(context, :workbench_state, workbench_state)}
          {:error, reason} ->
            IO.puts("❌ Widget Workbench not loaded: #{reason}")
            {:error, reason}
        end
      end

      when_ "we load the MenuBar component", context do
        case SemanticUI.load_component("Menu Bar") do
          {:ok, load_result} ->
            IO.puts("✅ MenuBar loaded successfully: #{inspect(load_result)}")
            {:ok, Map.put(context, :load_result, load_result)}
          {:error, reason} ->
            IO.puts("❌ Failed to load MenuBar: #{reason}")
            # Still return {:ok, context} but with error info for debugging
            {:ok, Map.put(context, :load_error, reason)}
        end
      end

      then_ "MenuBar appears with menu items", context do
        if Map.has_key?(context, :load_error) do
          # We got an error during loading - let's see what we can observe
          rendered_content = ScriptInspector.get_rendered_text_string()
          IO.puts("❌ MenuBar loading failed. Current UI state:")
          IO.puts("Rendered content: #{inspect(String.slice(rendered_content, 0, 400))}")
          
          # This is a soft failure - we document what went wrong but don't crash the test
          IO.puts("⚠️  MenuBar loading test failed, but we captured diagnostic info")
          
          # For now, let's just verify Widget Workbench is still running
          assert String.contains?(rendered_content, "Widget Workbench") or 
                 String.contains?(rendered_content, "Load Component"),
                 "Widget Workbench should still be running"
        else
          # Success case - verify MenuBar is working
          load_result = Map.get(context, :load_result, %{})
          
          assert load_result.loaded == true,
                 "MenuBar should be loaded"
          assert length(load_result.menu_items) >= 2,
                 "MenuBar should have at least 2 menu items, got: #{inspect(load_result.menu_items)}"
          
          IO.puts("🎉 MenuBar test passed! Found menu items: #{inspect(load_result.menu_items)}")
        end
        
        :ok
      end
    end
  end
end
```

## Gold Standard Example: Quillex Comprehensive Text Editing Spex

Here's an excerpt from our best spex example showing comprehensive coverage:

```elixir
defmodule Quillex.ComprehensiveTextEditingSpex do
  @moduledoc """
  COMPREHENSIVE Text Editing Spex for Quillex - Complete notepad.exe functionality.

  This spex covers ALL basic text editing operations that any text editor should support.
  It serves as both specification and acceptance tests for core text editing features.

  ## Feature Coverage:
  1. Basic Text Input/Output
  2. Cursor Movement (arrows, home/end, word boundaries)
  3. Text Modification (backspace, delete, insert)
  4. Line Operations (enter, line joining/splitting)
  5. Text Selection (all methods: keyboard, mouse, shortcuts)
  6. Clipboard Operations (copy, cut, paste with all edge cases)
  7. Selection State Management (highlighting, clearing, replacement)
  8. Multi-line Operations (vertical movement, cross-line selection)
  9. Edge Cases (boundaries, empty docs, rapid input)
  10. Error Handling (invalid operations, platform differences)

  Success Criteria: ALL scenarios must pass for Quillex to be considered feature-complete
  at the basic text editor level (equivalent to notepad.exe or gedit).
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  @tmp_screenshots_dir "test/spex/screenshots/comprehensive"

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Comprehensive Text Editing Operations - Complete Notepad Functionality",
    description: "Validates ALL essential text editing features for a complete basic text editor",
    tags: [:comprehensive, :text_editing, :core_functionality, :ai_driven] do

    # =============================================================================
    # 1. BASIC TEXT INPUT/OUTPUT
    # =============================================================================

    scenario "Basic character input and display", context do
      given_ "empty buffer ready for input", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])  # Clear any existing content
        Process.sleep(50)

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("basic_input_baseline")
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "user types various characters", context do
        # Test basic characters that we know work
        test_string = "Hello World! 123"
        ScenicMcp.Probes.send_text(test_string)
        Process.sleep(100)

        input_screenshot = ScenicMcp.Probes.take_screenshot("basic_input_typed")
        {:ok, Map.merge(context, %{test_string: test_string, input_screenshot: input_screenshot})}
      end

      then_ "all characters should be displayed correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(context.test_string),
               "All typed characters should appear. Expected: '#{context.test_string}', Got: '#{rendered_content}'"

        :ok
      end
    end

    # [... many more comprehensive scenarios covering all features ...]
  end
end
```

## Key Testing Tools

### ScenicMcp.Probes - Low-level Scenic Interaction

```elixir
defmodule ScenicMcp.Probes do
  @moduledoc """
  Semantic DOM-like probes for Scenic applications.
  
  Provides both low-level Scenic interaction helpers and high-level semantic
  DOM queries for AI-driven automation and testing.
  """
  
  alias Scenic.ViewPort

  # Send text input to the application
  def send_text(text) when is_binary(text) do
    driver_struct = driver_state()
    
    text
    |> String.graphemes()
    |> Enum.each(fn char ->
      case char_to_key_event(char) do
        {:ok, key_event} ->
          Scenic.Driver.send_input(driver_struct, key_event)
        :error ->
          # For unsupported characters, still try codepoint
          codepoint = char |> String.to_charlist() |> List.first()
          Scenic.Driver.send_input(driver_struct, {:codepoint, {codepoint, []}})
      end
    end)
    
    :ok
  end

  # Send key input with modifiers
  def send_keys(key, modifiers \\ []) when is_binary(key) and is_list(modifiers) do
    driver_struct = driver_state()
    key_atom = normalize_key(key)
    
    # Send key press
    Scenic.Driver.send_input(driver_struct, {:key, {key_atom, 1, modifiers}})
    
    # Send key release  
    Scenic.Driver.send_input(driver_struct, {:key, {key_atom, 0, modifiers}})
    
    :ok
  end

  # Send mouse click at coordinates
  def send_mouse_click(x, y, opts \\ []) when is_number(x) and is_number(y) do
    driver_struct = driver_state()
    button = Keyword.get(opts, :button, :left)
    action = Keyword.get(opts, :action, :click)
    
    button_atom = case button do
      :left -> :btn_left
      :right -> :btn_right
      :middle -> :btn_middle
      b when is_atom(b) -> b
      _ -> :btn_left
    end
    
    # Ensure coordinates are integers
    int_x = round(x)
    int_y = round(y)
    
    case action do
      :press ->
        Scenic.Driver.send_input(driver_struct, {:cursor_button, {button_atom, 1, [], {int_x, int_y}}})
      :release ->
        Scenic.Driver.send_input(driver_struct, {:cursor_button, {button_atom, 0, [], {int_x, int_y}}})
      :click ->
        # Send both press and release for a complete click
        Scenic.Driver.send_input(driver_struct, {:cursor_button, {button_atom, 1, [], {int_x, int_y}}})
        Process.sleep(10)  # Small delay between press and release
        Scenic.Driver.send_input(driver_struct, {:cursor_button, {button_atom, 0, [], {int_x, int_y}}})
    end
    
    :ok
  end

  # Send mouse move to coordinates
  def send_mouse_move(x, y) when is_number(x) and is_number(y) do
    driver_struct = driver_state()
    Scenic.Driver.send_input(driver_struct, {:cursor_pos, {round(x), round(y)}})
    :ok
  end

  # Take a screenshot
  def take_screenshot(filename \\ nil) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    final_filename = filename || "screenshot_#{timestamp}.png"
    
    case ScenicMcp.Tools.take_screenshot(%{"filename" => final_filename}) do
      %{status: "ok", path: path} -> path
      %{error: _reason} -> nil
      _other -> nil
    end
  end
end
```

### ScriptInspector - Reading Rendered Content

```elixir
defmodule ScenicWidgets.TestHelpers.ScriptInspector do
  @moduledoc """
  Inspects the rendered scripts in the Scenic viewport to extract text content.
  Useful for testing what is actually displayed on screen.
  """
  
  require Logger

  @doc """
  Gets all rendered text as a single string, useful for simple contains checks.
  """
  def get_rendered_text_string do
    try do
      viewport_pid = Process.whereis(:main_viewport)
      state = :sys.get_state(viewport_pid, 5000)
      script_table = Map.get(state, :script_table)
      
      scripts = :ets.tab2list(script_table)
      
      text_content = scripts
      |> Enum.flat_map(fn {_key, script_ops} ->
        extract_text_from_ops(script_ops)
      end)
      |> Enum.join(" ")
      
      text_content
    rescue
      error ->
        Logger.warn("Failed to get rendered text: #{Exception.message(error)}")
        ""
    end
  end
  
  @doc """
  Check if specific text is rendered anywhere on screen.
  """
  def rendered_text_contains?(search_text) do
    rendered = get_rendered_text_string()
    String.contains?(rendered, search_text)
  end

  # Extract text from Scenic script operations
  defp extract_text_from_ops(ops) when is_list(ops) do
    Enum.flat_map(ops, &extract_text_from_op/1)
  end
  defp extract_text_from_ops(_), do: []

  defp extract_text_from_op({:draw_text, text, _fill}) when is_binary(text), do: [text]
  defp extract_text_from_op({:draw_text, charlist, _fill}) when is_list(charlist) do
    [List.to_string(charlist)]
  end
  defp extract_text_from_op(_), do: []
end
```

### SemanticUI Helper - High-level UI Interactions

```elixir
defmodule ScenicWidgets.TestHelpers.SemanticUI do
  @moduledoc """
  Semantic UI testing helpers that work with rendered content and layout,
  rather than hardcoded coordinates.
  
  This provides a higher-level abstraction for UI testing that:
  1. Looks at what's actually rendered
  2. Finds elements by text/description  
  3. Clicks intelligently based on what's visible
  4. Verifies outcomes semantically
  """

  alias ScenicWidgets.TestHelpers.ScriptInspector
  alias ScenicMcp.Probes

  @doc """
  Complete workflow: Load a component in Widget Workbench.
  """
  def load_component(component_name) do
    IO.puts("🎯 Loading component: #{component_name}")
    
    with {:ok, _} <- verify_widget_workbench_loaded(),
         {:ok, _} <- click_load_component_button(),
         {:ok, _} <- click_component_in_modal(component_name),
         {:ok, result} <- verify_component_loaded(component_name) do
      
      IO.puts("✅ Successfully loaded #{component_name}")
      {:ok, result}
    else
      {:error, reason} -> 
        IO.puts("❌ Failed to load #{component_name}: #{reason}")
        {:error, reason}
    end
  end

  # Clicks using centroids based on calculated button bounds
  defp click_at_position(x, y) do
    driver_struct = get_driver_state()
    
    # Press
    Scenic.Driver.send_input(driver_struct, {:cursor_button, {:btn_left, 1, [], {x, y}}})
    Process.sleep(10)
    
    # Release
    Scenic.Driver.send_input(driver_struct, {:cursor_button, {:btn_left, 0, [], {x, y}}})
    Process.sleep(500)
  end
end
```

## MenuBar Standard Behaviors to Implement

Based on research of standard desktop menubar patterns:

1. **Click-to-Open Pattern**
   - First click opens dropdown menu
   - Menu stays open until user clicks elsewhere or selects item
   - Hover alone doesn't open menus (unlike web menus)

2. **Hover Navigation (After Activation)**
   - Once any menu is open, hovering over other menu items opens them
   - This allows quick navigation between menus
   - Moving cursor away from menubar closes all menus

3. **Keyboard Navigation**
   - Alt key activates menubar, underlines accelerator keys
   - Arrow keys navigate between menu items
   - Enter/Space selects current item
   - Escape closes current dropdown, second Escape deactivates menubar

4. **Visual Feedback**
   - Hover highlights menu items
   - Active/open menu has distinct visual state
   - Disabled items are visually distinct
   - Keyboard focus indicators

5. **Menu Item Types**
   - Standard action items (click to execute)
   - Toggle items with checkmarks
   - Radio items (mutually exclusive within group)
   - Separators for logical grouping
   - Submenu items with arrow indicators
   - Disabled/enabled states

6. **Z-Order Management**
   - Dropdowns appear above all other content
   - Modal behavior - captures all input while open
   - Click outside closes menu

## Your Task: Generate Comprehensive MenuBar Spex

Please generate a comprehensive MenuBar spex file that:

1. **Covers ALL MenuBar functionality** similar to how the Quillex spex covers all text editing
2. **Uses the same BDD Given-When-Then format** with SexySpex
3. **Tests both mouse and keyboard interactions**
4. **Includes edge cases and error scenarios**
5. **Uses the testing tools shown above** (ScenicMcp.Probes, ScriptInspector, SemanticUI)
6. **Organizes scenarios by feature area** (like the numbered sections in Quillex spex)

The spex should include scenarios for:
- Basic menu opening/closing with mouse clicks
- Hover behavior after activation
- Keyboard navigation (Alt activation, arrow keys, shortcuts)
- Menu item selection (standard items, toggles, radio items)
- Visual feedback verification (highlights, active states)
- Z-order and modal behavior
- Edge cases (rapid clicking, clicking while animating, etc.)
- Integration with Widget Workbench
- Accessibility features

The goal is a spex file that, when all scenarios pass, guarantees we have a production-ready MenuBar component that matches standard desktop application behavior.

Please generate the complete `menu_bar_comprehensive_spex.exs` file.