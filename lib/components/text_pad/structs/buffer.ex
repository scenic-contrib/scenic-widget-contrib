defmodule ScenicWidgets.TextPad.Structs.Buffer do
    alias ScenicWidgets.TextPad.Structs.Buffer.Cursor

    
    defstruct [
        id: nil,                # a unique id for referencing the buffer
        name: "unnamed",        # the name of the buffer that appears in the tab-bar
        type: nil,              # There are several types of buffers e.g. :text, :list - the most common though is :text
        data: nil,              # where the actual contents of the buffer is kept
        mode: nil,              # Buffers can be in various "modes" e.g. {:vim, :normal}, :edit
        source: nil,            # Description of where this buffer originally came from, e.g. {:file, filepath}
        cursors: [],            # a list of all the cursors in the buffer
        history: [],            # track all the modifications as we do them, for undo/redo purposes
        scroll_acc: {0,0},      # Where we keep track of how much we've scrolled the buffer around
        read_only?: false,      # a flag which lets us know if it's a read-only buffer
        dirty?: false,          # a `dirty` buffer is one which is changed / modified in memory but not yet written to disk
        timestamps: %{          # Where we track the timestamps for various operations
            opened: nil,
            last_update: nil,
            last_save: nil,
        }
    ]

    @valid_types [:text, :list]

    def new(%{id: {:buffer, name} = id, type: type, mode: mode}) when type in @valid_types do
        %__MODULE__{
            id: id,
            type: type,
            name: name,
            mode: mode,
            cursors: [Cursor.new(%{num: 1})]
        }
    end

    def new(%{id: {:buffer, name} = id, type: type}) when type in @valid_types do
        %__MODULE__{
            id: id,
            type: type,
            name: name,
            cursors: [Cursor.new(%{num: 1})]
        }
    end

    def update(%__MODULE__{} = old_buf, %{scroll_acc: new_scroll}) do
        old_buf |> Map.put(:scroll_acc, new_scroll)
    end

    #TODO update to dirty
    def update(%__MODULE__{data: nil} = old_buf, {:insert, text_2_insert, {:at_cursor, _cursor}}) do
        # if we have no text, just put it straight in there...
        old_buf |> Map.put(:data, text_2_insert)
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

    # NOTE - if we have more than 1 cursor, we need a more sophisticated update method...
    def update(%__MODULE__{cursors: [_old_cursor]} = old_buf, %{cursor: %Cursor{} = c}) do
        old_buf |> Map.put(:cursors, [c])
    end

    # NOTE - if we have more than 1 cursor, we need a more sophisticated update method...
    def update(%__MODULE__{cursors: [old_cursor]} = old_buf, %{cursor: %{line: _l, col: _c} = new_coords}) do
        c = Cursor.update(old_cursor, new_coords)
        old_buf |> Map.put(:cursors, [c])
    end
end