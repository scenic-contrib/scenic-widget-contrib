defmodule ScenicWidgets.TextPad.Painter do
  @moduledoc """
  A module to store functions which render %Scenic.Graph{}s
  """

  def render_text_pad(
        %{
          mode: :read_only,
          format_opts: %{
            alignment: :left,
            max_lines: 2,
            # TODO and grow infinitely long / or maybe cap it??
            wrap_opts: {:wrap, :end_of_line}
          }
        } = args
      ) do
    ascent = FontMetrics.ascent(args.font.size, args.font.metrics)
    # descent = FontMetrics.descent(args.font.size, args.font.metrics)

    # TODO there's still no definitive way to calculate line height, this is just a guess...
    # line_height = (4/3)*font_size
    # line_height = (4/3)*(ascent-descent) ## MAGIC!!! See https://www.thomasphinney.com/2011/03/point-size/ - "What About the Web?" section
    # line_height = ascent - descent

    wrapped_text =
      FontMetrics.wrap(
        args.text,
        # REMINDER: Take off both margins when calculating the widt0
        args.frame.dimensions.width - (args.margin.left + args.margin.right),
        args.font.size,
        args.font.metrics
      )

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect(args.frame.size,
          id: :background,
          fill: args.theme.thumb,
          stroke: {2, args.theme.border},
          scissor: args.frame.size
        )
        |> Scenic.Primitives.text(wrapped_text,
          id: :text_pad,
          font: :ibm_plex_mono,
          font_size: args.font.size,
          fill: args.theme.text,
          # translate: {0, ascent})
          # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
          translate: {args.margin.left, ascent}
        )
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  def render_text_pad(
        %{
          mode: :read_only,
          format_opts: %{
            alignment: :left,
            # TODO and grow infinitely long / or maybe cap it??
            wrap_opts: {:wrap, :end_of_line}
          }
        } = args
      ) do
    ascent = FontMetrics.ascent(args.font.size, args.font.metrics)
    # descnt = FontMetrics.descent(args.font.size, args.font.metrics)

    wrapped_text =
      FontMetrics.wrap(
        args.text,
        # REMINDER: Take off both margins when calculating the widt0
        args.frame.dimensions.width - (args.margin.left + args.margin.right),
        args.font.size,
        args.font.metrics
      )

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect(args.frame.size,
          id: :background,
          fill: args.theme.thumb,
          stroke: {2, args.theme.border},
          scissor: args.frame.size
        )
        |> Scenic.Primitives.text(wrapped_text,
          id: :text_pad,
          font: :ibm_plex_mono,
          font_size: args.font.size,
          fill: args.theme.text,
          # translate: {0, ascent})
          # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
          translate: {args.margin.left, ascent}
        )
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  # inside-frame editing (like a TidBit)
  # wrap-frame editing
  def render_text_pad(
        %{
          mode: :edit,
          format_opts: %{
            alignment: :left,
            wrap_opts: {:wrap, :end_of_line}
          }
        } = args
      ) do
    ascent = FontMetrics.ascent(args.font.size, args.font.metrics)
    # descnt = FontMetrics.descent(args.font.size, args.font.metrics)

    wrapped_text =
      FontMetrics.wrap(
        args.text,
        # REMINDER: Take off both margins when calculating the widt0
        args.frame.dimensions.width - (args.margin.left + args.margin.right),
        args.font.size,
        args.font.metrics
      )

    # TODO figure this out for realsies
    text_height = 29.0

    # NOTE: This only works for one cursor, for now...
    # [{1, %{col: col, line: line}}] = args.cursors |> IO.inspect

    # NOTE: This *must* be wrong, because it ought to be some multiple of 14.4 (or whatever 1 char width is)
    {x_pos, line_num} =
      FontMetrics.position_at(wrapped_text, args.cursor_pos, args.font.size, args.font.metrics)

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rrect(
          {args.frame.dimensions.width, args.frame.dimensions.height, 12},
          id: :background,
          fill: args.theme.active,
          stroke: {2, args.theme.border},
          scissor: args.frame.size
        )
        |> Scenic.Primitives.text(wrapped_text,
          id: :text_pad,
          font: :ibm_plex_mono,
          font_size: args.font.size,
          fill: args.theme.text,
          # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
          translate: {args.margin.left, ascent}
        )
        |> ScenicWidgets.TextPad.PadCaret.add_to_graph(%{
          coords: {x_pos, line_num * text_height},
          height: text_height
        })
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  # scroll-frame editing
  # add line numbers on wrap-frame
  def render_text_pad(
        %{
          mode: {:vim, :normal},
          format_opts: %{
            alignment: :left,
            wrap_opts: :no_wrap,
            scroll_opts: :all_directions,
            show_line_num?: true
          }
        } = args
      ) do
    ascent = FontMetrics.ascent(args.font.size, args.font.metrics)
    # descnt = FontMetrics.descent(args.font.size, args.font.metrics)

    # TODO from where??
    text_height = 29.0

    # NOTE: This *must* be wrong, because it ought to be some multiple of 14.4 (or whatever 1 char width is)
    {x_pos, line_num} =
      FontMetrics.position_at(args.text, args.cursor_pos, args.font.size, args.font.metrics)

    # TODO this needs to be a group, with translate
    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rrect(
          {args.frame.dimensions.width, args.frame.dimensions.height, 12},
          id: :background,
          fill: args.theme.active,
          stroke: {2, args.theme.border},
          scissor: args.frame.size
        )
        |> Scenic.Primitives.text(args.text,
          id: :text_pad,
          font: :ibm_plex_mono,
          font_size: args.font.size,
          fill: args.theme.text,
          # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
          translate: {args.margin.left, ascent}
        )
        |> ScenicWidgets.TextPad.PadCaret.add_to_graph(%{
          coords: {x_pos, line_num * text_height},
          height: text_height,
          # vim-normal mode
          mode: :block
        })
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  # def render_text_pad(%{
  #   mode: {:vim, :insert},
  #   format_opts: %{
  #     alignment: :left,
  #     # showline_num?: true, #TODO
  #     wrap_opts: :no_wrap}} = args) do
  def render_text_pad(
        %{mode: {:vim, :insert}, format_opts: %{alignment: :left, wrap_opts: :no_wrap}} = args
      ) do
    IO.puts("INSERT MODEEEEEEEEEEE - LEFTYYY ")

    ascent = FontMetrics.ascent(args.font.size, args.font.metrics)
    # descnt = FontMetrics.descent(args.font.size, args.font.metrics)

    wrapped_text =
      FontMetrics.wrap(
        args.text,
        # REMINDER: Take off both margins when calculating the widt0
        args.frame.dimensions.width - (args.margin.left + args.margin.right),
        args.font.size,
        args.font.metrics
      )

    # TODO figure this out for realsies
    text_height = 29.0

    # NOTE: This only works for one cursor, for now...
    # [{1, %{col: col, line: line}}] = args.cursors |> IO.inspect

    # NOTE: This *must* be wrong, because it ought to be some multiple of 14.4 (or whatever 1 char width is)
    {x_pos, line_num} =
      FontMetrics.position_at(wrapped_text, args.cursor_pos, args.font.size, args.font.metrics)

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rrect(
          {args.frame.dimensions.width, args.frame.dimensions.height, 12},
          id: :background,
          fill: args.theme.active,
          stroke: {2, args.theme.border},
          scissor: args.frame.size
        )
        |> Scenic.Primitives.text(wrapped_text,
          id: :text_pad,
          font: :ibm_plex_mono,
          font_size: args.font.size,
          fill: args.theme.text,
          # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
          translate: {args.margin.left, ascent}
        )
        |> ScenicWidgets.TextPad.PadCaret.add_to_graph(%{
          coords: {x_pos, line_num * text_height},
          height: text_height
        })
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  def render_text_pad(%{format_opts: _unknown_format_opts} = args) do
    raise "Unrecognised TextPad format requested. #{inspect(args)}"
  end
end
