defmodule ScenicWidgets.TextPad.Lib.RenderLib do


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

    # line_height = FontMetrics.line_height(args.font.size, args.font.metrics)
    # |> IO.inspect(label: "lineh")
    line_height = 29 #TODO this is hard-coded until FontMetrics.line height works, through trial and error I know this is the correct number for size 24 IBm Plex Mono

    # NOTE: This only works for one cursor, for now...
    # [{1, %{col: col, line: line}}] = args.cursors |> IO.inspect

    # NOTE: This *must* be wrong, because it ought to be some multiple of 14.4 (or whatever 1 char width is)
    {x_pos, line_num} =
      FontMetrics.position_at(args.text, args.cursor_pos, args.font.size, args.font.metrics)

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> draw_background(args)
        |> Scenic.Primitives.text(args.text,
          id: :text_pad,
          font: args.font.name,
          font_size: args.font.size,
          fill: args.theme.text,
          # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
          translate: {args.margin.left, args.margin.top + ascent}
        )
        |> ScenicWidgets.TextPad.CursorCaret.add_to_graph(%{
          coords: {args.margin.left + x_pos, args.margin.top + (line_num * line_height)}, # the -1 is just for aesthetics, I like it better this way
          height: line_height,
          mode: calc_mode(mm)
        })
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
end
