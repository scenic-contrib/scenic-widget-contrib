defmodule Widgex.ToyChest.Glyph do
  use Scenic.Component, has_children: false
  require Logger

  defstruct id: nil,
            size: nil,
            font: nil,
            tile: nil,
            glyph: nil

  def build(%{id: id, glyph: g}) when is_binary(g) do
    {:ok, font_metrics} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

    %__MODULE__{
      id: id,
      glyph: g,
      font: %{
        # size: 24,
        metrics: font_metrics
      },
      tile: %{
        color: :pink
      }
    }
  end

  @impl Scenic.Component
  def validate(%__MODULE__{} = state) do
    {:ok, state}
  end

  @impl Scenic.Scene
  def init(scene, state, opts) do
    IO.inspect(state, label: "Glyph state")
    Logger.info("Starting #{__MODULE__}...")

    init_graph = render_glyph(state, opts)

    init_scene =
      scene
      |> assign(graph: init_graph)
      |> assign(state: state)
      |> push_graph(init_graph)

    {:ok, init_scene}
  end

  # the glyph ratio is, what % of the box do we want to take up with the glyph
  @glyph_ratio 0.72
  def render_glyph(glyph, _opts) do
    # size =
    #   font = %{
    #     size: glyph.size * @glyph_ratio,
    #     metrics: glyph.font - metrics
    #   }

    font_size = glyph.size * @glyph_ratio

    char_width = FontMetrics.width(glyph.glyph, font_size, glyph.font.metrics)
    excess_width = glyph.size - char_width

    Scenic.Graph.build(font: :ibm_plex_mono)
    # |> Scenic.Primitives.rect(icon_size, fill: {:image, args.icon}, translate: translate)
    |> Scenic.Primitives.rect({glyph.size, glyph.size}, fill: glyph.tile.color)
    |> Scenic.Primitives.text(glyph.glyph,
      font_size: font_size,
      fill: :white,
      translate: {excess_width / 2, font_size}
    )
  end
end
