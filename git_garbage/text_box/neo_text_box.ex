
 


#     # def handle_cast({:search, search_term}, %{assigns: %{state: %{mode: :normal}}} = scene) do
#     #     {w, h} = {scene.assigns.frame.dimensions.width, scene.assigns.frame.dimensions.height}

#     #     new_graph = scene.assigns.graph
#     #     |> Scenic.Graph.delete(:sidebar_tabs)
#     #     |> Scenic.Graph.delete(:sidebar_memex_control)
#     #     |> Scenic.Graph.delete(:sidebar_open_tidbits)
#     #     |> Scenic.Graph.delete(:sidebar_search_results)
#     #     |> Sidebar.SearchResults.add_to_graph(%{
#     #         results: [],
#     #         frame: Frame.new(pin: {0, 0}, size: {w, h})},
#     #         id: :sidebar_search_results, t: scene.assigns.frame.pin)

#     #     new_state = scene.assigns.state |> Map.merge(%{mode: :search})

#     #     new_scene = scene
#     #     |> assign(state: new_state)
#     #     |> assign(graph: new_graph)
#     #     |> push_graph(new_graph)

#     #     {:noreply, new_scene}
#     #  end

#     #  #TODO note that fkin text input box fucks everything up... it captures keystrokes!!

#     #  def handle_cast({:search, search_term}, %{assigns: %{state: %{mode: :search}}} = scene) do
#     #     # {:ok, [sidebar_search_results: pid]} = Scenic.Scene.children(scene)
#     #     {:ok, children} = Scenic.Scene.children(scene)
#     #     children |> Enum.map(fn {:sidebar_search_results, pid} ->
#     #                                 GenServer.cast(pid, {:search, search_term})
#     #                             _else ->
#     #                                 :ok
#     #                         end)
        
#     #     {:noreply, scene}
#     #  end

#     #  def handle_input(@escape_key, _context, %{assigns: %{state: %{mode: :search}, frame: frame}} = scene) do
#     #     full_frame = {w, h} = {frame.dimensions.width, frame.dimensions.height}

#     #     {:gui_component, Flamelex.GUI.Component.Memex.HyperCard.Sidebar.SearchBox, :search_box}
#     #     |> ProcessRegistry.find!()
#     #     |> GenServer.cast(:deactivate)

#     #     IO.puts "YEYERYERY"
#     #     new_graph = scene.assigns.graph
#     #     |> Scenic.Graph.delete(:sidebar_tabs)
#     #     |> Scenic.Graph.delete(:sidebar_memex_control)
#     #     |> Scenic.Graph.delete(:sidebar_open_tidbits)
#     #     |> Scenic.Graph.delete(:sidebar_search_results)
#     #     |> Sidebar.Tabs.add_to_graph(%{
#     #         tabs: ["Open", "Recent", "More"],
#     #         frame: Frame.new(pin: {0, 0}, size: {w, @tabs_menu_height}),
#     #         id: :sidebar_tabs}, id: :sidebar_tabs, t: frame.pin)
#     #     |> Sidebar.OpenTidBits.add_to_graph(%{
#     #         open_tidbits: ["Luke", "Leah"],
#     #         frame: Frame.new(pin: {0, @tabs_menu_height}, size: {w, h-@tabs_menu_height})},
#     #         # frame: sidebar_open_tidbits_frame(frame)},
#     #         # id: {:sidebar, :low_pane, "Open"})
#     #         id: :sidebar_open_tidbits, t: frame.pin) # they all use this save id, so we can just delete this every time

#     #     new_state = scene.assigns.state |> Map.merge(%{mode: :normal})

#     #     new_scene = scene
#     #     |> assign(state: new_state)
#     #     |> assign(graph: new_graph)
#     #     |> push_graph(new_graph)

#     #     {:noreply, new_scene}
#     #   end

#     #  def handle_input(unrecognised_input, _context, scene) do
#     #     ic unrecognised_input

#     #     {:noreply, scene}
#     #  end
#  end