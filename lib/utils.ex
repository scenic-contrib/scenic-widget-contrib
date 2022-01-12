defmodule ScenicWidgets.Utils do
  @doc """
  Wrap and shorten text to a set number of lines

    iex> {:ok, {_type, fm}} = Scenic.Assets.Static.meta(:roboto)
    iex> line_width = 130
    iex> num_lines = 2
    iex> font_size = 16
    iex> wrap_and_shorten_text("Some text that needs to be wrapped and shortened", line_width, num_lines, font_size, fm)
    "Some text that
    needs to be wra…"
  """
  def wrap_and_shorten_text(text, line_width, num_lines, font_size, font_metrics) do
    text =
      text
      |> FontMetrics.shorten(line_width * num_lines, font_size, font_metrics)
      |> FontMetrics.wrap(line_width, font_size, font_metrics)

    lines = String.split(text, "\n")

    if length(lines) > num_lines do
      List.flatten([
        Enum.slice(lines, 0..(num_lines - 2)),
        # Join the last two lines and re-shorten it (the wrapping may have
        # introduced an extra line)
        Enum.slice(lines, (num_lines - 1)..-1)
        |> Enum.join(" ")
        |> FontMetrics.shorten(line_width, font_size, font_metrics)
      ])
      |> Enum.join("\n")
    else
      text
    end
  end
end
