defmodule ScenicWidgets.TextPad do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions
  alias ScenicWidgets.Core.Structs.Frame
  alias ScenicWidgets.TextPad.Structs.Buffer
  alias ScenicWidgets.TextPad.Structs.Buffer.Cursor
  require Logger


  # NOTE ok so - there's gonna be no choice, I better just try it - make each
  # line it's own (possibly dumb?) component.

  # Scroll wrapping - for this, I can go ahead with existing text (which wraps),
  # but treat it as larger than another container. However, ultimately
  # I want to be able to disable the scroll-wrapping talked about above,
  # so that I can render  continuous line, & potentially scroll it

  # Other unimplemented cases: Max 1 line height (e.g. KommandBuffer)



  @default_font :roboto
  @default_font_size 24
  @default_margin %{left: 4, top: 0, bottom: 0, right: 4}

  @newline_char "\n"

  def validate(%{text: nil} = args) do
    validate(Map.put(args, :text, ""))
  end

  def validate(
        %{
          # id: _id,
          # type: :text,
          frame: %Frame{} = _frame,
          text: text, #TODO change to data?
          mode: mode,
          # format_opts: %{ #TODo change to format? Layout? something else??
          #   alignment: :left,
          #   # TODO this is what I'm working on, making it line-wrap
          #   wrap_opts: _wrap_opts,
          #   # TODO this too
          #   # show_line_num?: show_line_num? #TODo I changed my mind, I think this should live in editor, not TextPad - textpad just renders lines of text...
          # }
        } = args
      )
      when is_bitstring(text) and
             mode in [:normal, :insert] do
            #  is_boolean(show_line_num?) do
    # Logger.debug("#{__MODULE__} accepted args: #{inspect(args)}")

    init_font_details = calc_font_details(args)
    frame_height = args.frame.dimensions.height
    line_height = line_height(init_font_details)
    num_lines = trunc(Float.ceil(frame_height / line_height))

    final_args =
      args
      # default to zero
      |> Map.merge(%{cursor_pos: args |> Map.get(:cursor, %{line: 1, col: 1})})
      |> Map.merge(%{margin: args[:margin] || @default_margin})
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
      |> assign(id: opts[:id])
      |> assign(theme: args.theme)
      |> assign(scroll_acc: args.scroll_acc)
      |> assign(graph: init_graph)
      # |> assign(percentage: 1.0) # TODO this is for scrolling...
      |> push_graph(init_graph)

    {:ok, init_scene}
  end

  def handle_cast({:redraw, %{data: nil} = args}, scene) do
    lines = [""]
    GenServer.cast(self(), {:redraw, Map.put(args, :data, lines)})
    {:noreply, scene}
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
            if not is_nil(Map.get(cursor, :mode)) do
              GenServer.cast(pid, {:mode, cursor.mode})
            end
          end

          line_width =
            FontMetrics.width(text, scene.assigns.font.size, scene.assigns.font.metrics)

          case child(scene, {:line, line_num}) do
            {:ok, [pid]} ->
              GenServer.cast(pid, {:redraw, text})
              {graph, line_widths ++ [line_width]}
            {:ok, []} ->
              # need to create a new LineOfText component...
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

    line = Enum.at(args.lines, args.cursor_pos.line-1)
    {x_pos, _line_num} =
      FontMetrics.position_at(line, args.cursor_pos.col-1, args.font.size, args.font.metrics)

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
              coords: {args.margin.left + x_pos, args.margin.top + ((args.cursor_pos.line-1) * line_height)},
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



  # GenServer.cast(pid, {:redraw, %{data: active_buffer.data, cursor: hd(active_buffer.cursors)}})
  # GenServer.cast(pid, {:redraw, %{scroll_acc: active_buffer.scroll_acc}})
  # def handle_update(%{text: t, cursor_pos: %Cursor{} = c, scroll_acc: s} = data, opts, scene) when is_bitstring(t) do

  #TODO ok this is stupid, we need to go through validate/1 to use this, even though most of it is a waste of time...

  # def handle_update(%{text: t, cursor: c, scroll_acc: s} = data, opts, scene) when is_bitstring(t) do
  #   # IO.puts "HAND:ING UPDATEEEE"
  #   # lines = String.split(t, @newline_char)
  #   GenServer.cast(self(), %{data: t, cursor: c})
  #   GenServer.cast(self(), %{scroll_acc: s})
  #   {:noreply, scene}
  # end  


  # def handle_cast({:redraw, %{data: text} = args}, scene) when is_bitstring(text) do
  #   Logger.debug "converting text input to list of lines..."
  #   lines = String.split(text, @newline_char)
  #   GenServer.cast(self(), {:redraw, Map.put(args, :data, lines)})
  #   {:noreply, scene}
  # end















  # defmodule Scenic.Component.Input.TextField do
