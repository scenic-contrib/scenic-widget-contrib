defmodule ScenicWidgets.UbuntuBar do
  use Widgex.Component

  defstruct id: __MODULE__,
            menu_map: nil,
            menu_map_config: nil,
            theme: nil,
            layout: {:column, :center}

  def draw do
    %__MODULE__{
      menu_map: [
        %{glyph: "~", hi: 1}
      ],
      theme: QuillEx.GUI.Themes.midnight_shadow()
    }
  end

  def render(%Scenic.Graph{} = graph, %__MODULE__{} = state, %Frame{} = f) do
    graph
    |> fill_frame(f, color: state.theme.border)
    |> render_glyphs(state, f)
    |> Scenic.Components.button("Sample Button",
      id: :sample_btn_id,
      t: {5, 100},
      font: :ibm_plex_mono
    )
    |> Widgex.ToyChest.Glyph.add_to_graph(%{})
  end

  def render_glyphs(graph, %__MODULE__{layout: {:column, :center}} = state, %Frame{} = f) do
    # we want to render each glyph as a square, in a central column
    box_size = f.size.width

    Enum.reduce(state.menu_map, graph, fn %{glyph: glyph, hi: hi}, graph ->
      graph
      |> render_glyph(glyph, box_size)
    end)

    # final_graph
  end

  # the glyph ratio is, what % of the box do we want to take up with the glyph
  @glyph_ratio 0.72
  def render_glyph(graph, glyph, box_size) do
    # TODO...
    {:ok, ibm_plex_mono_font_metrics} =
      TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

    size = box_size * @glyph_ratio

    font = %{
      size: size,
      metrics: ibm_plex_mono_font_metrics
    }

    char_width = FontMetrics.width(glyph, font.size, font.metrics)
    excess_width = box_size - char_width

    graph
    # |> Scenic.Primitives.rect(icon_size, fill: {:image, args.icon}, translate: translate)
    |> Scenic.Primitives.rect({box_size, box_size}, fill: :blue)
    |> Scenic.Primitives.text(glyph,
      font_size: size,
      fill: :white,
      translate: {excess_width / 2, size}
    )
  end

  def handle_input({:cursor_pos, {_x, _y} = hover_coords}, _context, scene) do
    bounds = Scenic.Graph.bounds(scene.assigns.graph)

    if hover_coords |> ScenicWidgets.Utils.inside?(bounds) do
      cast_parent(scene, {:hover, scene.assigns.state.id})
    else
      cast_parent(scene, {:no_hover, scene.assigns.state.id})
    end

    {:noreply, scene}
  end

  def handle_input(
        {:cursor_button, {:btn_left, @key_pressed, [], {_x, _y} = click_coords}},
        _context,
        scene
      ) do
    IO.puts("GLUPH CLICKED")
    bounds = Scenic.Graph.bounds(scene.assigns.graph)

    if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
      cast_parent(scene, {:left_click, scene.assigns.state.id})
    end

    {:noreply, scene}
  end

  def handle_input(
        {:cursor_button, {:btn_left, x, [], {_x, _y} = click_coords}},
        _context,
        scene
      )
      when x in [@key_released, @key_held] do
    # ignore...
    {:noreply, scene}
  end

  def handle_event(event, _from_pid, scene) do
    IO.inspect(event)
    {:noreply, scene}
  end
end
