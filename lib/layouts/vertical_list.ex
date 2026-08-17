defmodule ScenicWidgets.VerticalList do
  use Scenic.Component
  require Logger
  alias Widgex.Frame

  def validate(
        %{
          id: _id,
          frame: _frame,
          items: _items,
          scroll: {_x, _y}
        } = data
      ) do
    {:ok, data}
  end

  # TODO delete this one below it;s old but keep it for now for bnackwards coatibility
  # def validate(%{frame: _frame, items: _item_list} = data) do
  #   {:ok, data}
  # end

  def init(scene, args, opts) do
    # Logger.debug "#{__MODULE__} initializing..."

    # TODO here we break the frame down into sub-frames and pass those
    # to the list of component/args, and just add those components with each frame

    # Batch render all items at once instead of one-at-a-time via GenServer.cast
    init_graph = init_render_with_items(args)

    init_scene =
      scene
      # we need an id so that when we cast events up to the parent, we can identify this component
      |> assign(id: args.id)
      |> assign(graph: init_graph)
      |> assign(frame: args.frame)
      # Items are now rendered immediately, no queue needed
      |> assign(items: args.items)
      |> assign(render_queue: [])
      |> push_graph(init_graph)

    request_input(init_scene, [:cursor_scroll])

    {:ok, init_scene}
  end

  def init_render(%{frame: f, scroll: scroll}) do
    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # add rect so v list has bounds
        |> Scenic.Primitives.rect(f.size.box)
        # |> ScenicWidgets.FrameBox.add_to_graph(%{frame: f, fill: :pink})
        # NOTE- make the container group, give it translation etc, just don't add any components yet
        |> Scenic.Primitives.group(
          fn graph ->
            graph
            # |> Scenic.Primitives.rect(
            #   f.size.box,
            #   scissor: f.size.box
            # )
          end,
          # NOTE: We will scroll this pane around later on, and need to
          #      add new TidBits to it with Modify
          # Scenic required we register groups/components with a name
          id: :v_list_window,
          translate: scroll
        )

        # draw a scissor rect around the entire list
        # |> Scenic.Primitives.rect(
        #   f.size.box,
        #   scissor: f.size.box
        # )
      end,
      # this scissor is _essential_ it's the only one that works lol
      scissor: f.size.box
    )
  end

  @doc """
  Batch render all items at once during init.
  This avoids the performance issue of sequential GenServer.cast rendering.
  """
  def init_render_with_items(%{frame: f, scroll: scroll, items: items}) do
    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # add rect so v list has bounds
        |> Scenic.Primitives.rect(f.size.box)
        # Render all items in a single pass
        |> Scenic.Primitives.group(
          fn graph ->
            Enum.reduce(items, graph, fn item, acc_graph ->
              render_item(acc_graph, item)
            end)
          end,
          id: :v_list_window,
          translate: scroll
        )
      end,
      scissor: f.size.box
    )
  end

  # Render a single item (component or draw function)
  defp render_item(graph, {draw_fn, %{frame: %Widgex.Frame{}} = args}) when is_function(draw_fn) do
    draw_fn.(graph, args)
  end

  defp render_item(graph, {component_module, %{frame: %Widgex.Frame{}} = args}) when is_atom(component_module) do
    if Kernel.function_exported?(component_module, :draw, 2) do
      component_module.draw(graph, args)
    else
      component_module.add_to_graph(graph, args)
    end
  end

  # def bounds(%{frame: %{pin: {top_left_x, top_left_y}, size: {width, height}}}, _opts) do
  #   # NOTE: Because we use this bounds/2 function to calculate whether or
  #   # not the mouse is hovering over any particular button, we can't
  #   # translate entire groups of sub-menus around. We ned to explicitely
  #   # draw buttons in their correct order, and not translate them around,
  #   # because bounds/2 doesn't seem to work correctly with translated elements
  #   # TODO talk to Boyd and see if I'm wrong about this, or maybe we can improve Scenic to work with it
  #   left = top_left_x
  #   right = top_left_x + width
  #   top = top_left_y
  #   bottom = top_left_y + height
  #   {left, top, right, bottom}
  # end

  def handle_input(
        {:cursor_scroll, {{_x_scroll, _y_scroll}, coords}},
        _context,
        scene
      ) do
    # TODO handle all this via a Reducer?? Or just keep it in the component??
    # Flamelex.Fluxus.action({Flamelex.GUI.Component.RapidSelector.Reducer, {:scroll, delta_scroll, __MODULE__}})

    # I think it needs be be via a reducer... because e.g. we want to change scroll by pressing shift to get fast scroll, so we need access to the global state

    # new_cumulative_scroll = compute_scroll(scene.assigns.scroll, delta_scroll)

    # new_graph =
    #   scene.assigns.graph
    #   |> Scenic.Graph.modify(
    #     :v_list_window,
    #     &Scenic.Primitives.update_opts(&1, translate: new_cumulative_scroll)
    #   )

    # new_scene =
    #   scene
    #   |> assign(graph: new_graph)
    #   |> assign(scroll: new_cumulative_scroll)
    #   |> push_graph(new_graph)

    # cast_parent(scene, {:click, details})

    # {:noreply, new_scene}

    bounds = Scenic.Graph.bounds(scene.assigns.graph)

    if coords |> ScenicWidgets.Utils.inside?(bounds) do
      cast_parent(
        scene,
        {:cursor_scroll, scene.assigns.id, {{_x_scroll, _y_scroll}, coords}}
      )
    end

    {:noreply, scene}
  end

  def handle_cast(:render_next_component, %{assigns: %{render_queue: []}} = scene) do
    # Logger.debug "#{__MODULE__} ignoring a request to render a component, there's nothing to render"
    {:noreply, scene}
  end

  def handle_cast(
        :render_next_component,
        # %{assigns: %{render_queue: [{module, args} = item | rest]}} = scene
        %{
          assigns: %{
            render_queue: [
              {draw_fn, %{frame: %Widgex.Frame{} = _f} = args} = item | rest
            ]
          }
        } = scene
      )
      when is_function(draw_fn) do
    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.add_to(:v_list_window, fn graph ->
        draw_fn.(graph, args)
      end)

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(items: scene.assigns.items ++ [item])
      |> assign(render_queue: rest)
      |> push_graph(new_graph)

    GenServer.cast(self(), :render_next_component)

    {:noreply, new_scene}
  end

  def handle_cast(
        :render_next_component,
        %{
          assigns: %{
            render_queue: [
              {component_module, %{frame: %Widgex.Frame{} = _f} = args} = item | rest
            ]
          }
        } = scene
      )
      when is_atom(component_module) do
    # Logger.debug("#{__MODULE__} attempting to render an additional component... #{inspect(item)}")

    # rendered_items = scene.assigns.items ++ [item]

    # note - need to calculate the item frame using the existing item list, not after we've added the new one!
    # args = put_in(args, [:frame], calc_item_frame(scene.assigns.frame, scene.assigns.items))

    # |> Scenic.Graph.add_to(:river_pane, fn graph ->
    #   graph
    #   # |> ScenicWidgets.FrameBox.add_to_graph(%{frame: Frame.new(%{pin: {400, 400}, size: {400, 400}}), fill: :blue})
    #   # |> ScenicWidgets.FrameBox.add_to_graph(%{frame: calc_hypercard_frame(scene), fill: :blue})
    #   |> Memelex.GUI.Components.HyperCard.add_to_graph(%{
    #     # id: tidbit.uuid,
    #     frame: calc_hypercard_frame(scene),
    #     # frame: Frame.new(%{pin: {400, 400}, size: {400, 400}}),
    #     state: tidbit
    #     # state: %{uuid: "123"}
    #   })

    #   # TODO pass id in the opts
    # end)

    # figure out if this is a `live` component or a `declaritive` one

    new_graph =
      if Kernel.function_exported?(component_module, :draw, 2) do
        scene.assigns.graph
        |> Scenic.Graph.add_to(:v_list_window, fn graph ->
          graph |> component_module.draw(args)
        end)
      else
        # assume it's a component
        scene.assigns.graph
        |> Scenic.Graph.add_to(:v_list_window, fn graph ->
          graph |> component_module.add_to_graph(args)
        end)
      end

    # new_graph =
    #   scene.assigns.graph
    #   |> Scenic.Graph.add_to(:v_list_window, fn graph ->
    #     graph |> component_module.add_to_graph(args)
    #   end)

    # |> module.add_to_graph(args)
    # |> Scenic.Graph.add_to(:river_pane, fn graph ->
    #   graph
    #   # |> ScenicWidgets.FrameBox.add_to_graph(%{frame: Frame.new(%{pin: {400, 400}, size: {400, 400}}), fill: :blue})
    #   # |> ScenicWidgets.FrameBox.add_to_graph(%{frame: calc_hypercard_frame(scene), fill: :blue})
    #   |> Memelex.GUI.Components.HyperCard.add_to_graph(%{
    #     # id: tidbit.uuid,
    #     frame: calc_hypercard_frame(scene),
    #     # frame: Frame.new(%{pin: {400, 400}, size: {400, 400}}),
    #     state: tidbit
    #     # state: %{uuid: "123"}
    #   })

    #   # TODO pass id in the opts
    # end)

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(items: scene.assigns.items ++ [item])
      |> assign(render_queue: rest)
      |> push_graph(new_graph)

    GenServer.cast(self(), :render_next_component)

    {:noreply, new_scene}
  end

  def handle_cast({:set_scroll, {_x, _y} = new_scroll}, scene) do
    new_graph =
      scene.assigns.graph
      |> Scenic.Graph.modify(
        :v_list_window,
        &Scenic.Primitives.update_opts(&1, translate: new_scroll)
      )

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast({:click, details}, scene) do
    cast_parent(scene, {:click, details})
    {:noreply, scene}
  end

  def handle_cast({:focus, _id}, scene) do
    # this is a bit of a hack but basically when the dropdown
    # drops it will msg the todo list (it's parent), we
    # set the whole component into dropdown mode, and in dropdown
    # mode we dont handle clicks from anything except the dropdown
    # - this will hopefully fix the bug ("workaround") where clicking
    # on a dropdown also clicks the item (usually a TODO) below it (in the z plane)
    {:noreply, scene}
  end

  # def bounds(%{frame: %{pin: {top_left_x, top_left_y}, size: {width, height}}}, _opts) do
  #   # NOTE: Because we use this bounds/2 function to calculate whether or
  #   # not the mouse is hovering over any particular button, we can't
  #   # translate entire groups of sub-menus around. We ned to explicitely
  #   # draw buttons in their correct order, and not translate them around,
  #   # because bounds/2 doesn't seem to work correctly with translated elements
  #   # TODO talk to Boyd and see if I'm wrong about this, or maybe we can improve Scenic to work with it
  #   left = top_left_x
  #   right = top_left_x + width
  #   top = top_left_y
  #   bottom = top_left_y + height
  #   {left, top, right, bottom}
  # end

  # def calc_item_frame(%{
  def calc_item_frame(%Frame{size: %{width: w}}, state) do
    # assigns: %{
    #   frame: %Frame{pin: %{x: x, y: y}, size: %{width: w}},
    #   state: state
    # }
    # }) do
    # TODO really calculate height
    item_height = 50
    items_offset = item_height * Enum.count(state)
    # extra_vertial_space = @spacing_buffer * Enum.count(open_tidbits_list)

    Frame.new(
      # pin: {x + @spacing_buffer, y + @spacing_buffer + open_tidbits_offset + extra_vertial_space},
      #  size: {w-(2*@spacing_buffer), {:flex_grow, %{min_height: 500}}})
      # TODO
      # size: {w - 2 * @spacing_buffer, 500}
      %{
        pin: {0, items_offset},
        size: {w, item_height}
      }
    )
  end

  # def handle_event(e, scene) do
  #   IO.inspect("VLIST - #{inspect(e)}")
  #   {:noreply, scene}
  # end

  # def handle_info(msg, scene) do
  #   IO.inspect("VLIST - #{inspect(msg)}")
  #   {:noreply, scene}
  # end
end
