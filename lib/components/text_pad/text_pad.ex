defmodule ScenicWidgets.TextPad do
  use Scenic.Component
  require Logger
  use ScenicWidgets.ScenicEventsDefinitions
  alias ScenicWidgets.TextPad.Lib.RenderLib

  @default_font :roboto
  @default_font_size 24
  @newline_char "\n"

  def validate(%{mode: :inactive, frame: %ScenicWidgets.Core.Structs.Frame{} = _frame} = args) do
    {:ok, args}
  end

  def validate(
        %{
          id: _id,
          frame: %ScenicWidgets.Core.Structs.Frame{} = _frame,
          text: text, #TODO change to data?
          mode: mode,
          format_opts: %{ #TODo change to format? Layout? something else??
            alignment: :left,
            # TODO this is what I'm working on, making it line-wrap
            wrap_opts: _wrap_opts,
            # TODO this too
            show_line_num?: show_line_num? #TODo I changed my mind, I think this should live in editor, not TextPad - textpad just renders lines of text...
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

    frame_height = args.frame.dimensions.height
    line_height = init_font_details.size * 1.2
    num_lines = trunc(Float.ceil(frame_height / line_height))

    final_args =
      args
      # default to zero
      |> Map.merge(%{cursor_pos: args |> Map.get(:cursor, %{line: 0, col: 0})})
      |> Map.merge(%{margin: %{left: 4, top: 4, bottom: 4, right: 4}}) #TODO here
      |> Map.merge(%{font: init_font_details})
      |> Map.merge(%{num_lines: num_lines})
      |> Map.merge(%{lines: String.split(text, @newline_char)})

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

  #TODO cursor changes...

  def handle_cast({:redraw, %{data: text}}, scene) when is_bitstring(text) do
    Logger.debug "converting text input to list of lines..."
    GenServer.cast(self(), {:redraw, String.split(text, @newline_char)})
    {:noreply, scene}
  end

  def handle_cast({:redraw, [] = _lines_of_text}, scene) do
    # do nothing...
    IO.puts "ENPTY LIST"
    {:noreply, scene}
  end

  def handle_cast({:redraw, [""] = _lines_of_text}, scene) do
    # do nothing...
    IO.puts "ENPTY LIST WITH A STINGLE"
    {:noreply, scene}
  end

  def handle_cast({:redraw, [l|_rest] = lines_of_text}, scene) when is_bitstring(l) do
    # cast down to each LineOfText component with the contents of each line,
    # those components are responsible for computing whether any changes are needed

    lines_of_text
    |> Enum.with_index(1)
    |> Enum.each(fn({l, i}) ->
        {:ok, [pid]} = child(scene, {:line, i})
        GenServer.cast(pid, {:redraw, l})
    end)
    
    {:noreply, scene}
  end

end
