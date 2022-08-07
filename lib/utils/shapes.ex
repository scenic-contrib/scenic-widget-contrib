defmodule ScenicWidgets.Utils.Shapes do
  # @prompt_color :ghost_white
  # @prompt_size 12
  # @prompt_margin 2
  # def draw_command_prompt(graph, %Frame{
  #   #NOTE: These are the coords/dimens for the whole CommandBuffer Frame
  #   top_left: %{x: _top_left_x, y: top_left_y},
  #   dimensions: %{height: height, width: _width}
  # }) do
  #   #NOTE: The y_offset
  #   #      ------------
  #   #      From the top-left position of the box, the command prompt
  #   #      y-offset. (height - prompt_size) is how much bigger the
  #   #      buffer is than the command prompt, so it gives us the extra
  #   #      space - we divide this by 2 to get how much extra space we
  #   #      need to add, to the reference y coordinate, to center the
  #   #      command prompt inside the buffer
  #   y_offset = top_left_y + (height - @prompt_size)/2

  #   #NOTE: How Scenic draws triangles
  #   #      --------------------------
  #   #      Scenic uses 3 points to draw a triangle, which look like this:
  #   #
  #   #           x - point1
  #   #           |\
  #   #           | \ x - point2 (apex of triangle)
  #   #           | /
  #   #           |/
  #   #           x - point3
  #   point1 = {@prompt_margin, y_offset}
  #   point2 = {@prompt_margin+prompt_width(@prompt_size), y_offset+@prompt_size/2}
  #   point3 = {@prompt_margin, y_offset + @prompt_size}

  #   graph
  #   |> Scenic.Primitives.triangle({point1, point2, point3}, fill: @prompt_color)
  # end

  def right_pointing_triangle(graph, %{
        top_left: %{x: _x, y: _y} = pin,
        height: height,
        color: color
      }) do
    # NOTE: How Scenic draws triangles
    #      --------------------------
    #      Scenic uses 3 points to draw a triangle, which look like this:
    #
    #           x - point1 (This is the `pin`)
    #           |\
    #           | \ x - point2 (apex of triangle)
    #           | /
    #           |/
    #           x - point3
    #
    #       remember that Scenic draws from the top-left, so adding
    #       to a value means going down the screen.
    point1 = {pin.x, pin.y}
    point2 = {pin.x + 0.67 * height, pin.y + height / 2}
    point3 = {pin.x, pin.y + height}

    graph
    |> Scenic.Primitives.triangle({point1, point2, point3}, fill: color)
  end

  def prompt_width(prompt_size) do
    prompt_size * 0.67
  end
end
