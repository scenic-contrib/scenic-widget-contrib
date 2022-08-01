defmodule ScenicWidgets.TextPad.ToolBag do

    def calc_ascent_descent(%{size: size, metrics: metrics}) do
        %{
            ascent: FontMetrics.ascent(size, metrics),
            descent: FontMetrics.descent(size, metrics),
        }
    end
end