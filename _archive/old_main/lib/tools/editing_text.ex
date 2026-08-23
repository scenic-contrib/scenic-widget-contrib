defmodule QuillEx.Tools.TextEdit do
    @moduledoc """
    These functions are generic implementations of common text-editing operations.

    They are designed to be agnostic to your needs, just implement changes to text,
    e.g. backspace at a cursor. Give me the text & the cursor, I'll give you back a text
    & a cursor
    """
    
    @newline "\n"

    def insert_text_at_cursor(%{
        old_text: old_text,
        cursor: %{line: line, col: col} = c,
        text_2_insert: text_2_insert
     }) when is_bitstring(old_text) do
    
        all_lines =
            String.split(old_text, @newline)

        {line_to_edit, _other_lines} =
            # old_text
            # |> String.split(@newline)
            all_lines
            |> List.pop_at(line-1)

        {before_cursor_text, after_and_under_cursor_text} =
            line_to_edit
            |> String.split_at(col-1)

        new_full_line =
            before_cursor_text <> text_2_insert <> after_and_under_cursor_text

        updated_paragraph_lines =
            List.replace_at(all_lines, line-1, new_full_line)
        
        final_text = lines_2_string(updated_paragraph_lines)
        

        new_cursor =
            calc_text_insertion_cursor_movement(c, text_2_insert)

        # new_cursor = %{
        #     line: line, # keep same line
        #     col: col + String.length(text_2_insert)
        # }

        {final_text, new_cursor}
    end

    def lines_2_string(lines) do
        # convert back to one long string...
        Enum.reduce(lines, fn x, acc -> acc <> "\n" <> x end)
    end

    def backspace(text, %{col: 1} = cursor, x, :at_cursor) when is_bitstring(text) do
        lines_of_text = String.split(text, "\n")
        # join 2 lines together
        {current_line, other_lines} = List.pop_at(lines_of_text, cursor.line-1)
        new_joined_line = Enum.at(other_lines, cursor.line-2) <> current_line
        all_lines_including_joined = List.replace_at(other_lines, cursor.line-2, new_joined_line)

        # convert back to one long string...
        full_backspaced_text = Enum.reduce(all_lines_including_joined, fn x, acc -> acc <> "\n" <> x end)
        new_cursor = cursor |> Map.merge(%{line: cursor.line-1, col: String.length(Enum.at(lines_of_text, cursor.line-2))+1})
        
        {full_backspaced_text, new_cursor}
    end

    def backspace(text, cursor, x, position) when is_bitstring(text) do
        String.split(text, "\n") |> backspace(cursor, x, position)
    end

    def backspace(lines_of_text, cursor, x, :at_cursor) when is_list(lines_of_text) do
        line_to_edit = Enum.at(lines_of_text, cursor.line-1)
        # delete text left of this by 1 char
        {before_cursor_text, after_and_under_cursor_text} = line_to_edit |> String.split_at(cursor.col-1)
        {backspaced_text, _deleted_text} = before_cursor_text |> String.split_at(-1)
    
        full_backspaced_line = backspaced_text <> after_and_under_cursor_text
        all_lines_including_backspaced = List.replace_at(lines_of_text, cursor.line-1, full_backspaced_line)
    
        # convert back to one long string...
        full_backspaced_text = Enum.reduce(all_lines_including_backspaced, fn x, acc -> acc <> "\n" <> x end)
        new_cursor = cursor |> Map.merge(%{col: cursor.col-1})
        
        {full_backspaced_text, new_cursor}
    end

    def move_cursor(_text, current_cursor, :first_line) do
        current_cursor |> Map.put(:line, 1)
    end

    def move_cursor(text, current_cursor, :last_line) do
        lines = String.split(text, "\n") #TODO just make it a list of lines already...
        current_cursor |> Map.put(:line, Enum.count(lines))
    end

    def move_cursor(text, current_cursor, cursor_delta) when is_bitstring(text) do
        lines = String.split(text, "\n") #TODO just make it a list of lines already...

        # these coords are just a candidate because they may not be valid...
        candidate_coords = {candidate_line, candidate_col} =
          Scenic.Math.Vector2.add({current_cursor.line, current_cursor.col}, cursor_delta)
          |> QuillEx.Lib.Utils.apply_floor({1,1}) # don't allow scrolling below the origin
          |> QuillEx.Lib.Utils.apply_ceil({length(lines), Enum.max_by(lines, fn l -> String.length(l) end)}) # don't allow scrolling beyond the last line or the longest line
    
        candidate_line_text = Enum.at(lines, candidate_line-1)
    
        final_coords =
          if String.length(candidate_line_text) <= candidate_col-1 do # NOTE: ned this -1 because if the cursor is sitting at the end of a line, e.g. a line with 8 chars, then it's column will be 9
            {candidate_line, String.length(candidate_line_text)+1} # need the +1 because for e.g. a 4 letter line, to put the cursor at the end of the line, we need to put it in column 5
          else
            candidate_coords
          end

        {new_line, new_col} = final_coords

        current_cursor
        |> Map.put(:line, new_line)
        |> Map.put(:col, new_col)

    
        # new_cursor = QuillEx.Structs.Buffer.Cursor.move(current_cursor, final_coords)

        # new_cursor
    end

    def calc_text_insertion_cursor_movement(cursor, "") do
        cursor
    end

    def calc_text_insertion_cursor_movement(%{line: cursor_line, col: cursor_col} = cursor, "\n" <> rest) do
        # for a newline char, go down one line and return to column 1
        calc_text_insertion_cursor_movement(%{cursor | line: cursor_line+1, col: 1}, rest)
    end

    def calc_text_insertion_cursor_movement(%{line: cursor_line, col: cursor_col} = cursor, <<char::utf8, rest::binary>>) do
        # for a utf8 character just move along one column
        calc_text_insertion_cursor_movement(%{cursor | line: cursor_line, col: cursor_col+1}, rest)
    end
