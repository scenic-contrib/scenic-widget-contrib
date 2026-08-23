defmodule ScenicWidgets.ScenicEventsDefinitions do
  @moduledoc """
  Contains module attribute definitions of all the Scenic input events.

  Example:

  ```
  defmodule SomeModule do
    use ScenicWidgets.ScenicEventsDefinitions

    ...

    handle_cast(@left_shift, state)
      ..

  ```

  Simply `use` this module to apply the macro that will bind all these
  constants, which match up to Scenic inputs, inside that module.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      # key-state numbers
      # These are the numbers used by Scenic to represent the
      # state of a key-press. I just prefer to use these names,
      # so I bind them here.
      # @key_pressed 0
      # @key_released 1

      # I think on mac & Linux these are reversed :(
      @key_pressed 1
      @key_released 0
      @key_held 2

      # for mouse-related events, e.g. `{:cursor_button, {:btn_left, 1, [], _coords}}`
      @click 1
      @clicked @click
      @release_click 0
      @un_click @release_click

      @space_bar {:key, {:key_space, @key_pressed, []}}

      @left_shift {:key, {:key_leftshift, @key_pressed, []}}
      @right_shift {:key, {:key_rightshift, @key_pressed, []}}
      @left_ctrl {:key, {:key_leftctrl, @key_pressed, []}}
      @right_ctrl {:key, {:key_rightctrl, @key_pressed, []}}
      @left_alt_dn {:key, {:key_leftalt, @key_pressed, []}}
      @left_alt_up {:key, {:key_leftalt, @key_released, [:alt]}}
      @right_alt {:key, {:key_rightalt, @key_pressed, []}}
      # in macOS the meta-key registers as :key_unknown, but appears as [:meta] in a keypress combination still
      @meta {:key, {:key_unknown, @key_pressed, []}}

      @left_ctrl_dn {:key, {:key_leftctrl, @key_pressed, []}}
      @left_ctrl_up {:key, {:key_leftctrl, @key_released, [:ctrl]}}

      @left_shift_up {:key, {:key_leftshift, @key_released, [:shift]}}

      @escape_key {:key, {:key_esc, @key_pressed, []}}
      @tab_key {:key, {:key_tab, @key_pressed, []}}

      @enter_key_dn {:key, {:key_enter, @key_pressed, []}}
      # @enter_key_up {:key, {:key_enter, @key_released, []}}
      @enter_key @enter_key_dn
      @enter @enter_key_dn

      @keypad_enter {:key, {:key_kpenter, @key_pressed, []}}

      @backspace_key_dn {:key, {:key_backspace, @key_pressed, []}}
      # @backspace_key_up {:key, {:key_backspace, @key_released, []}}
      @backspace_key @backspace_key_dn
      @backspace @backspace_key_dn

      @shift_space {:key, {:key_space, @key_pressed, [:shift]}}
      @shift_tab {:key, {:key_tab, @key_pressed, [:shift]}}
      @shift_enter {:key, {:key_enter, @key_pressed, [:shift]}}

      @up_arrow {:key, {:key_up, @key_pressed, []}}
      @left_arrow {:key, {:key_left, @key_pressed, []}}
      @down_arrow {:key, {:key_down, @key_pressed, []}}
      @right_arrow {:key, {:key_right, @key_pressed, []}}

      @number_0 {:key, {:key_0, @key_pressed, []}}
      @number_1 {:key, {:key_1, @key_pressed, []}}
      @number_2 {:key, {:key_2, @key_pressed, []}}
      @number_3 {:key, {:key_3, @key_pressed, []}}
      @number_4 {:key, {:key_4, @key_pressed, []}}
      @number_5 {:key, {:key_5, @key_pressed, []}}
      @number_6 {:key, {:key_6, @key_pressed, []}}
      @number_7 {:key, {:key_7, @key_pressed, []}}
      @number_8 {:key, {:key_8, @key_pressed, []}}
      @number_9 {:key, {:key_9, @key_pressed, []}}

      @all_numbers [
        @number_0,
        @number_1,
        @number_2,
        @number_3,
        @number_4,
        @number_5,
        @number_6,
        @number_7,
        @number_8,
        @number_9
      ]

      @number_keys @all_numbers

      @lowercase_a {:key, {:key_a, @key_pressed, []}}
      @lowercase_b {:key, {:key_b, @key_pressed, []}}
      @lowercase_c {:key, {:key_c, @key_pressed, []}}
      @lowercase_d {:key, {:key_d, @key_pressed, []}}
      @lowercase_e {:key, {:key_e, @key_pressed, []}}
      @lowercase_f {:key, {:key_f, @key_pressed, []}}
      @lowercase_g {:key, {:key_g, @key_pressed, []}}
      @lowercase_h {:key, {:key_h, @key_pressed, []}}
      @lowercase_i {:key, {:key_i, @key_pressed, []}}
      @lowercase_j {:key, {:key_j, @key_pressed, []}}
      @lowercase_k {:key, {:key_k, @key_pressed, []}}
      @lowercase_l {:key, {:key_l, @key_pressed, []}}
      @lowercase_m {:key, {:key_m, @key_pressed, []}}
      @lowercase_n {:key, {:key_n, @key_pressed, []}}
      @lowercase_o {:key, {:key_o, @key_pressed, []}}
      @lowercase_p {:key, {:key_p, @key_pressed, []}}
      @lowercase_q {:key, {:key_q, @key_pressed, []}}
      @lowercase_r {:key, {:key_r, @key_pressed, []}}
      @lowercase_s {:key, {:key_s, @key_pressed, []}}
      @lowercase_t {:key, {:key_t, @key_pressed, []}}
      @lowercase_u {:key, {:key_u, @key_pressed, []}}
      @lowercase_v {:key, {:key_v, @key_pressed, []}}
      @lowercase_w {:key, {:key_w, @key_pressed, []}}
      @lowercase_x {:key, {:key_x, @key_pressed, []}}
      @lowercase_y {:key, {:key_y, @key_pressed, []}}
      @lowercase_z {:key, {:key_z, @key_pressed, []}}

      @uppercase_A {:key, {:key_a, @key_pressed, [:shift]}}
      @uppercase_B {:key, {:key_b, @key_pressed, [:shift]}}
      @uppercase_C {:key, {:key_c, @key_pressed, [:shift]}}
      @uppercase_D {:key, {:key_d, @key_pressed, [:shift]}}
      @uppercase_E {:key, {:key_e, @key_pressed, [:shift]}}
      @uppercase_F {:key, {:key_f, @key_pressed, [:shift]}}
      @uppercase_G {:key, {:key_g, @key_pressed, [:shift]}}
      @uppercase_H {:key, {:key_h, @key_pressed, [:shift]}}
      @uppercase_I {:key, {:key_i, @key_pressed, [:shift]}}
      @uppercase_J {:key, {:key_j, @key_pressed, [:shift]}}
      @uppercase_K {:key, {:key_k, @key_pressed, [:shift]}}
      @uppercase_L {:key, {:key_l, @key_pressed, [:shift]}}
      @uppercase_M {:key, {:key_m, @key_pressed, [:shift]}}
      @uppercase_N {:key, {:key_n, @key_pressed, [:shift]}}
      @uppercase_O {:key, {:key_o, @key_pressed, [:shift]}}
      @uppercase_P {:key, {:key_p, @key_pressed, [:shift]}}
      @uppercase_Q {:key, {:key_q, @key_pressed, [:shift]}}
      @uppercase_R {:key, {:key_r, @key_pressed, [:shift]}}
      @uppercase_S {:key, {:key_s, @key_pressed, [:shift]}}
      @uppercase_T {:key, {:key_t, @key_pressed, [:shift]}}
      @uppercase_U {:key, {:key_u, @key_pressed, [:shift]}}
      @uppercase_V {:key, {:key_v, @key_pressed, [:shift]}}
      @uppercase_W {:key, {:key_w, @key_pressed, [:shift]}}
      @uppercase_X {:key, {:key_x, @key_pressed, [:shift]}}
      @uppercase_Y {:key, {:key_y, @key_pressed, [:shift]}}
      @uppercase_Z {:key, {:key_z, @key_pressed, [:shift]}}

      @lowercase_letters [
        @lowercase_a,
        @lowercase_b,
        @lowercase_c,
        @lowercase_d,
        @lowercase_e,
        @lowercase_f,
        @lowercase_g,
        @lowercase_h,
        @lowercase_i,
        @lowercase_j,
        @lowercase_k,
        @lowercase_l,
        @lowercase_m,
        @lowercase_n,
        @lowercase_o,
        @lowercase_p,
        @lowercase_q,
        @lowercase_r,
        @lowercase_s,
        @lowercase_t,
        @lowercase_u,
        @lowercase_v,
        @lowercase_w,
        @lowercase_x,
        @lowercase_y,
        @lowercase_z
      ]

      @uppercase_letters [
        @uppercase_A,
        @uppercase_B,
        @uppercase_C,
        @uppercase_D,
        @uppercase_E,
        @uppercase_F,
        @uppercase_G,
        @uppercase_H,
        @uppercase_I,
        @uppercase_J,
        @uppercase_K,
        @uppercase_L,
        @uppercase_M,
        @uppercase_N,
        @uppercase_O,
        @uppercase_P,
        @uppercase_Q,
        @uppercase_R,
        @uppercase_S,
        @uppercase_T,
        @uppercase_U,
        @uppercase_V,
        @uppercase_W,
        @uppercase_X,
        @uppercase_Y,
        @uppercase_Z
      ]

      @all_letters @lowercase_letters ++ @uppercase_letters

      @ctrl_s {:key, {:key_s, @key_pressed, [:ctrl]}}
      @ctrl_h {:key, {:key_h, @key_pressed, [:ctrl]}}
      @ctrl_a {:key, {:key_a, @key_pressed, [:ctrl]}}
      @ctrl_c {:key, {:key_c, @key_pressed, [:ctrl]}}
      @ctrl_v {:key, {:key_v, @key_pressed, [:ctrl]}}
      @ctrl_x {:key, {:key_x, @key_pressed, [:ctrl]}}
      @ctrl_f {:key, {:key_f, @key_pressed, [:ctrl]}}
      @ctrl_g {:key, {:key_g, @key_pressed, [:ctrl]}}
      @ctrl_u {:key, {:key_u, @key_pressed, [:ctrl]}}
      @ctrl_r {:key, {:key_r, @key_pressed, [:ctrl]}}

      @backtick {:key, {:key_grave, @key_pressed, []}}
      @tilde {:key, {:key_grave, @key_pressed, [:shift]}}
      @bang {:key, {:key_1, @key_pressed, [:shift]}}
      @asperand {:key, {:key_2, @key_pressed, [:shift]}}
      @hash {:key, {:key_3, @key_pressed, [:shift]}}
      @dollar_sign {:key, {:key_4, @key_pressed, [:shift]}}
      @percent_sign {:key, {:key_5, @key_pressed, [:shift]}}
      @caret {:key, {:key_6, @key_pressed, [:shift]}}
      @ampersand {:key, {:key_7, @key_pressed, [:shift]}}
      @asterisk {:key, {:key_8, @key_pressed, [:shift]}}
      @left_parenthesis {:key, {:key_9, @key_pressed, [:shift]}}
      @right_parenthesis {:key, {:key_0, @key_pressed, [:shift]}}
      @minus_sign {:key, {:key_minus, @key_pressed, []}}
      @underscore {:key, {:key_minus, @key_pressed, [:shift]}}
      @equals_sign {:key, {:key_equal, @key_pressed, []}}
      @plus_sign {:key, {:key_equal, @key_pressed, [:shift]}}
      @left_square_bracket {:key, {:key_leftbrace, @key_pressed, []}}
      @right_square_bracket {:key, {:key_rightbrace, @key_pressed, []}}
      @left_brace {:key, {:key_leftbrace, @key_pressed, [:shift]}}
      @right_brace {:key, {:key_rightbrace, @key_pressed, [:shift]}}
      @backslash {:key, {:key_backslash, @key_pressed, []}}
      @pipe {:key, {:key_backslash, @key_pressed, [:shift]}}
      @semicolon {:key, {:key_semicolon, @key_pressed, []}}
      @colon {:key, {:key_semicolon, @key_pressed, [:shift]}}
      @apostrophe {:key, {:key_apostrophe, @key_pressed, []}}
      @quotation {:key, {:key_apostrophe, @key_pressed, [:shift]}}
      @comma {:key, {:key_comma, @key_pressed, []}}
      @less_than {:key, {:key_comma, @key_pressed, [:shift]}}
      @period {:key, {:key_dot, @key_pressed, []}}
      @greater_than {:key, {:key_dot, @key_pressed, [:shift]}}
      @forward_slash {:key, {:key_slash, @key_pressed, []}}
      @question_mark {:key, {:key_slash, @key_pressed, [:shift]}}

      @all_punctuation [
        @backtick,
        @tilde,
        @bang,
        @asperand,
        @hash,
        @dollar_sign,
        @percent_sign,
        @caret,
        @ampersand,
        @asterisk,
        @left_parenthesis,
        @right_parenthesis,
        @minus_sign,
        @underscore,
        @equals_sign,
        @plus_sign,
        @left_square_bracket,
        @right_square_bracket,
        @left_brace,
        @right_brace,
        @backslash,
        @pipe,
        @semicolon,
        @colon,
        @apostrophe,
        @quotation,
        @comma,
        @less_than,
        @period,
        @greater_than,
        @forward_slash,
        @question_mark
      ]

      @left_arrow {:key, {:key_left, @key_pressed, []}}
      @right_arrow {:key, {:key_right, @key_pressed, []}}
      @up_arrow {:key, {:key_up, @key_pressed, []}}
      @down_arrow {:key, {:key_down, @key_pressed, []}}

      @arrow_keys [@left_arrow, @right_arrow, @up_arrow, @down_arrow]

      # Shift+Arrow keys for text selection
      @shift_left_arrow {:key, {:key_left, @key_pressed, [:shift]}}
      @shift_right_arrow {:key, {:key_right, @key_pressed, [:shift]}}
      @shift_up_arrow {:key, {:key_up, @key_pressed, [:shift]}}
      @shift_down_arrow {:key, {:key_down, @key_pressed, [:shift]}}

      @shift_arrow_keys [@shift_left_arrow, @shift_right_arrow, @shift_up_arrow, @shift_down_arrow]

      @home_key {:key, {:key_home, @key_pressed, []}}
      @end_key {:key, {:key_end, @key_pressed, []}}
      @delete_key {:key, {:key_delete, @key_pressed, []}}

      @valid_text_input_characters @all_letters ++
                                     @all_numbers ++
                                     @all_punctuation ++
                                     [
                                       @space_bar,
                                       @enter_key
                                     ]

      @meta_lowercase_s {:key, {:key_s, @key_pressed, [:meta]}}

      # opacity or alpha is given as Hex values in Scenic, these are for convenience
      @zero_percent_opaque 0x00
      @one_percent_opaque 0x03
      @two_percent_opaque 0x05
      @three_percent_opaque 0x08
      @four_percent_opaque 0x0A
      @five_percent_opaque 0x0D
      @six_percent_opaque 0x0F
      @seven_percent_opaque 0x12
      @eight_percent_opaque 0x14
      @nine_percent_opaque 0x17
      @ten_percent_opaque 0x1A
      @eleven_percent_opaque 0x1C
      @twelve_percent_opaque 0x1F
      @thirteen_percent_opaque 0x21
      @fourteen_percent_opaque 0x24
      @fifteen_percent_opaque 0x26
      @sixteen_percent_opaque 0x29
      @seventeen_percent_opaque 0x2B
      @eighteen_percent_opaque 0x2E
      @nineteen_percent_opaque 0x30
      @twenty_percent_opaque 0x33
      @twenty_one_percent_opaque 0x36
      @twenty_two_percent_opaque 0x38
      @twenty_three_percent_opaque 0x3B
      @twenty_four_percent_opaque 0x3D
      @twenty_five_percent_opaque 0x40
      @twenty_six_percent_opaque 0x42
      @twenty_seven_percent_opaque 0x45
      @twenty_eight_percent_opaque 0x47
      @twenty_nine_percent_opaque 0x4A
      @thirty_percent_opaque 0x4D
      @thirty_one_percent_opaque 0x4F
      @thirty_two_percent_opaque 0x52
      @thirty_three_percent_opaque 0x54
      @thirty_four_percent_opaque 0x57
      @thirty_five_percent_opaque 0x59
      @thirty_six_percent_opaque 0x5C
      @thirty_seven_percent_opaque 0x5E
      @thirty_eight_percent_opaque 0x61
      @thirty_nine_percent_opaque 0x63
      @forty_percent_opaque 0x66
      @forty_one_percent_opaque 0x69
      @forty_two_percent_opaque 0x6B
      @forty_three_percent_opaque 0x6E
      @forty_four_percent_opaque 0x70
      @forty_five_percent_opaque 0x73
      @forty_six_percent_opaque 0x75
      @forty_seven_percent_opaque 0x78
      @forty_eight_percent_opaque 0x7A
      @forty_nine_percent_opaque 0x7D
      @fifty_percent_opaque 0x80
      @fifty_one_percent_opaque 0x82
      @fifty_two_percent_opaque 0x85
      @fifty_three_percent_opaque 0x87
      @fifty_four_percent_opaque 0x8A
      @fifty_five_percent_opaque 0x8C
      @fifty_six_percent_opaque 0x8F
      @fifty_seven_percent_opaque 0x92
      @fifty_eight_percent_opaque 0x94
      @fifty_nine_percent_opaque 0x97
      @sixty_percent_opaque 0x99
      @sixty_one_percent_opaque 0x9C
      @sixty_two_percent_opaque 0x9E
      @sixty_three_percent_opaque 0xA1
      @sixty_four_percent_opaque 0xA3
      @sixty_five_percent_opaque 0xA6
      @sixty_six_percent_opaque 0xA9
      @sixty_seven_percent_opaque 0xAB
      @sixty_eight_percent_opaque 0xAE
      @sixty_nine_percent_opaque 0xB0
      @seventy_percent_opaque 0xB3
      @seventy_one_percent_opaque 0xB5
      @seventy_two_percent_opaque 0xB8
      @seventy_three_percent_opaque 0xBA
      @seventy_four_percent_opaque 0xBD
      @seventy_five_percent_opaque 0xBF
      @seventy_six_percent_opaque 0xC2
      @seventy_seven_percent_opaque 0xC5
      @seventy_eight_percent_opaque 0xC7
      @seventy_nine_percent_opaque 0xCA
      @eighty_percent_opaque 0xCC
      @eighty_one_percent_opaque 0xCF
      @eighty_two_percent_opaque 0xD1
      @eighty_three_percent_opaque 0xD4
      @eighty_four_percent_opaque 0xD6
      @eighty_five_percent_opaque 0xD9
      @eighty_six_percent_opaque 0xDB
      @eighty_seven_percent_opaque 0xDE
      @eighty_eight_percent_opaque 0xE1
      @eighty_nine_percent_opaque 0xE3
      @ninety_percent_opaque 0xE6
      @ninety_one_percent_opaque 0xE8
      @ninety_two_percent_opaque 0xEB
      @ninety_three_percent_opaque 0xED
      @ninety_four_percent_opaque 0xF0
      @ninety_five_percent_opaque 0xF2
      @ninety_six_percent_opaque 0xF5
      @ninety_seven_percent_opaque 0xF8
      @ninety_eight_percent_opaque 0xFA
      @ninety_nine_percent_opaque 0xFD
      @hundred_percent_opaque 0xFF

      ## convert a keystroke into a string - used for inputing text

      def key2string(@number_0), do: "0"
      def key2string(@number_1), do: "1"
      def key2string(@number_2), do: "2"
      def key2string(@number_3), do: "3"
      def key2string(@number_4), do: "4"
      def key2string(@number_5), do: "5"
      def key2string(@number_6), do: "6"
      def key2string(@number_7), do: "7"
      def key2string(@number_8), do: "8"
      def key2string(@number_9), do: "9"

      def key2string(@lowercase_a), do: "a"
      def key2string(@lowercase_b), do: "b"
      def key2string(@lowercase_c), do: "c"
      def key2string(@lowercase_d), do: "d"
      def key2string(@lowercase_e), do: "e"
      def key2string(@lowercase_f), do: "f"
      def key2string(@lowercase_g), do: "g"
      def key2string(@lowercase_h), do: "h"
      def key2string(@lowercase_i), do: "i"
      def key2string(@lowercase_j), do: "j"
      def key2string(@lowercase_k), do: "k"
      def key2string(@lowercase_l), do: "l"
      def key2string(@lowercase_m), do: "m"
      def key2string(@lowercase_n), do: "n"
      def key2string(@lowercase_o), do: "o"
      def key2string(@lowercase_p), do: "p"
      def key2string(@lowercase_q), do: "q"
      def key2string(@lowercase_r), do: "r"
      def key2string(@lowercase_s), do: "s"
      def key2string(@lowercase_t), do: "t"
      def key2string(@lowercase_u), do: "u"
      def key2string(@lowercase_v), do: "v"
      def key2string(@lowercase_w), do: "w"
      def key2string(@lowercase_x), do: "x"
      def key2string(@lowercase_y), do: "y"
      def key2string(@lowercase_z), do: "z"

      def key2string(@uppercase_A), do: "A"
      def key2string(@uppercase_B), do: "B"
      def key2string(@uppercase_C), do: "C"
      def key2string(@uppercase_D), do: "D"
      def key2string(@uppercase_E), do: "E"
      def key2string(@uppercase_F), do: "F"
      def key2string(@uppercase_G), do: "G"
      def key2string(@uppercase_H), do: "H"
      def key2string(@uppercase_I), do: "I"
      def key2string(@uppercase_J), do: "J"
      def key2string(@uppercase_K), do: "K"
      def key2string(@uppercase_L), do: "L"
      def key2string(@uppercase_M), do: "M"
      def key2string(@uppercase_N), do: "N"
      def key2string(@uppercase_O), do: "O"
      def key2string(@uppercase_P), do: "P"
      def key2string(@uppercase_Q), do: "Q"
      def key2string(@uppercase_R), do: "R"
      def key2string(@uppercase_S), do: "S"
      def key2string(@uppercase_T), do: "T"
      def key2string(@uppercase_U), do: "U"
      def key2string(@uppercase_V), do: "V"
      def key2string(@uppercase_W), do: "W"
      def key2string(@uppercase_X), do: "X"
      def key2string(@uppercase_Y), do: "Y"
      def key2string(@uppercase_Z), do: "Z"

      def key2string(@space_bar), do: " "
      def key2string(@enter_key), do: "\n"

      def key2string(@backtick), do: "`"
      def key2string(@tilde), do: "~"
      def key2string(@bang), do: "!"
      def key2string(@asperand), do: "@"
      def key2string(@hash), do: "#"
      def key2string(@dollar_sign), do: "$"
      def key2string(@percent_sign), do: "%"
      def key2string(@caret), do: "^"
      def key2string(@ampersand), do: "&"
      def key2string(@asterisk), do: "*"
      def key2string(@left_parenthesis), do: "("
      def key2string(@right_parenthesis), do: ")"
      def key2string(@minus_sign), do: "-"
      def key2string(@underscore), do: "_"
      def key2string(@equals_sign), do: "="
      def key2string(@plus_sign), do: "+"
      def key2string(@left_square_bracket), do: "["
      def key2string(@right_square_bracket), do: "]"
      def key2string(@left_brace), do: "{"
      def key2string(@right_brace), do: "}"
      def key2string(@backslash), do: "\\"
      def key2string(@pipe), do: "|"
      def key2string(@semicolon), do: ";"
      def key2string(@colon), do: ":"
      def key2string(@apostrophe), do: "'"
      def key2string(@quotation), do: "\""
      def key2string(@comma), do: ","
      def key2string(@less_than), do: "<"
      def key2string(@period), do: "."
      def key2string(@greater_than), do: ">"
      def key2string(@forward_slash), do: "/"
      def key2string(@question_mark), do: "?"

      def key2string(x) do
        # NOTE: I originally had this here for debugging, but it raises
        #      an interesting question - maybe it's just one's personal
        #      style, but, should we put this catchall here? I guess that
        #      question becomes, do we want things to start crashing if
        #      we can't convert a key to it's known string.
        #
        #      On the one hand, obviously we are not able to process the
        #      original intent of the request - we have no direct way of
        #      mapping this key to it's actually intended string representation -
        #      and since we can't service the request, we should fail.
        #      Probably, an erlang purist would revert to the classic
        #      'let it crash!' maxim - but to me it's an engineering/design
        #      choice.
        #
        #      On the other hand, maybe that's not enough of a reason to
        #      fail! After all, we could just map it to something stupid
        #      like "X" or "?" or whatever (interestingly there's no
        #      character glyff for "null" on a standard modern keyboard !?)
        #
        #      Elsewhere within flamelex I have experienced the situation where
        #      sometimes I really want to see a detailed debug stacktrace, but
        #      other times that same stacktrack is noise - it depends on the level
        #      of abstraction that I'm on on any particular day. Having the ability
        #      to adjust the level of runtime failure has proven useful during development
        #
        #      I think the most fundamental truth about what I have learned
        #      from working with the BEAM is that it's important to understand
        #      and know how your program *will* fail, so you can design
        #      around that - which is the actual source of robust programs -
        #      good design. So should we fail here? The choice is yours~

        take_the_red_pill? = true

        if take_the_red_pill? do
          raise "Unable to convert #{inspect(x)} to a valid string."
        else
          "X"
        end
      end
    end
  end
end
