# defmodule Widgex.ScrollBars do
#   # defmacro __using__(_) do
#   #   quote do
#   @scrollbar_content_boxes [
#     {:widgex_component, __MODULE__, :scrollbar_x_content_box},
#     {:widgex_component, __MODULE__, :scrollbar_y_content_box}
#   ]
#   def handle_input(
#         {:cursor_pos, {_x, _y} = cursor_coords},
#         scroll_box,
#         %{assigns: %{scrollbar_clicked?: true}} = scene
#       )
#       when scroll_box in @scrollbar_content_boxes do
#     IO.puts("DRAGN")

#     # flip order of subtraction to account for backwards way coords works
#     scroll_delta = Scenic.Math.Vector2.sub(scene.assigns.scrollbar_click_coords, cursor_coords)

#     # TODO need to figure out what % of movement through the textbox this delta scroll is & adjust

#     ii = {:cursor_scroll, {scroll_delta, cursor_coords}}

#     QuillEx.Fluxus.user_input(%{input: ii, component_id: scene.assigns.state.widgex.id})

#     new_scene =
#       scene
#       |> assign(scrollbar_click_coords: cursor_coords)

#     {:noreply, new_scene}
#   end

#   def handle_input(
#         {:cursor_pos, {_x, _y} = coords},
#         scroll_box,
#         scene
#       )
#       when scroll_box in @scrollbar_content_boxes do
#     # [
#     #   %Scenic.Primitive{data: box_size}
#     # ] = Scenic.Graph.get(scene.assigns.graph, scroll_box)

#     # IO.inspect(primitive)

#     # Graph.modify(graph, :rect, fn(p) ->
#     #   update_opts(p, rotate: 0.5)
#     # end)

#     # we capture cursor pos so that all cursor_pos input gets routed
#     # to this component, so that when we leave the bounds of this component,
#     # we know that we've left (and thus to change the background color back to normal,
#     # not to mention releasing the cursor_pos input)
#     :ok = capture_input(scene, [:cursor_pos, :cursor_button])

#     {r, g, b} = scene.assigns.state.widgex.theme.accent2

#     new_graph =
#       scene.assigns.graph
#       |> Scenic.Graph.modify(
#         scroll_box,
#         &Scenic.Primitives.update_opts(&1, fill: {r, g, b, @scroll_box_whilst_hovered_opacity})
#       )

#     new_scene =
#       scene
#       # |> assign(state: new_state)
#       |> assign(graph: new_graph)
#       |> push_graph(new_graph)

#     {:noreply, new_scene}
#   end

#   def handle_input(
#         {:cursor_pos, {_x, _y} = _coords},
#         _any_other_component,
#         scene
#       ) do
#     # if we get in here then we're capturing cursor_pos input but
#     # we're not hovering over the scroll bar box, so we need to release it
#     :ok = release_input(scene)

#     {r, g, b} = scene.assigns.state.widgex.theme.accent2

#     new_graph =
#       Enum.reduce(
#         @scrollbar_content_boxes,
#         scene.assigns.graph,
#         fn scroll_box, graph ->
#           graph
#           |> Scenic.Graph.modify(
#             scroll_box,
#             &Scenic.Primitives.update_opts(&1, fill: {r, g, b, @scroll_box_no_hover_opacity})
#           )
#         end
#       )

#     new_scene =
#       scene
#       # |> assign(state: new_state)
#       |> assign(scrollbar_clicked?: false)
#       |> assign(graph: new_graph)
#       |> push_graph(new_graph)

#     {:noreply, new_scene}
#   end

#   # def handle_input({:cursor_pos, {_x, _y} = coords}, _context, scene) do
#   #   IO.puts("HOVER COORDS: #{inspect(coords)}")
#   #   # NOTE: `menu_bar_max_height` is the full height, including any
#   #   #       currently rendered sub-menus. As new sub-menus of different
#   #   #       lengths get rendered, this max-height will change.
#   #   #
#   #   #       menu_bar_max_height = @height + num_sub_menu*@sub_menu_height
#   #   # {_x, _y, _viewport_width, menu_bar_max_height} = Scenic.Graph.bounds(scene.assigns.graph)

#   #   # if y > menu_bar_max_height do
#   #   #   GenServer.cast(self(), {:cancel, scene.assigns.state.mode})
#   #   #   {:noreply, scene}
#   #   # else
#   #   #   # TODO here check if we veered of sideways in a sub-menu
#   #   #   {:noreply, scene}
#   #   # end

#   #   {:noreply, scene}
#   # end

#   def handle_input(
#         {:cursor_button, {:btn_left, @clicked, [], click_coords}},
#         scroll_box,
#         scene
#       )
#       when scroll_box in @scrollbar_content_boxes do
#     IO.puts("CLICKCKCK }")
#     # bounds = Scenic.Graph.bounds(scene.assigns.graph)

#     # if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
#     #   cast_parent(scene, {:click, scene.assigns.state.unique_id})
#     # end