end

#   @doc """
#   Wrap and shorten text to a set number of lines

#     iex> {:ok, {_type, fm}} = Scenic.Assets.Static.meta(:roboto)
#     iex> line_width = 130
#     iex> num_lines = 2
#     iex> font_size = 16
#     iex> wrap_and_shorten_text("Some text that needs to be wrapped and shortened", line_width, num_lines, font_size, fm)
#     "Some text that
#     needs to be wra…"
#   """
#   def wrap_and_shorten_text(text, line_width, num_lines, font_size, font_metrics) do
#     text =
#       text
#       |> FontMetrics.shorten(line_width * num_lines, font_size, font_metrics)
#       |> FontMetrics.wrap(line_width, font_size, font_metrics)

#     lines = String.split(text, "\n")

#     if length(lines) > num_lines do
#       List.flatten([
#         Enum.slice(lines, 0..(num_lines - 2)),
#         # Join the last two lines and re-shorten it (the wrapping may have
#         # introduced an extra line)
#         Enum.slice(lines, (num_lines - 1)..-1)
#         |> Enum.join(" ")
#         |> FontMetrics.shorten(line_width, font_size, font_metrics)
#       ])
#       |> Enum.join("\n")
#     else
#       text
#     end
#   end

#   def draw_frame_footer(
#         %Scenic.Graph{} = graph,
#         %{ frame: %__MODULE__{} = frame,
#            draw_footer?: true })
#   do

#     w = frame.dimensions.width + 1 #NOTE: Weird scenic thing, we need the +1 or we see a thin line to the right of the box
#     h = Flamelex.GUI.Component.MenuBar.height()
#     x = frame.top_left.x
#     y = frame.dimensions.height - h # go to the bottom & back up how high the bar will be
#     c = Flamelex.GUI.Colors.menu_bar()

#     # font_size = Flamelex.GUI.Fonts.size()
#     font_size = 24 #TODO
#     mode_textbox_width = 250

#     stroke_width = 2
#     mode_string = "NORMAL_MODE"
#     left_margin = 25

#     frame_label = if frame.label == nil, do: "", else: frame.label

