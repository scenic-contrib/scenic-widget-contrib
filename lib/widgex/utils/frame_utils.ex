defmodule Widgex.Frame.Utils do
  @moduledoc """
  Utility functions for working with frames.
  """
  alias Widgex.Frame
  alias Widgex.Structs.Coordinates

  @doc """
  Split a frame into two frames, one to the left of the other.

  ## Parameters
    * `frame` - The frame to split.
    * `px` - The number of pixels to split the frame at.

  ## Returns
  A list of two frames, the first frame is the left frame, the second frame is the right frame.
  """
  def h_split(frame) do
    h_split(frame, fraction: 0.5)
  end

  def h_split(%Frame{} = f, px: px) do
    left =
      Frame.new(%{
        pin: f.pin.point,
        size: %{width: px, height: f.size.height}
      })

    right =
      Frame.new(%{
        pin: {
          f.pin.x + px,
          f.pin.y
        },
        size: %{
          width: f.size.width - px,
          height: f.size.height
        }
      })

    [left, right]
  end

  # def stack(%Scenic.ViewPort{size: {_vp_width, vp_height}} = vp, :h_split) do
  #   # split it down the middle (horizontally)
  #   stack(vp, {:horizontal_split, {vp_height / 2, :px}})
  # end

  def h_split(%Frame{} = f, fraction: pc) when is_float(pc) and pc >= 0 and pc <= 1 do
    left =
      Frame.new(%{
        pin: f.pin.point,
        size: %{
          width: pc * f.size.width,
          height: f.size.height
        }
      })

    right =
      Frame.new(%{
        pin: {f.pin.x + pc * f.size.width, f.pin.y},
        size: %{width: (1 - pc) * f.size.width, height: f.size.height}
      })

    [left, right]
  end

  @doc """
  Split a frame into two frames, one above the other.

  ## Parameters
    * `frame` - The frame to split.
    * `px` - The number of pixels to split the frame at.

  ## Returns
  A list of two frames, the first frame is the top frame, the second frame is the bottom frame.
  """
  def v_split(%Widgex.Frame{size: %{width: f_width}} = f, px: px) do
    # TODO assert that px < f.size.height
    # Top frame preserves the parent frame's pin position
    top = Frame.new(%{pin: f.pin.point, size: {f_width, px}})

    bottom =
      Frame.new(
        pin: {f.pin.x, f.pin.y + px},
        size: {f_width, f.size.height - px}
      )

    [top, bottom]
  end

  # def v_split(
  #       %Scenic.ViewPort{size: {vp_width, vp_height}},
  #       {:vertical_split, {split, :px}}
  #     ) do
  #   # The day someone discovers buffers in vim/emacs...
  #   #
  #   # +----------------------+
  #   # |           |          |
  #   # |           |          |
  #   # |           |          |
  #   # |           |          |
  #   # |<- split ->|          |
  #   # |           |          |
  #   # |           |          |
  #   # |           |          |
  #   # |           |          |
  #   # +----------------------+
  #   #             ^
  #   #           divider (in pixels, from the left)

  #   f1 = Frame.new(pin: {0, 0}, size: {split, vp_height})
  #   f2 = Frame.new(pin: {split, 0}, size: {vp_width - split, vp_height})

  #   [f1, f2]
  # end

  # def col_split(%Frame{} = f, n) when is_integer(n) and n > 3 do
  #   col_width = f.size.width / n

  #   [
  #     Frame.new(pin: f.pin, size: {col_width, h}),
  #     Frame.new(pin: {f.pin.x + col_width, y}, size: {col_width, h}),
  #     Frame.new(pin: {f.pin.x + 2 * col_width, y}, size: {col_width, h})
  #   ]
  # end

  def col_split(%Frame{} = f, n) when is_integer(n) and n > 0 do
    col_width = f.size.width / n

    # col_num starts at zero and goes up to n-1, so n columns in total but 0 indexed
    Enum.map(0..(n - 1), fn col_num ->
      Frame.new(
        # Adjust pin based on the current column
        pin: {f.pin.x + col_num * col_width, f.pin.y},
        # Keep height consistent, only adjust width
        size: {col_width, f.size.height}
      )
    end)
  end

  def shrink(%Widgex.Frame{} = f, factor, :top)
      when is_number(factor) and factor >= 0 and factor <= 1 do
    new_height = f.size.height * factor
    Widgex.Frame.new(%{pin: f.pin, size: {f.size.width, new_height}})
  end

  def with_margin(%Widgex.Frame{} = f, m) do
    raise "not but do it!"
  end
