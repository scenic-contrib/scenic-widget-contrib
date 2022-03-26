defmodule ScenicWidgets.Core.Structs.Theme do
  @moduledoc """
  A Frame struct defines the rectangular size of a component.
  """

  # The default Theme is `light`
  defstruct active: {40, 40, 40},
            background: :black,
            border: :light_grey,
            focus: :cornflower_blue,
            highlight: :sandy_brown,
            text: :white,
            thumb: :cornflower_blue

  # def new(:dark) do

  # end

  def new(:hexdocs_light) do
    %__MODULE__{}
    |> Map.merge(%{background: :purple})
  end
end
