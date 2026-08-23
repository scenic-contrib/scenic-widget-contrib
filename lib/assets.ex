defmodule ScenicWidgets.Assets do
  use Scenic.Assets.Static,
    otp_app: :scenic_widget_contrib,
    alias: [
      ibm_plex_mono: "fonts/IBMPlexMono-Regular.ttf"
    ]
end
