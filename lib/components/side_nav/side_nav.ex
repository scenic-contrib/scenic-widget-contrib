defmodule ScenicWidgets.SideNav do
    use Scenic.Component
    require Logger
    # alias ScenicWidgets.MenuBar.FloatButton
    alias ScenicWidgets.Core.Structs.Frame
    # use ScenicWidgets.ScenicEventsDefinitions


    def validate(
          %{
            # The %Frame{} struct describing the rectangular size & placement of the component
            frame: %Frame{} = _f,
            # A list containing the contents of the Menu, and what functions to call if that item gets clicked on
            state: %{nav_tree: _tree}
          } = data
        ) do

  
    #   init_state = %{
    #     mode: :inactive,
    #     font: calc_font_data(args.font),
    #     menu_map: args.menu_map,
    #     sub_menu: args.sub_menu,
    #     item_width: args.item_width
    #   }

      {:ok, data}
    end
  
    def init(scene, args, opts) do
      # Logger.debug("#{__MODULE__} initializing...")

      id = opts[:id] || raise "#{__MODULE__} must receive `id` via opts."
  
      theme =
        (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
        |> Scenic.Primitive.Style.Theme.normalize()

      init_graph = render(args.frame, args.state)

      init_scene =
        scene
        |> assign(id: id)
        |> assign(state: args.state)
        |> assign(graph: init_graph)
        |> assign(frame: args.frame)
        |> assign(theme: theme)
        |> push_graph(init_graph)
  
      {:ok, init_scene}
    end

    def handle_cast({:state_change, new_state}, scene) do
        IO.puts "GOT NEW STATE #{inspect new_state}"

        new_graph = render(scene.assigns.frame, new_state)

        new_scene = scene
        |> assign(state: new_state)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)
    
        {:noreply, new_scene}
    end

    def render(%Frame{} = frame, state) do
        Scenic.Graph.build()
        # |> Scenic.Primitives.rect(args.frame.size, fill: :dark_red, translate: args.frame.pin)
        |> Scenic.Primitives.group(
            fn graph ->
              graph
              |> render_nav_tree(%{frame: frame, state: state})
            end,
            translate: frame.pin
        )
    end

    def render_nav_tree(graph, %{frame: _f, state: %{nav_tree: tree}}) when is_list(tree) do

        length = Enum.count(tree)

        # IO.inspect tree, label: "TTTTT"
        graph
        |> Scenic.Primitives.rect({100, 100},
            # id: :background,
            # fill: if(args.hover_highlight?, do: theme.highlight, else: theme.active)
            fill: :gold,
            t: {100, 100}
        )
        |> Scenic.Primitives.group(
            fn group_graph ->

                {final_graph, _final_offset} = 
                    Enum.reduce(tree, {group_graph, 0}, fn item, {acc_graph, offset} ->
                        new_graph =
                            acc_graph
                            |> render_nav_tree_item(item, offset)

                        {new_graph, offset+1}
                    end)

                final_graph
            end,
            id: :nav_tree
        )
    end

    def render_nav_tree_item(graph, item, offset) when is_bitstring(item) do
        
        font = 

        graph
        # |> Scenic.Primitives.group(
        #     fn graph ->
        #         graph
        |> Scenic.Primitives.rect({20*offset, 20},
            # id: :background,
            # fill: if(args.hover_highlight?, do: theme.highlight, else: theme.active)
            fill: :yellow,
            t: {200, 100}
        )
        |> Scenic.Primitives.text(item,
            # id: :label,
            # font: args.font.name,
            # font_size: args.font.size,
            translate: {150, (50*offset)+ScenicWidgets.TextUtils.v_pos(font)},
            fill: :white
            # fill: theme.text
        )
        #     end,
        #     # id: {:nav_tree_iterm, args.unique_id},
        #     translate: {72*offset, 0}
        # )
    end
  
    defp font do
        {:ok, ibm_plex_mono_metrics} =
            TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

        font = %{
            name: :ibm_plex_mono,
            size: 24,
            metrics: ibm_plex_mono_metrics
        }
    end
end
  