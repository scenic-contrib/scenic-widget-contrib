defmodule ScenicWidgets.Utils do
  @doc """
  Checks if a coordinate point (a tuple in the form `{x, y}`)
  is inside a bounding box, defined in the same format as
  (Scenic.bounds/1)[https://hexdocs.pm/scenic/0.11.0-beta.0/Scenic.Graph.html#bounds/1], `{left, top, right, bottom}`
  """
  def inside?({x, y}, {left, top, right, bottom} = _bounds) do
    # NOTE: Because the y axis starts at zero in the top-left, and
    # gets larger as we go down the page, it's a little counter-intuitive
    # to calculate if we're inside the bounds
    x >= left and x <= right and (y >= top and y <= bottom)
  end

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
