defmodule ScenicWidgets.Utils do
  @doc """
  Checks if a coordinate point (a tuple in the form `{x, y}`)
  is inside a bounding box, defined in the same format as
  (Scenic.bounds/1)[https://hexdocs.pm/scenic/0.11.0-beta.0/Scenic.Graph.html#bounds/1], `{left, top, right, bottom}`
  """
  def inside?({x, y}, {left, top, right, bottom} = _bounds) do
    # NOTE: Because the y axis starts at zero in the top-left, and
    # gets larger as we go down the page, it's a little counter-intuitive
    # to calculate if we're inside the bounds
    x >= left and x <= right and (y >= top and y <= bottom)
  end

  # this clause is here because if the %Scenic.Graph{} is empty, bounds returns nil
  def inside?(_coords, nil = _bounds) do
    false
  end
end





# defmodule Flamelex.GUI.GeometryLib.Trigonometry do
#   use Flamelex.ProjectAliases


#     #NOTE: How Scenic draws triangles
#     #      --------------------------
#     #      Scenic uses 3 points to draw a triangle, which look like this:
#     #
#     #           x - point1
#     #           |\
#     #           | \ x - point2 (apex of triangle)
#     #           | /
#     #           |/
#     #           x - point


#   def equilateral_triangle_coords(%Coordinates{} = centroid, centroid_to_vertex_length, _rotation \\ 0) do
#     cvl = centroid_to_vertex_length # for convenience

#     {
#       {centroid.x - :math.sqrt(3) * cvl / 2, centroid.y + cvl/2},
#       {centroid.x, centroid.y - cvl},
#       {centroid.x + :math.sqrt(3) * cvl / 2, centroid.y + cvl/2}
#     }
#   end
# end
