defmodule ScenicWidgets.TextPad.CursorCaret do
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

  @valid_modes [:cursor, :block]
  # @block_modes [:block, :normal] # these cursors render as a block

  # caret blink speed in hertz
  # @caret_hz 0.5
  # @caret_ms trunc(1000 / @caret_hz / 2)

  def validate(%{coords: _coords, height: _h, mode: m} = data) when m in @valid_modes do
    #Logger.debug("#{__MODULE__} accepted params: #{inspect(data)}")
    {:ok, data}
  end

  # def validate(%{coords: num} = data) when is_integer(num) and num >= 0 do
  def validate(%{coords: _coords, height: _h, margin: margin} = data) do
    Logger.warn "Using a validate path in Cursor which should be DEPRECATED"
    # vim-insert mode by default
    validate(data |> Map.merge(%{mode: :cursor, margin: margin}))
  end

  def init(scene, args, opts) do
    #Logger.debug("#{__MODULE__} initializing...")

    # NOTE: `color` is not an option for this CursorCaret, even though it is in the Scenic.TextField.Caret component
    theme =
      (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
      |> Scenic.Primitive.Style.Theme.normalize()

    {x_pos, y_pos} = args.coords

    init_graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.group(
        fn graph ->
          graph
          |> Scenic.Primitives.rect({calc_width(args.mode, args.font), args.height},
            id: :blinker,
            fill: theme.text
          )
        end,
        id: :cursor,
        translate: {x_pos, y_pos+2} #TODO I like this a little better, moving the cursor down 2
      )

    init_scene =
      scene
      |> assign(graph: init_graph)
      |> assign(args: args) # TODO lol
      |> assign(theme: theme)
      |> push_graph(init_graph)

    {:ok, init_scene}
  end

  def handle_cast({:move, {x_pos, y_pos} = _new_coords}, scene) do

    new_graph = scene.assigns.graph
    |> Scenic.Graph.modify(:cursor, &Scenic.Primitives.update_opts(&1, translate: {x_pos, y_pos+2})) #TODO I like this a little better, moving the cursor down 2

    new_scene = scene
    |> assign(graph: new_graph)
    |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast({:set_mode, new_mode}, scene) do

    new_graph = scene.assigns.graph
    |> Scenic.Graph.modify(:blinker, &Scenic.Primitives.rectangle(&1,
        {
          calc_width(new_mode, scene.assigns.args.font),
          scene.assigns.args.height
        }
    ))

    new_scene = scene
    |> assign(graph: new_graph)
    |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def calc_width(:cursor, _font), do: @cursor_width
  def calc_width(:block, font) do
    #TODO this isn't gonna work for block fonts... but then again, what is???
    FontMetrics.width("#", font.size, font.metrics)
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

















# defmodule Flamelex.GUI.Component.TextCursor do
#   @moduledoc """
#   Cursor is the blinky thing on screen that shows the user
#   a) "where" we are in the file
#   b) what mode we're in (by either blinking as a block, or being a straight line)
#   """
#   use Flamelex.ProjectAliases
#   # use Flamelex.GUI.ComponentBehaviour
#   use Scenic.Component
#   use Flamelex.ProjectAliases
#       require Logger
#   alias Flamelex.GUI.Component.Utils.TextCursor, as: CursorUtils


#   @blink_ms trunc(500) # blink speed in hertz

#   @valid_directions [:up, :down, :left, :right]

#   # def redraw() do
#   #   ProcessRegistry.find!({:cursor, n, {:gui_component, state.rego_tag}})
#   #   |> GenServer.cast({:reposition, new_cursor}) #TODO change this to update
#   # end

#   def validate(data) do
#     {:ok, data}
#   end

#   def init(scene, params, opts) do

#     params = custom_init_logic(params)
#     ProcessRegistry.register(rego_tag(params))
#     # Process.register(self(), __MODULE__)
#     # Flamelex.GUI.ScenicInitialize.load_custom_fonts_into_global_cache()

#     #NOTE: `Flamelex.GUI.Controller` will boot next & take control of
#     #      the scene, so we just need to initialize it with *something*
#     new_graph = 
#       render(params.frame, params)


#       # new_graph = 
#       # Scenic.Graph.build()
#       # |> Scenic.Primitives.rect({80, 80}, fill: :white,  translate: {100, 100})
#     new_scene =
#       scene
#       |> assign(graph: new_graph)
#       |> assign(params: params)
#       |> push_graph(new_graph)

#     {:ok, new_scene}
#   end

#   @impl Flamelex.GUI.ComponentBehaviour
#   def custom_init_logic(%{num: _n} = params) do # buffers need to keep track of cursors somehow, so we just use simple numbering

#     GenServer.cast(self(), :start_blink)

#     Flamelex.Utils.PubSub.subscribe(topic: :gui_update_bus)

#     starting_coords = CursorUtils.calc_starting_coordinates(params.frame)

#     mode = if params.mode == :insert, do: :insert, else: :normal

#     params |> Map.merge(%{
#       #TODO do everything in terms of grids...
#       # grid_pos: nil,  # where we are in the file, e.g. line 3, column 5
#       #TODO make this original_coords
#       original_coordinates: starting_coords,        # so we can track how we've moved around
#       current_coords: starting_coords,
#       hidden?: false,                               # internal variable used to control blinking
#       override?: nil,                               # override lets us disable the blinking temporarily, for when we want to move the cursor
#       timer: nil,                                   # holds an erlang :timer for the blink
#       mode: mode,                                   # normal mode renders a block, insert mode renders a vertical line
#       draw_footer?: false                           # cursors will never (?) need to draw their Frame
#     })
#   end

#   @impl Flamelex.GUI.ComponentBehaviour
#   #TODO this is a deprecated version of render
#   def render(%Frame{} = frame, params) do
#     render(params |> Map.merge(%{frame: frame}))
#   end


#   def render(%{ref: buf_ref, current_coords: coords, mode: mode}) do
#     # Draw.blank_graph()
#     Scenic.Graph.build()
#     |> Scenic.Primitives.rect(
#           CursorUtils.cursor_box_dimensions(mode),
#             id: buf_ref,
#             translate: coords,
#             fill: :ghost_white,
#             hidden?: false)
#   end


#   def rego_tag(%{ref: {:gui_component, _details} = ref, num: num}) when is_integer(num) and num >= 1 do
#     {:text_cursor, num, ref}
#   end

#   # @impl Flamelex.GUI.ComponentBehaviour
#   # def handle_action(
#   #         {graph, %{ref: buf_ref, current_coords: {_x, _y} = current_coords} = state},
#   #         {:move_cursor, direction, distance})
#   #           when direction in @valid_directions
#   #           and distance >= 1 do

#   #   CursorUtils.move(graph, state, %{
#   #     current_coords: current_coords,
#   #     direction: direction,
#   #     distance: distance,
#   #     buf_ref: buf_ref
#   #   })
#   # end


#   # NEXT TODOs
#   # - get blinking working
#   # - get status bar rendering
#   # - be able to move between modes / input text / move cursor
#   # - get KommandBuffer going



#   #TODO this needs to become a SCENE
#   def handle_cast(:start_blink, scene) do
#     {:ok, timer} = :timer.send_interval(@blink_ms, :blink)
#     # new_state = %{state | timer: timer}
#     scene = scene
#     |> assign(timer: timer)
#     {:noreply, scene}
#   end

#   def handle_cast({:move, details}, scene) do
#     {new_graph, new_params} = CursorUtils.move_cursor({scene.assigns.graph, scene.assigns.params}, details)
#     scene =
#       scene
#       |> assign(graph: new_graph)
#       |> assign(params: new_params)
#       |> push_graph(new_graph)
#     {:noreply, scene}
#   end

#   def handle_cast({:update, new_coords}, scene) do
#     # {new_graph, new_state} = CursorUtils.reposition({graph, state}, new_coords)
#     {new_graph, new_params} = CursorUtils.reposition({scene.assigns.graph, scene.assigns.params}, new_coords)
#     scene =
#       scene
#       |> assign(graph: new_graph)
#       |> assign(params: new_params)
#       |> push_graph(new_graph)
#     {:noreply, scene}
#   end

#   def handle_cast(:reset, scene) do
#     {new_graph, new_params} = CursorUtils.reset_position({scene.assigns.graph, scene.assigns.params})
#     scene =
#       scene
#       |> assign(graph: new_graph)
#       |> assign(params: new_params)
#       |> push_graph(new_graph)
#     {:noreply, scene}
#   end

#   def handle_cast(any, state) do
#     # IO.warn "GOT ANY #{inspect any}"
#     {:noreply, state}
#   end

#   # def handle_info({:switch_mode, new_mode}, {graph, %{ref: _buf_ref} = state}) do
#   def handle_info({:switch_mode, new_mode}, scene) do
#     {new_graph, new_params} = CursorUtils.switch_mode({scene.assigns.graph, scene.assigns.params}, new_mode)
#     # {:noreply, {new_graph, new_state}, push: new_graph}
#     # new_state = new_state |> |> assign(params: params)
#     new_scene =
#       scene
#       |> assign(graph: new_graph)
#       |> assign(params: new_params)
#       |> push_graph(new_graph)
#     {:noreply, new_scene}
#   end

#   @impl Scenic.Scene
#   # def handle_info(:blink, {graph, %{ref: _buf_ref} = state}) do
#   def handle_info(:blink, scene) do
#     # {new_graph, new_state} = CursorUtils.handle_blink({graph, state})
#     {new_graph, new_params} = CursorUtils.handle_blink({scene.assigns.graph, scene.assigns.params})
#     new_scene =
#       scene
#       |> assign(graph: new_graph)
#       |> assign(params: new_params)
#       |> push_graph(new_graph)
#     {:noreply, new_scene}
#   end
# end











# defmodule Flamelex.GUI.Component.BlinkingCursor do


#   def move(cursor_id, :right) do
#     cursor_id |> action(:move_right_one_column)
#   end



#   @impl Scenic.Scene
#   def handle_cast({:action, :move_right_one_column}, {state, graph}) do
#     %Dimensions{height: _height, width: width} =
#       state.frame.dimensions
#     %Coordinates{x: current_top_left_x, y: current_top_left_y} =
#       state.frame.top_left

#     new_state =
#       %{state|frame:
#           state.frame |> Frame.reposition(
#             x: current_top_left_x + width, #TODO this is actually just *slightly* too narrow for some reason
#             y: current_top_left_y)}

#     new_graph =
#       graph
#       |> Graph.modify(state.frame.id, fn %Scenic.Primitive{} = box ->
#            put_transform(box, :translate, {new_state.frame.top_left.x, new_state.frame.top_left.y})
#          end)

#     {:noreply, {new_state, new_graph}, push: new_graph}
#   end

#   @impl Scenic.Scene
#   def handle_cast({:action, :reset_position}, {state, graph}) do
#     new_state =
#       state.frame.top_left |> put_in(state.original_coordinates)

#     new_graph =
#       graph
#       |> Graph.modify(state.frame.id, fn %Scenic.Primitive{} = box ->
#            put_transform(box, :translate, {new_state.frame.top_left.x, new_state.frame.top_left.y})
#          end)

#     {:noreply, {new_state, new_graph}, push: new_graph}
#   end




#   # def handle_cast({:action, 'MOVE_LEFT_ONE_COLUMN'}, {state, graph}) do
#   #   {width, _height} = state.dimensions
#   #   {current_top_left_x, current_top_left_y} = state.top_left_corner

#   #   new_state =
#   #     %{state|top_left_corner: {current_top_left_x - width, current_top_left_y}}

#   #   new_graph =
#   #     graph
#   #     |> Graph.modify(:cursor, fn %Scenic.Primitive{} = box ->
#   #          put_transform(box, :translate, new_state.top_left_corner)
#   #        end)

#   #   {:noreply, {new_state, new_graph}, push: new_graph}
#   # end




#   # def handle_cast({:move, [top_left_corner: new_top_left_corner, dimensions: {new_width, new_height}]}, {state, graph}) do
#   #   new_state =
#   #     %{state|top_left_corner: new_top_left_corner, dimensions: {new_width, new_height}}

#   #   [%Scenic.Primitive{id: :cursor, styles: %{fill: color, hidden: hidden?}}] =
#   #     Graph.find(graph, fn primitive -> primitive == :cursor end)

#   #   new_graph =
#   #     graph
#   #     |> Graph.delete(:cursor)
#   #     |> rect({new_width, new_height},
#   #          id: :cursor,
#   #          translate: new_state.top_left_corner,
#   #          fill: color,
#   #          hidden?: hidden?)

#   #   {:noreply, {new_state, new_graph}, push: new_graph}
#   # end



#   # # --------------------------------------------------------
#   # def handle_cast(:stop_blink, %{graph: old_graph, timer: timer} = state) do
#   #   # hide the caret
#   #   new_graph =
#   #     old_graph
#   #     |> Graph.modify(:blinking_box, &update_opts(&1, hidden: true))

#   #   # stop the timer
#   #   case timer do
#   #     nil -> :ok
#   #     timer -> :timer.cancel(timer)
#   #   end

#   #   new_state =
#   #     %{state | graph: new_graph, hidden: true, timer: nil}

#   #   {:noreply, new_state, push: new_graph}
#   # end


# end













#   def handle_blink({graph, %{ref: buf_ref} = state}) do
#     # IO.puts "BLINK"
#     new_state =
#       case state.override? do
#         :visible ->
#           %{state|hidden?: false, override?: nil}
#         :invisible ->
#           %{state|hidden?: true, override?: nil}
#         nil ->
#           %{state|hidden?: not state.hidden?}
#       end

#     new_graph =
#       graph
#       |> Scenic.Graph.modify(
#                 buf_ref,
#                 &Scenic.Primitives.update_opts(&1,
#                                       hidden: new_state.hidden?))

#     {new_graph, new_state}
#   end

#   def reposition({graph, state}, %{line: l, col: c}) do

#     {start_x, start_y} = state.original_coordinates

#     new_x = start_x + (cursor_box_width()*(c-1)) #REMINDER: we need the -1 here because we starts lines & columns at 1 not zero
#     new_y = start_y + (cursor_box_height()*(l-1))

#     new_state =
#       %{state|current_coords: {new_x, new_y}, override?: :visible} # the visual effect is better if you dont blink the cursor when moving it

#     new_graph =
#       graph |> modify_cursor_position(new_state)

#     {new_graph, new_state}
#   end

#   def move_cursor({graph, state}, %{instructions: instructions}) do

#     new_coords =
#         state
#         |> reposition_cursor(%{move: instructions})

#     new_state =
#         %{state|current_coords: new_coords, override?: :visible} # the visual effect is better if you dont blink the cursor when moving it

#     new_graph =
#         graph |> modify_cursor_position(new_state)

#     {new_graph, new_state}
#   end