defmodule ScenicWidgets.TextPad.Utils do
   alias ScenicWidgets.TextPad.Structs.Font

   @doc """
   Builds a new %TextPad{} struct.
   """
   def new do
      %ScenicWidgets.TextPad{
         lines: [""],
         mode: :edit,
         font: default_font(),
         margin: default_margin(),
         cursor: %{line: 1, col: 1},
      }
   end

   # def new(%{buffer: %{mode: buf_mode}, font: %Font{} = f, margin: margin}) do
   #    # create a standard buffer & just override the other args
   #    base = new()
   #    %{base|font: f, mode: buf_mode, margin: margin}
   # end

   # def new(%{buffer: %{mode: buf_mode}, font: %Font{} = f}) do
   #    # create a standard buffer & just override the other args
   #    base = new()
   #    %{base|font: f, mode: buf_mode}
   # end

   #TODO place cursor in last line of the TextPad when we pass in some text...

   def new(%{
      mode: mode,
      text: text,
      font: font
   }) when is_bitstring(text) do
      base = new()
      %{base|lines: String.split(text, "\n"), font: font, mode: mode}
   end


   def new(%{
      text: text,
      font: font,
      cursor: cursor
   }) when is_bitstring(text) do
      base = new()
      %{base|lines: String.split(text, "\n"), font: font, cursor: cursor}
   end

   def new(%{
      buffer: %{
         data: data,
         mode: buf_mode,
         cursors: [cursor] #TODO handle multiple cursors
      },
      font: %Font{} = f,
      margin: margin
   }) when is_bitstring(data) and is_map(margin) do
      # create a standard buffer & just override the other args
      base = new()
      %{base|mode: buf_mode, lines: String.split(data, "\n"), margin: margin, font: f, cursor: cursor}
   end

   #TODO this needs to go, but for now just use it to accept default margin
   def new(%{
      buffer: %{
         data: data,
         mode: buf_mode,
         cursors: [cursor] #TODO handle multiple cursors
      },
      font: %Font{} = f
   }) when is_bitstring(data) do
      # create a standard buffer & just override the other args
      base = new()
      %{base|mode: buf_mode, lines: String.split(data, "\n"), font: f, cursor: cursor}
   end

   # def new(%{
   #    data: data,
   #    mode: buf_mode
   # }) when is_bitstring(data) do
   #    # create a standard buffer & just override the other args
   #    base = new()
   #    %{base|mode: buf_mode, lines: String.split(data, "\n")}
   # end

   def backspace(lines_of_text, %{col: 1} = cursor, x, :at_cursor) do
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

   def backspace(lines_of_text, cursor, x, :at_cursor) do
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

   # def new(%{data: data}) when is_bitstring(data) do
   #    raise "here"
   # end

   def default_margin do
      %{left: 2, top: 0, bottom: 0, right: 2}
   end

   def default_font do
      name = :roboto
      %{
         name: name,
         size: 24,
         metrics: Font.font_metrics(name)
      }
   end
end