#     @moduledoc """
#     Add a text field input to a graph
#     ## Data
#     `initial_value`
#     * `initial_value` - is the string that will be the starting value
#     ## Messages
#     When the text in the field changes, it sends an event message to the host
#     scene in the form of:
#     `{:value_changed, id, value}`
#     ## Styles
#     Text fields honor the following styles
#     * `:hidden` - If `false` the component is rendered. If `true`, it is skipped.
#     The default is `false`.
#     * `:theme` - The color set used to draw. See below. The default is `:dark`
#     ## Additional Options
#     Text fields honor the following list of additional options.
#     * `:filter` - Adding a filter option restricts which characters can be
#     entered into the text_field component. The value of filter can be one of:
#       * `:all` - Accept all characters. This is the default
#       * `:number` - Any characters from "0123456789.,"
#       * `"filter_string"` - Pass in a string containing all the characters you
#       will accept
#       * `function/1` - Pass in an anonymous function. The single parameter will
#       be the character to be filtered. Return `true` or `false` to keep or reject
#       it.
#     * `:hint` - A string that will be shown (greyed out) when the entered value
#     of the component is empty.
#     * `:hint_color` - any [valid color](Scenic.Primitive.Style.Paint.Color.html).
#     * `:type` - Can be one of the following options:
#       * `:all` - Show all characters. This is the default.
#       * `:password` - Display a string of '*' characters instead of the value.
#     * `:width` - set the width of the control.
#     ## Theme
#     Text fields work well with the following predefined themes: `:light`, `:dark`
#     To pass in a custom theme, supply a map with at least the following entries:
#     * `:text` - the color of the text
#     * `:background` - the background of the component
#     * `:border` - the border of the component
#     * `:focus` - the border while the component has focus
#     ## Usage
#     You should add/modify components via the helper functions in
#     [`Scenic.Components`](Scenic.Components.html#text_field/3)
#     ## Examples
#         graph
#         |> text_field("Sample Text", id: :text_id, translate: {20,20})
#         graph
#         |> text_field(
#           "", id: :pass_id, type: :password, hint: "Enter password", translate: {20,20}
#         )
#     """

#     @default_hint ""
#     @default_hint_color :grey
#     @default_font :roboto_mono
#     @default_font_size 20
#     @char_width 12
#     @inset_x 10

#     @default_type :text
#     @default_filter :all

#     @default_width @char_width * 24
#     @default_height @default_font_size * 1.5

#     @input_capture [:cursor_button, :codepoint, :key]

#     # --------------------------------------------------------
#     @doc false
#     @impl Scenic.Scene
#     def init(scene, value, opts) do
#       id = opts[:id]

#       # theme is passed in as an inherited style
#       theme =
#         (opts[:theme] || Theme.preset(:dark))
#         |> Theme.normalize()

#       # get the text_field specific opts
#       hint = opts[:hint] || @default_hint
#       width = opts[:width] || opts[:w] || @default_width
#       height = opts[:height] || opts[:h] || @default_height
#       type = opts[:type] || @default_type
#       filter = opts[:filter] || @default_filter
#       hint_color = opts[:hint_color] || @default_hint_color

#       index = String.length(value)

#       display = display_from_value(value, type)

#       caret_v = -trunc((height - @default_font_size) / 4)

#       scene =
#         assign(
#           scene,
#           graph: nil,
#           theme: theme,
#           width: width,
#           height: height,
#           value: value,
#           display: display,
#           hint: hint,
#           hint_color: hint_color,
#           index: index,
#           char_width: @char_width,
#           focused: false,
#           type: type,
#           filter: filter,
#           id: id,
#           caret_v: caret_v
#         )

