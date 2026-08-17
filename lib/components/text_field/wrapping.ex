defmodule ScenicWidgets.TextField.Wrapping do
  @moduledoc """
  Pure text wrapping shared by TextField layout, rendering, and scrolling.

  Word mode prefers whitespace boundaries. A single token wider than the
  viewport falls back to grapheme wrapping, which prevents long identifiers
  and URLs from escaping the editor pane.
  """

  @type measure :: (String.t() -> number())

  @spec word(String.t(), number(), measure()) :: [String.t()]
  def word(line, max_width, measure) when is_binary(line) and is_function(measure, 1) do
    cond do
      line == "" ->
        [""]

      measure.(line) <= max_width ->
        [line]

      true ->
        line
        |> String.split(" ")
        |> Enum.reduce({[], ""}, &place_word(&1, &2, max_width, measure))
        |> finish()
    end
  end

  @spec character(String.t(), number(), measure()) :: [String.t()]
  def character(line, max_width, measure) when is_binary(line) and is_function(measure, 1) do
    cond do
      line == "" -> [""]
      measure.(line) <= max_width -> [line]
      true -> split_graphemes(line, max_width, measure)
    end
  end

  defp place_word(word, {lines, current}, max_width, measure) do
    candidate = if current == "", do: word, else: current <> " " <> word

    cond do
      measure.(candidate) <= max_width ->
        {lines, candidate}

      current != "" ->
        place_word(word, {lines ++ [current], ""}, max_width, measure)

      true ->
        chunks = split_graphemes(word, max_width, measure)
        {lines ++ Enum.drop(chunks, -1), List.last(chunks, "")}
    end
  end

  defp split_graphemes(text, max_width, measure) do
    {chunks, current} =
      Enum.reduce(String.graphemes(text), {[], ""}, fn grapheme, {chunks, current} ->
        candidate = current <> grapheme

        cond do
          current == "" and measure.(candidate) > max_width -> {chunks ++ [grapheme], ""}
          measure.(candidate) <= max_width -> {chunks, candidate}
          true -> {chunks ++ [current], grapheme}
        end
      end)

    if current == "", do: chunks, else: chunks ++ [current]
  end

  defp finish({lines, ""}), do: if(lines == [], do: [""], else: lines)
  defp finish({lines, current}), do: lines ++ [current]
end
