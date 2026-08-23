defmodule QuillEx.Structs.Buffer do
   alias QuillEx.Structs.Buffer.Cursor

    
   defstruct [
      id: nil,                 # a unique id for referencing the buffer
      name: "unnamed",         # the name of the buffer that appears in the tab-bar
      type: :text,             # There are several types of buffers e.g. :text, :list - the most common though is :text
      data: nil,               # where the actual contents of the buffer is kept
      mode: :edit,             # Buffers can be in various "modes" e.g. {:vim, :normal}, :edit
      source: nil,             # Description of where this buffer originally came from, e.g. {:file, filepath}
      cursors: [],             # a list of all the cursors in the buffer
      history: [],             # track all the modifications as we do them, for undo/redo purposes
      scroll_acc: {0,0},       # Where we keep track of how much we've scrolled the buffer around
      read_only?: false,       # a flag which lets us know if it's a read-only buffer
      dirty?: true,            # a `dirty` buffer is one which is changed / modified in memory but not yet written to disk
      timestamps: %{           # Where we track the timestamps for various operations
         opened: nil,
         last_update: nil,
         last_save: nil,
      }
   ]

   @valid_types [:text, :list]
   @vim_modes [{:vim, :insert}, {:vim, :normal}]
   @valid_modes [:edit] ++ @vim_modes

   def new(%{id: {:buffer, name} = buf_id} = args) do
      %__MODULE__{
         id: buf_id,
         name: validate_name(name),
         type: :text, #TODO,
         data: args[:data] || "",
         mode: validate_mode(args[:mode]) || :edit,
         source: args[:source] || nil,
         cursors: args[:cursors] || [Cursor.new(%{num: 1})],
         history: [],
         scroll_acc: args[:scroll_acc] || {0, 0},
         read_only?: args[:read_only?] || false,
         dirty?: args[:dirty?] || false,
         timestamps: %{
               opened: DateTime.utc_now() #TODO use some kind of default timezone
         }
      }
   end

    def update(%__MODULE__{} = old_buf, %{scroll_acc: new_scroll}) do
        old_buf |> Map.put(:scroll_acc, new_scroll)
    end

    def update(%__MODULE__{data: nil} = old_buf, {:insert, text_2_insert, {:at_cursor, _cursor}}) do
        %{old_buf|data: text_2_insert, dirty?: true}
    end

    def update(%__MODULE__{} = old_buf, %{dirty?: dirty?}) when is_boolean(dirty?) do
        %{old_buf|dirty?: true}
    end

    def update(%__MODULE__{data: old_text} = old_buf, {:insert_line, [after: n, text: new_line]}) when is_bitstring(new_line) do
        lines = String.split(old_text, "\n")

        new_lines = List.insert_at(lines, n, new_line) # NOTE: because Elixir List begins at 0, this puts the new line after n

        new_full_text = Enum.reduce(new_lines, fn x, acc -> acc <> "\n" <> x end)

        old_buf |> Map.put(:data, new_full_text)
    end

    def update(%__MODULE__{data: old_text} = old_buf, {:insert, text_2_insert, {:at_cursor, %Cursor{line: l, col: c}}}) when is_bitstring(old_text) and is_bitstring(text_2_insert) do
        lines = String.split(old_text, "\n")     
        line_2_edit = Enum.at(lines, l-1)

        {before_split, after_split} = String.split_at(line_2_edit, c-1) 

        full_text_list = List.replace_at(lines, l-1, before_split <> text_2_insert <> after_split)

        new_full_text = Enum.reduce(full_text_list, fn x, acc -> acc <> "\n" <> x end)

        old_buf |> Map.put(:data, new_full_text)
    end

    def update(%__MODULE__{} = old_buf, %{data: text}) when is_bitstring(text) do
        old_buf |> Map.put(:data, text)
    end

    def update(%__MODULE__{data: old_text} = old_buf, {:delete_line, line_num}) do
        lines =
            String.split(old_text, "\n")     
            |> List.delete_at(line_num-1)

        new_full_text = Enum.reduce(lines, fn x, acc -> acc <> "\n" <> x end)

        old_buf |> Map.put(:data, new_full_text)
    end

    # NOTE - if we have more than 1 cursor, we need a more sophisticated update method...
    def update(%__MODULE__{cursors: [_old_cursor]} = old_buf, %{cursor: %Cursor{} = c}) do
        old_buf |> Map.put(:cursors, [c])
    end

    # NOTE - if we have more than 1 cursor, we need a more sophisticated update method...
    def update(%__MODULE__{cursors: [old_cursor]} = old_buf, %{cursor: %{line: _l, col: _c} = new_coords}) do
        c = Cursor.update(old_cursor, new_coords)
        old_buf |> Map.put(:cursors, [c])
    end

    def update(%__MODULE__{} = buf, %{mode: new_mode}) do
        %{buf|mode: new_mode}
    end

    # def substitution(text) do

    # end

    # def deletion do

    # end

    # def insertion do

    # end

    # def delete(text, :last_character) do
    #     {backspaced_text, _deleted_text} = text |> String.split_at(-1)
    #     backspaced_text
    # end
    
    # def handle(%{buffers: buf_list} = radix, {:modify_buf, buf, {:append, text}}) do
    #   new_buf_list =
    #     buf_list
    #     |> Enum.map(fn
    #       %{id: ^buf} = buffer -> %{buffer | data: buffer.data <> text}
    #       any_other_buffer -> any_other_buffer
    #     end)

    #   {:ok, radix |> Map.put(:buffers, new_buf_list)}
    # end

    def new_untitled_buf_name([]) do
        "untitled*"
    end

    def new_untitled_buf_name(buf_list) when is_list(buf_list) and length(buf_list) >= 1 do
        num_untitled_open =
            buf_list
            |> Enum.filter(fn
                # %{id {:buffer, "untitled" <> _rest}, unsaved_changes?: true} ->
                %{dirty?: true} ->
                    true
                _else ->
                    false
            end)
            |> Enum.count()

        #TODO do a final check to make sure that we arent accidentally giving it the same name as an existing buffer
        "untitled#{inspect num_untitled_open+2}*" # add 2 because we go straight to untitled2 if we have 2 buffers open
    end

    def validate_name(Flamelex.API.Kommander), do: "Kommander"
    def validate_name(n) when is_bitstring(n), do: n

    def validate_mode(nil), do: nil
    def validate_mode(m) when m in @valid_modes, do: m
    def validate_mode(invalid_mode) do
        Logger.warn "invalid mode: #{inspect invalid_mode} given when initializing buffer!"
        nil
    end
end