#     graph
#     # first, draw the background
#     |> Scenic.Primitives.rect({w, h},
#                 translate:  {x, y},
#                 fill:       c)
#     # then, draw the backgrounnd rectangle for the mode-string box
#     |> Scenic.Primitives.rect({mode_textbox_width, h},
#                 id: :mode_string_box,
#                 translate:  {x, y},
#                 fill:       Flamelex.GUI.Colors.mode(:normal))
#     # draw the text showing the mode_string
#     |> Scenic.Primitives.text(mode_string,
#                 id: :mode_string,
#                 # font:       Flamelex.GUI.Fonts.primary(),
#                 font:       :ibm_plex_mono,
#                 translate:  {x+left_margin, y+font_size+stroke_width}, # text draws from bottom-left corner??
#                 font_size:  font_size,
#                 fill:       :black)
#     # draw the text showing the frame_label
#     |> Scenic.Primitives.text(frame_label,
#                 # ont:       Flamelex.GUI.Fonts.primary(),
#                 font:       :ibm_plex_mono,
#                 translate:  {x+mode_textbox_width+left_margin, y+font_size+stroke_width}, # text draws from bottom-left corner??
#                 font_size:  font_size,
#                 fill:       :black)
#     # draw a simple line above the frame footer
#     |> Scenic.Primitives.line({{x, y}, {w, y}},
#                 stroke:     {stroke_width, :black})
#   end

#   def draw_frame_footer(%Scenic.Graph{} = graph, _params) do
#     #NOTE: do nothing, as we didn't match on the correct frame_opts
#     graph
#   end

#   def decorate_graph(%Scenic.Graph{} = graph, %{frame: %__MODULE__{} = frame} = params) do
#     Logger.debug "#{__MODULE__} framing up... frame: #{inspect frame}, params: #{inspect params}"
#     Logger.warn "Not rly framing anything yet..."
#     graph
#   end

#   def reposition(%__MODULE__{top_left: coords} = frame, x: new_x, y: new_y) do
#     new_coordinates =
#       coords
#       |> Coordinates.modify(x: new_x, y: new_y)

#     %{frame|top_left: new_coordinates}
#   end

#   def resize(%__MODULE__{dimensions: dimens} = frame, reduce_height_by: h) do
#     new_height = frame.dimensions.height - h

#     new_dimensions =
#       dimens |> Dimensions.modify(
#                       width: frame.dimensions.width,
#                       height: new_height )

#     %{frame|dimensions: new_dimensions}
#   end

#   # def test do
#   #   new("tester", {100, 100}, {100, 100})
#   # end

#   # def new(label, %Coordinates{} = c, %Dimensions{}  = d) do
#   #   new(
#   #     id:              label,
#   #     top_left_corner: %Coordinates{} = c,
#   #     dimensions:      %Dimensions{}  = d
#   #   )
#   # end
#   # def new(label, coords, dimensions) do
#   #   new(label, Coordinates.new(coords), Dimensions.new(dimensions))
#   # end

#   def calculate_frame_position(%{show_menubar?: true}) do
#     Coordinates.new(x: 0, y: Flamelex.GUI.Component.MenuBar.height())
#   end
#   def calculate_frame_position(_otherwise) do
#     Coordinates.new(x: 0, y: 0)
#   end
#   #   case opts |> Map.fetch(:show_menubar?) do
#   #     {:ok, true} ->

#   #     _otherwise ->

#   #   end
#   # end

#   def calculate_frame_size(opts, layout_dimens) do
#     case opts |> Map.fetch(:show_menubar?) do
#       {:ok, true} ->
#         Dimensions.new(width: layout_dimens.width, height: layout_dimens.height)
#       _otherwise ->
#         Dimensions.new(width: layout_dimens.width, height: layout_dimens.height)
#     end
#   end

#   # def draw(%Scenic.Graph{} = graph, %__MODULE__{} = frame) do
#   #   graph
#   #   |> Draw.border_box(frame)
#   #   |> draw_frame_footer(frame)
#   # end

#   # def draw(%Scenic.Graph{} = graph, %__MODULE__{} = frame, opts) when is_map(opts) do
#   #   graph
#   #   |> draw_frame_footer(frame, opts)
#   #   |> Draw.border_box(frame)
#   # end

#   # def draw(%Scenic.Graph{} = graph, %__MODULE__{} = frame, %Flamelex.Fluxus.Structs.RadixState{} = radix_state) do
#   #   graph
#   #   |> draw_frame_footer(frame, radix_state)
#   #   |> Draw.border_box(frame)
#   # end

#   # def draw_frame_footer(graph, frame, %{mode: :normal} = opts) when is_map(opts) do
#   #   w = frame.dimensions.width + 1 #NOTE: Weird scenic thing, we need the +1 or we see a thin line to the right of the box
#   #   h = Flamelex.GUI.Component.MenuBar.height()
#   #   x = frame.top_left.x
#   #   y = frame.dimensions.height - h # go to the bottom & back up how high the bar will be
#   #   c = Flamelex.GUI.Colors.menu_bar()

