defmodule ScenicWidgets.MenuBar.FloatButton do
  # use Scenic.Component
  # require Logger
  # @moduledoc """
  # This module is really not that different from a normal Scenic Button,
  # just customized a little bit.
  # """

  # def validate(%{label: _l, menu_index: _n, frame: _f, margin: _m, font: _fs} = data) do
  #     #Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
  #     {:ok, data}
  # end

  # def init(scene, args, opts) do
  #     #Logger.debug "#{__MODULE__} initializing..."

  #     theme = QuillEx.Utils.Themes.theme(opts)

  #     init_graph = render(args, theme)

  #     init_scene = scene
  #     |> assign(graph: init_graph)
  #     |> assign(frame: args.frame)
  #     |> assign(theme: theme)
  #     |> assign(state: %{
  #                 mode: :inactive,
  #                 font: args.font,
  #                 menu_index: args.menu_index})
  #     |> push_graph(init_graph)

  #     request_input(init_scene, [:cursor_pos, :cursor_button])

  #     {:ok, init_scene}
  # end

  # def render(args, theme) do
  #     {_width, height} = args.frame.size

  #     # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
  #     vpos = height/2 + (args.font.ascent/2) + (args.font.descent/3)

  #     Scenic.Graph.build()
  #     |> Scenic.Primitives.group(fn graph ->
  #         graph
  #         |> Scenic.Primitives.rect(args.frame.size,
  #                 id: :background,
  #                 fill: theme.active)
  #         |> Scenic.Primitives.text(args.label,
  #                 id: :label,
  #                 font: :ibm_plex_mono,
  #                 font_size: args.font.size,
  #                 translate: {args.margin, vpos},
  #                 fill: theme.text)
  #       end, [
  #          id: {:float_button, args.menu_index},
  #          translate: args.frame.pin
  #       ])
  # end

  # def handle_input({:cursor_pos, {x, y} = coords}, _context, scene) do
  #     bounds = Scenic.Graph.bounds(scene.assigns.graph)
  #     theme  = scene.assigns.theme

  #     new_graph =
  #         if coords |> QuillEx.Utils.HoverUtils.inside?(bounds) do
  #             GenServer.cast(QuillEx.GUI.Components.MenuBar, {:hover, scene.assigns.state.menu_index})
  #             scene.assigns.graph
  #             #TODO and change text to black
  #             |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: theme.highlight))
  #         else
  #             # GenServer.cast(QuillEx.GUI.Components.MenuBar, {:cancel, {:hover, scene.assigns.state.menu_index}})
  #             scene.assigns.graph
  #             |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: theme.active))
  #         end

  #     new_scene = scene
  #     |> assign(graph: new_graph)
  #     |> push_graph(new_graph)

  #     {:noreply, new_scene}
  # end

  # #TODO accept clicks, send msg bck up to menu bar??
  # def handle_input({:cursor_pos, {x, y} = coords}, _context, scene) do
  #     bounds = Scenic.Graph.bounds(scene.assigns.graph)

  #     new_graph =
  #         if coords |> QuillEx.Utils.HoverUtils.inside?(bounds) do
  #             GenServer.cast(QuillEx.GUI.Components.MenuBar, {:hover, scene.assigns.state.menu_index})
  #             scene.assigns.graph
  #             |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: :green))
  #         else
  #             # GenServer.cast(QuillEx.GUI.Components.MenuBar, {:cancel, {:hover, scene.assigns.state.menu_index}})
  #             scene.assigns.graph
  #             |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: :blue))
  #         end

  #     new_scene = scene
  #     |> assign(graph: new_graph)
  #     |> push_graph(new_graph)

  #     {:noreply, new_scene}
  # end

  # def handle_input({:cursor_button, {:btn_left, 0, [], click_coords}}, _context, scene) do
  #     bounds = Scenic.Graph.bounds(scene.assigns.graph)
  #     if click_coords |> QuillEx.Utils.HoverUtils.inside?(bounds) do
  #         GenServer.cast(QuillEx.GUI.Components.MenuBar, {:click, scene.assigns.state.menu_index})
  #     end
  #     {:noreply, scene}
  # end

  # def handle_input(input, _context, scene) do
  #     # Logger.debug "#{__MODULE__} ignoring input: #{inspect input}..."
  #     {:noreply, scene}
  # end
end
