defmodule ScenicWidgets.MenuBar.TextHelper do
  @moduledoc """
  Helper functions for text rendering with overflow handling.

  Provides utilities to truncate text with ellipsis when it exceeds
  a maximum width, using FontMetrics for accurate measurement.
  """

  alias Scenic.Assets.Static

  @default_font :roboto
  @default_font_size 16
  @ellipsis "..."

  @doc """
  Truncate text to fit within a maximum width, adding ellipsis if needed.

  ## Parameters
  - `text`: The text string to potentially truncate
  - `max_width`: Maximum width in pixels
  - `opts`: Optional keyword list
    - `:font` - Font to use (default: :roboto)
    - `:font_size` - Font size (default: 16)
    - `:ellipsis` - String to append when truncating (default: "...")

  ## Returns
  - `{:ok, text}` - Original text if it fits
  - `{:truncated, truncated_text}` - Truncated text with ellipsis
  - `{:error, reason}` - If font metrics can't be loaded

  ## Examples

      iex> truncate_text("Short", 100)
      {:ok, "Short"}

      iex> truncate_text("Very Long Text Here", 50, font_size: 16)
      {:truncated, "Very L..."}
  """
  def truncate_text(text, max_width, opts \\ []) do
    font = Keyword.get(opts, :font, @default_font)
    font_size = Keyword.get(opts, :font_size, @default_font_size)
    ellipsis = Keyword.get(opts, :ellipsis, @ellipsis)

    case Static.meta(font) do
      {:ok, {Static.Font, fm}} ->
        text_width = FontMetrics.width(text, font_size, fm)

        if text_width <= max_width do
          {:ok, text}
        else
          # Text needs truncation
          truncate_to_width(text, max_width, ellipsis, font_size, fm)
        end

      error ->
        # Can't load font metrics, return original text
        {:error, {:font_metrics_unavailable, error}}
    end
  end

  @doc """
  Measure the width of text in pixels.

  ## Parameters
  - `text`: The text string to measure
  - `opts`: Optional keyword list
    - `:font` - Font to use (default: :roboto)
    - `:font_size` - Font size (default: 16)

  ## Returns
  - `{:ok, width}` - Width in pixels
  - `{:error, reason}` - If font metrics can't be loaded
  """
  def measure_text(text, opts \\ []) do
    font = Keyword.get(opts, :font, @default_font)
    font_size = Keyword.get(opts, :font_size, @default_font_size)

    case Static.meta(font) do
      {:ok, {Static.Font, fm}} ->
        {:ok, FontMetrics.width(text, font_size, fm)}

      error ->
        {:error, {:font_metrics_unavailable, error}}
    end
  end

  # Private functions

  defp truncate_to_width(text, max_width, ellipsis, font_size, fm) do
    ellipsis_width = FontMetrics.width(ellipsis, font_size, fm)
    available_width = max_width - ellipsis_width

    # Binary search for the longest prefix that fits
    truncated = find_max_fitting_prefix(text, available_width, font_size, fm)

    {:truncated, truncated <> ellipsis}
  end

  defp find_max_fitting_prefix(text, max_width, font_size, fm) do
    graphemes = String.graphemes(text)
    do_find_prefix(graphemes, [], max_width, font_size, fm)
  end

  # Iteratively add characters until we exceed the width
  defp do_find_prefix([], acc, _max_width, _font_size, _fm) do
    acc |> Enum.reverse() |> Enum.join()
  end

  defp do_find_prefix([char | rest], acc, max_width, font_size, fm) do
    candidate = [char | acc] |> Enum.reverse() |> Enum.join()
    width = FontMetrics.width(candidate, font_size, fm)

    if width <= max_width do
      # Still fits, continue adding
      do_find_prefix(rest, [char | acc], max_width, font_size, fm)
    else
      # Exceeds width, return what we had before
      acc |> Enum.reverse() |> Enum.join()
    end
  end
end
