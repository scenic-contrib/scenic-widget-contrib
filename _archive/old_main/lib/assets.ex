defmodule QuillEx.Assets do
  use Scenic.Assets.Static,
    otp_app: :quillex,
    alias: [
      ibm_plex_mono: "fonts/IBMPlexMono-Regular.ttf",
      iosevka: "fonts/iosevka-etoile-regular.ttf",
      source_code_pro: "fonts/SourceCodePro-Regular.ttf",
      fira_code: "fonts/FiraCode-Regular.ttf",
      bitter: "fonts/Bitter-Regular.ttf"
    ]
end
