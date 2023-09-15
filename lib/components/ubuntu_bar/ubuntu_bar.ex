defmodule ScenicWidgets.UbuntuBar do
  use Widgex.Component

  defstruct menu_map: nil,
            color: :grey

  def render(%__MODULE__{} = state, %Frame{} = frame) do
    # Logger.debug("#{__MODULE__} rendering...")
    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> render_background(state, frame)
      end,
      id: __MODULE__
    )
  end

  def render_background(
        %Scenic.Graph{} = graph,
        %__MODULE__{color: c} = state,
        %Frame{size: f_size}
      )
      when not is_nil(c) do
    graph
    |> Scenic.Primitives.rect(Dimensions.box(f_size),
      fill: state.color,
      opacity: 0.5
    )
  end
end
