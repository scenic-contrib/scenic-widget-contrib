defmodule ScenicWidgets.TextPad do
  use Scenic.Component
  require Logger
  use ScenicWidgets.ScenicEventsDefinitions
  alias ScenicWidgets.TextPad.{ToolBag, Painter}


      # Scroll wrapping - for this, I can go ahead with existing text (which wraps),
    # but treat it as larger than another container. However, ultimately
    # I want to be able to disable the scroll-wrapping talked about above,
    # so that I can render  continuous line, & potentially scroll it

    
    # Other unimplemented cases: Max 1 line height (e.g. KommandBuffer)

  def validate(
        %{
          id: _id,
          frame: %ScenicWidgets.Core.Structs.Frame{} = _frame,
          text: text,
          mode: mode,
          format_opts: %{
            alignment: :left,
            wrap_opts: wrap_opts, #TODO this is what I'm working on, making it line-wrap
            show_line_num?: show_line_num? #TODO this too
          },
          font: %{
            name: _name,
            size: _size,
            metrics: %FontMetrics{} = _fm
          }
        } = args
      )
      when is_bitstring(text)
      and mode in [:read_only, :edit]
      and is_boolean(show_line_num?)
    do
      Logger.debug("#{__MODULE__} accepted args: #{inspect(args)}")
      # Cursor 1, 1st column, 1st line
      final_args = args
      # |> Map.merge(%{cursors: [{1, %{col: 1, line: 1}}]})
      |> Map.merge(%{cursor_pos: 0})
      |> Map.merge(%{margin: %{left: 5, top: 0, bottom: 0, right: 5}})
      
      {:ok, final_args}
  end

  def init(scene, args, opts) do
    Logger.debug("#{__MODULE__} initializing...")
    theme = ScenicWidgets.Utils.Theme.get_theme(opts)
    %{ascent: ascent, descent: descent} = ToolBag.calc_ascent_descent(args.font)
    

    # NOTE: This only works for one cursor, for now...
    # [{1, %{col: _col, line: line}}] = args.cursors

    # # NOTE: This *must* be wrong, because it ought to be some multiple of 14.4 (or whatever 1 char width is)
    # {x_pos, line_num} =
    #   FontMetrics.position_at(args.text, {col, line}, args.font.size, args.font.metrics)

    # current_line = args.text |> String.split("\n") |> Enum.at(line_num)

    # TODO ok so the puzzle right now seems to be - I can get the width of 1 char using FontMetrics.width,
    #       and since I'm using a monospce font, that means thats 1 char width. It's a hack but...
    #       even so, I cant get the line hgiehght - maybe FontMetrics is lcking

    
    # {x_min, y_min, x_max, y_max} = FontMetrics.max_box(args.font.size, args.font.metrics)


    # text_height = ascent-descnt
    # text_height = 31.0
    # text_height = 30.0 #NOTE - got this by truncing ascent & descent -> 24-(-6)=30
    # NOTE - got this by truncing ascent & descent -> 24-(-6)=30
    text_height = 29.0
    # mayyy = -1 * y_min + y_max
    # maxxx = -1 * x_min + x_max
    # IO.inspect(text_height, label: "textHeight")
    # IO.inspect(mayyy, label: "mayyy")
    # IO.inspect(maxxx, label: "maxxx")
    # IO.inspect(x_max, label: "XMX")

    # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
    # vpos = ascent / 2 + descnt / 3
    # IO.inspect(vpos, label: "VPOS")

    # TODO this is something I need to be able to get *exactly*
    # line_height = text_height

    {frame_width, frame_height} = args.frame.size

    init_graph = Painter.render_text_pad(args |> Map.merge(%{theme: theme}))

    init_scene =
      scene
      |> assign(id: args.id)
      |> assign(text: args.text)
      |> assign(mode: args.mode)
      |> assign(format_opts: args.format_opts)
      |> assign(font: args.font)
      |> assign(frame: args.frame)
      |> assign(graph: init_graph)
      |> push_graph(init_graph)

    request_input(init_scene, [:key])

    {:ok, init_scene}
  end

  

  #TODO just forward all input up to StoryRiver, which wil then forward it all over to the event bus (InputListener)
  def handle_input(input, _context, scene) when input in @arrow_keys do
    IO.puts "ARROW"
    {:noreply, scene}
  end

  def handle_input(input, _context, scene) when input in @valid_text_input_characters do
    Logger.debug "#{__MODULE__} recv'd input: #{inspect input}"

    new_text = scene.assigns.text <> key2string(input)
    send_parent_event(scene, {:value_changed, scene.assigns.id, new_text})

    {:noreply, scene}
  end

  def handle_input(input, _context, scene) do
    Logger.debug "#{__MODULE__} ignoring some input: #{inspect input}"
    {:noreply, scene}
  end

end


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
