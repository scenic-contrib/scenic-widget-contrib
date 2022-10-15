defmodule ScenicWidgets.TextPad.LineOfText do
    use Scenic.Component
    require Logger
  
    @default_font :roboto
    @default_font_size 24

    #TODO handle tab characters
  
    def validate(%{
        line_num: line_num,
        font: %{size: _size},
        frame: %ScenicWidgets.Core.Structs.Frame{} = _frame,
        text: text,
        name: name, #TODO this sucks so bad but we need it to get the text back later using GenServer.call
        theme: theme
      } = args) when is_integer(line_num) and line_num >= 1 and (is_bitstring(text) or is_nil(text)) do
      {:ok, args}
    end
  
    #TODO make better use of opts here, it has tons of font shit in it ??
    def init(scene, %{text: text} = args, opts) do
        #Logger.debug("#{__MODULE__} initializing... #{inspect args.line_num}, text: #{args.text}")

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
                    translate: {args.frame.top_left.x, args.frame.top_left.y + ascent}
                )
            end

        #TODO use real registry properly
        # name = String.to_atom(args.name)

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(text: text)
        |> assign(name: args.name)
        |> assign(frame: args.frame)
        |> assign(args: args) # lol TODO
        |> push_graph(init_graph)

        Process.register(self(), String.to_atom(args.name))
    
        {:ok, init_scene}
    end

    # def bounds(%{font: font, frame: %{pin: {top_left_x, top_left_y}, size: {frame_width, height}}} = args, opts) do
        
    #     #TODO so fkin dumb but whatever...
    #     {:ok, text} = GenServer.call(String.to_atom(args.name), :get_text)

    #     text_width = 
    #         cond do
    #             is_nil(text) ->
    #                 0
    #             is_bitstring(text) ->
    #                 FontMetrics.width(text, font.size, font.metrics)
    #         end

    #     # true_width = if text_width >= frame_width, do: text_width, else: frame_width
    #     # IO.inspect true_width, label: "TW"
    #      # {left, top, right, bottom}
    #     {top_left_x, top_left_y, top_left_x+text_width, top_left_y+height}
    # end

    def handle_call(:get_text, _from, scene) do
        {:reply, {:ok, scene.assigns.text}, scene}
    end

    def handle_cast({:redraw, text}, %{assigns: %{text: text}} = scene) do
        # make no changes, the text for this line is the same
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
                # translate: {args.margin.left, args.margin.top + ascent + y_offset(args)}
                translate: {args.frame.top_left.x, args.frame.top_left.y + ascent}
            )
        end

        new_scene = scene
        |> assign(graph: new_graph)
        |> assign(text: new_text)
        |> push_graph(new_graph)

      {:noreply, new_scene}
    end

    def random_string do
        # https://dev.to/diogoko/random-strings-in-elixir-e8i
        for _ <- 1..10, into: "", do: <<Enum.random('0123456789abcdef')>>
    end
end