end

# @doc """
# The first page we ever learned to rule-up at school.

# +-----------------+
# |                 |
# +-----------------+   <-- linemark
# |                 |
# |                 |
# |                 |
# |                 |
# |                 |
# |                 |
# +-----------------+
# """

# def new(
#       %Scenic.ViewPort{size: {vp_width, vp_height}},
#       {:standard_rule, frame: 1, linemark: linemark}
#     ) do
#   new(pin: {0, 0}, size: {vp_width, linemark})
# end

# def new(
#       %Scenic.ViewPort{size: {vp_width, vp_height}},
#       {:standard_rule, frame: 2, linemark: linemark}
#     ) do
#   new(pin: {0, linemark}, size: {vp_width, vp_height - linemark})
# end

# # split the screen horizontally
# def stack(
#       %Scenic.ViewPort{size: {vp_width, vp_height}},
#       {:horizontal_split, {split_point, :px}}
#     ) do
#   # The first page we ever learned to rule-up at school.
#   #
#   # +-----------------+
#   # |                 |
#   # +-----------------+   <-- divider (in pixels, from the top)
#   # |                 |
#   # |                 |
#   # |                 |
#   # |                 |
#   # |                 |
#   # |                 |
#   # +-----------------+
#   f1 = new(pin: {0, 0}, size: {vp_width, split_point})
#   f2 = new(pin: {0, split_point}, size: {vp_width, vp_height - split_point})

#   [f1, f2]
# end

# def stack(%Scenic.ViewPort{size: {vp_width, _vp_height}} = vp, :v_split) do
#   # split it down the middle (vertically)
#   stack(vp, {:vertical_split, {vp_width / 2, :px}})
# end

# def stack(
#       %Scenic.ViewPort{size: {vp_width, vp_height}} = vp,
#       {:vertical_split, {split, :ratio}}
#     )
#     when is_float(split) and split >= 0 and split <= 1 do
#   stack(vp, {:vertical_split, {split * vp_width, :px}})
# end

# @doc """
# Constructs a new `Frame` struct that corresponds to the entire `Scenic.ViewPort`.

# Given a `Scenic.ViewPort`, this function will create a `Frame` that represents the entire viewport by utilizing the `size` attribute of the `ViewPort`.

# ## Params

# - `view_port`: The `Scenic.ViewPort` from which the frame is to be constructed.

# ## Examples

#     iex> alias Scenic.ViewPort
#     iex> alias Widgex.Structs.{Frame, Coordinates, Dimensions}
#     iex> view_port = %ViewPort{size: {800, 600}}
#     iex> Frame.from_viewport(view_port)
#     %Frame{pin: %Coordinates{x: 0, y: 0}, size: %Dimensions{width: 800, height: 600}}
# """

# @spec from_viewport(Scenic.ViewPort.t()) :: t()
# def from_viewport(%Scenic.ViewPort{size: {vp_width, vp_height}}) do
#   # Uncomment the line below to include the hack* (without it we get a dark strip on the right hand side)
#   # width = vp_width + 1

#   # Uncomment the line below for the intended behavior
#   width = vp_width

#   new(%Coordinates{x: 0, y: 0}, %Dimensions{width: width, height: vp_height})
# end