#   #   font_size = Flamelex.GUI.Fonts.size()

#   #   graph
#   #   |> Scenic.Primitives.rect({w, h}, translate: {x, y}, fill: c)
#   #   |> Scenic.Primitives.rect({168, h}, translate: {x, y}, fill: Flamelex.GUI.Colors.mode(:normal))
#   #   |> Scenic.Primitives.line({{x, y}, {w, y}}, stroke: {2, :black})
#   #   |> Scenic.Primitives.line({{x, y}, {w, y}}, stroke: {2, :black})
#   #   |> Scenic.Primitives.text("NORMAL-MODE", font: Flamelex.GUI.Fonts.primary(),
#   #               translate: {x + 25, y + font_size + 2}, # text draws from bottom-left corner??
#   #               font_size: font_size, fill: :black)
#   #   |> Scenic.Primitives.text(frame.id, font: Flamelex.GUI.Fonts.primary(), #TODO should be frame.name ??
#   #               translate: {x + 200, y + font_size + 2}, # text draws from bottom-left corner??
#   #               font_size: font_size, fill: :black)
#   # end

#   # def draw_frame_footer(graph, frame, %{mode: :insert} = opts) when is_map(opts) do
#   #   w = frame.dimensions.width + 1 #NOTE: Weird scenic thing, we need the +1 or we see a thin line to the right of the box
#   #   h = Flamelex.GUI.Component.MenuBar.height()
#   #   x = frame.top_left.x
#   #   y = frame.dimensions.height - h # go to the bottom & back up how high the bar will be
#   #   c = Flamelex.GUI.Colors.menu_bar()

#   #   font_size = Flamelex.GUI.Fonts.size()

#   #   graph
#   #   |> Scenic.Primitives.rect({w, h}, translate: {x, y}, fill: c)
#   #   |> Scenic.Primitives.rect({168, h}, translate: {x, y}, fill: Flamelex.GUI.Colors.mode(:insert))
#   #   |> Scenic.Primitives.line({{x, y}, {w, y}}, stroke: {2, :black})
#   #   |> Scenic.Primitives.line({{x, y}, {w, y}}, stroke: {2, :black})
#   #   |> Scenic.Primitives.text("INSERT-MODE", font: Flamelex.GUI.Fonts.primary(),
#   #               translate: {x + 25, y + font_size + 2}, # text draws from bottom-left corner??
#   #               font_size: font_size, fill: :black)
#   #   |> Scenic.Primitives.text(frame.id, font: Flamelex.GUI.Fonts.primary(), #TODO should be frame.name ??
#   #               translate: {x + 200, y + font_size + 2}, # text draws from bottom-left corner??
#   #               font_size: font_size, fill: :black)
#   # end

#   # def draw_frame_footer(graph, frame) do
#   #   w = frame.dimensions.width + 1 #NOTE: Weird scenic thing, we need the +1 or we see a thin line to the right of the box
#   #   h = Flamelex.GUI.Component.MenuBar.height()
#   #   x = frame.top_left.x
#   #   y = frame.dimensions.height # go to the bottom & back up how high the bar will be
#   #   c = Flamelex.GUI.Colors.menu_bar()

#   #   graph
#   #   |> Scenic.Primitives.rect({w, h}, translate: {x, y}, fill: c)
#   # end

#   # def draw_frame_footer(graph, frame, %Flamelex.Fluxus.Structs.RadixState{mode: :normal}) do
#   #   w = frame.dimensions.width + 1 #NOTE: Weird scenic thing, we need the +1 or we see a thin line to the right of the box
#   #   h = Flamelex.GUI.Component.MenuBar.height()
#   #   x = frame.top_left.x
#   #   y = frame.dimensions.height - h # go to the bottom & back up how high the bar will be
#   #   c = Flamelex.GUI.Colors.menu_bar()

#   #   font_size = Flamelex.GUI.Fonts.size()

