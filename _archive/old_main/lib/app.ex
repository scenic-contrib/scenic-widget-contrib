defmodule QuillEx.App do
  @moduledoc """
  QuillEx is a simple text-editor, written in Elixir, using the Scenic gfx lib.
  """

  def start(_type, _args) do
    # QuillEx.Metrics.Instrumenter.setup()

    # NOTE: The starting order here is important.
    # First we start the Registry beccause other processes depend on it.
    # Then we start RadixStore, it does not need to use the PubSub (and
    # won't try to broadcast during initialization) but the Root Scene
    # depends on it, it shall call the RadixStore and get the current
    # RadixState during initialization. Also all Listeners depend on both
    # the Registry and the RadixStore.
    children = [
      # QuillEx.Metrics.Stash,
      {Registry, keys: :duplicate, name: QuillEx.PubSub},
      QuillEx.Fluxus.RadixStore,
      {Scenic, [scenic_config()]},
      QuillEx.Fluxus.ActionListener,
      QuillEx.Fluxus.UserInputListener
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @window_title "QuillEx"
  @default_resolution {1680, 1005}
  def scenic_config() do
    [
      name: :main_viewport,
      size: @default_resolution,
      default_scene: {QuillEx.Scene.RootScene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          window: [
            title: @window_title,
            resizeable: true
          ],
          on_close: :stop_system
          # limit_ms: 500
        ]
      ]
    ]
  end
end
