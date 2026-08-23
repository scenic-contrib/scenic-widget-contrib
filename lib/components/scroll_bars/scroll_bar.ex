# defmodule ScenicWidgets.TextPad.ScrollBar do
#     use Scenic.Component
#     alias ScenicWidgets.Core.Structs.Frame
#     require Logger

#     @valid_orientations [:horizontal, :vertical]

#     def validate(%{frame: %Frame{} = _frame, orientation: o, position: _pos} = data) when o in @valid_orientations do
#       # Logger.debug("#{__MODULE__} accepted params: #{inspect(data)}")
#       {:ok, data}
#     end

#     def init(scene, args, opts) do
#       # Logger.debug("#{__MODULE__} initializing...")

#       theme =
#         (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
#         |> Scenic.Primitive.Style.Theme.normalize()

#       init_graph =
#         Scenic.Graph.build()
#         |> Scenic.Primitives.group(
#           fn graph ->
#             graph
#             |> Scenic.Primitives.rect(args.frame.size,
#               id: :background,
#               fill: theme.active
#             )
#             |> Scenic.Primitives.rect(args.frame.size,
#               id: :scroller,
#               fill: theme.border,
#               hidden: true
#             )
#           end,
#           translate: args.frame.pin
#         )

#       init_scene =
#         scene
#         |> assign(frame: args.frame)
#         |> assign(graph: init_graph)
#         |> push_graph(init_graph)

#       {:ok, init_scene}
#     end

#     def handle_cast({:scroll_percentage, :horizontal, percentage}, scene) when percentage >= 1 do

#       new_graph = scene.assigns.graph
#       |> Scenic.Graph.modify(:scroller, &Scenic.Primitives.rectangle(&1, scene.assigns.frame.size))
#       |> Scenic.Graph.modify(:scroller, &Scenic.Primitives.update_opts(&1, hidden: true))

#       new_scene =
#           scene
#           |> assign(graph: new_graph)
#           |> push_graph(new_graph)

#       {:noreply, new_scene}
#     end

#     def handle_cast({:scroll_percentage, :horizontal, percentage}, scene) do
#         IO.puts "GOT PERCENTAGE #{inspect percentage}"

#         h = scene.assigns.frame.dimens.height
#         w = percentage * scene.assigns.frame.dimens.width

#         new_graph = scene.assigns.graph
#         |> Scenic.Graph.modify(:scroller, &Scenic.Primitives.rectangle(&1, {w, h}))
#         |> Scenic.Graph.modify(:scroller, &Scenic.Primitives.update_opts(&1, hidden: false))

#         new_scene =
#             scene
#             |> assign(graph: new_graph)
#             |> push_graph(new_graph)

#         {:noreply, new_scene}
#     end
# end
