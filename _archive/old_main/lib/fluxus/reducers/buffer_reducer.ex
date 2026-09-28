defmodule QuillEx.Reducers.BufferReducer do
  alias QuillEx.Reducers.BufferReducer.Utils
  require Logger

  def process(
        # NOTE: No need to re-draw the layers if we're already using :editor
        # %{root: %{active_app: :editor}, editor: %{active_buf: nil}} = radix_state,
        radix_state,
        {:open_buffer, %{name: name, data: text} = args}
      )
      when is_bitstring(text) do
    # TODO check this worked?? ok/error tuple
    new_buf =
      QuillEx.Structs.Buffer.new(
        Map.merge(args, %{
          id: {:buffer, name},
          type: :text,
          data: text,
          dirty?: true
        })
      )

    new_radix_state =
      radix_state
      |> put_in([:root, :active_app], :editor)
      |> put_in([:editor, :buffers], radix_state.editor.buffers ++ [new_buf])
      |> put_in([:editor, :active_buf], new_buf.id)

    {:ok, new_radix_state}
  end

  def process(
        %{editor: %{buffers: buf_list}} = radix_state,
        {:open_buffer, %{data: text, mode: buf_mode}}
      )
      when is_bitstring(text) do
    new_buf_name = QuillEx.Structs.Buffer.new_untitled_buf_name(buf_list)
    process(radix_state, {:open_buffer, %{name: new_buf_name, data: text, mode: buf_mode}})
  end

  def process(radix_state, {:open_buffer, %{file: filename, mode: buf_mode}})
      when is_bitstring(filename) do
    Logger.debug("Opening file: #{inspect(filename)}...")

    # TODO need to check if the file is already open first... otherwise we end up putting the same entry into the list of buffers twice & Flamelex doesn't like that
    text = File.read!(filename)

    process(
      radix_state,
      {:open_buffer, %{name: filename, data: text, mode: buf_mode, source: filename}}
    )
  end

  def process(%{editor: %{buffers: []}}, {:modify_buf, buf_id, _modification}) do
    Logger.warn("Could not modify the buffer #{inspect(buf_id)}, there are no open buffers...")
    :ignore
  end

  def process(radix_state, {:modify_buf, buf_id, {:set_mode, buf_mode}})
      when buf_mode in [:edit, {:vim, :normal}, {:vim, :insert}] do
    {:ok, radix_state |> Utils.update_buf(%{id: buf_id}, %{mode: buf_mode})}
  end

  def process(
        %{editor: %{buffers: buf_list}} = radix_state,
        {:modify_buf, buf, {:insert, text, :at_cursor}}
      ) do
    # Insert text at the position of the cursor (and thus, also move the cursor)

    edit_buf = Utils.filter_buf(radix_state, buf)
    edit_buf_cursor = hd(edit_buf.cursors)

    new_cursor =
      QuillEx.Structs.Buffer.Cursor.calc_text_insertion_cursor_movement(edit_buf_cursor, text)

    new_radix_state =
      radix_state
      |> Utils.update_buf(edit_buf, {:insert, text, {:at_cursor, edit_buf_cursor}})
      |> Utils.update_buf(edit_buf, %{cursor: new_cursor})

    {:ok, new_radix_state}
  end

  # TODO handle backspacing multiple characters
  def process(
        %{editor: %{buffers: buf_list}} = radix_state,
        {:modify_buf, buf, {:backspace, 1, :at_cursor}}
      ) do
    [%{data: full_text, cursors: [%{line: cursor_line, col: cursor_col}]}] =
      buf_list |> Enum.filter(&(&1.id == buf))

    all_lines = String.split(full_text, "\n")

    {full_backspaced_text, new_cursor_coords} =
      if cursor_col == 1 do
        # join 2 lines together
        {current_line, other_lines} = List.pop_at(all_lines, cursor_line - 1)
        new_joined_line = Enum.at(other_lines, cursor_line - 2) <> current_line

        all_lines_including_joined =
          List.replace_at(other_lines, cursor_line - 2, new_joined_line)

        # convert back to one long string...
        full_backspaced_text =
          Enum.reduce(all_lines_including_joined, fn x, acc -> acc <> "\n" <> x end)

        {full_backspaced_text,
         %{line: cursor_line - 1, col: String.length(Enum.at(all_lines, cursor_line - 2)) + 1}}
      else
        line_to_edit = Enum.at(all_lines, cursor_line - 1)
        # delete text left of this by 1 char
        {before_cursor_text, after_and_under_cursor_text} =
          line_to_edit |> String.split_at(cursor_col - 1)

        {backspaced_text, _deleted_text} = before_cursor_text |> String.split_at(-1)

        full_backspaced_line = backspaced_text <> after_and_under_cursor_text

        all_lines_including_backspaced =
          List.replace_at(all_lines, cursor_line - 1, full_backspaced_line)

        # convert back to one long string...
        full_backspaced_text =
          Enum.reduce(all_lines_including_backspaced, fn x, acc -> acc <> "\n" <> x end)

        {full_backspaced_text, %{line: cursor_line, col: cursor_col - 1}}
      end

    new_radix_state =
      radix_state
      |> Utils.update_active_buf(%{data: full_backspaced_text})
      |> Utils.update_active_buf(%{cursor: new_cursor_coords})

    {:ok, new_radix_state}
  end

  def process(radix_state, {:activate, {:buffer, _id} = buf_ref}) do
    {
      :ok,
      radix_state
      |> put_in([:root, :active_app], :editor)
      |> put_in([:editor, :active_buf], buf_ref)
    }
  end

  def process(
        %{root: %{active_app: :editor}, editor: %{buffers: buf_list, active_buf: active_buf}} =
          radix_state,
        {:close_buffer, buf_to_close}
      ) do
    new_buf_list = buf_list |> Enum.reject(&(&1.id == buf_to_close))

    new_radix_state =
      if new_buf_list == [] do
        radix_state
        |> put_in([:root, :active_app], :desktop)
        |> put_in([:editor, :buffers], new_buf_list)
        |> put_in([:editor, :active_buf], nil)
      else
        radix_state
        |> put_in([:editor, :buffers], new_buf_list)
        |> put_in([:editor, :active_buf], hd(new_buf_list).id)
      end

    {:ok, new_radix_state}
  end

  def process(radix_state, {:scroll, :active_buf, delta_scroll}) do
    # NOTE: It is (a little unfortunately) necessary to keep scroll data up in
    # the editor level rather than down at the TextPad level. This is because we
    # may not always want to scroll the text when we use scroll (e.g. if a menu
    # pop-up is active, we may want to scroll the menu, not the text). This is why
    # we go to the effort of having TextPad send us back the scroll_state, so that
    # we may use it to calculate the changes when scrolling, and prevent changes
    # in the scroll accumulator if we're at or above the scroll limits.
    new_scroll_acc = Utils.calc_capped_scroll(radix_state, delta_scroll)
    {:ok, radix_state |> Utils.update_active_buf(%{scroll_acc: new_scroll_acc})}
  end

  # assume this means the active_buffer
  def process(radix_state, {:move_cursor, :active_buf, absolute_position}) do
    active_buf = Utils.filter_active_buf(radix_state)
    buf_cursor = hd(active_buf.cursors)

    new_cursor =
      QuillEx.Tools.TextEdit.move_cursor(
        active_buf.data,
        buf_cursor,
        absolute_position
      )

    new_radix_state =
      radix_state
      |> Utils.update_buf(active_buf, %{cursor: new_cursor})

    {:ok, new_radix_state}
  end

  # TODO we're implicitely assuming it's the active buffer here
  def process(radix_state, {:move_cursor, {:delta, {_column_delta, _line_delta} = cursor_delta}}) do
    edit_buf = Utils.filter_active_buf(radix_state)
    buf_cursor = hd(edit_buf.cursors)

    new_cursor = QuillEx.Tools.TextEdit.move_cursor(edit_buf.data, buf_cursor, cursor_delta)

    # current_cursor_coords = {buf_cursor.line, buf_cursor.col}

    # lines = String.split(edit_buf.data, "\n") #TODO just make it a list of lines already...

    # # these coords are just a candidate because they may not be valid...
    # candidate_coords = {candidate_line, candidate_col} =
    #   Scenic.Math.Vector2.add(current_cursor_coords, cursor_delta)
    #   |> Utils.apply_floor({1,1}) # don't allow scrolling below the origin
    #   |> Utils.apply_ceil({length(lines), Enum.max_by(lines, fn l -> String.length(l) end)}) # don't allow scrolling beyond the last line or the longest line

    # candidate_line_text = Enum.at(lines, candidate_line-1)

    # final_coords =
    #   if String.length(candidate_line_text) <= candidate_col-1 do # NOTE: ned this -1 because if the cursor is sitting at the end of a line, e.g. a line with 8 chars, then it's column will be 9
    #     {candidate_line, String.length(candidate_line_text)+1} # need the +1 because for e.g. a 4 letter line, to put the cursor at the end of the line, we need to put it in column 5
    #   else
    #     candidate_coords
    #   end

    # new_cursor = QuillEx.Structs.Buffer.Cursor.move(buf_cursor, final_coords)

    new_radix_state =
      radix_state
      |> Utils.update_buf(edit_buf, %{cursor: new_cursor})

    {:ok, new_radix_state}
  end

  def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buf, buf, mod}) do
    new_radix_state = radix_state |> Utils.update_buf(buf, mod)

    {:ok, new_radix_state}
  end

  def process(radix_state, {:save, buf}) do
    buf_to_save = Utils.filter_buf(radix_state, buf)

    case buf_to_save do
      %{type: :text, source: source, data: text} when not is_nil(source) ->
        IO.puts("WE SHOULD SAVE")
        Logger.info("Saving `#{source}`...")
        File.write!(source, text)
        {:ok, radix_state |> Utils.update_buf(buf_to_save, %{dirty?: false})}

      _else ->
        Logger.warn("Couldn't save buffer: #{inspect(buf)}, no `source` in %Buffer{}")
        :ignore
    end
  end

  def process(radix_state, action) do
    IO.puts("#{__MODULE__} failed to process action: #{inspect(action)}")
    raise "surprise!"
  end
end