#   #   graph
#   #   |> Scenic.Primitives.rect({w, h}, translate: {x, y}, fill: c)
#   #   |> Scenic.Primitives.rect({168, h}, translate: {x, y}, fill: Flamelex.GUI.Colors.mode(:normal))
#   #   |> Scenic.Primitives.line({{x, y}, {w, y}}, stroke: {2, :black})
#   #   |> Scenic.Primitives.line({{x, y}, {w, y}}, stroke: {2, :black})
#   #   |> Scenic.Primitives.text("NORMAL-MODE", font: Flamelex.GUI.Fonts.primary(),
#   #               translate: {x + 25, y + font_size + 2}, # text draws from bottom-left corner??
#   #               font_size: font_size, fill: :black)
#   #   |> Scenic.Primitives.text(frame.id, font: Flamelex.GUI.Fonts.primary(), #TODO should be frame.name ??
#   #               translate: {x + 200, y + font_size + 2}, # text draws from bottom-left corner??
#   #               font_size: font_size, fill: :black)
#   # end
# end

# # defmodule Flamelex.GUI.Component.Frame do
# #   @moduledoc """
# #   Frames are a very special type of Component - they are a container,
# #   manipulatable by the layout of the root scene. Virtually all buffers
# #   will render their corresponding Component in a Frame.
# #   """

# #   use Scenic.Component
# #   use Flamelex.ProjectAliases
# #   require Logger

# #   @impl Scenic.Component
# #   def verify(%__MODULE__{} = frame), do: {:ok, frame}
# #   def verify(_else), do: :invalid_data

# #   @impl Scenic.Component
# #   def info(_data), do: ~s(Invalid data)

# #   ## GenServer callbacks
# #   ## -------------------------------------------------------------------

# #   @impl Scenic.Scene
# #   def init(%__MODULE__{} = frame, _opts) do
# #     # IO.puts "Initializing #{__MODULE__}..."
# #     {:ok, frame, push: GUI.GraphConstructors.Frame.convert(frame)}
# #   end

# #   # left-click
# #   def handle_input({:cursor_button, {:left, :press, _dunno, _coords}} = action, _context, frame) do
# #     # new_frame = frame |> ActionReducer.process(action)
# #     new_graph = frame |> GUI.GraphConstructors.Frame.convert_2()
# #     {:noreply, frame, push: new_graph}
# #   end

# #   def handle_input(event, _context, state) do
# #     # state = Map.put(state, :contained, true)
# #     IO.puts "EVENT #{inspect event}"
# #     # {:noreply, state, push: update_color(state)}
# #     {:noreply, state}
# #   end

# #   # def filter_event(event, _, state) do
# #   #   IO.puts "EVENT #{event}"
# #   #   {:cont, {:click, :transformed}, state}
# #   # end

# #   # def handle_continue(:draw_frame, frame) do

# #   #   new_graph =
# #   #     frame.graph
# #   #     |> Draw.box(
# #   #             x: frame.top_left.x,
# #   #             y: frame.top_left.y,
# #   #         width: frame.width,
# #   #        height: frame.height)

# #   #   new_frame =
# #   #     %{frame|graph: new_graph}

# #   #   {:noreply, new_frame}
# #   #   # {:noreply, new_frame, push: new_graph}
# #   # end

# #   ## private functions
# #   ## -------------------------------------------------------------------

# #   # defp register_process() do
# #   #   #TODO search for if the process is already registered, if it is, engage recovery procedure
# #   #   Process.register(self(), __MODULE__) #TODO this should be gproc
# #   # end

# #   # def initialize(%__MODULE__{} = frame) do
# #   #   # the textbox is internal to the command buffer, but we need the
# #   #   # coordinates of it in a few places, so we pre-calculate it here
# #   #   textbox_frame =
# #   #     %__MODULE__{} = DrawingHelpers.calc_textbox_frame(frame)

# #   #   Draw.blank_graph()
# #   #   |> Scenic.Primitives.group(fn graph ->
# #   #        graph
# #   #        |> Draw.background(frame, @command_mode_background_color)
# #   #        |> DrawingHelpers.draw_command_prompt(frame)
# #   #        |> DrawingHelpers.draw_input_textbox(textbox_frame)
# #   #        |> DrawingHelpers.draw_cursor(textbox_frame, id: @cursor_component_id)
# #   #        |> DrawingHelpers.draw_text_field("", textbox_frame, id: @text_field_id) #NOTE: Start with an empty string
# #   #   end, [
# #   #     id: @component_id,
# #   #     hidden: true
# #   #   ])
# #   # end

