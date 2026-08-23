defmodule ScenicWidgets.Markup.Header1 do
  @font_size 40
  @font_color :black

  def draw(graph, %{frame: %Widgex.Frame{} = f, text: text} = args)
      when is_binary(text) do
    draw(graph, f, text)
  end

  def draw(graph, %Widgex.Frame{} = f, text) when is_binary(text) do
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # |> maybe_draw_debug_layer(f, args)
        |> Scenic.Primitives.text(text,
          font_size: @font_size,
          # note we dont want to use Center here because that returns the centroid of the
          # frame in _absolute_ coordinates (taking into account frame pins & such)
          # whereas here we really just want to translate the text relative to the
          # outer graph, and that outer graph is already translated to the frame pin
          translate: {f.size.width / 2, (f.size.height - @font_size) / 2 + @font_size - 5}, # TODO magic number at thge end here
          # translate: {Widgex.Frame.center(f).x, (f.size.height - @font_size) / 2 + @font_size},
          text_align: :center,
          fill: @font_color
          # fill: Map.get(args, :color, @font_color)
        )
      end,
      translate: f.pin.point,
      scissors: f.size.box
    )
  end

  # if we're in debug mode then print out the background
  def maybe_draw_debug_layer(graph, %Widgex.Frame{} = f, %{debug?: true}) do
    graph
    |> Widgex.Frame.draw_guidewires(f)
  end

  def maybe_draw_debug_layer(graph, %Widgex.Frame{} = f, _args) do
    graph
  end
end
