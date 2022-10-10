defmodule ScenicWidgets.TextPad.LineOfText do
    use Scenic.Component
    require Logger
  
    @default_font :roboto
    @default_font_size 24

    #TODO handle tab characters
  
    def validate(%{
        line_num: line_num,
        font: %{size: _size},
        width: _width,
        text: text,
        theme: theme
      } = args) when is_integer(line_num) and line_num >= 1 and (is_bitstring(text) or is_nil(text)) do
      {:ok, args}
    end
  
    def init(scene, %{text: text} = args, opts) do
        Logger.debug("#{__MODULE__} initializing... #{inspect args.line_num}, text: #{args.text}")

        #TODO make this more efficient, pass it in same everywhere
        ascent = FontMetrics.ascent(args.font.size, args.font.metrics)

        init_graph =
            if is_nil(text) or text == "" do
                Scenic.Graph.build()
            else
                Scenic.Graph.build()
                |> Scenic.Primitives.text(text,
                    font: args.font.name,
                    font_size: args.font.size,
                    fill: args.theme.text,
                    # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
                    translate: {args.margin.left, args.margin.top + ascent + y_offset(args)}
                )
            end

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(text: text)
        |> assign(args: args) # lol TODO
        |> push_graph(init_graph)

    
        {:ok, init_scene}
    end

    def handle_cast({:redraw, text}, %{assigns: %{text: text}} = scene) do
        IO.puts "NO CHANGE NOT RENDERIN"
        {:noreply, scene}
    end
  
    def handle_cast({:redraw, new_text}, %{assigns: %{args: args}} = scene) do
      ascent = FontMetrics.ascent(args.font.size, args.font.metrics)

      new_graph =
        if is_nil(new_text) or new_text == "" do
            Scenic.Graph.build()
        else
            Scenic.Graph.build()
            |> Scenic.Primitives.text(new_text,
                font: args.font.name,
                font_size: args.font.size,
                fill: args.theme.text,
                # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
                translate: {args.margin.left, args.margin.top + ascent + y_offset(args)}
            )
        end

        new_scene = scene
        |> assign(graph: new_graph)
        |> assign(text: new_text)
        |> push_graph(new_graph)

      {:noreply, new_scene}
    end
  
    def y_offset(%{line_num: n, font: %{size: size}}) do
        # calculate how many line down we need to move this line
       (n-1)*(1.2*size) 
    end

  end