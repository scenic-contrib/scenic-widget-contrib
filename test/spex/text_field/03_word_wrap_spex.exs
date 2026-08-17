defmodule ScenicWidgets.TextField.WordWrapSpex do
  @moduledoc """
  TextField Word Wrap Specification

  Verifies togglable word wrap:
  - `wrap_mode: :word` wraps long text onto multiple visual rows
  - `wrap_mode: :none` keeps a line on a single visual row (clipped instead
    of wrapped)

  Each wrapped visual row is rendered as its own `text` primitive translated
  to `{x, (row - 1) * line_height}` (see `Renderer.render_visible_lines/*` in
  `lib/components/text_field/renderer.ex`), while `wrap_mode: :none` renders
  the whole line as a single primitive. That means the first and last words
  of a long line land in the *same* rendered text primitive (and therefore
  the same y position) when wrapping is off, and in *different* primitives
  (different y positions) when wrapping is on - which is exactly what these
  scenarios assert via `ScenicMcp.Query.text_with_positions/0`, instead of
  comparing screenshots.
  """

  use SexySpex

  alias ScenicMcp.Query

  @long_text "This is a very long line of text that definitely exceeds the width and should wrap to multiple lines when line_wrap is enabled"
  @first_word "This"
  @last_word "enabled"

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  defp load_text_field(opts) do
    frame = Widgex.Frame.new(pin: {100, 100}, size: {300, 200})
    data = Map.merge(%{frame: frame, input_mode: :direct}, opts)

    WidgetWorkbench.Scene.load_component("Text Field", ScenicWidgets.TextField, data)
    Process.sleep(400)
    :ok
  end

  # Y-position of the rendered text primitive containing `pattern`, or nil.
  defp y_for(pattern) do
    Query.text_with_positions()
    |> Enum.find(fn %{text: text} -> String.contains?(text, pattern) end)
    |> case do
      %{y: y} -> y
      nil -> nil
    end
  end

  spex "TextField Word Wrap Functionality",
    description: "Verifies text wraps at container boundaries when wrap_mode is :word",
    tags: [:text_field, :word_wrap, :rendering] do
    scenario "Long text wraps to multiple lines when wrap_mode is :word", context do
      given_ "TextField is configured with wrap_mode: :word and a long line", context do
        load_text_field(%{wrap_mode: :word, initial_text: @long_text})
        {:ok, context}
      end

      then_ "the first and last words render on different visual rows" do
        first_y = y_for(@first_word)
        last_y = y_for(@last_word)

        assert first_y != nil, "'#{@first_word}' should be visible"
        assert last_y != nil, "'#{@last_word}' should be visible"

        assert first_y != last_y,
               "wrap_mode: :word should split the long line across multiple visual rows"

        :ok
      end
    end

    scenario "Short text stays on a single line when wrap_mode is :word", context do
      given_ "TextField is configured with wrap_mode: :word and short text", context do
        load_text_field(%{wrap_mode: :word, initial_text: "Short"})
        {:ok, context}
      end

      then_ "the short text is visible and does not need to wrap" do
        assert Query.text_visible?("Short"), "Short text should be visible"
        :ok
      end
    end
  end

  spex "TextField Word Wrap Functionality - Disabled",
    description: "Verifies text stays on one row (clipped) when wrap_mode is :none",
    tags: [:text_field, :word_wrap, :rendering] do
    scenario "Long text stays on a single visual row when wrap_mode is :none", context do
      given_ "TextField is configured with wrap_mode: :none and the same long line", context do
        load_text_field(%{wrap_mode: :none, initial_text: @long_text})
        {:ok, context}
      end

      then_ "the first and last words render on the same visual row" do
        first_y = y_for(@first_word)
        last_y = y_for(@last_word)

        assert first_y != nil, "'#{@first_word}' should be visible"
        assert last_y != nil, "'#{@last_word}' should be visible"

        assert first_y == last_y,
               "wrap_mode: :none should keep the whole line on a single visual row"

        :ok
      end
    end
  end
end
