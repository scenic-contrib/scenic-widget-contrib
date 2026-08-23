# defmodule QuillEx.GUI.Components.PlainTextScrollable do
#   use Widgex.Component, scrollable: :all_axis

#   defstruct widgex: nil,
#             scenic: nil,
#             text: "",
#             scroll: {0, 0}

#   def new(rdx_state, text) when is_binary(text) do
#     %__MODULE__{
#       widgex: %Widgex.Component.Widget{
#         id: __MODULE__,
#         # frame: %Frame{},
#         theme: rdx_state.theme
#         # layout: %Widgex.Layout{},
#       },
#       scenic: %{
#         # hidden - show or hide the primitive
#         # fill - fill in the area of the text. Only solid colors!
#         # font - name (or key) of font to use
#         # font_size - point size of the font
#         font_size: 24
#         # font_blur - option to blur the characters
#         # text_align - alignment of lines of text
#         # text_height - spacing between lines of text
#       },
#       text: text,
#       scroll: {0, 0}
#       # file_bar: %{
#       #   show?: true,
#       #   filename: nil
#       # }
#     }
#   end

#   # the idea here is that if we end up embedding this state inside a %Widgex.Component{}, instead of what we
#   # are doing now (which is the reverse, each component contains a %Widget{}), then this functioin will
#   # return the state of this component only
#   # def cast(_args) do
#   #   %__MODULE__{}
#   # end

#   # def radix_cast(radix_state, {:scroll, input}) do

#   # end

#   def radix_diff(%__MODULE__{} = old_state, new_rdx) do
#     # old_component = Enum.find(old_rdx.components, &(&1.widgex.id == __MODULE__))
#     new_state = Enum.find(new_rdx.components, &(&1.widgex.id == __MODULE__))

#     # in our case it will alway sbe the same because the UBuntuBar never changes...
#     # new_state = draw()

#     # IO.puts("DIF DIF DIF SCROLLABLE")

#     if old_state == new_state do
#       {false, old_state}
#     else
#       IO.puts("Scrollable DIFF DIFF DIFF")
#       {true, new_state}
#     end
#   end

#   def render(%Scenic.Graph{} = graph, %__MODULE__{} = s, %Frame{} = f) do
#     graph
#     |> paint_background(s, f)
#     |> draw_text(s, f)
#   end

#   def paint_background(graph, state, frame) do
#     graph |> fill_frame(frame, fill: state.widgex.theme.bg, input: [:cursor_scroll])
#   end

#   def draw_text(graph, state, frame) do
#     # all text needs to be translated by the left margin and the font size just to render normally
#     text_pin = {@left_margin, state.scenic.font_size}
#     # then the actual pin we use to translate takes the scroll into account
#     pin = Scenic.Math.Vector2.add(text_pin, state.scroll)

#     graph
#     |> Scenic.Primitives.text(state.text,
#       translate: pin,
#       fill: state.widgex.theme.fg
#     )
#   end

#   def handle_input({:cursor_scroll, {_scroll_delta, _cursor_coords}} = ii, context, scene) do
#     # TODO this action name/details is temporary but I'm just establishing the link
#     # QuillEx.Fluxus.user_input({:scroll, {input, scene.assigns.state.widgex.id}})
#     QuillEx.Fluxus.user_input(%{input: ii, component_id: scene.assigns.state.widgex.id})
#     {:noreply, scene}
#   end

#   def handle_user_input(
#         %{lateral: false} = _radix_state,
#         %__MODULE__{} = _state,
#         {:cursor_scroll, {{_delta_x, delta_y} = delta_scroll, _coords_i_think_are_global?}}
#       ) do
#     # new_scroll = Scenic.Math.Vector2.add(state.scroll, {5 * delta_x, 5 * delta_y})
#     # %{state | scroll: new_scroll}
#     {:action, {:scroll, delta_scroll}}
#   end

#   def handle_user_input(
#         %{lateral: true} = _radix_state,
#         %__MODULE__{} = _state,
#         {:cursor_scroll, {{_delta_x, delta_y} = delta_scroll, _coords_i_think_are_global?}}
#       ) do
#     # new_scroll = Scenic.Math.Vector2.add(state.scroll, {5 * delta_x, 5 * delta_y})
#     # %{state | scroll: new_scroll}
#     # reverse scrolling!!
#     {:action, {:scroll, {delta_y, 0}}}
#   end

#   @fast_scroll_factor 7
#   def handle_action(
#         %__MODULE__{} = state,
#         {:action, {:scroll, {delta_x, delta_y}}}
#       ) do

#     new_scroll =
#       Scenic.Math.Vector2.add(
#         state.scroll,
#         {@fast_scroll_factor * delta_x, @fast_scroll_factor * delta_y}
#       )
#       |> cap_scroll_position()

#     %{state | scroll: new_scroll}
#   end

#   # <3 @vacarsu
#   def cap_scroll_position(scroll) do
#     # The most complex idea here is that to scroll to the right, we
#     # need to translate the text to the _left_, which means applying
#     # a negative translation, and visa-versa for vertical scroll - so
#     # to prevent us from scrolling too far "backward" we can't let the
#     # scroll value be greater than 0, and to prevent us from scrolling
#     # too far forward we can't let it be less than the absolute magnitude
#     # of the size of the underlying pane
#     scroll
#     |> calc_floor({0, 0})
#     |> calc_ceil({100, 100})
#   end

