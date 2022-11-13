defmodule ScenicWidgets.Core.Utils.FlexiFrame do
    @moduledoc """
    Struct which holds 2d points.
    """
    use ScenicWidgets.Core.Utils.CustomGuards
    alias ScenicWidgets.Core.Structs.Frame
 

   @doc """
   The first page we ever learned to rule-up at school.

   +-----------------+
   |                 |
   +-----------------+   <-- linemark
   |                 |
   |                 |
   |                 |
   |                 |
   |                 |
   |                 |
   +-----------------+
   """
   def calc(
      %Scenic.ViewPort{size: {vp_width, vp_height}} = vp,
      {:standard_rule, linemark: linemark, linemark_visible?: false}
   ) do
      top_frame = Frame.new(pin: {0, 0}, size: {vp_width, linemark})
      rest_frame = Frame.new(pin: {0, linemark}, size: {vp_width, vp_height-linemark})
      root_frame = Frame.new(vp)

      %{
         root: root_frame,
         framestack: [
            top_frame,
            rest_frame
         ]
      }
   end

   def calc(vp, {:standard_rule, linemark: linemark}) do
      # default to an invisible linemark
      calc(vp, {:standard_rule, linemark: linemark, linemark_visible?: false})
   end

   def split(%Frame{pin: {x, y}, size: {w, h}} = frame) do
      [
         Frame.new(pin: {x, y}, size: {w/2, h}),
         Frame.new(pin: {x+(w/2), y}, size: {w/2, h})
      ]
   end
 end