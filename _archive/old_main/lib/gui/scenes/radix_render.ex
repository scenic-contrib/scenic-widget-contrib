defmodule QuillEx.Scene.RadixRender do
  # alias QuillEx.GUI.Components.{Editor, SplashScreen}
  # alias ScenicWidgets.Core.Structs.Frame
  # alias ScenicWidgets.Core.Utils.FlexiFrame
  alias QuillEx.Fluxus.Structs.RadixState
  alias Widgex.Structs.Frame

  def render(
        %Scenic.ViewPort{} = vp,
        %RadixState{} = radix_state,
        children \\ []
      ) do
    # menu_bar_frame =
    #   Frame.new(vp, {:standard_rule, frame: 1, linemark: radix_state.menu_bar.height})

    # editor_frame =
    #   Frame.new(vp, {:standard_rule, frame: 2, linemark: radix_state.menu_bar.height})

    # |> render_menubar(%{frame: menubar_f, radix_state: radix_state})

    Scenic.Graph.build(font: :ibm_plex_mono)
    |> Scenic.Primitives.group(
      fn graph ->
        graph |> render_components(vp, radix_state, children)
      end,
      id: :quillex_root
    )
  end

  def render_components(graph, _vp, %{components: []} = _radix_state, _children) do
    graph
  end

  # TODO join_together(layout, components) - the output of this
  # function is a zipped-list of tuples with each component having
  # been assigned a %Frame{} (and a layer??) - no, layer management
  # happens at a higher level

  def render_components(graph, vp, radix_state, children) do
    # new_graph = graph

    # IO.inspect(children)

    framestack = Frame.stack(vp, radix_state.layout)

    # |> ScenicWidgets.FrameBox.draw(%{frame: hd(editor_f), color: :blue})
    # |> Editor.add_to_graph(args |> Map.merge(%{app: QuillEx}), id: :editor)

    # TODO after zipping them together here with a frame, look in the
    # children for an existing process

    component_frames =
      cond do
        length(radix_state.components) == length(framestack) ->
          Enum.zip(radix_state.components, framestack)

        # |> tag_children(children)

        length(radix_state.components) < length(framestack) ->
          # just take the first 'n' frames
          first_frames = Enum.take(framestack, length(radix_state.components))

          Enum.zip(radix_state.components, framestack)

        # |> tag_children(children)

        length(radix_state.components) > length(framestack) ->
          raise "more components than we have frames, cannot render"
      end

    # component_frames = Enum.zip(radix_state.components, framestack)

    # {:ok, [{:plaintext, #PID<0.336.0>}, {ScenicWidgets.UbuntuBar, #PID<0.339.0>}]}

    # paired_component_frames = Enum.zip(children, component_frames)

    # paired_component_frames =
    #   Enum.map(component_frames, fn {c, f} ->
    #     if process_alive?(c.widgex.pid) do
    #       # {c, f}
    #       # push the diff to the component
    #       {pid, c, f}
    #     else
    #       {nil, f}
    #     end

    #     if(Enum.member?())

    #     if c.widgex.id == :ubuntu_bar do
    #       {c, f}
    #     else
    #       {c, f}
    #     end
    #   end)

    graph |> do_render_components(component_frames)
  end

  defp tag_children(component_frames, children) do
    Enum.map(component_frames, fn {c, f} ->
      case find_child(c.widgex.id, children) do
        {component_id, pid} when is_pid(pid) ->
          {c, f, pid}

        nil ->
          {c, f}
      end

      # if pid = find_child(c.widgex.id, children) do
      #   {c, f, pid}
      # else
      #   {, f}
      # end
    end)
  end

  defp find_child(id, children) do
    Enum.find(children, fn {component_id, _} -> component_id == id end)
  end

  defp do_render_components(graph, []) do
    graph
  end

  defp do_render_components(graph, [{nil, _f} | rest]) do
    # if component is nil just draw nothing
    graph |> do_render_components(rest)
  end

  # defp do_render_components(graph, [{c, f, pid} | rest]) when is_pid(pid) do
  #   IO.puts("UPDATE DONT REDRAW")

  #   graph
  #   |> c.__struct__.add_to_graph({c, f}, id: Map.get(c, :id) || c.widgex.id)
  #   # |> c.__struct__.add_to_graph({c, f}, id: c.widgex.id)
  #   |> do_render_components(rest)
  # end

  # defp do_render_components(graph, [%Widgex.Component{} = c | rest]) when is_struct(c) do
  # TODO maybe we enforce ID here somehjow??
  defp do_render_components(graph, [{c, %Frame{} = f} | rest]) when is_struct(c) do
    graph
    # |> c.__struct__.add_to_graph({c, f}, id: c.id || c.widgex.id)
    |> c.__struct__.add_to_graph({c, f}, id: c.widgex.id)
    |> do_render_components(rest)
  end

  # defp do_render_components(graph, [{c, %Frame{} = f} | rest]) when is_struct(c) do
  #   graph
  #   # |> c.__struct__.add_to_graph({c, f}, id: c.id || c.widgex.id)
  #   # # |> c.__struct__.add_to_graph({c, f})
  #   # |> do_render_components(rest)
  # end

  defp do_render_components(graph, [{sub_stack, sub_frame_stack} | rest])
       when is_list(sub_stack) and is_list(sub_frame_stack) do
    if length(sub_stack) != length(sub_frame_stack) do
      raise "length of (sub!) components and framestack must match"
    end

    sub_component_frames = Enum.zip(sub_stack, sub_frame_stack)

    graph
    |> do_render_components(sub_component_frames)
    |> do_render_components(rest)
  end

  # def render_menubar(graph, %{frame: frame, radix_state: radix_state}) do
  #   menubar_args = %{
  #     frame: frame,
  #     menu_map: calc_menu_map(radix_state),
  #     font: radix_state.desktop.menu_bar.font
  #   }

  #   graph
  #   # |> ScenicWidgets.FrameBox.draw(%{frame: menubar_f, color: :red})
  #   |> ScenicWidgets.MenuBar.add_to_graph(menubar_args, id: :menu_bar)
  # end

  # def calc_menu_map(%{editor: %{buffers: []}}) do
  #   [
  #     {:sub_menu, "Buffer",
  #      [
  #        {"new", &QuillEx.API.Buffer.new/0}
  #      ]},
  #     {:sub_menu, "View",
  #      [
  #        {"toggle line nums", fn -> raise "no" end},
  #        {"toggle file tray", fn -> raise "no" end},
  #        {"toggle tab bar", fn -> raise "no" end},
  #        {:sub_menu, "font",
  #         [
  #           {:sub_menu, "primary font",
  #            [
  #              {"ibm plex mono",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:ibm_plex_mono)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"roboto",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:roboto)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"roboto mono",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:roboto_mono)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"iosevka",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:iosevka)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"source code pro",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:source_code_pro)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"fira code",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:fira_code)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end},
  #              {"bitter",
  #               fn ->
  #                 QuillEx.Fluxus.RadixStore.get()
  #                 |> QuillEx.Reducers.RadixReducer.change_font(:bitter)
  #                 |> QuillEx.Fluxus.RadixStore.put()
  #               end}
  #            ]},
  #           {"make bigger",
  #            fn ->
  #              QuillEx.Fluxus.RadixStore.get()
  #              |> QuillEx.Reducers.RadixReducer.change_font_size(:increase)
  #              |> QuillEx.Fluxus.RadixStore.put()
  #            end},
  #           {"make smaller",
  #            fn ->
  #              QuillEx.Fluxus.RadixStore.get()
  #              |> QuillEx.Reducers.RadixReducer.change_font_size(:decrease)
  #              |> QuillEx.Fluxus.RadixStore.put()
  #            end}
  #         ]}
  #      ]},
  #     {:sub_menu, "Help",
  #      [
  #        {"about QuillEx", &QuillEx.API.Misc.makers_mark/0}
  #      ]}
  #   ]
  # end

  # def calc_menu_map(%{editor: %{buffers: buffers}})
  #     when is_list(buffers) and length(buffers) >= 1 do
  #   # NOTE: Here what we do is just take the base menu (with no open buffers)
  #   # and add the new buffer menu in to it using Enum.map

  #   base_menu = calc_menu_map(%{editor: %{buffers: []}})

  #   open_bufs_sub_menu =
  #     buffers
  #     |> Enum.map(fn %{id: {:buffer, name} = buf_id} ->
  #       # NOTE: Wrap this call in it's closure so it's a function of arity /0
  #       {name, fn -> QuillEx.API.Buffer.activate(buf_id) end}
  #     end)

  #   Enum.map(base_menu, fn
  #     {:sub_menu, "Buffer", base_buffer_menu} ->
  #       {:sub_menu, "Buffer",
  #        base_buffer_menu ++ [{:sub_menu, "open-buffers", open_bufs_sub_menu}]}

  #     other_menu ->
  #       other_menu
  #   end)
  # end
end
