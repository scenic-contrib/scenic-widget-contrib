# defmodule ScenicWidgets.TabSelector.Painter do
#     @defmodule """
#     A module to store functions which render %Scenic.Graph{}s
#     """
#     alias ScenicWidgets.TabSelector.SingleTab

#     @tab_margin 10

#     def render(init_graph, %{
#         frame: frame,
#         theme: theme,
#         tab_list: tab_list,
#         active: active_tab,
#         font: %{size: _sz, metrics: _fm} = font,
#         menu_item: %{width: _miw} = menu_item, #TODO - allow tabs to be flexible width & grow to be as wide as their label
#     }) when length(tab_list) >= 2 do

#         render_tabs = fn(init_graph) ->
#             {final_graph, _final_offset} = 
#                 tab_list
#                 |> Enum.with_index()
#                 |> Enum.reduce({init_graph, _init_offset = 0}, fn {label, index}, {graph, offset} ->
#                         label_width = menu_item.width
#                         item_width  = label_width+@tab_margin
#                         carry_graph = graph
#                         |> SingleTab.add_to_graph(%{
#                                 label: label,
#                                 ref: label,
#                                 active?: label == active_tab,
#                                 margin: @tab_margin,
#                                 font: %{
#                                     size: font.size,
#                                     ascent: FontMetrics.ascent(font.size, font.metrics),
#                                     descent: FontMetrics.descent(font.size, font.metrics),
#                                     metrics: font.metrics
#                                 },
#                                 frame: %{
#                                     pin: {offset, 0}, #REMINDER: coords are like this, {x_coord, y_coord}
#                                     size: {item_width, frame.dimensions.height}
#                                 }}) 
#                         {carry_graph, offset+item_width}
#                 end)

#             final_graph
#         end

#         new_graph = init_graph
#         |> Scenic.Primitives.group(fn graph ->
#             graph
#             |> Scenic.Primitives.rect({frame.dimensions.width, 40}, fill: theme.background)
#             |> render_tabs.()
#           end, [
#              id: :tab_selector
#           ])

#         # finally, return `new_graph`
#         new_graph
#     end

# end