#       graph =
#         Graph.build(
#           font: @default_font,
#           font_size: @default_font_size,
#           scissor: {width, height}
#         )
#         |> rect(
#           {width, height},
#           # fill: :clear,
#           fill: theme.background,
#           stroke: {2, theme.border},
#           id: :border,
#           input: :cursor_button
#         )
#         |> group(
#           fn g ->
#             g
#             |> text(
#               @default_hint,
#               fill: hint_color,
#               t: {0, @default_font_size},
#               id: :text
#             )
#             |> Caret.add_to_graph(height, id: :caret)
#           end,
#           t: {@inset_x, 2}
#         )
#         |> update_text(display, scene.assigns)
#         |> update_caret(display, index, caret_v)

#       scene =
#         scene
#         |> assign(graph: graph)
#         |> push_graph(graph)

#       {:ok, scene}
#     end

#     @impl Scenic.Component
#     def bounds(_data, opts) do
#       width = opts[:width] || opts[:w] || @default_width
#       height = opts[:height] || opts[:h] || @default_height
#       {0, 0, width, height}
#     end

#     # ============================================================================

#     # --------------------------------------------------------
#     # to be called when the value has changed
#     defp update_text(graph, "", %{hint: hint, hint_color: hint_color}) do
#       Graph.modify(graph, :text, &text(&1, hint, fill: hint_color))
#     end

#     defp update_text(graph, value, %{theme: theme}) do
#       Graph.modify(graph, :text, &text(&1, value, fill: theme.text))
#     end

#     # ============================================================================

#     # --------------------------------------------------------
#     defp update_caret(graph, value, index, caret_v) do
#       str_len = String.length(value)

#       # double check the postition
#       index =
#         cond do
#           index < 0 -> 0
#           index > str_len -> str_len
#           true -> index
#         end

#       # calc the caret position
#       x = index * @char_width

#       # move the caret
#       Graph.modify(graph, :caret, &update_opts(&1, t: {x, caret_v}))
#     end

#     # --------------------------------------------------------
#     defp capture_focus(%{assigns: %{focused: false, graph: graph, theme: theme}} = scene) do
#       # capture the input
#       capture_input(scene, @input_capture)

#       # start animating the caret
#       cast_children(scene, :start_caret)

#       # show the caret
#       graph =
#         graph
#         |> Graph.modify(:caret, &update_opts(&1, hidden: false))
#         |> Graph.modify(:border, &update_opts(&1, stroke: {2, theme.focus}))

#       # update the state
#       scene
#       |> assign(focused: true, graph: graph)
#       |> push_graph(graph)
#     end

#     # --------------------------------------------------------
#     defp release_focus(%{assigns: %{focused: true, graph: graph, theme: theme}} = scene) do
#       # release the input
#       release_input(scene)

#       # stop animating the caret
#       cast_children(scene, :stop_caret)

#       # hide the caret
#       graph =
#         graph
#         |> Graph.modify(:caret, &update_opts(&1, hidden: true))
#         |> Graph.modify(:border, &update_opts(&1, stroke: {2, theme.border}))

#       # update the state
#       scene
#       |> assign(focused: false, graph: graph)
#       |> push_graph(graph)
#     end

#     # --------------------------------------------------------
#     # get the text index from a mouse position. clap to the
#     # beginning and end of the string
#     defp index_from_cursor_pos({x, _}, value) do
#       # account for the text inset
#       x = x - @inset_x

#       # get the max index
#       max_index = String.length(value)

#       # calc the new index
#       d = x / @char_width
#       i = trunc(d)
#       i = i + round(d - i)
#       # clamp the result
#       cond do
#         i < 0 -> 0
#         i > max_index -> max_index
#         true -> i
#       end
#     end

#     # --------------------------------------------------------
#     defp display_from_value(value, :password) do
#       String.to_charlist(value)
#       |> Enum.map(fn _ -> @password_char end)
#       |> to_string()
#     end

#     defp display_from_value(value, _), do: value

#     # ============================================================================
#     # User input handling - get the focus

#     # --------------------------------------------------------
#     # unfocused click in the text field
#     @doc false
#     @impl Scenic.Scene
#     def handle_input(
#           {:cursor_button, {:btn_left, 1, _, _}} = inpt,
#           :border,
#           %{assigns: %{focused: false}} = scene
#         ) do
#       handle_input(inpt, :border, capture_focus(scene))
#     end

