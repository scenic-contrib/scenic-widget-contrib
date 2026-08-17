import Config

# Configure scenic_mcp to use port 9996 instead of 9999
config :scenic_mcp, :tcp_port, 9996
config :scenic_mcp, :port, 9996
config :scenic_mcp, :driver_name, :widget_wkb_scenic_driver

# Enable tidewave for development
config :scenic_widget_contrib, :environment, :dev

# Configure exsync for auto-reloading
config :exsync,
  src_monitor: true,
  reload_timeout: 75,
  logging_enabled: true
