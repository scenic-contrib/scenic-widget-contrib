defmodule ScenicWidgets.Utils do

  @doc """
  Checks if a coordinate point (a tuple in the form `{x, y}`)
  is inside a bounding box, defined in the same format as
  (Scenic.bounds/1)[https://hexdocs.pm/scenic/0.11.0-beta.0/Scenic.Graph.html#bounds/1],
  `{left, top, right, bottom}`
  """
  def inside?({x, y}, {left, top, right, bottom} = _bounds) do
    # NOTE: Because the y axis starts at zero in the top-left, and
    # gets larger as we go down the page, it's a little counter-intuitive
    # to calculate if we're inside the bounds
    (x >= left and x <= right) and (y >= top and y <= bottom)
  end
end
