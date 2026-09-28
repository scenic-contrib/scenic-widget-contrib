import Config

config :scenic, :assets,
    module: ScenicWidgets.Assets

# Configure scenic_live_reload for development
if Mix.env() == :dev do
  config :scenic_live_reload,
    viewports: [
      %{
        name: :main_viewport,
        scenes: [
          {"lib/widget_workbench/widget_wkb_scene.ex", WidgetWorkbench.Scene},
          {"lib/widget_workbench", WidgetWorkbench.Scene},
          {"lib/widget_workbench/components", []}
        ]
      }
    ]
end

import_config "#{Mix.env()}.exs"
