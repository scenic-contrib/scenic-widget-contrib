import Config

config :scenic, :assets, module: ScenicWidgets.Assets

# Use different port and process names for test environment
# This allows dev and test viewports to run simultaneously
config :scenic_mcp,
  port: 9998,
  viewport_name: :test_viewport,  # Different from :main_viewport
  driver_name: :test_driver       # Different from :scenic_driver
