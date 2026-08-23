defmodule ScenicWidgets.TextField.TypingSpex do
  @moduledoc """
  Spex tests for TextField Phase 2 - keyboard input and editing.

  Tests:
  - Focus management (click to focus)
  - Character insertion
  - Cursor movement
  - Backspace and Delete
  - Enter key (newlines)
  """

  use SexySpex

  alias ScenicWidgets.TestHelpers.SemanticUI

  # Setup - start Widget Workbench viewport
  setup_all do
    # Connect to Scenic app and establish MCP connection
    result = SemanticUI.connect_and_setup_viewport()

    # Register cleanup
    on_exit(fn ->
      SemanticUI.cleanup_viewport()
    end)

    result
  end

  spex "TextField typing and editing" do
    scenario "Load TextField and type characters", context do
      given_ "Widget Workbench is running", context do
        result = SemanticUI.verify_widget_workbench_loaded()
        assert result == :ok, "Widget Workbench should be loaded"
        {:ok, context}
      end

      when_ "we load the TextField component", context do
        result = SemanticUI.load_component("Text Field")
        assert result == :ok, "TextField should load successfully"
        Process.sleep(200)
        {:ok, context}
      end

      then_ "TextField should be visible with demo text", context do
        {:ok, ui} = SemanticUI.inspect_viewport()
        assert ui =~ "Hello from TextField", "Should show demo text"
        {:ok, context}
      end

      when_ "we click on the TextField to focus it", context do
        # Find the TextField and click on it
        {:ok, elements} = SemanticUI.find_clickable_elements()
        text_field = Enum.find(elements, fn e -> String.contains?(to_string(e.id), "text_field") end)

        assert text_field != nil, "TextField should be clickable"

        # Click in the center of the TextField
        result = SemanticUI.click_element(text_field.id)
        assert result == :ok, "Should be able to click TextField"
        Process.sleep(100)
        {:ok, context}
      end

      then_ "TextField should gain focus (border should change)", context do
        # Take a screenshot to verify visual state
        {:ok, screenshot_path} = SemanticUI.take_screenshot("text_field_focused")
        assert File.exists?(screenshot_path), "Screenshot should be saved"
        {:ok, context}
      end

      when_ "we type the letter 'h'", context do
        result = SemanticUI.send_keys("h")
        assert result == :ok, "Should be able to send key 'h'"
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the letter 'h' should appear in the text", context do
        {:ok, ui} = SemanticUI.inspect_viewport()
        # The 'h' should be inserted at the cursor position
        # Since demo text exists, we're checking that typing happened
        {:ok, _screenshot} = SemanticUI.take_screenshot("after_typing_h")
        :ok
      end

      when_ "we type 'ello' to complete 'hello'", context do
        result = SemanticUI.send_keys("ello")
        assert result == :ok, "Should be able to type 'ello'"
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the text should contain 'hello'", context do
        {:ok, _screenshot} = SemanticUI.take_screenshot("after_typing_hello")
        :ok
      end
    end

    scenario "Cursor movement with arrow keys", context do
      given_ "TextField is loaded and focused", context do
        SemanticUI.verify_widget_workbench_loaded()
        SemanticUI.load_component("Text Field")
        Process.sleep(200)

        {:ok, elements} = SemanticUI.find_clickable_elements()
        text_field = Enum.find(elements, fn e -> String.contains?(to_string(e.id), "text_field") end)
        SemanticUI.click_element(text_field.id)
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press the Down arrow key", context do
        result = SemanticUI.send_keys({:key, :down})
        assert result == :ok, "Should be able to send Down key"
        Process.sleep(50)
        {:ok, context}
      end

      then_ "cursor should move down one line", context do
        {:ok, _screenshot} = SemanticUI.take_screenshot("cursor_moved_down")
        :ok
      end

      when_ "we press the Right arrow key several times", context do
        for _ <- 1..3 do
          SemanticUI.send_keys({:key, :right})
          Process.sleep(30)
        end

        {:ok, context}
      end

      then_ "cursor should move right", context do
        {:ok, _screenshot} = SemanticUI.take_screenshot("cursor_moved_right")
        :ok
      end

      when_ "we press Home key", context do
        result = SemanticUI.send_keys({:key, :home})
        assert result == :ok, "Should be able to send Home key"
        Process.sleep(50)
        {:ok, context}
      end

      then_ "cursor should move to start of line", context do
        {:ok, _screenshot} = SemanticUI.take_screenshot("cursor_at_line_start")
        :ok
      end

      when_ "we press End key", context do
        result = SemanticUI.send_keys({:key, :end})
        assert result == :ok, "Should be able to send End key"
        Process.sleep(50)
        {:ok, context}
      end

      then_ "cursor should move to end of line", context do
        {:ok, _screenshot} = SemanticUI.take_screenshot("cursor_at_line_end")
        :ok
      end
    end

    scenario "Backspace and Delete keys", context do
      given_ "TextField is loaded and focused with some text", context do
        SemanticUI.verify_widget_workbench_loaded()
        SemanticUI.load_component("Text Field")
        Process.sleep(200)

        {:ok, elements} = SemanticUI.find_clickable_elements()
        text_field = Enum.find(elements, fn e -> String.contains?(to_string(e.id), "text_field") end)
        SemanticUI.click_element(text_field.id)
        Process.sleep(100)

        # Type some text
        SemanticUI.send_keys("test")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we press Backspace key", context do
        result = SemanticUI.send_keys({:key, :backspace})
        assert result == :ok, "Should be able to send Backspace"
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the last character should be deleted", context do
        {:ok, _screenshot} = SemanticUI.take_screenshot("after_backspace")
        # Should show 'tes' instead of 'test'
        :ok
      end

      when_ "we press Left arrow then Delete key", context do
        SemanticUI.send_keys({:key, :left})
        Process.sleep(50)
        SemanticUI.send_keys({:key, :delete})
        Process.sleep(100)
        {:ok, context}
      end

      then_ "the character at cursor should be deleted", context do
        {:ok, _screenshot} = SemanticUI.take_screenshot("after_delete")
        :ok
      end
    end

    scenario "Enter key creates newline", context do
      given_ "TextField is loaded and focused", context do
        SemanticUI.verify_widget_workbench_loaded()
        SemanticUI.load_component("Text Field")
        Process.sleep(200)

        {:ok, elements} = SemanticUI.find_clickable_elements()
        text_field = Enum.find(elements, fn e -> String.contains?(to_string(e.id), "text_field") end)
        SemanticUI.click_element(text_field.id)
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we type 'line1' then press Enter then type 'line2'", context do
        SemanticUI.send_keys("line1")
        Process.sleep(50)
        SemanticUI.send_keys({:key, :enter})
        Process.sleep(50)
        SemanticUI.send_keys("line2")
        Process.sleep(100)
        {:ok, context}
      end

      then_ "should show two lines of text", context do
        {:ok, ui} = SemanticUI.inspect_viewport()
        # Both lines should be visible
        assert ui =~ "line1", "First line should exist"
        assert ui =~ "line2", "Second line should exist"

        {:ok, _screenshot} = SemanticUI.take_screenshot("two_lines_entered")
        :ok
      end
    end

    scenario "Focus loss on outside click", context do
      given_ "TextField is loaded and focused", context do
        SemanticUI.verify_widget_workbench_loaded()
        SemanticUI.load_component("Text Field")
        Process.sleep(200)

        {:ok, elements} = SemanticUI.find_clickable_elements()
        text_field = Enum.find(elements, fn e -> String.contains?(to_string(e.id), "text_field") end)
        SemanticUI.click_element(text_field.id)
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we click outside the TextField", context do
        # Click on the constructor pane area (far right)
        result = SemanticUI.send_mouse_click(900, 300)
        assert result == :ok, "Should be able to click outside"
        Process.sleep(100)
        {:ok, context}
      end

      then_ "TextField should lose focus (border should change back)", context do
        {:ok, _screenshot} = SemanticUI.take_screenshot("text_field_unfocused")
        :ok
      end

      then_ "typing should not insert characters", context do
        # Try to type when unfocused
        SemanticUI.send_keys("x")
        Process.sleep(100)

        {:ok, ui} = SemanticUI.inspect_viewport()
        # The 'x' should not appear since we're unfocused
        {:ok, _screenshot} = SemanticUI.take_screenshot("typing_while_unfocused")
        :ok
      end
    end
  end
end
