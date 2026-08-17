defmodule QuillEx.GUI.Themes do
  # this is my color pallete that I made up...
  @midnight_pallette %{
    # I made this one up...
    black_outliner: {40, 33, 40},
    # 2596be
    primary: {37, 150, 190},
    # 292931
    dark: {41, 41, 49},
    # 778899
    slate: {119, 136, 153},
    # a7a3bb
    gray: {167, 163, 187},
    # c1937a
    light_brown: {193, 147, 122},
    # 6c6d7b
    dark_gray: {108, 109, 123},
    # 8fb27b
    light_green: {143, 178, 123},
    # 28df28
    nuclear_green: {40, 233, 40},
    # 78584f
    brown: {120, 88, 79},
    # 4b4d5c
    rly_dark_gray: {75, 77, 92},
    # 533432
    red_brown: {83, 52, 50},
    # 556c4d
    green: {85, 108, 77},
    # 6694da
    blue: {102, 148, 218}
  }

  @solarized %{
    dark_background_01: {0, 43, 54},
    dark_background_02: {7, 54, 66},
    base_content_01: {88, 110, 117},
    base_content_02: {101, 123, 131},
    base_content_03: {131, 148, 150},
    base_content_04: {147, 161, 161},
    light_background_01: {238, 232, 213},
    light_background_02: {253, 246, 227},
    accent_yellow: {181, 137, 0},
    accent_orange: {203, 75, 22},
    accent_red: {220, 50, 47},
    accent_magenta: {211, 54, 130},
    accent_violet: {108, 113, 196},
    accent_blue: {38, 139, 210},
    accent_cyan: {42, 161, 152},
    accent_green: {133, 153, 0}
  }

  @dracula %{
    background: {40, 42, 54},
    current_line: {68, 71, 90},
    selection: {68, 71, 90},
    foreground: {248, 248, 242},
    comment: {98, 114, 164},
    cyan: {139, 233, 253},
    green: {80, 250, 123},
    orange: {255, 184, 108},
    pink: {255, 121, 198},
    purple: {189, 147, 249},
    red: {255, 85, 85},
    yellow: {241, 250, 140}
  }

  def theme(:solarized_light) do
    %{
      # background
      bg: @solarized.light_background_01,
      bg2: @solarized.light_background_02,
      # foreground
      fg: @solarized.base_content_01,
      fg2: @solarized.base_content_01,
      # base
      base1: @solarized.base_content_01,
      base2: @solarized.base_content_01,
      base3: @solarized.base_content_01,
      base4: @solarized.base_content_01,
      # accent
      accent1: @solarized.accent_yellow,
      accent2: @solarized.accent_orange,
      accent3: @solarized.accent_red,
      accent4: @solarized.accent_magenta,
      accent5: @solarized.accent_violet,
      accent6: @solarized.accent_blue,
      accent7: @solarized.accent_cyan,
      accent8: @solarized.accent_green
    }
  end

  def scenic_light,
    do: %{
      text: :black,
      background: :white,
      border: :dark_grey,
      active: {215, 215, 215},
      thumb: :cornflower_blue,
      focus: :blue,
      highlight: :saddle_brown
    }

  def midnight_shadow,
    do: %{
      text: @midnight_pallette.nuclear_green,
      background: @midnight_pallette.dark_gray,
      border: @midnight_pallette.rly_dark_gray,
      active: @midnight_pallette.light_green,
      thumb: @midnight_pallette.red_brown,
      focus: @midnight_pallette.blue,
      highlight: @midnight_pallette.primary,

      # these below are the extended colours

      extended: %{
        black_outliner: @midnight_pallette.black_outliner,
        primary: @midnight_pallette.primary,
        dark: @midnight_pallette.dark,
        slate: @midnight_pallette.slate,
        gray: @midnight_pallette.gray,
        light_brown: @midnight_pallette.light_brown,
        dark_gray: @midnight_pallette.dark_gray,
        light_green: @midnight_pallette.light_green,
        nuclear_green: @midnight_pallette.nuclear_green,
        brown: @midnight_pallette.brown,
        rly_dark_gray: @midnight_pallette.rly_dark_gray,
        red_brown: @midnight_pallette.red_brown,
        green: @midnight_pallette.green,
        blue: @midnight_pallette.blue
      }
    }

  # def midnight_shadow,
  #   do: %{
  #     # 9ca5b6
  #     text: {156, 165, 182},
  #     # 282b33
  #     background: {40, 43, 51},
  #     # 202329
  #     border: {32, 35, 41},
  #     # 6694da
  #     focus: {102, 148, 218},
  #     # e3c18a
  #     highlight: {227, 193, 138}
  #   }
end
