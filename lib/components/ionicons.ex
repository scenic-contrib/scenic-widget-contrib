defmodule ScenicWidgets.Ionicons.Black32 do
    # https://ionic.io/ionicons

    #NOTE - Scenic apparently doesn't handle the idea of having assets in a dependency app... I needed to move the assets up to that app

    @margin (50-32)/2

    def plus(graph, opts \\ []) do
        # this function is a convenience wrapper...
        add(graph, opts)
    end

    def add(graph, _opts \\ []) do
        graph
        # |> Scenic.Primitives.rect({50, 50}, fill: :antique_white)
        |> Scenic.Primitives.rect({32, 32}, fill: {:image, "ionicons/black_32/cog.png"}, translate: {@margin, @margin})
    end
end