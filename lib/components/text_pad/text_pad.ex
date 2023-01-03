defmodule ScenicWidgets.TextPad do
   use Scenic.Component
   use ScenicWidgets.ScenicEventsDefinitions
   alias ScenicWidgets.Core.Structs.Frame
   alias ScenicWidgets.TextPad.Structs.Font
   require Logger

   @newline_char "\n"

   #TODO handle mutiple cursors

   defstruct [
      mode: nil,                 # affects how we render the cursor
      font: nil,                 # the font settings for this TextPad   
      lines: nil,                # hold the list of LineOfText structs
      margin: nil,               # how much margin we want to leave around the edges
      cursor: %{                 # maintains the cursor coords, note we just support single-cursor for now
         line: nil,
         col: nil
      },
      opts: %{
         alignment: :left,
         wrap: :no_wrap,
         scroll: %{
            direction: :all,
            acc: {0, 0}          # An accumulator for the amount of scroll
         },
         show_line_nums?: false  # toggles the display of line numbers in the left margin
      }
   ]


   defdelegate new(), to: ScenicWidgets.TextPad.Utils
   defdelegate new(args), to: ScenicWidgets.TextPad.Utils
   defdelegate backspace(lines_of_text, cursor, x, position), to: ScenicWidgets.TextPad.Utils


   def validate(%{frame: %Frame{} = _f, state: %__MODULE__{} = _s} = data)  do
      {:ok, data}
   end

   def init(scene, args, opts) do

      id = opts[:id] || raise "#{__MODULE__} must receive `id` via opts."

      init_theme = ScenicWidgets.Utils.Theme.get_theme(opts)

      init_graph = render(%{
         id: id,
         frame: args.frame,
         theme: init_theme,
         state: args.state
      })

      init_scene =
         scene
         |> assign(id: id)
         |> assign(theme: init_theme)
         |> assign(frame: args.frame)
         |> assign(state: args.state)
         |> assign(graph: init_graph)
         |> push_graph(init_graph)

      {:ok, init_scene}
   end

   #TODO handle_update, in such a way that we just go through init/3 again, but
   # without needing to spin up sub-processes.... eliminate all the extra handle_cast logic

   def handle_cast({:redraw, %{data: nil} = args}, scene) do
      lines = [""]
      GenServer.cast(self(), {:redraw, Map.put(args, :data, lines)})
      {:noreply, scene}
   end

   def handle_cast({:redraw, %{data: text} = args}, scene) when is_bitstring(text) do
      lines = String.split(text, @newline_char)
      GenServer.cast(self(), {:redraw, Map.put(args, :data, lines)})
      {:noreply, scene}
   end

   def handle_cast({:redraw, buffer}, scene) do

      new_graph =
         scene.assigns.graph
         |> scroll_text_area(scene, buffer)
         |> update_data(scene, buffer)
         |> update_cursor(scene, buffer)
      
      update_scroll_limits(scene, buffer)

      if new_graph == scene.assigns.graph do
         {:noreply, scene}
      else
         new_scene = scene
         |> assign(graph: new_graph)
         |> push_graph(new_graph)

         {:noreply, new_scene}
      end
   end

   def render(%{id: id, frame: frame, state: _s, theme: _t} = args) do
      Scenic.Graph.build()
      |> Scenic.Primitives.group(
         fn graph ->
            graph
            |> draw_background(args)
            |> draw_text_area(args)
            # |> draw_scrollbars(args)
         end,
         id: {__MODULE__, id},
         translate: frame.coords.point
      )
   end

   def draw_background(graph, %{frame: frame, theme: theme}) do
      graph
      |> Scenic.Primitives.rect(
         {frame.dimens.width, frame.dimens.height},
         id: :background,
         fill: theme.active,
         stroke: {2, theme.border},
         scissor: frame.dimens.box
      )
   end

   def draw_text_area(graph, %{id: id, frame: frame, state: state} = args) do
      graph
      |> Scenic.Primitives.group(
         fn graph ->
            graph
            |> draw_lines_of_text(args)
            |> draw_cursor(args)
         end,
         id: {__MODULE__, id, :text_area},
         translate: state.opts.scroll.acc
      )
   end

   def draw_lines_of_text(graph, %{frame: frame, state: %{lines: lines, font: font}} = args) do
      {_total_num_lines, final_graph} =
         1..Enum.count(lines)
         |> Enum.map_reduce(graph, fn line_num, graph ->
            new_graph =
               graph
               |> ScenicWidgets.TextPad.LineOfText.add_to_graph(%{
                  line_num: line_num,
                  name: random_string(),
                  font: font,
                  frame: calc_line_of_text_frame(frame, args.state, line_num),
                  text: Enum.at(lines, line_num-1),
                  theme: args.theme,
               }, id: {:line, line_num})
      
            {line_num+1, new_graph}
         end)
   
      final_graph
   end

   def draw_cursor(graph, %{state: %{mode: :read_only}}) do
      # no cursors in read-only mode...
      graph
   end

   def draw_cursor(graph, %{state: state}) do
      line_height = Font.line_height(state.font)

      graph
      |> ScenicWidgets.TextPad.CursorCaret.add_to_graph(%{
         margin: state.margin,
         coords: calc_cursor_caret_coords(state, line_height),
         height: line_height,
         font: state.font,
         mode: calc_cursor_mode(state.mode),
      }, id: {:cursor, 1})
   end

   def update_data(graph, scene, %{data: [l|_rest] = lines_of_text}) when is_bitstring(l) do

      final_graph =
         lines_of_text
         |> Enum.with_index(1)
         |> Enum.reduce(graph,
            fn({text, line_num}, acc_graph) ->

               case child(scene, {:line, line_num}) do
                  {:ok, [pid]} ->
                     GenServer.cast(pid, {:redraw, text})
                     acc_graph
                  {:ok, []} ->
                     # need to create a new LineOfText component...
                     acc_graph
                     |> Scenic.Graph.add_to({__MODULE__, scene.assigns.id, :text_area}, fn graph ->
                        graph
                        |> ScenicWidgets.TextPad.LineOfText.add_to_graph(%{
                        line_num: line_num,
                        name: random_string(),
                        font: scene.assigns.state.font,
                        frame: calc_line_of_text_frame(scene.assigns.frame, scene.assigns.state, line_num),
                        text: text,
                        theme: scene.assigns.theme,
                        }, id: {:line, line_num})
                     end)
               end
            end)

      final_graph
   end

   def update_cursor(graph, %{assigns: %{state: state}} = scene, %{data: lines, cursors: [cursor], mode: buffer_mode}) do

      line_of_text = Enum.at(lines, cursor.line-1)

      #TODO this might be more relevent when we get to wrapping...
      {x_pos, _cursor_line_num} =
         FontMetrics.position_at(line_of_text, cursor.col-1, state.font.size, state.font.metrics)

      new_cursor =
         {
            state.margin.left + x_pos,
            state.margin.top + ((cursor.line-1) * Font.line_height(state.font))
         }

      {:ok, [pid]} = child(scene, {:cursor, 1})
      GenServer.cast(pid, {:move, new_cursor})
      GenServer.cast(pid, {:set_mode, calc_cursor_mode(buffer_mode)})

      graph # unchanged...
   end

   def update_scroll_limits(scene, %{data: lines_of_text}) do
      
      # buffer height = number of lines of text * line_height
      h = length(lines_of_text) * Font.line_height(scene.assigns.state.font)

      line_widths =
         Enum.map(lines_of_text, fn line ->
            FontMetrics.width(line, scene.assigns.state.font.size, scene.assigns.state.font.metrics)
         end)

      cast_parent(scene, {:scroll_limits, %{
         inner: %{
         width: Enum.max(line_widths),
         height: h,
         },
         frame: scene.assigns.frame
      }})

      #TODO is this fast enough?? Will it pick up changes fast enough , since they are done asyncronously???
      # {left, _top, right, _bottom} =
      #   scene.assigns.graph
      #   |> Scenic.Graph.bounds()

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


   #TODO check scroll in the state against new scroll, maybe we can skip this if they haven't changed
   def scroll_text_area(graph, scene, buffer) do
      # first update the graph with any scroll updates
      #TODO cast to scroll bars... make them visible/not visible, adjust position & percentage shown aswell
      graph
      |> Scenic.Graph.modify(
         {__MODULE__, scene.assigns.id, :text_area},
         &Scenic.Primitives.update_opts(&1, translate: buffer.scroll_acc) #TODO check this
      )
   end

   def calc_cursor_mode({:vim, :normal}) do
      :block
   end

   def calc_cursor_mode(m) when m in [
      :edit,
      {:vim, :insert}
   ] do
      :cursor
   end

   def calc_cursor_caret_coords(state, line_height) when line_height >= 0 do
      line = Enum.at(state.lines, state.cursor.line-1)
      {x_pos, _line_num} =
         FontMetrics.position_at(line, state.cursor.col-1, state.font.size, state.font.metrics)
   
      {
         state.margin.left + x_pos,
         state.margin.top + ((state.cursor.line-1) * line_height)
      }
   end

   def calc_line_of_text_frame(frame, %{margin: margin, font: font}, line_num) do
      line_height = Font.line_height(font)
      y_offset = (line_num-1)*line_height # how far we need to move this line down, based on what line number it is
      Frame.new(%{
         pin: {margin.left, margin.top+y_offset},
         size: {frame.dimens.width, line_height}
      })
   end

   defp draw_scrollbars(graph, args) do
      raise "nop cant yet"

               # |> ScenicWidgets.TextPad.ScrollBar.add_to_graph(%{
         #       frame: horizontal_scroll_bar_frame(args.frame),
         #       orientation: :horizontal,
         #       position: 1
         # }, id: {:scrollbar, :horizontal}, hidden: true)
   end

