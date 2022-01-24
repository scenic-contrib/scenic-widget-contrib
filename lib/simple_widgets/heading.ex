defmodule ScenicWidgets.Simple.Heading do
    @moduledoc """
    This module wraps a lot of the behaviour required for rendering
    a text heading - it scissors outside the frame, handles wrapping etc.


    It doesn't really require it's own Component, everything can be achieved
    just by chaining this function in a %Graph{} pipeline.

    Example:

        graph
        |> ScenicWidgets.Simple.Heading.add_to_graph(%{
				text: "A title that I want to display",
				frame: Frame.new(pin: {5, 5}, size: {500, {max_lines, 2}}),
				font: :ibm_plex_mono,
				color: :green,
				# text_wrap_opts: :wrap #TODO
				background_color: :yellow
		})
    """
    
    def add_to_graph(graph, %{
        text: t,
        frame: %ScenicWidgets.Core.Structs.Frame{dimensions: %{height: {:max_lines, max_lines}}} = _frame,
        font: %{
            name: font_name,
            size: font_size,
            metrics: font_metrics},
        color: font_color,
        background_color: background_color
    } = args) when is_bitstring(t) do

        ascent = FontMetrics.ascent(font_size, font_metrics)
        descent = FontMetrics.descent(font_size, font_metrics)
        
        #TODO there's still no definitive way to calculate line height, this is just a guess...
        # line_height = (4/3)*font_size
        # line_height = (4/3)*(ascent-descent) ## MAGIC!!! See https://www.thomasphinney.com/2011/03/point-size/ - "What About the Web?" section
        line_height = ascent-descent

        # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
        # vpos = font_size/2 + ascent/2
        vpos = line_height/2 + ascent/2 + descent/3 # WHy does this work!? It's a miracle!

        wrapped_text = FontMetrics.wrap(args.text, args.frame.dimensions.width, font_size, font_metrics)
        wrapped_text_list = String.split(wrapped_text, "\n")
        num_lines =
            if (num_wrapped = Enum.count(wrapped_text_list)) <= max_lines do
                num_wrapped
            else
                max_lines
            end

        heading_rectangular_size = {args.frame.dimensions.width, num_lines*line_height}

        graph
        |> Scenic.Primitives.group(
                fn graph ->
                    graph
                    |> Scenic.Primitives.rect(heading_rectangular_size,
                            fill: background_color)
                    |> Scenic.Primitives.text(wrapped_text,
                            font: font_name,
                            font_size: font_size,
                            translate: {0, vpos},
                            fill: font_color)
                end,
                scissor: heading_rectangular_size,
                translate: args.frame.pin # translate: {tl_x+left_margin, tl_y+top_margin}, # text draws from bottom-left corner??
        )   
    end
end