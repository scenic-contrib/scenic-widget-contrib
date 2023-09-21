defmodule Widgex.ToyChest.Glyph do
  use Scenic.Component, has_children: false

  @impl Scenic.Component
  def validate(args) do
    {:ok, args}
  end

  @impl Scenic.Scene
  def init(scene, args, opts) do
    {:ok, scene}
  end
end
