defmodule ScenicWidgets.Utils.Theme do
    

    # `theme` is passed in as an inherited style by Scenic - e.g.
    #
    # %{
    #     active: {58, 94, 201},
    #     background: {72, 122, 252},
    #     border: :light_grey,
    #     focus: :cornflower_blue,
    #     highlight: :sandy_brown,
    #     text: :white,
    #     thumb: :cornflower_blue
    # }
    
    def get_theme(opts) do
        (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
        |> Scenic.Primitive.Style.Theme.normalize()
    end
end
