defmodule ScenicWidgets.ModalShell do
  @moduledoc """
  Shared geometry and chrome for modal dialogs.

  Modal components keep their domain-specific contents and response events,
  while this layer owns centering, the dimming overlay, panel background, and
  the full-viewport input shield.
  """

  alias Scenic.Primitives

  @overlay {0, 0, 0, 160}

  def bounds(frame, {panel_width, panel_height}) do
    {width, height} = size(frame)

    %{
      x: (width - panel_width) / 2,
      y: (height - panel_height) / 2,
      width: panel_width,
      height: panel_height
    }
  end

  def overlay(graph, frame, id, opts \\ []) do
    {width, height} = size(frame)

    Primitives.rect(graph, {width, height},
      id: id,
      fill: Keyword.get(opts, :fill, @overlay),
      input: [:cursor_button]
    )
  end

  def panel(graph, bounds, id, opts \\ []) do
    Primitives.rrect(graph, {bounds.width, bounds.height, Keyword.get(opts, :radius, 8)},
      id: id,
      fill: Keyword.get(opts, :fill, {45, 48, 55}),
      stroke: Keyword.get(opts, :stroke, {1, {80, 85, 95}}),
      translate: {bounds.x, bounds.y}
    )
  end

  defp size(%{size: %{width: width, height: height}}), do: {width, height}
  defp size(%{size: %{box: {width, height}}}), do: {width, height}
  defp size(%{size: size}) when is_tuple(size), do: size
  defp size({width, height}), do: {width, height}
end