#     # --------------------------------------------------------
#     # focused click in the text field
#     def handle_input(
#           {:cursor_button, {:btn_left, 1, _, pos}},
#           :border,
#           %{assigns: %{focused: true, value: value, index: index, graph: graph, caret_v: caret_v}} =
#             scene
#         ) do
#       {index, graph} =
#         case index_from_cursor_pos(pos, value) do
#           ^index ->
#             {index, graph}

#           i ->
#             # reset_caret the caret blinker
#             cast_children(scene, :reset_caret)

#             # move the caret
#             {i, update_caret(graph, value, i, caret_v)}
#         end

#       scene =
#         scene
#         |> assign(index: index, graph: graph)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     # focused click outside the text field
#     def handle_input(
#           {:cursor_button, {:btn_left, 1, _, _}},
#           _id,
#           %{assigns: %{focused: true}} = scene
#         ) do
#       {:cont, release_focus(scene)}
#     end

#     # ignore other button press events
#     def handle_input({:cursor_button, {_, _, _, _}}, _id, scene) do
#       {:noreply, scene}
#     end

#     # ============================================================================
#     # control keys

#     # --------------------------------------------------------
#     def handle_input(
#           {:key, {:key_left, 1, _}},
#           _id,
#           %{assigns: %{index: index, value: value, graph: graph, caret_v: caret_v}} = scene
#         ) do
#       # move left. clamp to 0
#       {index, graph} =
#         case index do
#           0 ->
#             {0, graph}

#           i ->
#             # reset_caret the caret blinker
#             cast_children(scene, :reset_caret)
#             # move the caret
#             i = i - 1
#             {i, update_caret(graph, value, i, caret_v)}
#         end

#       scene =
#         scene
#         |> assign(index: index, graph: graph)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     def handle_input(
#           {:key, {:key_right, 1, _}},
#           _id,
#           %{assigns: %{index: index, value: value, graph: graph, caret_v: caret_v}} = scene
#         ) do
#       # the max position for the caret
#       max_index = String.length(value)

#       # move left. clamp to 0
#       {index, graph} =
#         case index do
#           ^max_index ->
#             {index, graph}

#           i ->
#             # reset the caret blinker
#             cast_children(scene, :reset_caret)

#             # move the caret
#             i = i + 1
#             {i, update_caret(graph, value, i, caret_v)}
#         end

#       scene =
#         scene
#         |> assign(index: index, graph: graph)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     def handle_input({:key, {:key_pageup, 1, mod}}, id, state) do
#       handle_input({:key, {:key_home, 1, mod}}, id, state)
#     end

#     def handle_input(
#           {:key, {:key_home, 1, _}},
#           _id,
#           %{assigns: %{index: index, value: value, graph: graph, caret_v: caret_v}} = scene
#         ) do
#       # move left. clamp to 0
#       {index, graph} =
#         case index do
#           0 ->
#             {index, graph}

#           _ ->
#             # reset the caret blinker
#             cast_children(scene, :reset_caret)

#             # move the caret
#             {0, update_caret(graph, value, 0, caret_v)}
#         end

#       scene =
#         scene
#         |> assign(index: index, graph: graph)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     def handle_input({:key, {:key_pagedown, 1, mod}}, id, scene) do
#       handle_input({:key, {:key_end, 1, mod}}, id, scene)
#     end

#     def handle_input(
#           {:key, {:key_end, 1, _}},
#           _id,
#           %{assigns: %{index: index, value: value, graph: graph, caret_v: caret_v}} = scene
#         ) do
#       # the max position for the caret
#       max_index = String.length(value)

#       # move left. clamp to 0
#       {index, graph} =
#         case index do
#           ^max_index ->
#             {index, graph}

#           _ ->
#             # reset the caret blinker
#             cast_children(scene, :reset_caret)

#             # move the caret
#             {max_index, update_caret(graph, value, max_index, caret_v)}
#         end

#       scene =
#         scene
#         |> assign(index: index, graph: graph)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     # ignore backspace if at index 0
#     def handle_input({:key, {:key_backspace, 1, _}}, _id, %{assigns: %{index: 0}} = scene),
#       do: {:noreply, scene}