#   def horizontal_scroll_bar_frame(outer_frame) do
#     bar_height = 20
#     bottom_left_corner = Frame.bottom_left(outer_frame)

#     #NOTE: Don't go all the way to the edges of the outer frame, we
#     # want to sit perfectly snug inside it
#     Frame.new(
#       pin: {bottom_left_corner.x+1, bottom_left_corner.y-bar_height-1},
#       size: {outer_frame.dimens.width-2, bar_height}
#     )
#   end


#   def calc_font_details(args) do
#     case Map.get(args, :font, :not_found) do
#       %{name: font_name, size: font_size, metrics: %FontMetrics{} = _fm} = provided_details
#       when is_atom(font_name) and is_integer(font_size) ->
#         provided_details

#       %{name: font_name, size: custom_font_size}
#       when is_atom(font_name) and is_integer(custom_font_size) ->
#         {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
#         %{name: font_name, metrics: custom_font_metrics, size: custom_font_size}

#       :not_found ->
#         {:ok, {_type, default_font_metrics}} = Scenic.Assets.Static.meta(@default_font)
#         %{name: @default_font, metrics: default_font_metrics, size: @default_font_size}

#       font_name when is_atom(font_name) ->
#         {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
#         %{name: font_name, metrics: custom_font_metrics, size: @default_font_size}
#     end
#   end

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
  #       {__MODULE__, scene.assigns.id, :text_area},
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

  #   {x_pos, _cursor_line_num} =
  #       FontMetrics.position_at(text, cursor.col-1, scene.assigns.state.font.size, scene.assigns.state.font.metrics)

  #   new_cursor =
  #     {
  #       (scene.assigns.state.margin.left + x_pos),
  #       (scene.assigns.state.margin.top + ((cursor.line-1) * line_height(scene.assigns)))
  #     }

  #   {:ok, [pid]} = child(scene, {:cursor, 1})
  #   GenServer.cast(pid, {:move, new_cursor})

  #   {:noreply, scene}
  # end



  # GenServer.cast(pid, {:redraw, %{data: active_buffer.data, cursor: hd(active_buffer.cursors)}})
  # GenServer.cast(pid, {:redraw, %{scroll_acc: active_buffer.scroll_acc}})
  # def handle_update(%{text: t, cursor: %Cursor{} = c, scroll_acc: s} = data, opts, scene) when is_bitstring(t) do

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
#     defp index_from_cursor({x, _}, value) do
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
#         case index_from_cursor(pos, value) do
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


