defmodule ScenicWidgets.SpareParts.LukesTextField do
  @moduledoc """
  A re-usable text field component.
  """

  use Scenic.Component
  alias Scenic.Primitives

  def validate(%{frame: _frame} = data) do
    # For now, we assume a frame is passed correctly, add more validations later if needed.
    {:ok, data}
  end

  def init(scene, %{frame: frame, text: text} = _args, _opts) do
    graph =
      Scenic.Graph.build()
      |> Primitives.text(text,
        font_size: 20,
        translate: {frame.size.width / 2, frame.size.height / 2},
        text_align: :center
      )

    scene =
      scene
      |> assign(graph: graph)
      |> assign(frame: frame)
      |> assign(text: text)
      |> push_graph(graph)

    {:ok, scene}
  end
end
