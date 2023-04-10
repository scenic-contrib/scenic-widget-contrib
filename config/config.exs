import Config

config :scenic, :assets,
    module: ScenicWidgets.Assets

import_config "#{Mix.env()}.exs"