# #   # defp initialize_graph(coordinates: {x, y}, dimensions: {w, h}, color: c) do
# #   #   Graph.build()
# #   #   |> rect({w, h}, translate: {x, y}, fill: c)
# #   # end
# #   # defp initialize_graph(coordinates: {x, y}, dimensions: {w, h}, color: c, stroke: {s, border_color}) do
# #   #   Graph.build()
# #   #   |> rect({w, h}, translate: {x, y}, fill: c, stroke: {s, border_color})
# #   # end
# # end

# @prompt_color :ghost_white
# @prompt_size 12
# @prompt_margin 2
# def draw_command_prompt(graph, %Frame{
#   #NOTE: These are the coords/dimens for the whole CommandBuffer Frame
#   top_left: %{x: _top_left_x, y: top_left_y},
#   dimensions: %{height: height, width: _width}
# }) do
#   #NOTE: The y_offset
#   #      ------------
#   #      From the top-left position of the box, the command prompt
#   #      y-offset. (height - prompt_size) is how much bigger the
#   #      buffer is than the command prompt, so it gives us the extra
#   #      space - we divide this by 2 to get how much extra space we
#   #      need to add, to the reference y coordinate, to center the
#   #      command prompt inside the buffer
#   y_offset = top_left_y + (height - @prompt_size)/2

#   #NOTE: How Scenic draws triangles
#   #      --------------------------
#   #      Scenic uses 3 points to draw a triangle, which look like this:
#   #
#   #           x - point1
#   #           |\
#   #           | \ x - point2 (apex of triangle)
#   #           | /
#   #           |/
#   #           x - point3
#   point1 = {@prompt_margin, y_offset}
#   point2 = {@prompt_margin+prompt_width(@prompt_size), y_offset+@prompt_size/2}
#   point3 = {@prompt_margin, y_offset + @prompt_size}

#   graph
#   |> Scenic.Primitives.triangle({point1, point2, point3}, fill: @prompt_color)
# end









    # descnt = FontMetrics.descent(args.font.size, args.font.metrics)

    # TODO this is crashing after a little bit!!
    # wrapped_text =
    #   FontMetrics.wrap(
    #     args.text,
    #     # REMINDER: Take off both margins when calculating the widt0
    #     args.frame.dimensions.width - (args.margin.left + args.margin.right),
    #     args.font.size,
    #     args.font.metrics
    #   )















    # def backspace(lines_of_text, %{col: 1} = cursor, x, :at_cursor) do
    #     # join 2 lines together
    #     {current_line, other_lines} = List.pop_at(lines_of_text, cursor.line-1)
    #     new_joined_line = Enum.at(other_lines, cursor.line-2) <> current_line
    #     all_lines_including_joined = List.replace_at(other_lines, cursor.line-2, new_joined_line)
  
    #     # convert back to one long string...
    #     full_backspaced_text = Enum.reduce(all_lines_including_joined, fn x, acc -> acc <> "\n" <> x end)
    #     new_cursor = cursor |> Map.merge(%{line: cursor.line-1, col: String.length(Enum.at(lines_of_text, cursor.line-2))+1})
        
    #     {full_backspaced_text, new_cursor}
    #  end
  
    #  def backspace(text, cursor, x, position) when is_bitstring(text) do
    #     String.split(text, "\n") |> backspace(cursor, x, position)
    #  end
  
    #  def backspace(lines_of_text, cursor, x, :at_cursor) do
    #     line_to_edit = Enum.at(lines_of_text, cursor.line-1)
    #     # delete text left of this by 1 char
    #     {before_cursor_text, after_and_under_cursor_text} = line_to_edit |> String.split_at(cursor.col-1)
    #     {backspaced_text, _deleted_text} = before_cursor_text |> String.split_at(-1)
     
    #     full_backspaced_line = backspaced_text <> after_and_under_cursor_text
    #     all_lines_including_backspaced = List.replace_at(lines_of_text, cursor.line-1, full_backspaced_line)
     
    #     # convert back to one long string...
    #     full_backspaced_text = Enum.reduce(all_lines_including_backspaced, fn x, acc -> acc <> "\n" <> x end)
    #     new_cursor = cursor |> Map.merge(%{col: cursor.col-1})
        
    #     {full_backspaced_text, new_cursor}
    #  end