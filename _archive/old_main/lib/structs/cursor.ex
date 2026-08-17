defmodule QuillEx.Structs.Buffer.Cursor do

    defstruct [
        #TODO maybe we don't need cursor nums, we can just use the place in the list of cursors as their number...
        num: nil,       # which number cursor this is in the buffer, cursor 1 is considered the main cursor
        line: 1,        # which line the cursor is on
        col: 1          # which column the cursor is on. Think of this like a block cursor ("normal mode") not a baret cursor ("insert mode")
        # mode: m

    ]

    def new(%{num: n}) when is_integer(n) and n >= 1 do
        %__MODULE__{
            num: n
        }
    end

    def update(%__MODULE__{line: _l, col: _c} = old_cursor, %{line: new_line, col: new_col}) do
        old_cursor
        |> Map.put(:line, new_line)
        |> Map.put(:col, new_col)
    end

    def move(%__MODULE__{} = old_cursor, {new_line, new_col}) do
        old_cursor
        |> Map.put(:line, new_line)
        |> Map.put(:col, new_col)
    end


    @doc """
    This function calculates how much the cursor needs to move when some text
    is inserted into a Buffer.
    """
    def calc_text_insertion_cursor_movement(%__MODULE__{} = cursor, "") do
        cursor
    end

    def calc_text_insertion_cursor_movement(%__MODULE__{line: cursor_line, col: cursor_col} = cursor, "\n" <> rest) do
        # for a newline char, go down one line and return to column 1
        calc_text_insertion_cursor_movement(%{cursor | line: cursor_line+1, col: 1}, rest)
    end

    def calc_text_insertion_cursor_movement(%__MODULE__{line: cursor_line, col: cursor_col} = cursor, <<char::utf8, rest::binary>>) do
        # for a utf8 character just move along one column
        calc_text_insertion_cursor_movement(%{cursor | line: cursor_line, col: cursor_col+1}, rest)
    end
end