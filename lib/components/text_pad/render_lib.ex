defmodule ScenicWidgets.TextPad.Lib.RenderLib do


  def render(%{mode: :inactive} = args) do
    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  def render(%{mode: mm, format_opts: %{alignment: :left, wrap_opts: :no_wrap}} = args) do
    ascent = FontMetrics.ascent(args.font.size, args.font.metrics)
    # descnt = FontMetrics.descent(args.font.size, args.font.metrics)

    # TODO this is crashing after a little bit!!
    # wrapped_text =
    #   FontMetrics.wrap(
    #     args.text,
    #     # REMINDER: Take off both margins when calculating the widt0
    #     args.frame.dimensions.width - (args.margin.left + args.margin.right),
    #     args.font.size,
    #     args.font.metrics
    #   )

    # the default line-height is 1.2
    # https://hexdocs.pm/scenic/0.11.0-beta.0/Scenic.Primitive.Style.LineHeight.html
    # https://github.com/memononen/nanovg/blob/master/src/nanovg.h#L583
    line_height = args.font.size * 1.2

    {x_pos, line_num} =
      FontMetrics.position_at(args.text, args.cursor_pos, args.font.size, args.font.metrics)

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> draw_background(args)
        |> draw_lines_of_text(args)
        # |> Scenic.Primitives.text(args.text, #TODO change this to lines of text, each line is a new component LineOfText
        #   id: :text_pad,
        #   font: args.font.name,
        #   font_size: args.font.size,
        #   fill: args.theme.text,
        #   # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
        #   translate: {args.margin.left, args.margin.top + ascent - 2} #TODO the -2 just looks good, I dunno
        # )
        |> ScenicWidgets.TextPad.CursorCaret.add_to_graph(%{
          coords: {args.margin.left + x_pos, args.margin.top + (line_num * line_height)},
          height: line_height,
          mode: calc_mode(mm)
        }, id: {:cursor, 1})
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  defp calc_mode(:normal), do: :block
  defp calc_mode(:insert), do: :line

  defp draw_background(graph, args) do
    graph
    |> Scenic.Primitives.rect(
      {args.frame.dimensions.width, args.frame.dimensions.height},
      id: :background,
      fill: args.theme.active,
      stroke: {2, args.theme.border},
      scissor: args.frame.size
    )
  end

  #TODO wrap this in another group, so we can scroll the entire group at once
  defp draw_lines_of_text(graph, %{num_lines: num_lines, lines: lines, font: font, frame: frame, theme: theme, margin: margin}) do
    {_total_num_lines, final_graph} =
      1..num_lines
      |> Enum.map_reduce(graph, fn line_num, graph ->
        new_graph = graph
        |> ScenicWidgets.TextPad.LineOfText.add_to_graph(%{
          line_num: line_num,
          font: font,
          width: frame.dimensions.width,
          text: Enum.at(lines, line_num-1),
          theme: theme,
          margin: margin
        }, id: {:line, line_num})

        {line_num+1, new_graph}
      end)

    final_graph
  end
end
