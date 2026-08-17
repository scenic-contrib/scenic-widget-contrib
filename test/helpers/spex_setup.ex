defmodule ScenicWidgets.SpexSetup do
  @moduledoc """
  Shared setup for spex tests. Starts the scenic_widget_contrib application
  and a Widget Workbench viewport, following the quillex pattern of
  centralizing lifecycle management.

  Usage in a spex file:

      setup_all do
        ScenicWidgets.SpexSetup.ensure_workbench_started!()
      end
  """

  def ensure_workbench_started! do
    # Use the same viewport/driver names ScenicMcp.Config resolves to, so the
    # viewport we boot here is the one ScenicMcp.Query/Probes will find. These
    # are overridden in config/test.exs (:test_viewport / :test_driver) so a
    # test run doesn't collide with a dev instance's :main_viewport.
    viewport_name = ScenicMcp.Config.viewport_name()
    driver_name = ScenicMcp.Config.driver_name()

    case Application.ensure_all_started(:scenic_widget_contrib) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
      {:error, reason} -> raise "Failed to start scenic_widget_contrib: #{inspect(reason)}"
    end

    unless Process.whereis(viewport_name) do
      viewport_config = [
        name: viewport_name,
        size: {1200, 800},
        theme: :dark,
        default_scene: {WidgetWorkbench.Scene, []},
        drivers: [
          [
            module: Scenic.Driver.Local,
            name: driver_name,
            window: [
              resizeable: true,
              title: "Widget Workbench - Spex"
            ],
            on_close: :stop_viewport,
            cursor: true,
            antialias: true
          ]
        ]
      ]

      {:ok, _pid} = Scenic.ViewPort.start_link(viewport_config)
    end

    Process.sleep(2000)
    :ok
  end
end
