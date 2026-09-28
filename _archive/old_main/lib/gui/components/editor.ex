defmodule QuillEx.GUI.Components.Editor do
  use Scenic.Component

  require Logger
  alias ScenicWidgets.{TabSelector, TextPad}
  alias ScenicWidgets.Core.Structs.Frame
  alias QuillEx.Structs.Buffer
  alias ScenicWidgets.TextPad.Structs.Font

  # NOTE - we need to take in the `app` because this component is re-used by Flamelex...

  # TODO remove, this should come from the font or something
  @tab_selector_height 40

  # this module is used by both QUillex & Flamelex, so we need to pass in
  # the correct pubsub module for whichever app is utilizing this module...
  @higher_app [QuillEx, Flamelex]

  def validate(%{frame: %Frame{} = _f, radix_state: _rx, app: app} = data)
      when app in @higher_app do
    # Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
    {:ok, data}
  end

  def init(scene, args, opts) do
    #  Logger.debug("#{__MODULE__} initializing...")

    # TODO convert QuillEx into having it's own internal Fluxus tree...
    pubsub_mod = Module.concat(args.app, Lib.Utils.PubSub)
    pubsub_mod.subscribe(topic: :radix_state_change)

    init_graph = render(args)

    init_state = calc_state(args.radix_state)

    init_scene =
      scene
      |> assign(app: args.app)
      |> assign(font: args.radix_state.editor.font)
      |> assign(frame: args.frame)
      |> assign(graph: init_graph)
      |> assign(state: init_state)
      |> push_graph(init_graph)

    {:ok, init_scene}
  end

  def handle_cast({:frame_reshape, new_frame}, scene) do
    # new_graph = scene.assigns.graph
    # |> Scenic.Graph.modify(:menu_background, &Scenic.Primitives.rect(&1, new_frame.size))

    # new_scene = scene
    # |> assign(graph: new_graph)
    # |> assign(frame: new_frame)
    # |> push_graph(new_graph)
    raise "cant resize yet"

    {:noreply, scene}
  end

  def handle_cast(
        {:scroll_limits, %{inner: %{width: _w, height: _h}, frame: _f} = new_scroll_state},
        scene
      ) do
    # update the RadixStore, without broadcasting the changes,
    # so we can keep accurate calculations for scrolling
    radix_store(scene)

    radix_store(scene).get()
    #  |> radix_reducer(scene).change_editor_scroll_state(new_scroll_state)
    |> radix_store(scene).put()

    {:noreply, scene}
  end

  def handle_info(
        {:radix_state_change, %{editor: %{font: new_font}} = new_radix_state},
        %{assigns: %{font: current_font}} = scene
      )
      when new_font != current_font do
    # Logger.debug "font changed..."

    new_graph = render(%{frame: scene.assigns.frame, radix_state: new_radix_state})

    new_scene =
      scene
      |> assign(font: new_radix_state.editor.font)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_info({:radix_state_change, %{editor: %{buffers: []}}}, scene) do
    new_graph = Scenic.Graph.build()

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_info(
        {:radix_state_change, %{editor: %{active_buf: radix_active_buf}} = new_radix_state},
        %{assigns: %{state: %{active_buf: state_active_buf}}} = scene
      )
      when radix_active_buf != state_active_buf do
    # Logger.debug "Swapped the Active buffer to a different buf..."

    new_graph = render(%{frame: scene.assigns.frame, radix_state: new_radix_state})

    new_state = calc_state(new_radix_state)

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> assign(state: new_state)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_info({:radix_state_change, %{editor: %{buffers: buf_list}} = new_state}, scene)
      when length(buf_list) >= 1 do
    # Logger.debug "Active buffer got updated..."

    [active_buffer] = buf_list |> Enum.filter(&(&1.id == new_state.editor.active_buf))
    # tab_list = buf_list |> Enum.map(& &1.id)

    # TODO maybe send it a list of lines instead? Do the rope calc here??
    {:ok, [pid]} = child(scene, {:text_pad, active_buffer.id})

    GenServer.cast(pid, {:redraw, active_buffer})

    {:noreply, scene}
  end

  # def handle_event({:tab_clicked, tab_label}, _from, %{assigns: %{app: app}} = scene) do
  #   # Flamelex.Fluxus.action({MemexReducer, :new_tidbit})
  #   # TODO buffer.find, then Buffer.activate
  #   Logger.warn("TAB CLICKED")
  #   buffer_api(app).activate(tab_label)
  #   {:noreply, scene}
  # end

  # def handle_event({:hover_tab, tab_label}, _from, scene) do
  #   # Flamelex.Fluxus.action({MemexReducer, :new_tidbit})
  #   # TODO buffer.find, then Buffer.activate
  #   Logger.warn("TAB HOVERED")
  #   {:noreply, scene}
  # end

  # def handle_event({:value_changed, :text_pad, new_value}, _from, scene) do
  #   Logger.warn("TEXT PAD CHANGED")
  #   {:noreply, scene}
  # end

  def calc_state(%{editor: %{active_buf: active_buf}} = _radix_state) do
    %{active_buf: active_buf}
  end

  def render(%{frame: frame, radix_state: %{editor: %{active_buf: nil}} = radix_state}) do
    Scenic.Graph.build()
    |> Scenic.Primitives.group(fn graph -> graph end, id: :editor)
  end

  def render(%{frame: editor_frame, radix_state: %{editor: %{buffers: buf_list}} = radix_state}) do
    [active_buffer] = buf_list |> Enum.filter(&(&1.id == radix_state.editor.active_buf))

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # |> render_tab_selector()
        |> render_text_pad(%{
          frame: editor_frame,
          buffer: active_buffer,
          font: radix_state.editor.font
        })
      end,
      id: :editor
    )
  end

  #   def render_tab_selector do
  #             # |> TabSelector.add_to_graph(%{
  #         #   frame:
  #         #     Frame.new(width: scene.assigns.frame.dimens.width, height: @tab_selector_height),
  #         #   theme: theme,
  #         #   tab_list: tab_list,
  #         #   active: active_buffer.id,
  #         #   font: font,
  #         #   menu_item: %{width: 220}
  #         # })
  #   end

  def render_text_pad(graph, %{
        frame: %Frame{} = frame,
        buffer: %Buffer{} = buffer,
        font: %Font{} = font
      }) do
    graph
    |> TextPad.add_to_graph(
      %{
        frame: calc_text_pad_frame(frame),
        state:
          TextPad.new(%{
            buffer: buffer,
            font: font
          })
      },
      id: {:text_pad, buffer.id}
    )
  end

  def calc_text_pad_frame(%Frame{pin: pin, size: {w, h}}) do
    # NOTE: Add the extra 10 because on MacOS the stupid rounded corners of the GLFW frame make the window look stupid, F-U Steve J.
    Frame.new(pin: pin, size: {w, h - 10})
  end

  # NOTE - we need these because Editor component is used by both QuilleEx & Flamelex...
  def radix_store(%{assigns: %{app: app}}) do
    Module.concat(app, Fluxus.RadixStore)
  end

  def radix_reducer(%{assigns: %{app: app}}) do
    #  Module.concat(app, Fluxus.Reducers.RadixReducer)
    QuillEx.Reducers.RadixReducer
  end

  defp theme do
    %{
      active: {58, 94, 201},
      background: {72, 122, 252},
      border: :light_grey,
      focus: :cornflower_blue,
      highlight: :sandy_brown,
      text: :white,
      thumb: :cornflower_blue
    }
  end
