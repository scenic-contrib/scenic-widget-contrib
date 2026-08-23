defmodule QuillEx.Fluxus.Structs.RadixState do
  # defmodule Root do
  #   defstruct active_app: :editor

  #   @type t :: %__MODULE__{
  #           layout: atom()
  #           components: []
  #         }
  # end

  # defmodule GUI do
  #   defstruct viewport: nil

  #   @type t :: %__MODULE__{
  #           viewport: any()
  #         }
  # end

  # defmodule Desktop do
  #   defmodule MenuBar do
  #     defstruct height: 60,
  #               button_width: 180,
  #               font: nil

  #     @type t :: %__MODULE__{
  #             height: integer(),
  #             button_width: integer(),
  #             font: Font.t()
  #           }
  #   end

  #   defstruct menu_bar: nil

  #   @type t :: %__MODULE__{
  #           menu_bar: MenuBar.t()
  #         }
  # end

  # defmodule Editor do
  #   defstruct font: nil,
  #             buffers: [],
  #             active_buf: nil,
  #             config: nil

  #   @type t :: %__MODULE__{
  #           font: Font.t(),
  #           buffers: list(any()),
  #           active_buf: any(),
  #           config: Config.t()
  #         }

  #   defmodule Config do
  #     defstruct scroll: nil

  #     @type t :: %__MODULE__{
  #             scroll: Scroll.t()
  #           }

  #     defmodule Scroll do
  #       defstruct speed: nil

  #       @type t :: %__MODULE__{
  #               speed: Speed.t()
  #             }

  #       defmodule Speed do
  #         defstruct horizontal: 5,
  #                   vertical: 3

  #         @type t :: %__MODULE__{
  #                 horizontal: integer(),
  #                 vertical: integer()
  #               }
  #       end
  #     end
  #   end
  # end

  # defstruct root: %Root{},
  # defstruct root: nil
  # gui: nil,
  # desktop: nil,
  # editor: nil

  alias QuillEx.GUI.Components.PlainText
  alias QuillEx.GUI.Components.PlainTextScrollable

  @default_theme QuillEx.GUI.Themes.theme(:solarized_light)

  defstruct layout: nil,
            components: [],
            lateral: false,
            theme: @default_theme

  # menu_bar: %{
  #   height: nil
  # }

  # @type t :: %__MODULE__{
  #         # root: Root.t()
  #         layout: atom(),
  #         components: list()
  #         # gui: GUI.t(),
  #         # desktop: Desktop.t(),
  #         # editor: Editor.t()
  #       }

  # alias ScenicWidgets.TextPad.Structs.Font

  # how much vertical real estate we devote to the menu bar
  @menubar_height 60

  def new do
    new(%{theme: @default_theme})
  end

  def new(%{theme: _t} = args) do
    # text =
    #   ~s|# {:ok, {_type, ibm_plex_mono_font_metrics}} = Scenic.Assets.Static.meta(:ibm_plex_mono)
    # # font = Font.new(name: :ibm_plex_mono, size: 24, metrics: ibm_plex_mono_font_metrics)
    # # menu_font = Font.new(name: :ibm_plex_mono, size: 36, metrics: ibm_plex_mono_font_metrics)
    # |

    # convert a %Layout{} into a list/stack/tree of frames, which will get zipped with components

    %__MODULE__{
      # layout: :full_screen,
      # layout: :v_split,
      layout: {:vertical_split, {60, :px}},
      # layout: {:horizontal_split, {60, :px}},
      # layout: {:vertical_split, {0.17, :ratio}},
      # layout: {:standard_rule, linemark: @menubar_height},
      components: [
        # %ScenicWidgets.MenuBar{},
        ScenicWidgets.UbuntuBar.new(%{theme: args.theme})
        # PlainText.draw(text)
        # TODO simply put 2 components in a list, to reflect nested components
        # %QuillEx.GUI.Components.PlainText{text: text, color: :pink}
        # %QuillEx.GUI.Components.PlainText{text: "Second buffer!!", color: :grey}
        # %QuillEx.GUI.Components.EditorTwo{text: "Second buffer!!", color: :yellow}
      ],
      lateral: false,
      theme: args.theme
      # root: %Root{}
      # gui: %GUI{},
      # desktop: %Desktop{menu_bar: %Desktop.MenuBar{font: menu_font}},
      # editor: %Editor{font: font, config: %Editor.Config{scroll: %Editor.Config.Scroll{}}}
    }
  end

  def show_text_pane(%__MODULE__{} = rdx_state) do
    new_components = [
      ScenicWidgets.UbuntuBar.new(rdx_state),
      PlainText.draw(:one, ~s|Hello world!|)
    ]

    Map.put(rdx_state, :components, new_components)
  end

  def show_text_pane_two(%__MODULE__{} = rdx_state) do
    text = File.read!("test/support/spinozas_ethics_p1.txt")

    new_components = [
      ScenicWidgets.UbuntuBar.new(rdx_state),
      PlainText.draw(:two, text)
    ]

    Map.put(rdx_state, :components, new_components)
  end

  def show_text_pane_scrollable(%__MODULE__{} = rdx_state) do
    text = File.read!("test/support/spinozas_ethics_p1.txt")

    new_components = [
      ScenicWidgets.UbuntuBar.new(rdx_state),
      PlainTextScrollable.new(rdx_state, text)
    ]

    Map.put(rdx_state, :components, new_components)
  end

  @scroll_factor 3
  def scroll_editor(
        rdx_state,
        {:scroll, {{:cursor_scroll, {{delta_x, delta_y}, _coords}}, component_id}}
      ) do
    rdx_state
    |> update_component(component_id, fn component ->
      # TODO this is a hack, we need to be able to update the state of a component
      old_scroll = component.scroll
      fast_scroll = {0, @scroll_factor * delta_y}
      new_scroll = Scenic.Math.Vector2.add(old_scroll, fast_scroll)

      component |> Map.put(:scroll, new_scroll)
    end)
  end

  def minor_mode(%{lateral: false} = rdx_state, :lateral) do
    %{rdx_state | lateral: true}
    # |> update_component(:one, fn component ->
    #   component |> Map.put(:minor_mode, m)
    # end)
  end

  def minor_mode(rdx_state, nil) do
    %{rdx_state | lateral: false}
  end

  def update_component(%{components: components} = rdx_state, component_id, fun) do
    new_components =
      Enum.map(components, fn component ->
        # todo lol this one's brilliant
        if component.widgex.id == component_id do
          fun.(component)
        else
          component
        end
      end)

    Map.put(rdx_state, :components, new_components)
  end
end
