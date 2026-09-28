defmodule QuillEx.GUI.Components.SplashScreen do
    use Scenic.Component
    use ScenicWidgets.ScenicEventsDefinitions
    alias ScenicWidgets.Core.Structs.Frame
    require Logger
  

    def validate(%{frame: %Frame{} = _f} = data) do
      # Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
      {:ok, data}
    end
  
    def init(scene, args, opts) do
      Logger.debug("#{__MODULE__} initializing...")
      # Process.register(self(), __MODULE__)
  
      # QuillEx.Lib.Utils.PubSub.subscribe(topic: :radix_state_change)

      init_graph = Scenic.Graph.build()
      |> Scenic.Primitives.rect(args.frame.size, fill: :purple, translate: args.frame.pin)
  
      init_scene =
        scene
        |> assign(frame: args.frame)
        |> assign(graph: init_graph)
        |> push_graph(init_graph)
  
      request_input(init_scene, [:key])
  
      {:ok, init_scene}
    end
  
  end
  