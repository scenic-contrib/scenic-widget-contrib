defmodule ScenicWidgets.TextPad.Structs.Font do
   @moduledoc """
   Used to pass fonts to TextPad.
   """
   use ScenicWidgets.Core.Utils.CustomGuards

   # the default line-height is 1.2
   # https://hexdocs.pm/scenic/0.11.0-beta.0/Scenic.Primitive.Style.LineHeight.html
   # https://github.com/memononen/nanovg/blob/master/src/nanovg.h#L583
   @default_line_height_multipler 1.2

   defstruct [
      name: nil,
      size: nil,
      metrics: nil
   ]

   def default do
      name = :roboto
      %{
         name: name,
         size: 24,
         metrics: font_metrics(name)
      }
   end

   def font_metrics(font_name) when is_atom(font_name) do
      {:ok, {Scenic.Assets.Static.Font, font_metrics}} = Scenic.Assets.Static.meta(font_name)
      font_metrics
   end

   def new(%{
      name: name,
      size: size,
      metrics: %FontMetrics{} = metrics
   }) when is_atom(name) and is_positive_integer(size) do
      %__MODULE__{
         name: name,
         size: size,
         metrics: metrics
      }
   end

   def line_height(args) do
      line_height(@default_line_height_multipler, args)
   end

   def line_height(m, %{font: f}), do: line_height(m, f)

   def line_height(m, %{size: font_size}) when is_positive_integer(font_size) do
     m*font_size
   end

end
