defmodule ScenicWidgets.FilePicker.State do
  @moduledoc """
  State struct for the FilePicker component.

  Tracks current directory, file listings, selected item, and scroll position.
  """

  use Widgex.Scrollable, direction: :vertical
  require Logger

  alias Widgex.Frame

  @item_height 28
  # (default start path is resolved at runtime in new/1 — a module attribute
  # would bake in the directory `mix compile` happened to run in)

  defstruct [
    :frame,
    :current_path,
    :entries,
    :selected_index,
    :scroll,
    :show_hidden,
    :filter,
    :font,
    # Save mode fields
    # :open or :save
    mode: :open,
    # Filename being typed in save mode
    filename: "",
    # Cursor position in filename input
    filename_cursor: 0
  ]

  @type entry :: %{
          name: String.t(),
          path: String.t(),
          type: :directory | :file,
          size: non_neg_integer() | nil
        }

  @type t :: %__MODULE__{
          frame: Frame.t(),
          current_path: String.t(),
          entries: [entry()],
          selected_index: non_neg_integer(),
          scroll: Widgex.Scroll.ScrollState.t(),
          show_hidden: boolean(),
          filter: String.t() | nil,
          font: map() | nil,
          mode: :open | :save,
          filename: String.t(),
          filename_cursor: non_neg_integer()
        }

  @doc """
  Create new FilePicker state.

  ## Options
    * `:start_path` - Initial directory (default: user home)
    * `:show_hidden` - Show hidden files (default: false)
    * `:filter` - File extension filter, e.g. ".txt" (default: nil = all files)
    * `:mode` - :open or :save (default: :open)
    * `:filename` - Initial filename for save mode (default: "")
  """
  def new(%{frame: %Frame{} = frame} = opts) do
    start_path = Map.get(opts, :start_path) || File.cwd!()
    show_hidden = Map.get(opts, :show_hidden, false)
    filter = Map.get(opts, :filter, nil)
    mode = Map.get(opts, :mode, :open)
    filename = Map.get(opts, :filename, "")
    filename_cursor = String.length(filename)

    entries = list_directory(start_path, show_hidden, filter)
    content_height = length(entries) * @item_height

    # Calculate the list frame (modal area minus header and buttons)
    list_frame = list_frame(frame, mode)

    %__MODULE__{
      frame: frame,
      current_path: start_path,
      entries: entries,
      selected_index: 0,
      scroll: init_scroll(list_frame, content_height: content_height),
      show_hidden: show_hidden,
      filter: filter,
      font: Map.get(opts, :font),
      mode: mode,
      filename: filename,
      filename_cursor: filename_cursor
    }
  end

  @doc """
  Navigate to a new directory.
  """
  def navigate_to(%__MODULE__{} = state, path) do
    case File.dir?(path) do
      true ->
        entries = list_directory(path, state.show_hidden, state.filter)
        content_height = length(entries) * @item_height
        lf = list_frame(state.frame, state.mode)

        %{
          state
          | current_path: path,
            entries: entries,
            selected_index: 0,
            scroll: init_scroll(lf, content_height: content_height)
        }

      false ->
        state
    end
  end

  @doc """
  Navigate up one directory level.
  """
  def navigate_up(%__MODULE__{current_path: current_path} = state) do
    parent = Path.dirname(current_path)

    if parent != current_path do
      navigate_to(state, parent)
    else
      state
    end
  end

  @doc """
  Select the next item in the list.
  """
  def select_next(%__MODULE__{entries: entries, selected_index: idx} = state) do
    new_idx = min(idx + 1, length(entries) - 1)

    state
    |> Map.put(:selected_index, new_idx)
    |> ensure_selected_visible()
  end

  @doc """
  Select the previous item in the list.
  """
  def select_prev(%__MODULE__{selected_index: idx} = state) do
    new_idx = max(idx - 1, 0)

    state
    |> Map.put(:selected_index, new_idx)
    |> ensure_selected_visible()
  end

  @doc """
  Get the currently selected entry.
  """
  def selected_entry(%__MODULE__{entries: entries, selected_index: idx}) do
    Enum.at(entries, idx)
  end

  @doc """
  Activate (enter directory or select file) the current selection.
  Returns `{:directory, new_state}` or `{:file, path}`.
  """
  def activate_selection(%__MODULE__{} = state) do
    case selected_entry(state) do
      %{type: :directory, path: path} ->
        {:directory, navigate_to(state, path)}

      %{type: :file, path: path} ->
        {:file, path}

      nil ->
        {:none, state}
    end
  end

  # ===========================================================================
  # Save Mode - Filename Editing
  # ===========================================================================

  @doc """
  Insert a character at the cursor position in the filename.
  """
  def insert_char(%__MODULE__{filename: filename, filename_cursor: cursor} = state, char) do
    {before, after_cursor} = String.split_at(filename, cursor)
    new_filename = before <> char <> after_cursor
    %{state | filename: new_filename, filename_cursor: cursor + String.length(char)}
  end

  @doc """
  Delete the character before the cursor (backspace).
  """
  def backspace(%__MODULE__{filename: filename, filename_cursor: cursor} = state) do
    if cursor > 0 do
      {before, after_cursor} = String.split_at(filename, cursor)
      new_before = String.slice(before, 0..-2//1)
      new_filename = new_before <> after_cursor
      %{state | filename: new_filename, filename_cursor: cursor - 1}
    else
      state
    end
  end

  @doc """
  Delete the character at the cursor position (delete key).
  """
  def delete_at_cursor(%__MODULE__{filename: filename, filename_cursor: cursor} = state) do
    if cursor < String.length(filename) do
      {before, after_cursor} = String.split_at(filename, cursor)
      new_after = String.slice(after_cursor, 1..-1//1)
      new_filename = before <> new_after
      %{state | filename: new_filename}
    else
      state
    end
  end

  @doc """
  Move the cursor left in the filename.
  """
  def cursor_left(%__MODULE__{filename_cursor: cursor} = state) do
    %{state | filename_cursor: max(0, cursor - 1)}
  end

  @doc """
  Move the cursor right in the filename.
  """
  def cursor_right(%__MODULE__{filename: filename, filename_cursor: cursor} = state) do
    %{state | filename_cursor: min(String.length(filename), cursor + 1)}
  end

  @doc """
  Move cursor to the start of the filename.
  """
  def cursor_home(%__MODULE__{} = state) do
    %{state | filename_cursor: 0}
  end

  @doc """
  Move cursor to the end of the filename.
  """
  def cursor_end(%__MODULE__{filename: filename} = state) do
    %{state | filename_cursor: String.length(filename)}
  end

  @doc """
  Get the full save path (current directory + filename).
  """
  def save_path(%__MODULE__{current_path: dir, filename: filename}) do
    Path.join(dir, filename)
  end

  @doc """
  Check if the filename is valid (non-empty, no path separators).
  """
  def valid_filename?(%__MODULE__{filename: filename}) do
    String.length(String.trim(filename)) > 0 and
      not String.contains?(filename, "/") and
      not String.contains?(filename, "\\")
  end

  @doc """
  Get the height of each list item.
  """
  def item_height, do: @item_height

  @doc """
  Calculate the frame for the file list area.
  In save mode, footer is larger to accommodate filename input.
  """
  def list_frame(%Frame{} = frame, mode \\ :open) do
    # Modal takes center 70% of the frame
    modal_width = frame.size.width * 0.7
    modal_height = frame.size.height * 0.7

    # List area: modal minus header (60px) and footer
    # Save mode has larger footer (110px) for filename input
    footer_height = if mode == :save, do: 110, else: 70
    list_height = modal_height - 60 - footer_height

    Frame.new(
      pin: {0, 0},
      size: {modal_width - 40, list_height}
    )
  end

  # Ensure the selected item is visible by scrolling if needed
  defp ensure_selected_visible(%__MODULE__{selected_index: idx, scroll: scroll} = state) do
    item_y = idx * @item_height
    rect = {0, item_y, 100, @item_height}

    new_scroll = scroll_to_show(scroll, rect, 4)
    %{state | scroll: new_scroll}
  end

  # List directory contents, returning sorted entries (directories first)
  defp list_directory(path, show_hidden, filter) do
    case File.ls(path) do
      {:ok, names} ->
        entries =
          names
          |> Enum.filter(fn name ->
            show_hidden || not String.starts_with?(name, ".")
          end)
          |> Enum.map(fn name ->
            full_path = Path.join(path, name)
            type = if File.dir?(full_path), do: :directory, else: :file

            size =
              case File.stat(full_path) do
                {:ok, %{size: s}} -> s
                _ -> nil
              end

            %{name: name, path: full_path, type: type, size: size}
          end)
          |> Enum.filter(fn entry ->
            # Apply file filter (directories always pass)
            entry.type == :directory ||
              filter == nil ||
              String.ends_with?(entry.name, filter)
          end)
          |> Enum.sort_by(fn entry ->
            # Sort: directories first, then alphabetically
            {if(entry.type == :directory, do: 0, else: 1), String.downcase(entry.name)}
          end)

        entries

      {:error, reason} ->
        Logger.warning("Failed to list directory #{path}: #{inspect(reason)}")
        []
    end
  end
end
