defmodule ScenicWidgets.TextField.Folding do
  @moduledoc "Pure indentation-fold calculations used by TextField view state."

  @type folds :: MapSet.t(pos_integer())

  def foldable?(lines, line) do
    with current when is_binary(current) <- Enum.at(lines, line - 1),
         {_next_line, next} <- next_nonblank(lines, line + 1) do
      indent(next) > indent(current)
    else
      _ -> false
    end
  end

  def toggle(lines, folds, line) do
    cond do
      MapSet.member?(folds, line) -> MapSet.delete(folds, line)
      foldable?(lines, line) -> MapSet.put(folds, line)
      true -> folds
    end
  end

  def unfold_all, do: MapSet.new()

  def fold_to_level(lines, level) when level in 1..4 do
    lines
    |> foldable_lines_with_levels()
    |> Enum.reduce(MapSet.new(), fn {line, fold_level}, acc ->
      if fold_level == level, do: MapSet.put(acc, line), else: acc
    end)
  end

  @doc "Return all indentation-fold headers in one linear pass."
  def foldable_lines(lines) do
    lines
    |> foldable_lines_with_levels()
    |> MapSet.new(&elem(&1, 0))
  end

  @doc "Return `{source_line, text, folded_child_count}` visible rows."
  def projection(lines, folds) do
    foldable = foldable_lines(lines)

    lines
    |> Enum.with_index(1)
    |> do_projection(folds, foldable, [])
    |> Enum.reverse()
  end

  def expand_to_line(lines, folds, target) do
    Enum.reduce(folds, folds, fn header, acc ->
      if target in hidden_range(lines, header), do: MapSet.delete(acc, header), else: acc
    end)
  end

  def reconcile_after_edit(folds, old_lines, new_lines) do
    if length(old_lines) == length(new_lines), do: folds, else: MapSet.new()
  end

  defp do_projection([], _folds, _foldable, acc), do: acc

  defp do_projection([{text, line} | rest], folds, foldable, acc) do
    if MapSet.member?(folds, line) and MapSet.member?(foldable, line) do
      {remaining, hidden_count} = skip_folded_children(rest, indent(text), 0)
      do_projection(remaining, folds, foldable, [{line, text, hidden_count} | acc])
    else
      do_projection(rest, folds, foldable, [{line, text, 0} | acc])
    end
  end

  defp skip_folded_children([], _base_indent, count), do: {[], count}

  defp skip_folded_children([{text, _line} | rest] = remaining, base_indent, count) do
    if String.trim(text) == "" or indent(text) > base_indent do
      skip_folded_children(rest, base_indent, count + 1)
    else
      {remaining, count}
    end
  end

  defp hidden_range(lines, header) do
    base = lines |> Enum.at(header - 1, "") |> indent()

    last =
      (header + 1)..length(lines)
      |> Enum.reduce_while(header, fn line, previous ->
        text = Enum.at(lines, line - 1, "")

        if String.trim(text) == "" or indent(text) > base,
          do: {:cont, line},
          else: {:halt, previous}
      end)

    if last > header, do: (header + 1)..last, else: []
  end

  defp next_nonblank(lines, line) do
    if line > length(lines) do
      nil
    else
      line..length(lines)
      |> Enum.find_value(fn n ->
        text = Enum.at(lines, n - 1, "")
        if String.trim(text) != "", do: {n, text}
      end)
    end
  end

  # Scan upward so each nonblank line already knows the indentation of the
  # next nonblank line. This replaces the old remaining-document scan for
  # every source line (quadratic on large buffers).
  defp foldable_lines_with_levels(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.reverse()
    |> Enum.reduce({[], nil}, fn {text, line}, {headers, next_indent} ->
      if String.trim(text) == "" do
        {headers, next_indent}
      else
        current_indent = indent(text)

        headers =
          if is_integer(next_indent) and next_indent > current_indent,
            do: [{line, div(current_indent, 2) + 1} | headers],
            else: headers

        {headers, current_indent}
      end
    end)
    |> elem(0)
  end

  defp indent(text) do
    text
    |> String.to_charlist()
    |> Enum.reduce_while(0, fn
      ?\s, n -> {:cont, n + 1}
      ?\t, n -> {:cont, n + 4}
      _, n -> {:halt, n}
    end)
  end
end
