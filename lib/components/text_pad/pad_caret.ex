defmodule ScenicWidgets.TextPad.PadCaret do
  use Scenic.Component
  require Logger
  #     @moduledoc """
  #     Add a blinking text-input caret to a graph.
  #     ## Data
  #     `height`
  #     * `height` - The height of the caret. The caller (TextEdit) calculates this based
  #       on its :font_size (often the same thing).
  #     ## Options
  #     * `color` - any [valid color](Scenic.Primitive.Style.Paint.Color.html).
  #     You can change the color of the caret by setting the color option
  #     ```elixir
  #     Graph.build()
  #       |> caret( 20, color: :white )
  #     ```
  #     ## Usage
  #     The caret component is used by the TextField component and usually isn't accessed directly,
  #     although you are free to do so if it fits your needs. There is no short-cut helper
  #     function so you will need to add it to the graph manually.
  #     The following example adds a blue caret to a graph.
  #     ```elixir
  #     graph
  #       |> Caret.add_to_graph(24, id: :caret, color: :blue )
  #     ```
  #     """

  # how wide the cursor is
  @cursor_width 2
  @block_width 12

  # caret blink speed in hertz
  # @caret_hz 0.5
  # @caret_ms trunc(1000 / @caret_hz / 2)

  def validate(%{coords: _coords, height: _h, mode: _m} = data) do
    Logger.debug("#{__MODULE__} accepted params: #{inspect(data)}")
    {:ok, data}
  end

  # def validate(%{coords: num} = data) when is_integer(num) and num >= 0 do
  def validate(%{coords: _coords, height: _h} = data) do
    validate(data |> Map.merge(%{mode: :cursor})) # vim-insert mode by default
  end


  def init(scene, args, opts) do
    Logger.debug("#{__MODULE__} initializing...")

    # {line, col} = args.coords

    # NOTE: `color` is not an option for this PadCaret, even though it is in the Scenic.TextField.Caret component
    theme =
      (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
      |> Scenic.Primitive.Style.Theme.normalize()

    width = if args.mode == :block, do: @block_width, else: @cursor_width
    # width =
    #   if args.mode in @normal_modes do
    #     @cursor_width
    #   end

    init_graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.group(
        fn graph ->
          graph
          |> Scenic.Primitives.rect({width, args.height},
            id: :blinker,
            fill: theme.text
          )
        end,
        id: :blinker,
        translate: args.coords
      )

    #       graph =
    #         Graph.build()
    #         |> line(
    #           {{0, @inset_v}, {0, height - @inset_v}},
    #           stroke: {@width, color},
    #           hidden: true,
    #           id: :caret
    #         )

    init_scene =
      scene
      |> assign(graph: init_graph)
      # |> assign(frame: args.frame)
      |> assign(coords: args.coords)
      |> push_graph(init_graph)

    {:ok, init_scene}
  end

  def handle_cast({:move, 1} = msg, %{assigns: %{coords: {x_pos, y_pos} = coords}} = scene) do
    new_coords = {x_pos + 19, y_pos} #TODo get real char width lol
    new_graph = scene.assigns.graph
    |> Scenic.Graph.modify(:blinker, &Scenic.Primitives.update_opts(&1, translate: new_coords))

    new_scene = scene
    |> assign(graph: new_graph)
    |> assign(coords: new_coords)
    |> push_graph(new_graph)

    {:noreply, new_scene}
  end
end

#     import Scenic.Primitives,
#       only: [
#         {:line, 3},
#         {:update_opts, 2}
#       ]

#     alias Scenic.Graph
#     alias Scenic.Primitive.Style.Theme

#     @inset_v 4

#       # build the graph, initially not showing
#       # the height and the color are variable, which means it can't be
#       # built at compile time

#       scene =
#         scene
#         |> assign(
#           graph: graph,
#           hidden: true,
#           timer: nil,
#           focused: false
#         )
#         |> push_graph(graph)

#       {:ok, scene}
#     end

#     @impl Scenic.Component
#     def bounds(height, _opts) do
#       {0, 0, @width, height}
#     end

#     # --------------------------------------------------------
#     @doc false
#     @impl GenServer
#     def handle_cast(:start_caret, %{assigns: %{graph: graph, timer: nil}} = scene) do
#       # start the timer
#       {:ok, timer} = :timer.send_interval(@caret_ms, :blink)

#       # show the caret
#       graph = Graph.modify(graph, :caret, &update_opts(&1, hidden: false))

#       scene =
#         scene
#         |> assign(graph: graph, hidden: false, timer: timer, focused: true)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     def handle_cast(:stop_caret, %{assigns: %{graph: graph, timer: timer}} = scene) do
#       # hide the caret
#       graph = Graph.modify(graph, :caret, &update_opts(&1, hidden: true))

#       # stop the timer
#       case timer do
#         nil -> :ok
#         timer -> :timer.cancel(timer)
#       end

#       scene =
#         scene
#         |> assign(graph: graph, hidden: true, timer: nil, focused: false)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     def handle_cast(
#           :reset_caret,
#           %{assigns: %{graph: graph, timer: timer, focused: true}} = scene
#         ) do
#       # show the caret
#       graph = Graph.modify(graph, :caret, &update_opts(&1, hidden: false))

#       # stop the timer
#       if timer, do: :timer.cancel(timer)
#       # restart the timer
#       {:ok, timer} = :timer.send_interval(@caret_ms, :blink)

#       scene =
#         scene
#         |> assign(graph: graph, hidden: false, timer: timer)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end

#     # --------------------------------------------------------
#     # throw away unknown messages
#     # def handle_cast(_, scene), do: {:noreply, scene}

#     # --------------------------------------------------------
#     @doc false
#     @impl GenServer
#     def handle_info(:blink, %{assigns: %{graph: graph, hidden: hidden}} = scene) do
#       graph = Graph.modify(graph, :caret, &update_opts(&1, hidden: !hidden))

#       scene =
#         scene
#         |> assign(graph: graph, hidden: !hidden)
#         |> push_graph(graph)

#       {:noreply, scene}
#     end
#   end
