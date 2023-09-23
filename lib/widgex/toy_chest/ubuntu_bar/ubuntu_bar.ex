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
        # %{glyph: "~", hi: 1}
        Widgex.ToyChest.Glyph.build(%{id: :g1, glyph: "!"}),
        second_glyph(),
        %{
          id: :g3,
          glyph: "&",
          font:
            %{
              # size: 24,
              # metrics: font_metrics
            },
          tile: %{
            color: QuillEx.GUI.Themes.midnight_shadow().background
          }
        },
        %{
          id: :g4,
          glyph: "$",
          font:
            %{
              # size: 24,
              # metrics: font_metrics
            },
          tile: %{
            color: QuillEx.GUI.Themes.midnight_shadow().border
          }
        },
        %{
          id: :g5,
          glyph: "%",
          font:
            %{
              # size: 24,
              # metrics: font_metrics
            },
          tile: %{
            color: QuillEx.GUI.Themes.midnight_shadow().active
          }
        }
      ],
      theme: QuillEx.GUI.Themes.midnight_shadow()
    }
  end

  def second_glyph do
    %{
      id: :g2,
      glyph: "~",
      font:
        %{
          # size: 24,
          # metrics: font_metrics
        },
      tile: %{
        color: QuillEx.GUI.Themes.midnight_shadow().focus
      }
    }
  end

  def render(%Scenic.Graph{} = graph, %__MODULE__{} = state, %Frame{} = f) do
    graph
    |> fill_frame(f, color: state.theme.border)
    |> render_glyphs(state, f)

    # |> Scenic.Components.button("Sample Button",
    #   id: :sample_btn_id,
    #   t: {5, 100},
    #   font: :ibm_plex_mono
    # )
  end

  def render_glyphs(graph, %__MODULE__{layout: {:column, :center}} = state, %Frame{} = f) do
    # we want to render each glyph as a square, in a central column
    box_size = f.size.width

    {final_graph, _final_offset} =
      Enum.reduce(state.menu_map, {graph, _init_offset = 0}, fn glyph, {graph, offset} ->
        new_graph =
          graph
          # |> Widgex.ToyChest.Glyph.add_to_graph(%{glyph | size: box_size})

          |> render_glyph(glyph, box_size, offset)

        {new_graph, offset + 1}
      end)

    final_graph
  end

  # the glyph ratio is, what % of the box do we want to take up with the glyph
  @glyph_ratio 0.72
  def render_glyph(graph, glyph, box_size, offset) do
    # TODO...
    {:ok, ibm_plex_mono_font_metrics} =
      TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

    size = box_size * @glyph_ratio

    font = %{
      size: size,
      metrics: ibm_plex_mono_font_metrics
    }

    char_width = FontMetrics.width(glyph.glyph, font.size, font.metrics)
    excess_width = box_size - char_width

    # id: :btn, input: :cursor_button

    # TODO here we could consider using the UbuntuBar state.theme, but right now just want to hack it to get it working...
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # |> Scenic.Primitives.rect(icon_size, fill: {:image, args.icon}, translate: translate)
        |> Scenic.Primitives.rect({box_size, box_size},
          id: :btn,
          input: :cursor_button,
          fill: glyph.tile.color
        )
        |> Scenic.Primitives.text(glyph.glyph,
          font_size: size,
          fill: :white,
          translate: {excess_width / 2, size}
        )
      end,
      id: __MODULE__,
      translate: {0, offset * box_size}
    )
  end

  # def handle_input({:cursor_pos, {_x, _y} = hover_coords}, _context, scene) do
  #   bounds = Scenic.Graph.bounds(scene.assigns.graph)

  #   if hover_coords |> ScenicWidgets.Utils.inside?(bounds) do
  #     cast_parent(scene, {:hover, scene.assigns.state.id})
  #   else
  #     cast_parent(scene, {:no_hover, scene.assigns.state.id})
  #   end

  #   {:noreply, scene}
  # end

  # def handle_input(
  #       {:cursor_button, {:btn_left, @key_pressed, [], {_x, _y} = click_coords}},
  #       _context,
  #       scene
  #     ) do
  #   IO.puts("GLUPH CLICKED")
  #   bounds = Scenic.Graph.bounds(scene.assigns.graph)

  #   if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
  #     cast_parent(scene, {:left_click, scene.assigns.state.id})
  #   end

  #   {:noreply, scene}
  # end

  # def handle_input(
  #       {:cursor_button, {:btn_left, x, [], {_x, _y} = click_coords}},
  #       _context,
  #       scene
  #     )
  #     when x in [@key_released, @key_held] do
  #   # ignore...
  #   {:noreply, scene}
  # end

  def handle_input(
        {:cursor_button, {:btn_left, @clicked, _empty_list?, _local_coords}},
        _context,
        scene
      ) do
    IO.puts("LEFT CLICKLE")
    {:noreply, scene}
  end

  def handle_input({:cursor_button, _details} = input, _context, scene) do
    Logger.debug("ignoring input.... #{inspect(input)}")
    {:noreply, scene}
  end

  def handle_event(event, _from_pid, scene) do
    IO.inspect(event)
    {:noreply, scene}
  end
end
