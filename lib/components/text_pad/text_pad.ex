defmodule ScenicWidgets.TextPad do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions
  alias ScenicWidgets.Core.Structs.Frame
  require Logger

  @default_font :roboto
  @default_font_size 24
  @default_margin %{left: 4, top: 0, bottom: 0, right: 4}

  @newline_char "\n"

  def validate(%{text: nil} = args) do
    validate(Map.put(args, :text, ""))
  end

  def validate(
        %{
          id: _id,
          frame: %Frame{} = _frame,
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
    line_height = line_height(init_font_details)
    num_lines = trunc(Float.ceil(frame_height / line_height))

    final_args =
      args
      # default to zero
      |> Map.merge(%{cursor_pos: args |> Map.get(:cursor, %{line: 1, col: 1})})
      |> Map.merge(%{margin: @default_margin})
      |> Map.merge(%{font: init_font_details})
      |> Map.merge(%{num_lines: num_lines})
      |> Map.merge(%{lines: String.split(text, @newline_char)})
      |> Map.merge(%{scroll_acc: {0,0}})

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
      |> assign(frame: args.frame)
      |> assign(margin: args.margin)
      |> assign(id: args.id)
      |> assign(theme: args.theme)
      |> assign(scroll_acc: args.scroll_acc)
      |> assign(graph: init_graph)
      # |> assign(percentage: 1.0) # TODO this is for scrolling...
      |> push_graph(init_graph)

    {:ok, init_scene}
  end

  def handle_cast({:redraw, %{data: text} = args}, scene) when is_bitstring(text) do
    Logger.debug "converting text input to list of lines..."
    lines = String.split(text, @newline_char)
    GenServer.cast(self(), {:redraw, Map.put(args, :data, lines)})
    {:noreply, scene}
  end

  def handle_cast({:redraw, %{scroll_acc: new_scroll_acc}}, scene) do

    new_graph = scene.assigns.graph |> Scenic.Graph.modify(
      {__MODULE__, scene.assigns.id, :scrollable},
      &Scenic.Primitives.update_opts(&1, translate: new_scroll_acc)
    )

    #TODO cast to scroll bars... make them visible/not visible, adjust position & percentage shown aswell

    new_scene = scene
    |> assign(graph: new_graph)
    |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  # def handle_cast({:redraw, %{scroll: _delta}}, %{assigns: %{percentage: p}} = scene) when p >= 1 do
  #   IO.puts "NO SCRTOLL"
  #   {:noreply, scene}
  # end

  # def handle_cast({:redraw, %{scroll: {delta_x, delta_y}}}, scene) do

  #   IO.puts "GOT SCROLL!?!???"



  #   diff = (1-scene.assigns.percentage) * scene.assigns.frame.dimensions.width

  #   {x_diff, y_diff} = new_scroll_acc =
  #     Scenic.Math.Vector2.add(scene.assigns.scroll_acc, {delta_x*x_scroll_factor, delta_y*@scroll_speed})
  #     |> calc_ceil(@min_position_cap)
  #     # |> IO.inspect(label: "NEW SCROLL")

  #   if abs(x_diff) >= diff do
  #     IO.puts "YESSS - DONT SCROLLLLLLL"
  #     IO.inspect x_diff, label: "XDIF"
  #     IO.inspect diff, label: "DIF"

  #     {:noreply, scene}

  #   else
  #     IO.puts "NOOOOO"
  #     IO.inspect x_diff, label: "XDIF"
  #     IO.inspect diff, label: "DIF"

  #     new_graph =scene.assigns.graph |> Scenic.Graph.modify(
  #       {__MODULE__, scene.assigns.id, :scrollable},
  #       &Scenic.Primitives.update_opts(&1, translate: new_scroll_acc)
  #     )

  #     #TODO update scroll bar
  
  #     new_scene = scene
  #     |> assign(graph: new_graph)
  #     |> push_graph(new_graph)
  
  #     {:noreply, new_scene}

  #   end
  # end

  #NOTE: This doesn't work simply because when we type a msg, the line of
  # text doesn't get updated before we try to calculate the cursor position
  # def handle_cast({:redraw, %{cursor: cursor}}, scene) do
  #   # text = Enum.at(scene.assigns.data, cursor.line-1)

  #   {:ok, [pid]} = child(scene, {:line, cursor.line})
  #   {:ok, text} = GenServer.call(pid, :get_text)

  #   {x_pos, _cursor_pos_line_num} =
  #       FontMetrics.position_at(text, cursor.col-1, scene.assigns.font.size, scene.assigns.font.metrics)

  #   new_cursor_pos =
  #     {
  #       (scene.assigns.margin.left + x_pos),
  #       (scene.assigns.margin.top + ((cursor.line-1) * line_height(scene.assigns)))
  #     }

  #   {:ok, [pid]} = child(scene, {:cursor, 1})
  #   GenServer.cast(pid, {:move, new_cursor_pos})

  #   {:noreply, scene}
  # end

  # and is_integer(l) and l >= 1 and is_integer(c) and c >= 1 
  # NOTE: We need to handle data & cursor updates together, hang on do we??
  def handle_cast({:redraw, %{data: [l|_rest] = lines_of_text, cursor: cursor}}, scene) when is_bitstring(l) do
    # cast down to each LineOfText component with the contents of each line,
    # those components are responsible for computing whether any changes are needed

    {final_graph, line_widths} =
      lines_of_text
      |> Enum.with_index(1)
      |> Enum.reduce({scene.assigns.graph, []}, fn({text, line_num}, {graph, line_widths}) ->

          # # if this is the line the cursor is on, update the cursor
          if line_num == cursor.line do
            {x_pos, _cursor_pos_line_num} =
              FontMetrics.position_at(text, cursor.col-1, scene.assigns.font.size, scene.assigns.font.metrics)

            new_cursor_pos =
              {scene.assigns.margin.left + x_pos, scene.assigns.margin.top + ((cursor.line-1) * line_height(scene.assigns))}

            {:ok, [pid]} = child(scene, {:cursor, 1})
            GenServer.cast(pid, {:move, new_cursor_pos})
          end

          line_width =
            FontMetrics.width(text, scene.assigns.font.size, scene.assigns.font.metrics)

          case child(scene, {:line, line_num}) do
            {:ok, [pid]} ->
              GenServer.cast(pid, {:redraw, text})
              {graph, line_widths ++ [line_width]}
            {:ok, []} ->
              # need to create a new LineOfText component...
              IO.puts "SHOULDNT BE HERE YET ANYWAY"
              new_graph =
                graph
                |> Scenic.Graph.add_to({__MODULE__, scene.assigns.id, :scrollable}, fn graph ->
                  graph
                  |> ScenicWidgets.TextPad.LineOfText.add_to_graph(%{
                    line_num: line_num,
                    name: random_string(),
                    font: scene.assigns.font,
                    frame: calc_line_of_text_frame(scene.assigns.frame, scene.assigns.margin, scene.assigns.font, line_num),
                    text: text,
                    theme: scene.assigns.theme,
                  }, id: {:line, line_num})
                end)

              {new_graph, line_widths ++ [line_width]}
          end
      end)


    #TODO is this fast enough?? Will it pick up changes fast enough , since they are done asyncronously???
    # {left, _top, right, _bottom} =
    #   scene.assigns.graph
    #   |> Scenic.Graph.bounds()

    h = length(line_widths) * line_height(scene.assigns.font)

    cast_parent(scene, {:scroll_limits, %{
      inner: %{
        width: Enum.max(line_widths),
        height: h,
      },
      frame: scene.assigns.frame
    }})

    if final_graph == scene.assigns.graph do
      {:noreply, scene}
    else
      new_scene = scene
        |> assign(graph: final_graph)
        |> push_graph(final_graph)

      {:noreply, new_scene}
    end

    # {left, _top, right, _bottom} =
    #   scene.assigns.graph
    #   |> Scenic.Graph.bounds()

    # text_width = right-left
    # %{dimensions: %{width: frame_width}} = scene.assigns.frame

    # percentage = frame_width/text_width

    # {:ok, [pid]} = child(scene, {:scrollbar, :horizontal})
    # GenServer.cast(pid, {:scroll_percentage, :horizontal, percentage})
    # {:noreply, scene |> assign(percentage: percentage)}

    # cond do
    #   frame_width >= text_width ->
    #     {:noreply, scene}
    #   text_width > frame_width ->
    #     {:ok, [pid]} = child(scene, {:scrollbar, :horizontal})
    #     GenServer.cast(pid, {:scroll_percentage, :horizontal, frame_width/text_width})
    #     {:noreply, scene}
    # end

    
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
        |> Scenic.Primitives.group(
          fn graph ->
            graph
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
          id: {__MODULE__, args.id, :scrollable},
          translate: args.scroll_acc
        )
        # |> ScenicWidgets.TextPad.ScrollBar.add_to_graph(%{
        #       frame: horizontal_scroll_bar_frame(args.frame),
        #       orientation: :horizontal,
        #       position: 1
        # }, id: {:scrollbar, :horizontal}, hidden: true)
      end,
      id: {__MODULE__, args.id},
      translate: args.frame.pin
    )
  end

  def line_height(%{font: font}), do: line_height(font)

  def line_height(%{size: font_size}) do
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
          name: random_string(),
          font: font,
          # width: frame.dimensions.width,
          frame: calc_line_of_text_frame(frame, margin, font, line_num),
          text: Enum.at(lines, line_num-1),
          theme: theme,
          # margin: margin
        }, id: {:line, line_num})

        {line_num+1, new_graph}
      end)

    final_graph
  end

  def horizontal_scroll_bar_frame(outer_frame) do
    bar_height = 20
    bottom_left_corner = Frame.bottom_left(outer_frame)

    #NOTE: Don't go all the way to the edges of the outer frame, we
    # want to sit perfectly snug inside it
    Frame.new(
      pin: {bottom_left_corner.x+1, bottom_left_corner.y-bar_height-1},
      size: {outer_frame.dimensions.width-2, bar_height}
    )
  end

  def calc_line_of_text_frame(frame, %{left: left_margin, top: top_margin} = _margin, font, line_num) do
    line_height = line_height(font)
    y_offset = (line_num-1)*line_height # how far we need to move this line down, based on what line number it is
    Frame.new(%{
      pin: {left_margin, top_margin+y_offset},
      size: {frame.dimensions.width, line_height}
    })
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



  def random_string do
    # https://dev.to/diogoko/random-strings-in-elixir-e8i
    for _ <- 1..10, into: "", do: <<Enum.random('0123456789abcdef')>>
  end
end
