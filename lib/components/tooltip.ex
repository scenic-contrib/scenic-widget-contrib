defmodule ScenicWidgets.Tooltip do
  @moduledoc """
  A hover label: what this button does, in words, next to the pointer.

  Drawn straight into a host's graph rather than being a component of its own,
  because a tooltip has no state worth a process — it exists only while the
  pointer is over something, and the host already knows when that is.

  ## Using it

  Keep `nil` when nothing is hovered, and a `%{text: String.t(), at: {x, y}}`
  when something is:

      graph |> Tooltip.add(state.tooltip, theme, frame_width)

  The host is responsible for deciding *when* — usually a `:cursor_pos`
  handler that hit-tests its own buttons — because only the host knows what
  its buttons are.

  ## Why a shared module

  It was written twice: once properly inside `IconMenu`, and once not at all
  in every other component with buttons, which is why the search bar's
  navigation arrows and its close cross went unexplained for so long. An icon
  that cannot say what it is has to be guessed at.
  """

  alias Scenic.Graph
  alias Scenic.Primitives
  alias ScenicWidgets.MenuBar.TextHelper

  @padding 7
  @default_font_size 12

  @doc """
  Add a tooltip to a graph, or leave it untouched when there is nothing to say.

  `available_width` keeps a tooltip near the right-hand edge from being drawn
  off it — the label shifts left rather than being clipped.
  """
  @spec add(
          Graph.t(),
          nil | %{text: String.t(), at: {number(), number()}},
          map(),
          number() | nil,
          keyword()
        ) :: Graph.t()
  def add(graph, tooltip, theme, available_width \\ nil, opts \\ [])

  def add(graph, nil, _theme, _available_width, _opts), do: graph

  def add(graph, %{text: text, at: {x, y}}, theme, available_width, opts) do
    # Ids are the caller's, because a host may already have things pointed at
    # them — a test looking the tooltip up by name, most likely.
    id = Keyword.get(opts, :id, :tooltip)
    font_size = Map.get(theme, :tooltip_font_size, @default_font_size)
    width = width(text, Map.get(theme, :font, :roboto), font_size)
    height = font_size + @padding * 2

    Primitives.group(
      graph,
      fn g ->
        g
        |> Primitives.rect({width, height},
          fill: Map.get(theme, :tooltip_bg, {25, 25, 25}),
          stroke: {1, Map.get(theme, :tooltip_border, {95, 95, 95})},
          id: :"#{id}_bg"
        )
        |> Primitives.text(text,
          fill: Map.get(theme, :tooltip_text, :white),
          font: Map.get(theme, :font, :roboto),
          font_size: font_size,
          translate: {@padding, font_size + div(@padding, 2)},
          id: :"#{id}_text"
        )
      end,
      id: id,
      translate: {fit_x(x + 10, width, available_width), y + 4}
    )
  end

  @doc "How wide the label will be, measured rather than guessed where possible."
  def width(text, font, font_size) do
    measured =
      case TextHelper.measure_text(text, font: font, font_size: font_size) do
        {:ok, width} -> width
        {:error, _} -> String.length(text) * font_size * 0.6
      end

    ceil(measured) + @padding * 2
  end

  @doc "Keep the label inside the host, when the host has said how wide it is."
  def fit_x(preferred_x, _width, nil), do: preferred_x

  def fit_x(preferred_x, width, available_width),
    do: min(preferred_x, available_width - width - 4)
end
