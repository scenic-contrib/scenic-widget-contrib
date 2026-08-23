defmodule ScenicWidgets.TextField.MatchingBrace do
  @moduledoc false

  @pairs %{"(" => ")", "[" => "]", "{" => "}"}
  @reverse Map.new(@pairs, fn {open, close} -> {close, open} end)

  @doc "Returns the brace beside the cursor and its matching partner, if any."
  def find(lines, {line, col}) when is_list(lines) do
    tokens = positioned_graphemes(lines)

    with {index, {brace, position}} <- brace_at_cursor(tokens, line, col),
         {:ok, match_index} <- matching_index(tokens, index, brace) do
      {_match, match_position} = Enum.at(tokens, match_index)
      {position, match_position}
    else
      _ -> nil
    end
  end

  defp positioned_graphemes(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {text, line} ->
      text
      |> String.graphemes()
      |> Enum.with_index(1)
      |> Enum.map(fn {char, col} -> {char, {line, col}} end)
    end)
  end

  defp brace_at_cursor(tokens, line, col) do
    right = Enum.find_index(tokens, fn {char, pos} -> pos == {line, col} and brace?(char) end)
    left = Enum.find_index(tokens, fn {char, pos} -> pos == {line, col - 1} and brace?(char) end)
    index = right || left
    if index, do: {index, Enum.at(tokens, index)}, else: nil
  end

  defp matching_index(tokens, index, brace) when is_map_key(@pairs, brace) do
    walk_forward(Enum.drop(tokens, index + 1), brace, @pairs[brace], 1, index + 1)
  end

  defp matching_index(tokens, index, brace) when is_map_key(@reverse, brace) do
    walk_backward(Enum.reverse(Enum.take(tokens, index)), @reverse[brace], brace, 1, index - 1)
  end

  defp matching_index(_tokens, _index, _brace), do: :error

  defp walk_forward([], _open, _close, _depth, _index), do: :error

  defp walk_forward([{char, _} | rest], open, close, depth, index) do
    depth = if char == open, do: depth + 1, else: depth
    depth = if char == close, do: depth - 1, else: depth
    if depth == 0, do: {:ok, index}, else: walk_forward(rest, open, close, depth, index + 1)
  end

  defp walk_backward([], _open, _close, _depth, _index), do: :error

  defp walk_backward([{char, _} | rest], open, close, depth, index) do
    depth = if char == close, do: depth + 1, else: depth
    depth = if char == open, do: depth - 1, else: depth
    if depth == 0, do: {:ok, index}, else: walk_backward(rest, open, close, depth, index - 1)
  end

  defp brace?(char), do: is_map_key(@pairs, char) or is_map_key(@reverse, char)
end
