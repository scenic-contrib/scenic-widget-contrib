defmodule ScenicWidgets.TextField.TextEditingSpex do
  @moduledoc """
  TextField Text Editing Specification

  Consolidates what used to be `02_typing_spex.exs` and
  `02_comprehensive_text_editing_spex.exs` into a single spex that validates
  core notepad.exe-level editing:

  - Focus management (typing is ignored until the field is clicked)
  - Character input
  - Cursor movement (arrows, Home/End)
  - Text modification (Backspace, Delete)
  - Line operations (Enter, multi-line up/down navigation)
  - Selection and replacement (Shift+Arrow, Ctrl+A)

  ## Known gap: clipboard

  TextField's Ctrl+C/X/V handlers only *emit* `{:clipboard_copy, ...}`,
  `{:clipboard_cut, ...}` and `{:clipboard_paste_requested, ...}` events to
  the parent scene (see `lib/components/text_field/reducer.ex`) - TextField
  has no clipboard of its own. `WidgetWorkbench.Scene` has no `handle_event/3`
  clause for those events (its catch-all clause is a no-op), so copy/cut/paste
  cannot round-trip when TextField is hosted in Widget Workbench. Those
  scenarios are intentionally omitted here rather than encoding a test that
  can only fail; wiring clipboard support into Widget Workbench is a
  separate piece of work.
  """

  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

  @frame_pin {100, 100}
  @frame_size {400, 300}

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  # Loads a fresh TextField (discarding any previous one) without clicking
  # into it, so focus-related scenarios can start from a known unfocused
  # state.
  defp load_text_field(opts \\ %{}) do
    frame = Widgex.Frame.new(pin: @frame_pin, size: @frame_size)
    data = Map.merge(%{frame: frame, initial_text: "", input_mode: :direct}, opts)

    WidgetWorkbench.Scene.load_component("Text Field", ScenicWidgets.TextField, data)
    Process.sleep(300)
    frame
  end

  # Loads a fresh TextField and clicks its center to grant it focus, which is
  # what every editing scenario needs before it can type.
  defp load_and_focus(opts \\ %{}) do
    frame = load_text_field(opts)
    click_center(frame)
    frame
  end

  defp click_center(%{pin: {px, py}, size: {w, h}}) do
    Probes.click(px + div(w, 2), py + div(h, 2))
    Process.sleep(50)
  end

  spex "Text Editing - Character Input and Cursor Movement",
    description: "Validates typing, arrow-key movement, Backspace/Delete and Home/End",
    tags: [:text_field, :text_editing, :input] do
    scenario "Typing characters appears in the text field", context do
      given_ "a focused, empty TextField", context do
        load_and_focus()
        {:ok, context}
      end

      when_ "we type 'Hello'", context do
        Probes.send_text("Hello")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "'Hello' is visible" do
        assert Query.text_visible?("Hello"), "Typed text should appear"
        :ok
      end
    end

    scenario "Arrow keys move the cursor for positional insertion", context do
      given_ "a focused TextField containing 'Test'", context do
        load_and_focus()
        Probes.send_text("Test")
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we press Left twice and insert 'XX'", context do
        Probes.send_keys("left", [])
        Probes.send_keys("left", [])
        Process.sleep(50)
        Probes.send_text("XX")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the insertion lands between 'Te' and 'st'" do
        assert Query.text_visible?("TeXXst"),
               "Left arrow should move the cursor so insertion lands at the right spot"

        :ok
      end
    end

    scenario "Backspace deletes the character before the cursor", context do
      given_ "a focused TextField containing 'Delete'", context do
        load_and_focus()
        Probes.send_text("Delete")
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we press Backspace", context do
        Probes.send_keys("backspace", [])
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the last character is gone" do
        refute Query.text_visible?("Delete"), "The full word should no longer be present"
        assert Query.text_visible?("Delet"), "The word minus its last character should remain"

        :ok
      end
    end

    scenario "Delete removes the character at the cursor", context do
      given_ "a focused TextField containing 'Remove' with cursor at Home", context do
        load_and_focus()
        Probes.send_text("Remove")
        Process.sleep(50)
        Probes.send_keys("home", [])
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we press Delete", context do
        Probes.send_keys("delete", [])
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the first character is gone" do
        refute Query.text_visible?("Remove"), "The full word should no longer be present"
        assert Query.text_visible?("emove"), "The word minus its first character should remain"

        :ok
      end
    end

    scenario "Home and End move the cursor to line boundaries", context do
      given_ "a focused TextField containing 'Middle'", context do
        load_and_focus()
        Probes.send_text("Middle")
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we go Home and type 'START', then go End and type 'END'", context do
        Probes.send_keys("home", [])
        Process.sleep(50)
        Probes.send_text("START")
        Process.sleep(50)
        Probes.send_keys("end", [])
        Process.sleep(50)
        Probes.send_text("END")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the text reads 'STARTMiddleEND'" do
        assert Query.text_visible?("STARTMiddleEND"),
               "Home/End should move the cursor to the true start/end of the line"

        :ok
      end
    end
  end

  spex "Text Editing - Lines and Multi-line Navigation",
    description: "Validates Enter (new line) and vertical Up/Down cursor movement",
    tags: [:text_field, :text_editing, :lines] do
    scenario "Enter creates a new line", context do
      given_ "a focused, empty TextField", context do
        load_and_focus()
        {:ok, context}
      end

      when_ "we type 'Line1', press Enter, then type 'Line2'", context do
        Probes.send_text("Line1")
        Process.sleep(50)
        Probes.send_keys("enter", [])
        Process.sleep(50)
        Probes.send_text("Line2")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "both lines are visible" do
        assert Query.text_visible?("Line1"), "First line should be visible"
        assert Query.text_visible?("Line2"), "Second line should be visible"

        :ok
      end
    end

    scenario "Up and Down arrows navigate between lines", context do
      given_ "a focused TextField with three lines", context do
        load_and_focus()
        Probes.send_text("Line1")
        Probes.send_keys("enter", [])
        Probes.send_text("Line2")
        Probes.send_keys("enter", [])
        Probes.send_text("Line3")
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we go Home (start of Line3), then Up, then insert a marker", context do
        Probes.send_keys("home", [])
        Process.sleep(50)
        Probes.send_keys("up", [])
        Process.sleep(50)
        Probes.send_text("MARK")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the marker landed at the start of Line2" do
        assert Query.text_visible?("MARKLine2"),
               "Up arrow should move the cursor to the previous line"

        :ok
      end
    end
  end

  spex "Text Editing - Focus Management",
    description: "Validates that keyboard input is only accepted once the field is clicked",
    tags: [:text_field, :text_editing, :focus] do
    scenario "TextField ignores keyboard input until clicked", context do
      given_ "a freshly loaded, unfocused TextField", context do
        load_text_field()
        {:ok, context}
      end

      when_ "we try to type without clicking it first", context do
        Probes.send_text("nope")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "nothing was inserted" do
        refute Query.text_visible?("nope"), "Unfocused TextField should not accept keyboard input"
        :ok
      end
    end

    scenario "Clicking the TextField grants focus so typing works", context do
      given_ "a freshly loaded, unfocused TextField", context do
        {:ok, Map.put(context, :frame, load_text_field())}
      end

      when_ "we click it and then type", context do
        click_center(context.frame)
        Probes.send_text("yes")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the typed text appears" do
        assert Query.text_visible?("yes"), "Clicking should focus the TextField and allow input"
        :ok
      end
    end
  end

  spex "Text Editing - Selection and Replacement",
    description:
      "Validates Shift+Arrow selection and Ctrl+A select-all, both replaceable by typing",
    tags: [:text_field, :text_editing, :selection] do
    scenario "Shift+Right selects text that gets replaced by typing", context do
      given_ "a focused TextField containing 'Select some text' with cursor after 'Select '",
             context do
        load_and_focus()
        Probes.send_text("Select some text")
        Process.sleep(50)
        Probes.send_keys("home", [])

        for _ <- 1..7, do: Probes.send_keys("right", [])
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we select 'some' with Shift+Right and type 'NEW'", context do
        for _ <- 1..4, do: Probes.send_keys("right", [:shift])
        Process.sleep(50)
        Probes.send_text("NEW")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the selection was replaced" do
        assert Query.text_visible?("Select NEW text"),
               "Typing over a selection should replace it"

        :ok
      end
    end

    scenario "Ctrl+A selects all text so typing replaces the whole buffer", context do
      given_ "a focused TextField with multiple lines", context do
        load_and_focus()
        Probes.send_text("Line1")
        Probes.send_keys("enter", [])
        Probes.send_text("Line2")
        Probes.send_keys("enter", [])
        Probes.send_text("Line3")
        Process.sleep(50)
        {:ok, context}
      end

      when_ "we press Ctrl+A and type 'Replaced'", context do
        Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        Probes.send_text("Replaced")
        Process.sleep(50)
        {:ok, context}
      end

      then_ "the entire buffer was replaced" do
        assert Query.text_visible?("Replaced"), "Replacement text should appear"
        refute Query.text_visible?("Line1"), "Original text should be gone"

        :ok
      end
    end
  end
end
