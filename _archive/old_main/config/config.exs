import Config

config :scenic, :assets, module: QuillEx.Assets

config :event_bus,
  topics: [
    :quill_ex_actions,
    :quill_ex_user_input
  ]

config :logger, level: :info

import_config "#{Mix.env()}.exs"