#     # handle backspace
#     def handle_input(
#           {:key, {:key_backspace, 1, _}},
#           _id,
#           %{
#             assigns: %{
#               graph: graph,
#               value: value,
#               index: index,
#               type: type,
#               id: id,
#               caret_v: caret_v
#             }
#           } = scene
#         ) do
#       # reset_caret the caret blinker
#       cast_children(scene, :reset_caret)

#       # delete the char to the left of the index
#       value =
#         String.to_charlist(value)
#         |> List.delete_at(index - 1)
#         |> to_string()

#       display = display_from_value(value, type)

#       # send the value changed event
#       send_parent_event(scene, {:value_changed, id, value})

#       # move the index
#       index = index - 1

#       # update the graph
#       graph =
#         graph
#         |> update_text(display, scene.assigns)
#         |> update_caret(display, index, caret_v)

#       scene =
#         scene
#         |> assign(
#           graph: graph,
#           value: value,
#           display: display,
#           index: index
#         )
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     def handle_input(
#           {:key, {:key_delete, 1, _}},
#           _id,
#           %{
#             assigns: %{
#               graph: graph,
#               value: value,
#               index: index,
#               type: type,
#               id: id
#             }
#           } = scene
#         ) do
#       # ignore delete if at end of the field
#       case index < String.length(value) do
#         false ->
#           {:noreply, scene}

#         true ->
#           # reset the caret blinker
#           cast_children(scene, :reset_caret)

#           # delete the char at the index
#           value =
#             String.to_charlist(value)
#             |> List.delete_at(index)
#             |> to_string()

#           display = display_from_value(value, type)

#           # send the value changed event
#           send_parent_event(scene, {:value_changed, id, value})

#           # update the graph (the caret doesn't move)
#           graph = update_text(graph, display, scene.assigns)

#           scene =
#             scene
#             |> assign(
#               graph: graph,
#               value: value,
#               display: display,
#               index: index
#             )
#             |> push_graph(graph)

#           {:noreply, scene}
#       end
#     end

#     # --------------------------------------------------------
#     defp do_handle_codepoint(
#            char,
#            %{
#              assigns: %{
#                graph: graph,
#                value: value,
#                index: index,
#                type: type,
#                id: id,
#                caret_v: caret_v
#              }
#            } = scene
#          ) do
#       # reset the caret blinker
#       cast_children(scene, :reset_caret)

#       # insert the char into the string at the index location
#       {left, right} = String.split_at(value, index)
#       value = Enum.join([left, char, right])
#       display = display_from_value(value, type)

#       # send the value changed event
#       send_parent_event(scene, {:value_changed, id, value})

#       # advance the index
#       index = index + String.length(char)

#       # update the graph
#       graph =
#         graph
#         |> update_text(display, scene.assigns)
#         |> update_caret(display, index, caret_v)

#       scene =
#         scene
#         |> assign(
#           graph: graph,
#           value: value,
#           display: display,
#           index: index
#         )
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     @doc false
#     @impl Scenic.Scene
#     def handle_get(_, %{assigns: %{value: value}} = scene) do
#       {:reply, value, scene}
#     end

#     @doc false
#     @impl Scenic.Scene
#     def handle_put(v, %{assigns: %{value: value}} = scene) when v == value do
#       # no change
#       {:noreply, scene}
#     end

#     def handle_put(
#           text,
#           %{
#             assigns: %{
#               graph: graph,
#               id: id,
#               index: index,
#               caret_v: caret_v,
#               type: type
#             }
#           } = scene
#         )
#         when is_bitstring(text) do
#       send_parent_event(scene, {:value_changed, id, text})

#       display = display_from_value(text, type)

#       # if the index is beyond the end of the string, move it back into range
#       max_index = String.length(display)

#       index =
#         case index > max_index do
#           true -> max_index
#           false -> index
#         end

#       graph =
#         graph
#         |> update_text(display, scene.assigns)
#         |> update_caret(display, index, caret_v)

#       scene =
#         scene
#         |> assign(graph: graph, value: text)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     def handle_put(v, %{assigns: %{id: id}} = scene) do
#       Logger.warn(
#         "Attempted to put an invalid value on TextField id: #{inspect(id)}, value: #{inspect(v)}"
#       )

#       {:noreply, scene}
#     end

#     @doc false
#     @impl Scenic.Scene
#     def handle_fetch(_, %{assigns: %{value: value}} = scene) do
#       {:reply, {:ok, value}, scene}
#     end
#   end


