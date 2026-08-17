defmodule QuillEx.Scene.RootScene do
  use Scenic.Scene
  alias QuillEx.Fluxus.Structs.RadixState
  alias QuillEx.Fluxus.RadixStore
  alias QuillEx.Scene.RadixRender
  require Logger

  def init(%Scenic.Scene{} = scene, _init_args, _opts) do
    Logger.debug("#{__MODULE__} initializing...")

    # the Root scene pulls from the radix store on bootup, and then subscribes to changes
    # the reason why I'm doing it this way, and not passing in the radix state
    # from the top (which would be possible, because I initialize the
    # radixstate during app bootup & pass it in to radix store, just so that
    # this process can then go fetch it) is because it seems cleaner to me
    # because if this process restarts then it will go & fetch the correct state &
    # continue from there, vs if I pass it in then it will restart again with
    # whatever I gave it originally (right??!?)

    # now that I type this out... wouldn't that be a safer, better option?
    # this process isn't supposed to crash, if it does crash probably it is due
    # to bad state, and then probably I don't want to immediately go & fetch that
    # bad state...

    # for that reason I actually _am_ going to pass it in from the top

    # After all this debate I changed my mind again, I dont want to be passing
    # around big blobs of state, I want the RadixStore process to just keep
    # the State and everything interacts with RadixState via that process, so
    # this process does go & fetch RadixState on bootup

    # Lol further addendum, I've decided that the reasoning of not wanting
    # to pass the RadixState in because I didnt want to copy a huge state variable
    # around is absurd given how muich I copy it around all over the place in
    # the rest of the app, but I'm going to stick with just fetching it on
    # startup because if the whole GUI does crash up to this level, I want
    # it to start again from the current RadixStore

    radix_state = RadixStore.get()
    init_graph = RadixRender.render(scene.viewport, radix_state)

    # |> maybe_render_debug_layer(scene.viewport, radix_state)

    init_scene =
      scene
      |> assign(state: radix_state)
      |> assign(graph: init_graph)
      |> push_graph(init_graph)

    QuillEx.Lib.Utils.PubSub.subscribe(topic: :radix_state_change)

    request_input(init_scene, [:viewport, :key])

    {:ok, init_scene}
  end

  # defp maybe_render_debug_layer(graph, _viewport, _radix_state) do
  #   # if radix_state.gui_config.debug do
  #   #   Scenic.Graph.add_layer(
  #   #     Scenic.Graph.new(:debug_layer),
  #   #     Scenic.Graph.new(:debug_layer, [Scenic.Primitives.text("DEBUG MODE")])
  #   #   )
  #   # else
  #   #   Scenic.Graph.new(:debug_layer)
  #   # end

  #   # for now, do nothing...
  #   # in the future we could render an overlay showing the layout
  #   graph
  # end

  def handle_input(
        {:viewport, {:reshape, {new_vp_width, new_vp_height} = new_size}},
        _context,
        scene
      ) do
    Logger.warn("If this didn't cause errors each time it ran I would raise here!!")
    # raise "Ignoring VIEWPORT RESHAPE - should handle this!"
    # TODO fire an action probably
    {:noreply, scene}
  end

  def handle_input({:viewport, {input, _coords}}, _context, scene)
      when input in [:enter, :exit] do
    # don't do anything when the mouse enters/leaves the viewport
    {:noreply, scene}
  end

  def handle_input(input, _context, scene) do
    # TODO ok in QuillEx I'm going to experiment with doing this all sequentially

    # Logger.debug "#{__MODULE__} recv'd some (non-ignored) input: #{inspect input}"
    # QuillEx.Useo
    # rInputHandler.process(input)
    # IO.puts("HJIHIHI")

    # TODO mayube here, we need to handle input in the same thread as root process? This (I think) would at least make all input processed on the radix state at the time of input, vs throwing an event it may introduce timing errors...

    # GenServer.call(QuillEx.Fluxus.RadixStore, {:user_input, input})

    # I am going to fully commit in QuillEx to trying the syncronous PubSub
    # and see how it goes. I think it will be easier to reason about, and
    # because each event is processed sequentially by the action listener
    QuillEx.Fluxus.input(scene.assigns.state, input)
    {:noreply, scene}
  end

  def handle_cast(msg, scene) do
    IO.inspect(msg, label: "MMM root scene")
    {:noreply, scene}
  end

  def handle_info(
        {:radix_state_change, new_radix_state},
        scene
      ) do
    # actually here the ROotScene never has to reply to changes but we have it here for now

    # TODO possibly this is an answer.. widgex components have to implement some functiuon which compares 2 radix state & determinnes if the component has changed or not - and this will be different for root scene as it will for Ubuntu bar, etc...
    no_changes? =
      not components_changed?(scene.assigns.state, new_radix_state) and
        not layout_changed?(scene.assigns.state, new_radix_state)

    # Enum.map(
    #   [:components, :layout],
    #   fn key ->
    #     scene.assigns.state[key] == new_radix_state[key]
    #   end
    # )

    if no_changes? do
      {:noreply, scene}
    else
      new_graph =
        scene.viewport
        |> RadixRender.render(new_radix_state)

      new_scene =
        scene
        |> assign(state: new_radix_state)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

      {:noreply, new_scene}
    end

    # TODO this might end up being overkill / inefficient... but ultimately, do I even care??
    # I only care if I end up spinning up new processes all the time.. which unfortunately I do think is what's happening :P

    # TODO pass in the list of childten to RadixRender so that it knows to only cast, not re-render from scratch, if that Child is alread alive
    # {:ok, children} = Scenic.Scene.children(scene)

    # new_graph =
    #   scene.viewport
    #   |> RadixRender.render(new_radix_state, children)

    # # |> maybe_render_debug_layer(scene_viewport, new_radix_state)

    # if new_graph.ids == scene.assigns.graph.ids do
    #   # no need to update the graph on this level

    #   new_scene =
    #     scene
    #     |> assign(state: new_radix_state)

    #   {:noreply, new_scene}
    # else
    #   new_scene =
    #     scene
    #     |> assign(state: new_radix_state)
    #     |> assign(graph: new_graph)
    #     |> push_graph(new_graph)

    #   {:noreply, new_scene}
    # end

    # new_scene =
    #   scene
    #   |> assign(state: new_radix_state)
    #   |> assign(graph: new_graph)
    #   |> push_graph(new_graph)

    # {:noreply, new_scene}
  end

  def components_changed?(old_radix_state, new_radix_state) do
    component_ids = fn rdx_state ->
      Enum.map(rdx_state.components, & &1.widgex.id)
    end

    component_ids.(old_radix_state) != component_ids.(new_radix_state)
    # old_radix_state.components != new_radix_state.components
  end

  def layout_changed?(old_radix_state, new_radix_state) do
    old_radix_state.layout != new_radix_state.layout
  end

  def handle_event(event, _from_pid, scene) do
    IO.puts("GOT AN EVENT BUYT I KNOW ITS A CLICK #{inspect(event)}}")

    {:glyph_clicked_event, button_num} = event

    # {:ok, kids} = Scenic.Scene.children(scene)

    if button_num == :g1 do
      QuillEx.Fluxus.action(:open_read_only_text_pane)
    else
      if button_num == :g2 do
        QuillEx.Fluxus.action(:open_text_pane)
      else
        if button_num == :g3 do
          QuillEx.Fluxus.action(:open_text_pane_scrollable)
        end
      end
    end

    {:noreply, scene}
  end

  # def handle_info(
  #       {:radix_state_change, new_radix_state},
  #       # %{assigns: %{menu_map: current_menu_map}} = scene
  #     ) do
  #   # check font change?
  #   new_font = new_radix_state.gui_config.fonts.primary
  #   current_font = scene.assigns.state.gui_config.fonts.primary

  #   # redraw everything...
  #   if new_font != current_font do
  #     new_graph = scene.assigns.graph
  #     # |> Scenic.Graph.delete(:quillex_main) #TODO go back to blank graph??
  #     # |> render(scene.assigns.viewport, new_radix_state)
  #     # render(scene.assigns.viewport, new_radix_state)

  #     new_scene =
  #       scene
  #       |> assign(state: new_radix_state)
  #       |> assign(graph: new_graph)

  #     # |> assign(menu_map: calc_menu_map(new_radix_state))

  #     IO.puts("PUSH PUSH PUSH")

  #     new_scene |> push_graph(new_graph)

  #     {:noreply, new_scene |> assign(state: new_radix_state)}
  #   else
  #     # check menu bar changed??
  #     new_menu_map = calc_menu_map(new_radix_state)

  #     new_scene =
  #       if new_menu_map != current_menu_map do
  #         Logger.debug("refreshing the MenuBar...")
  #         GenServer.cast(ScenicWidgets.MenuBar, {:put_menu_map, new_menu_map})
  #         scene |> assign(menu_map: new_menu_map)
  #       else
  #         scene
  #       end

  #     {:noreply, new_scene}
  #   end
  # end

  # # TODO expand this to include all changesd to menubar, including font type...
  # def handle_info(
  #       {:radix_state_change, new_radix_state},
  #       %{assigns: %{menu_map: current_menu_map}} = scene
  #     ) do
  #   new_menu_map = calc_menu_map(new_radix_state)

  #   IO.puts("HIHIHIHIHIHI")

  #   if new_menu_map != current_menu_map do
  #     IO.puts("UES UES YES WE GOT A NEW MENU MAP")
  #     # Logger.debug "refreshing the MenuBar..."

  #     # TODO make new function in Scenic `cast_child`
  #     # scene |> cast_child(:menu_bar, {:put_menu_map, new_menu_map})
  #     case child(scene, :menu_bar) do
  #       {:ok, []} ->
  #         Logger.warn("Could not find the MenuBar process.")
  #         {:noreply, scene}

  #       {:ok, [pid]} ->
  #         GenServer.cast(pid, {:put_menu_map, new_menu_map})
  #         {:noreply, scene |> assign(menu_map: new_menu_map)}
  #     end
  #   else
  #     {:noreply, scene}
  #   end
  # end
end