#     new_scene = scene |> assign(scrollbar_clicked?: true, scrollbar_click_coords: click_coords)

#     {:noreply, new_scene}
#   end

#   def handle_input(
#         {:cursor_button, {:btn_left, @release_click, [], _click_coords}},
#         scroll_box,
#         scene
#       )
#       when scroll_box in @scrollbar_content_boxes do
#     IO.puts("Unnnnnn CLICKCKCK }")

#     {:noreply, scene |> assign(scrollbar_clicked?: false)}
#   end

#   def handle_input(
#         {:cursor_button, _click_details},
#         scroll_box,
#         scene
#       )
#       when scroll_box in @scrollbar_content_boxes do
#     IO.puts("IGNLIGL }")
#     # bounds = Scenic.Graph.bounds(scene.assigns.graph)

#     # if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
#     #   cast_parent(scene, {:click, scene.assigns.state.unique_id})
#     # end

#     {:noreply, scene |> assign(scrollbar_clicked?: false)}
#   end

#   #   end
#   # end

#   def render(graph, state, frame, opts) do
#     IO.puts("RENERNERNERNERNER")

#     case Keyword.get(opts, :scrollable) do
#       :all_axis ->
#         IO.puts("HIHIHIHIHIH")

#         graph
#         |> render_scrollbar_x(state, frame, opts)
#         |> render_scrollbar_y(state, frame, opts)

#       _otherwise ->
#         IO.puts("OTHERWISE")
#         IO.inspect(opts)
#         graph
#     end
#   end

#   @scrollbar_size 20
#   @scrollbar_bg_opacity @fifteen_percent_opaque
#   @scroll_box_no_hover_opacity @thirty_percent_opaque
#   @scroll_box_whilst_hovered_opacity @sixty_percent_opaque
#   defp render_scrollbar_x(graph, state, frame, opts) do
#     {left, top, right, bottom} = Scenic.Graph.bounds(graph)
#     unscissored_width = right - left

#     if unscissored_width > frame.size.width do
#       # if we are going to render a vertical scrollbar we need to make room for it
#       unscissored_height = bottom - top

#       full_scrollbar_width =
#         if unscissored_height > frame.size.height do
#           frame.size.width - @scrollbar_size
#         else
#           frame.size.width
#         end

#       {scroll_x, _scroll_y} = state.scroll

#       content_box_scroll_offset =
#         frame.size.width * (-1 * scroll_x / (unscissored_width - frame.size.width))

#       content_box_width = frame.size.width * (frame.size.width / unscissored_width)

#       {r, g, b} = state.widgex.theme.accent2

#       graph
#       |> Scenic.Primitives.group(
#         fn graph ->
#           graph
#           |> Scenic.Primitives.rect({full_scrollbar_width, @scrollbar_size},
#             fill: {r, g, b, @scrollbar_bg_opacity}
#           )
#           |> Scenic.Primitives.rect({content_box_width, @scrollbar_size},
#             id: {:widgex_component, state.widgex.id, :scrollbar_x_content_box},
#             fill: {r, g, b, @scroll_box_no_hover_opacity},
#             translate: {content_box_scroll_offset, 0},
#             input: [:cursor_pos]
#           )
#         end,
#         id: {:widgex_component, state.widgex.id, :scrollbar_x},
#         translate: {0, frame.size.height - @scrollbar_size}
#       )
#     else
#       # no need to render an x scrollbar...
#       graph
#     end
#   end

#   defp render_scrollbar_y(graph, state, frame, opts) do
#     {_left, top, _right, bottom} = Scenic.Graph.bounds(graph)
#     unscissored_height = bottom - top

#     if unscissored_height > frame.size.height do
#       # to calculate the size of the "content box" on the scrollbar,
#       # we need to know what % of the underlying content is visible
#       # inside the current Frame - this is x% of the content, so
#       # we need to make the content box x% of the scrollbar size
#       {_scroll_x, scroll_y} = state.scroll

#       content_box_scroll_offset =
#         frame.size.height * (-1 * scroll_y / (unscissored_height - frame.size.height))

#       content_box_height = frame.size.height * (frame.size.height / unscissored_height)

#       {r, g, b} = state.widgex.theme.accent2

#       graph
#       |> Scenic.Primitives.group(
#         fn graph ->
#           graph
#           |> Scenic.Primitives.rect({@scrollbar_size, frame.size.height},
#             fill: {r, g, b, @scrollbar_bg_opacity}
#           )
#           |> Scenic.Primitives.rect({@scrollbar_size, content_box_height},
#             id: {:widgex_component, state.widgex.id, :scrollbar_y_content_box},
#             fill: {r, g, b, @scroll_box_no_hover_opacity},
#             translate: {0, content_box_scroll_offset},
#             input: [:cursor_pos]
#           )
#         end,
#         id: {:widgex_component, state.widgex.id, :scrollbar_y},
#         translate: {frame.size.width - @scrollbar_size, 0}
#       )
#     else
#       # no need to render a y scrollbar...
#       graph
#     end
#   end
# end
