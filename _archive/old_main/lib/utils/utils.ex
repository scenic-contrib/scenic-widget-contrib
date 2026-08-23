defmodule QuillEx.Lib.Utils do
    
   # these functions are used to cap scrolling
   def apply_floor({x, y}, {min_x, min_y}) do
    {max(x, min_x), max(y, min_y)}
   end

   def apply_ceil({x, y}, {max_x, max_y}) do
      {min(x, max_x), min(y, max_y)}
   end

end