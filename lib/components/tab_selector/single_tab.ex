defmodule ScenicWidgets.TabSelector.SingleTab do
    use Scenic.Component
    require Logger
    @moduledoc """
    This module is really not that different from a normal Scenic Button,
    just customized a little bit.
    """
    alias ScenicWidgets.TabSelector

    def validate(%{label: _l, frame: _f} = data) do
        #Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        #Logger.debug "#{__MODULE__} initializing..."

        theme =
            (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
            |> Scenic.Primitive.Style.Theme.normalize()

        init_graph = render(args, theme)

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(frame: args.frame)
        |> assign(theme: theme)
        |> assign(label: args.label)
        |> push_graph(init_graph)

        request_input(init_scene, [:cursor_pos, :cursor_button])

        {:ok, init_scene}
    end

    def render(%{frame: %{size: {_width, height}}} = args, theme) do
        # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
        vpos = height/2 + (args.font.ascent/2) + (args.font.descent/3)

        background = if args.active?, do: theme.border, else: theme.background

        Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect(args.frame.size,
                    id: :background,
                    fill: background)
            |> Scenic.Primitives.text(args.label,
                    id: :label,
                    font: :ibm_plex_mono,
                    font_size: args.font.size,
                    translate: {args.margin, vpos},
                    fill: theme.text)
          end, [
             id: {:single_tab, args.label},
             translate: args.frame.pin
          ])
    end

    # Change color of the text if we hover over a tab
    def handle_input({:cursor_pos, {_x, _y} = hover_coords}, _context, scene) do
        bounds = Scenic.Graph.bounds(scene.assigns.graph)
        theme  = scene.assigns.theme

        if hover_coords |> ScenicWidgets.Utils.inside?(bounds) do
            send_parent_event(scene, {:hover_tab, scene.assigns.label})
        end

        {:noreply, scene}
    end

    def handle_input({:cursor_button, {:btn_left, 0, [], click_coords}}, _context, scene) do
        bounds = Scenic.Graph.bounds(scene.assigns.graph)
    
        if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
            send_parent_event(scene, {:tab_clicked, scene.assigns.label})
        end
    
        {:noreply, scene}
      end

    def handle_input(input, _context, scene) do
        # Logger.debug "#{__MODULE__} ignoring input: #{inspect input}..."
        {:noreply, scene}
    end

end
