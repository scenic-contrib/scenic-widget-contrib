defmodule ScenicWidgets.TextPad do
  use Scenic.Component
  require Logger
  use ScenicWidgets.ScenicEventsDefinitions
  alias ScenicWidgets.TextPad.Lib.RenderLib

  @default_font :roboto
  @default_font_size 24

  def validate(
        %{
          id: _id,
          frame: %ScenicWidgets.Core.Structs.Frame{} = _frame,
          text: text,
          mode: mode,
          format_opts: %{
            alignment: :left,
            # TODO this is what I'm working on, making it line-wrap
            wrap_opts: _wrap_opts,
            # TODO this too
            show_line_num?: show_line_num?
          }
        } = args
      )
      when is_bitstring(text) and
             mode in [:normal, :insert] and
             is_boolean(show_line_num?) do
    # Logger.debug("#{__MODULE__} accepted args: #{inspect(args)}")


    init_font_details =
      case Map.get(args, :font, :not_found) do
        %{name: font_name, size: font_size, metrics: %FontMetrics{} = _fm} = provided_details
        when is_atom(font_name) and is_integer(font_size) ->
          provided_details

        %{name: font_name, size: custom_font_size}
        when is_atom(font_name) and is_integer(custom_font_size) ->
          {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
          %{name: font_name, metrics: custom_font_metrics, size: custom_font_size}

        :not_found ->
          {:ok, {_type, default_font_metrics}} = Scenic.Assets.Static.meta(@default_font)
          %{name: @default_font, metrics: default_font_metrics, size: @default_font_size}

        font_name when is_atom(font_name) ->
          {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
          %{name: font_name, metrics: custom_font_metrics, size: @default_font_size}
      end

    final_args =
      args
      # default to zero
      |> Map.merge(%{cursor_pos: args |> Map.get(:cursor, 0)})
      |> Map.merge(%{margin: %{left: 2, top: 2, bottom: 2, right: 2}}) #TODO here
      |> Map.merge(%{font: init_font_details})

    {:ok, final_args}
  end

  def init(scene, args, opts) do
    Logger.debug("#{__MODULE__} initializing...")
    theme = ScenicWidgets.Utils.Theme.get_theme(opts)

    args = Map.merge(args, %{theme: theme})
    init_graph = RenderLib.render(args)

    init_scene =
      scene
      |> push_graph(init_graph)

    {:ok, init_scene}
  end
end