#   defp calc_floor({x, y}, {max_x, max_y}), do: {min(x, max_x), min(y, max_y)}

#   defp calc_ceil({x, y}, {max_x, max_y}), do: {min(x, max_x), min(y, max_y)}
# end

#   # def cap_position(%{assigns: %{frame: frame}} = scene, coord) do
#   #    # NOTE: We must keep track of components, because one could
#   #    #      get yanked out the middle.
#   #    height = calc_acc_height(scene)
#   #    # height = scene.assigns.state.scroll.acc_length
#   #    if height > frame.dimensions.height do
#   #       coord
#   #       |> calc_floor({0, -height + frame.dimensions.height / 2})
#   #       |> calc_ceil({0, 0})
#   #    else
#   #       coord
#   #       |> calc_floor(@min_position_cap)
#   #       |> calc_ceil(@min_position_cap)
#   #    end
#   # end

#   # defp calc_floor({x, y}, {min_x, min_y}), do: {max(x, min_x), max(y, min_y)}

# # defmodule QuillEx.GUI.Components.PlainTextScrollable do
# #   # this module renders text inside a frame, but it *can* be scrolled, though it0er] has no rich-text or "smart" display, e.g. it can't handle tabs
# #   use Scenic.Component
# #   alias Widgex.Structs.{Coordinates, Dimensions, Frame}

# #   # Define the struct for PlainText
# #   # We could have 2 structs, one which is the state, and one which is the component
# #   # instead of defstruct macro, use like defwidget or defcomponent
# #   defstruct id: nil,
# #             text: nil,
# #             theme: nil,
# #             scroll: {0, 0},
# #             file_bar: %{
# #               show?: true,
# #               filename: nil
# #             }

# #   # Validate function to ensure proper parameters are being passed.
# #   def validate({%__MODULE__{text: text} = state, %Frame{} = frame})
# #       when is_binary(text) do
# #     {:ok, {state, frame}}
# #   end

# #   def new(%{text: t}) when is_binary(t) do
# #     raise "woopsey"
# #     %__MODULE__{text: t}
# #   end

# #   def draw(text) when is_binary(text) do
# #     %__MODULE__{
# #       id: :plaintext,
# #       text: text,
# #       theme: QuillEx.GUI.Themes.midnight_shadow()
# #     }
# #   end

# #   def init(scene, {%__MODULE__{} = state, %Frame{} = frame}, _opts) do
# #     init_graph = render(state, frame)
# #     init_scene = scene |> assign(graph: init_graph) |> push_graph(init_graph)

# #     # request_input(init_scene, [:cursor_scroll])

# #     {:ok, init_scene}
# #   end

# #   # def handle_info(:redraw, scene) do
# #   #   new_graph = render(%{text: scene.assigns.text, frame: scene.assigns.frame})

# #   #   new_scene = scene |> assign(graph: new_graph) |> push_graph(new_graph)
# #   #   {:noreply, new_scene}
# #   # end

# #   # This is the left-hand margin, text-editors just look better with a bit of left margin
# #   @left_margin 5

# #   # Scenic uses this text size by default, we need to use it to apply translations
# #   @default_text_size 24

# #   # TODO apply scissor
# #   def render(%__MODULE__{text: text} = state, %Frame{} = frame) when is_binary(text) do
# #     text_box_sub_frame = Dimensions.box(frame.size)

# #     Scenic.Graph.build(font: :ibm_plex_mono)
# #     |> Scenic.Primitives.group(
# #       fn graph ->
# #         graph
# #         |> render_background(state, frame)
# #         |> Scenic.Primitives.text(text,
# #           translate: {@left_margin, @default_text_size},
# #           fill: state.theme.text
# #         )
# #       end,
# #       id: __MODULE__,
# #       scissor: Dimensions.box(frame.size),
# #       translate: Coordinates.point(frame.pin)
# #     )
# #   end

# #   def render_background(
# #         %Scenic.Graph{} = graph,
# #         %__MODULE__{} = state,
# #         %Frame{size: f_size}
# #       ) do
# #     graph
# #     |> Scenic.Primitives.rect(Dimensions.box(f_size),
# #       # fill: state.theme.background,
# #       # fill: :red,
# #       opacity: 0.5,
# #       input: :cursor_scroll
# #     )
# #   end

# #   # def render_background(
# #   #       %Scenic.Graph{} = graph,
# #   #       _state,
# #   #       %Frame{size: f_size}
# #   #     ) do
# #   #   graph
# #   #   |> Scenic.Primitives.rect(Dimensions.box(f_size),
# #   #     opacity: 0.5,
# #   #     input: :cursor_scroll
# #   #   )
# #   # end

# #   def handle_input(
# #         {:cursor_scroll, {{_x_scroll, y_scroll} = delta_scroll, coords}},
# #         _context,
# #         scene
# #       ) do
# #     # Logger.debug("SCROLLING: #{inspect(delta_scroll)}")
# #     # IO.puts("YES YES YES #{inspect(delta_scroll)}")
# #     {:noreply, scene}
# #   end
# # end
