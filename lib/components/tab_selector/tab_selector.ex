defmodule ScenicWidgets.TabSelector do
    use Scenic.Component
    require Logger
    alias ScenicWidgets.TabSelector.Painter


    def validate(%{frame: _rs, tab_list: w, active: _a} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."

        init_theme = ScenicWidgets.Utils.Theme.get_theme(opts)

        init_graph =
            Scenic.Graph.build()
            |> Painter.render(args |> Map.merge(%{theme: init_theme}))

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(frame: args.frame)
        |> assign(theme: init_theme)
        |> push_graph(init_graph)

        {:ok, init_scene}
    end

end
