
#   # def handle_cast({:move_cursor, details}, {graph, state}) do

#   #   # instructions = translate_details(state, details)

#   #   {:gui_component, {:text_cursor, state.ref.ref, 1}} #TODO standardize this bastard wannabee tree format, also lmao
#   #   |> ProcessRegistry.find!()
#   #   |> GenServer.cast({:move, details})

#   #   {:noreply, {graph, state}}
#   # end

#   # defp translate_details(state, %{instructions: %{last: :line, same: :column}} = details) do
#   #   IO.puts "I know you pressed G..."

#   #   lines_of_text =
#   #     Flamelex.API.Buffer.read(state.ref)
#   #     |> TextBoxDrawUtils.split_into_a_list_of_lines_of_text_structs()


#   #   num_lines = lines_of_text |> Kernel.length()

#   #   details
#   #   |> Map.put(:instructions, {:down, num_lines, :line})
#   # end

#   # defp translate_details(_state, details) do
#   #   details
#   # end



#   # def handle_info({:switch_mode, new_mode}, {graph, state}) do
#   def handle_info({:switch_mode, new_mode}, scene) do

#     #TODO dont do anything when we're hiding the Footer

#     #     new_graph =
#     #       Draw.blank_graph()
#     #       |> Draw.background(state.frame, Flamelex.GUI.Colors.background())
#     #       |> TextBoxDraw.render_text_grid(%{
#     #            frame: state.frame,
#     #            text: state.text,
#     #            cursor_position: state.cursor_position,
#     #            cursor_blink?: state.cursor_blink?,
#     #            mode: m
#     #          })
#     #       |> Frame.draw(state.frame, %{mode: m})

#     #     new_state = %{state| graph: new_graph, mode: m}

#     #TODO ok so this is a bit weird I guess - any time we switch mode,
#     #     we calc this mode-string, but maybe this should be done down
#     #     lower
#     mode_string =
#       case new_mode do
#         :normal -> "NORMAL-MODE"
#         :insert -> "INSERT-MODE"
#         :kommand -> "COMMAND-MODE"
#         _unknown -> "UNKNOWN-MODE!?"
#       end

#     new_graph =
#       scene.assigns.graph
#       |> Scenic.Graph.modify(:mode_string, &Scenic.Primitives.text(&1, mode_string))
#       |> Scenic.Graph.modify(:mode_string_box, &Scenic.Primitives.update_opts(&1, fill: Flamelex.GUI.Colors.mode(new_mode)))
#       #TODO also we want to change the color of the box!
#       # |> Frame.redraw()

#     new_scene =
#       scene
#       |> assign(graph: new_graph)
#       |> push_graph(new_graph)


#     {:noreply, new_scene}
#     # {:noreply, {new_graph, state}, push: new_graph}
#   end

#   def handle_info({{:buffer, buffer_rego}, {:new_state, new_buffer_state}}, {old_graph, gui_component_state})
#   # when buffer_rego == gui_ref do # this GUI component's buffer got an update
#   do


#     # IO.puts "OK, HERE IS THE BIG QUESTION - HOW CAN WE RE-render, from state, also destroy all the old processes"


#     new_graph =
#       old_graph
#       # |> Scenic.Graph.modify(@text_field_id, fn x ->
#       #   x
#       # end)
#       # |> Flamelex.GUI.Component.TextBox.draw({frame, data, %{}}) #TODO check the old process is dieing...
#       # |> Flamelex.GUI.Component.TextBox.mount(%{frame: frame})
#       |> Draw.test_pattern()


#     #TODO stop using ref, use rego_tag
#     # new_graph = render(new_buffer_state |> Map.merge(%{ref: buffer_rego, frame: gui_component_state.frame})) #TODO does this kill the other processes???
#     # {:noreply, {new_graph, gui_component_state}, push: new_graph} #TODO do I need to update the GUI component state??
#     # IO.puts "HEY I THINK WERE HERE AT LEAST"
#     {:noreply, {new_graph, gui_component_state}, push: new_graph} #TODO do we need to update GUI component state??
#   end

#   # def handle_info(msg, state) do
#   #   IO.puts "#{__MODULE__} got info msg: #{inspect msg}, state: #{inspect state}"
#   #   {:noreply, state}
#   # end





#   # def handle_cast({:refresh, _buf_state, _gui_state}, {_graph, state}) do

#   #   new_graph = render(state)

#   #   {:noreply, {new_graph, state}, push: new_graph}

#   #       # data  = Buffer.read(buf)
#   #   # frame = calculate_framing(filename, state.layout)

#   #   # new_graph =
#   #   #   state.graph
#   #   #   # |> Scenic.Graph.modify(@text_field_id, fn x ->
#   #   #   #   IO.puts "YES #{inspect x}"
#   #   #   #   x
#   #   #   # end)
#   #   #   # |> Flamelex.GUI.Component.TextBox.draw({frame, data, %{}}) #TODO check the old process is dieing...
#   #   #   |> Flamelex.GUI.Component.TextBox.mount(%{frame: frame})
#   #   #   |> Draw.test_pattern()

#   #   # Flamelex.GUI.RootScene.redraw(new_graph)

#   #   # {:noreply, %{state|graph: new_graph}}

#   # end




# #   def handle_cast({:move_cursor, direction, _dist}, state) do

# #     _old_cursr_position = %{row: rr, col: cc} = state.cursor_position
# #     new_cursor_position =
# #       case direction do
# #         :left  -> %{row: rr,   col: cc-1}
# #         :down  -> %{row: rr-1, col: cc}
# #         :up    -> %{row: rr+1, col: cc}
# #         :right -> %{row: rr,   col: cc+1}
# #       end

# #     new_graph =
# #       Draw.blank_graph()
# #       |> Draw.background(state.frame, Flamelex.GUI.Colors.background())
# #       |> TextBoxDraw.render_text_grid(%{
# #            frame: state.frame,
# #            text: state.text,
# #            cursor_position: new_cursor_position,
# #            cursor_blink?: state.cursor_blink?
# #          })
# #       |> Frame.draw(state.frame, %{mode: :normal})

# #     new_state = %{state| graph: new_graph,
# #                          cursor_position: new_cursor_position }

# #     {:noreply, new_state, push: new_graph}
# #   end

# #   def handle_cast({:move_cursor, new_cursor_position}, state) do

# #     new_graph =
# #       Draw.blank_graph()
# #       |> Draw.background(state.frame, Flamelex.GUI.Colors.background())
# #       |> TextBoxDraw.render_text_grid(%{
# #            frame: state.frame,
# #            text: state.text,
# #            cursor_position: new_cursor_position,
# #            cursor_blink?: state.cursor_blink?
# #          })
# #       |> Frame.draw(state.frame, %{mode: state.mode})

# #     new_state = %{state| graph: new_graph,
# #                          cursor_position: new_cursor_position }

# #     {:noreply, new_state, push: new_graph}
# #   end
