defmodule ScenicWidgets.TextPad do
  use Scenic.Component
  require Logger
  use ScenicWidgets.ScenicEventsDefinitions

  @default_font :roboto
  @default_font_size 24
  @newline_char "\n"

  def validate(%{mode: :inactive, frame: %ScenicWidgets.Core.Structs.Frame{} = _frame} = args) do
    final_args =
      args
      |> Map.merge(%{cursor_pos: args |> Map.get(:cursor, %{line: 1, col: 1})})
      |> Map.merge(%{margin: %{left: 4, top: 4, bottom: 4, right: 4}}) #TODO here
      |> Map.merge(%{font: calc_font_details(args)})

    {:ok, final_args}
  end

  def validate(
        %{
          id: _id,
          frame: %ScenicWidgets.Core.Structs.Frame{} = _frame,
          text: text, #TODO change to data?
          mode: mode,
          format_opts: %{ #TODo change to format? Layout? something else??
            alignment: :left,
            # TODO this is what I'm working on, making it line-wrap
            wrap_opts: _wrap_opts,
            # TODO this too
            show_line_num?: show_line_num? #TODo I changed my mind, I think this should live in editor, not TextPad - textpad just renders lines of text...
          }
        } = args
      )
      when is_bitstring(text) and
             mode in [:normal, :insert] and
             is_boolean(show_line_num?) do
    # Logger.debug("#{__MODULE__} accepted args: #{inspect(args)}")

    init_font_details = calc_font_details(args)
    frame_height = args.frame.dimensions.height
    line_height = init_font_details.size * 1.2
    num_lines = trunc(Float.ceil(frame_height / line_height))

    final_args =
      args
      # default to zero
      |> Map.merge(%{cursor_pos: args |> Map.get(:cursor, %{line: 0, col: 0})})
      |> Map.merge(%{margin: %{left: 4, top: 4, bottom: 4, right: 4}}) #TODO here
      |> Map.merge(%{font: init_font_details})
      |> Map.merge(%{num_lines: num_lines})
      |> Map.merge(%{lines: String.split(text, @newline_char)})

    {:ok, final_args}
  end

  def init(scene, args, opts) do
    Logger.debug("#{__MODULE__} initializing...")
    theme = ScenicWidgets.Utils.Theme.get_theme(opts)

    args = Map.merge(args, %{theme: theme})

    init_graph = render(args)

    init_scene =
      scene
      |> assign(font: args.font)
      |> assign(margin: args.margin)
      |> push_graph(init_graph)

    {:ok, init_scene}
  end

  def handle_cast({:redraw, %{data: text, cursor: %{line: l, col: c}}}, scene)
    when is_bitstring(text) and is_integer(l) and l >= 1 and is_integer(c) and c >= 1 do
      Logger.debug "converting text input to list of lines..."
      lines = String.split(text, @newline_char)
      GenServer.cast(self(), {:redraw, %{data: lines, cursor: %{line: l, col: c}}})
      {:noreply, scene}
  end

  def handle_cast({:redraw, %{data: []}}, scene) do
    # do nothing...
    IO.puts "ENPTY LIST"
    {:noreply, scene}
  end

  def handle_cast({:redraw, %{data: [""]}}, scene) do
    # do nothing...
    IO.puts "ENPTY LIST WITH A STINGLE"
    {:noreply, scene}
  end

  def handle_cast({:redraw, %{data: [l|_rest] = lines_of_text, cursor: coords}}, scene) when is_bitstring(l) do
    # cast down to each LineOfText component with the contents of each line,
    # those components are responsible for computing whether any changes are needed

    IO.inspect coords, label: "COORDS"

    lines_of_text
    |> Enum.with_index(1)
    |> Enum.each(fn({text, line_num}) ->

        # if this is the line the cursor is on, update the cursor
        if line_num == coords.line do
          {x_pos, _cursor_pos_line_num} =
            FontMetrics.position_at(text, coords.col-1, scene.assigns.font.size, scene.assigns.font.metrics)

          new_cursor_pos =
            {scene.assigns.margin.left + x_pos, scene.assigns.margin.top + ((coords.line-1) * line_height(scene.assigns))}
    
          {:ok, [pid]} = child(scene, {:cursor, 1})
          GenServer.cast(pid, {:move, new_cursor_pos})
        end

        {:ok, [pid]} = child(scene, {:line, line_num}) #TODO ok here, if we have too many lines, this is now where it fucks up...
        GenServer.cast(pid, {:redraw, text})
    end)
    
    {:noreply, scene}
  end

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

    
    line_height = line_height(args)

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
          margin: args.margin,
          coords: {args.margin.left + x_pos, args.margin.top + (line_num * line_height)},
          height: line_height,
          mode: calc_mode(mm)
        }, id: {:cursor, 1})
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  def line_height(%{font: %{size: font_size}}) do
    # the default line-height is 1.2
    # https://hexdocs.pm/scenic/0.11.0-beta.0/Scenic.Primitive.Style.LineHeight.html
    # https://github.com/memononen/nanovg/blob/master/src/nanovg.h#L583
    1.2*font_size #TODO make this configurable
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

  def calc_font_details(args) do
    case Map.get(args, :font, :not_found) do
      %{name: font_name, size: font_size, metrics: %FontMetrics{} = _fm} = provided_details
      when is_atom(font_name) and is_integer(font_size) ->
        provided_details

      %{name: font_name, size: custom_font_size}
      when is_atom(font_name) and is_integer(custom_font_size) ->
        {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
        %{name: font_name, metrics: custom_font_metrics, size: custom_font_size}

      :not_found ->
        {:ok, {_type, default_font_metrics}} = Scenic.Assets.Static.meta(@default_font)
        %{name: @default_font, metrics: default_font_metrics, size: @default_font_size}

      font_name when is_atom(font_name) ->
        {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
        %{name: font_name, metrics: custom_font_metrics, size: @default_font_size}
    end
  end
end
