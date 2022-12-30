defmodule ScenicWidgets.TextUtils do

    def v_pos(%{size: size, metrics: %{ascent: ascent, descent: descent}} = _font) do
        # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
        (size/1000) * (ascent/2 + descent/3)
    end

end
  