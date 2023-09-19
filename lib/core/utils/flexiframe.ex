defmodule ScenicWidgets.Core.Utils.FlexiFrame do
  @moduledoc """
  Struct which holds 2d points.
  """
  use ScenicWidgets.Core.Utils.CustomGuards
  alias ScenicWidgets.Core.Structs.Frame

  def main_pane_frame(%Scenic.ViewPort{size: {vp_width, vp_height}}, menu_bar_height: mb_height) do
    Frame.new(pin: {0, mb_height}, size: {vp_width, vp_height - mb_height})
  end

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
    rest_frame = Frame.new(pin: {0, linemark}, size: {vp_width, vp_height - linemark})
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
      Frame.new(pin: {x, y}, size: {w / 2, h}),
      Frame.new(pin: {x + w / 2, y}, size: {w / 2, h})
    ]
  end

  def split_horizontal(%Frame{pin: {x, y}, size: {w, h}}, split_point) do
    left_frame_w = split_point / 100 * w
    right_frame_w = (1 - split_point / 100) * w

    [
      Frame.new(pin: {x, y}, size: {left_frame_w, h}),
      Frame.new(pin: {x + left_frame_w, y}, size: {right_frame_w, h})
    ]
  end

  def columns(%Frame{pin: {x, y}, size: {w, h}} = frame, 3) do
    [
      Frame.new(pin: {x, y}, size: {w / 3, h}),
      Frame.new(pin: {x + w / 3, y}, size: {w / 3, h}),
      Frame.new(pin: {x + 2 * w / 3, y}, size: {w / 3, h})
    ]
  end

  def columns(%Frame{pin: {x, y}, size: {w, h}} = frame, 3, :memex) do
    [
      Frame.new(pin: {x, y}, size: {w / 4, h}),
      Frame.new(pin: {x + w / 4, y}, size: {w / 2, h}),
      Frame.new(pin: {x + 3 * w / 4, y}, size: {w / 4, h})
    ]
  end

  # Layer + Layout of Frames = LayerCake
end