end

# NOTE: Don't handle events here, just let them bubble-up to the
#      parent scene - https://hexdocs.pm/scenic/Scenic.Scene.html#module-event-filtering
# def handle_event({:tab_clicked, tab_label}, _from, scene) do
#     {:noreply, scene}
# end

# #TODO right now, this re-draws every time there's a RadixState update - we ought to compare it against what we have, & only update/broadcast if it really changed
# # This case takes us from :inactive -> 2 buffers
# def handle_info({:radix_state_change, %{buffers: buf_list, active_buf: active_buf} = new_state}, scene) when length(buf_list) >= 2 and length(buf_list) <= 7 do
#     #Logger.debug "#{__MODULE__} ignoring radix_state: #{inspect new_state}, scene_state: #{inspect scene.assigns.state}}"
#     Logger.debug "#{__MODULE__} drawing a 2-tab TabSelector --"

#     {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")
#     fm = ibm_plex_mono_fm #TODO get this once and keep hold of it in the state

#     render_tabs = fn(init_graph) ->
#         {final_graph, _final_offset} =
#             buf_list
#             # |> Enum.map(fn %{id: id} -> id end) # we only care about id's...
#             |> Enum.with_index()
#             |> Enum.reduce({init_graph, _init_offset = 0}, fn {%{id: label}, index}, {graph, offset} ->
#                     label_width = @menu_width #TODO - either fixed width, or flex width (adapts to size of label)
#                     item_width  = label_width+@left_margin
#                     carry_graph = graph
#                     |> SingleTab.add_to_graph(%{
#                             label: label,
#                             ref: label,
#                             active?: label == active_buf,
#                             margin: 10,
#                             font: %{
#                                 size: @tab_font_size,
#                                 ascent: FontMetrics.ascent(@tab_font_size, fm),
#                                 descent: FontMetrics.descent(@tab_font_size, fm),
#                                 metrics: fm},
#                             frame: %{
#                                 pin: {offset, 0}, #REMINDER: coords are like this, {x_coord, y_coord}
#                                 size: {item_width, 40} #TODO dont hard-code
#                             }})
#                     {carry_graph, offset+item_width}
#             end)

#         final_graph

#     end

#     new_graph = scene.assigns.graph
#     |> Scenic.Graph.delete(:tab_selector)
#     |> Scenic.Primitives.group(fn graph ->
#         graph
#         |> Scenic.Primitives.rect({scene.assigns.frame.width, 40}, fill: scene.assigns.theme.background)
#         |> render_tabs.()
#       end, [
#          id: :tab_selector
#       ])

#     new_scene = scene
#     |> assign(graph: new_graph)
#     # |> assign(state: %{buffers: buf_list})
#     |> push_graph(new_graph)

#     {:noreply, new_scene}
# end

# # Single buffer open
# def handle_info(
#       {:radix_state_change,
#       %{editor: %{buffers: [%{id: id, data: text, cursor: cursor_coords}], active_buf: id}}},
#       scene
#     )
#     when is_bitstring(text) do
#   Logger.debug("drawing a single TextPad since we have only one buffer open!")

#   # TODO replace this with render
#   new_graph =
#     Scenic.Graph.build()
#     |> Scenic.Primitives.group(
#       fn graph ->
#         graph
#         |> TextPad.add_to_graph(
#           enhance_args(scene, %{
#             text: text,
#             cursor: cursor_coords,
#             frame: full_screen_buffer(scene)
#           })
#         )
#       end,
#       translate: scene.assigns.frame.pin,
#       id: :editor
#     )

#   new_scene =
#     scene
#     |> assign(graph: new_graph)
#     |> push_graph(new_graph)

#   {:noreply, new_scene}
# end
