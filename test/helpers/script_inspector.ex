defmodule ScenicWidgets.TestHelpers.ScriptInspector do
  @moduledoc """
  Test helper for inspecting rendered Scenic content in Widget Workbench.

  Provides utilities to examine what's actually rendered to the screen,
  enabling true black-box testing of GUI components.
  """

  require Logger

  @doc """
  Checks if the rendered text output is empty (user content only).
  """
  def rendered_text_empty?() do
    get_user_content() |> Enum.empty?()
  end

  @doc """
  Checks if the rendered output contains the specified text (user content only).
  For TextField testing, this filters out Widget Workbench UI.
  """
  def rendered_text_contains?(expected_text) do
    user_content = get_user_content()
    IO.puts("🔍 ScriptInspector: Looking for '#{expected_text}' in user_content:")
    IO.inspect(user_content, label: "User content list", limit: 10)

    result = Enum.any?(user_content, fn text ->
      String.contains?(text, expected_text)
    end)

    IO.puts("🔍 Found: #{result}")
    result
  end

  @doc """
  Gets the full rendered text as a string for inspection.
  Includes all text (for UI verification).
  """
  def get_rendered_text_string() do
    try do
      script_data = get_script_table_directly()

      # Flatten all script entries to get all draw commands
      all_commands = script_data
      |> Enum.flat_map(fn
        {_id, commands, _pid} -> commands
        commands when is_list(commands) -> commands
        _ -> []
      end)

      all_commands
      |> extract_text_primitives()
      |> Enum.map(&extract_text_content/1)
      |> Enum.join(" ")
      |> String.trim()
    rescue
      error ->
        Logger.warn("Failed to get rendered text: #{Exception.message(error)}")
        ""
    end
  end

  @doc """
  Gets user-entered content only (filters out all GUI elements).
  """
  def get_user_content() do
    try do
      script_data = get_script_table_directly()

      all_commands = script_data
      |> Enum.flat_map(fn
        {_id, commands, _pid} -> commands
        commands when is_list(commands) -> commands
        _ -> []
      end)

      all_text = all_commands
      |> extract_text_primitives()
      |> Enum.map(&extract_text_content/1)

      IO.puts("🔍 ALL text primitives (#{length(all_text)}): #{inspect(all_text, limit: :infinity)}")

      filtered = all_text
      |> Enum.reject(&is_widget_workbench_ui?/1)
      |> Enum.reject(&is_common_gui_element?/1)

      IO.puts("🔍 After filtering (#{length(filtered)}): #{inspect(filtered, limit: :infinity)}")

      filtered
    rescue
      error ->
        Logger.warn("Failed to get user content: #{Exception.message(error)}")
        []
    end
  end

  @doc """
  Get the script table directly from the viewport without going through ScenicMcp.Probes.
  This works in test environments where ScenicMcp may not be fully available.
  Uses configured viewport name from scenic_mcp config.
  """
  def get_script_table_directly() do
    # Get viewport name from config (allows test and dev to run simultaneously)
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :main_viewport)

    case Scenic.ViewPort.info(viewport_name) do
      {:ok, vp_info} ->
        # Get the script table reference from viewport info
        script_table = vp_info.script_table

        # Read all entries from the ETS table
        :ets.tab2list(script_table)

      _error ->
        []
    end
  end

  @doc """
  Debug function to dump the script table contents.
  """
  def debug_script_table() do
    try do
      script_data = get_script_table_directly()

      IO.puts("\n=== SCRIPT TABLE DEBUG ===")
      IO.puts("Total script entries: #{length(script_data)}")

      script_data
      |> Enum.with_index()
      |> Enum.each(fn {entry, index} ->
        IO.puts("Entry #{index}: #{inspect(entry, limit: :infinity)}")
      end)

      IO.puts("=== END SCRIPT TABLE ===\n")
    rescue
      error ->
        IO.puts("Failed to debug script table: #{Exception.message(error)}")
    end
  end

  @doc """
  Gets statistics about the rendered content.
  """
  def get_render_stats() do
    try do
      script_data = get_script_table_directly()

      text_primitives = extract_text_primitives(script_data)
      rect_primitives = extract_rect_primitives(script_data)

      %{
        total_script_entries: length(script_data),
        text_primitives_count: length(text_primitives),
        rect_primitives_count: length(rect_primitives),
        total_text_length: get_rendered_text_string() |> String.length()
      }
    rescue
      error ->
        Logger.warn("Failed to get render stats: #{Exception.message(error)}")
        %{error: Exception.message(error)}
    end
  end

  @doc """
  Gets all text primitives with their positions (x, y coordinates).
  Returns a list of maps with text content and position information.

  ## Returns
  List of `%{text: string, x: number, y: number}` maps, sorted by Y then X.

  ## Example
      iex> ScriptInspector.get_text_with_positions()
      [
        %{text: "Hello", x: 100, y: 50},
        %{text: "World", x: 150, y: 50},
        %{text: "Next line", x: 100, y: 85}
      ]
  """
  def get_text_with_positions() do
    try do
      script_data = get_script_table_directly()

      all_commands = script_data
      |> Enum.flat_map(fn
        {_id, commands, _pid} -> commands
        commands when is_list(commands) -> commands
        _ -> []
      end)

      all_commands
      |> Enum.filter(&is_text_primitive?/1)
      |> Enum.map(&extract_text_with_position/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn %{y: y, x: x} -> {y, x} end)
    rescue
      error ->
        Logger.warn("Failed to get text with positions: #{Exception.message(error)}")
        []
    end
  end

  @doc """
  Gets text primitives grouped by line (Y-coordinate).
  Text with similar Y-coordinates (within tolerance) are grouped together.

  ## Parameters
  - `y_tolerance`: Maximum Y-difference to consider text on same line (default: 5)

  ## Returns
  List of `{line_y, [text_items]}` tuples, sorted by Y coordinate (top to bottom).

  ## Example
      iex> ScriptInspector.get_text_by_lines()
      [
        {50, ["Hello", "World"]},
        {85, ["Next", "line"]}
      ]
  """
  def get_text_by_lines(y_tolerance \\ 5) do
    text_items = get_text_with_positions()

    # Group by Y coordinate (with tolerance)
    text_items
    |> Enum.group_by(fn %{y: y} ->
      # Round to nearest tolerance value to group similar Y coords
      round(y / y_tolerance) * y_tolerance
    end)
    |> Enum.map(fn {line_y, items} ->
      # Sort items on same line by X coordinate (left to right)
      sorted_items = Enum.sort_by(items, fn %{x: x} -> x end)
      text_list = Enum.map(sorted_items, fn %{text: text} -> text end)
      {line_y, text_list}
    end)
    |> Enum.sort_by(fn {y, _items} -> y end)  # Sort lines top to bottom
  end

  @doc """
  Checks if specific text appears on a given line number (1-indexed).

  ## Parameters
  - `text`: The text content to search for
  - `line_number`: Line number (1 = first line, 2 = second line, etc.)

  ## Example
      iex> ScriptInspector.text_appears_on_line?("Hello", 1)
      true
  """
  def text_appears_on_line?(text, line_number) do
    lines = get_text_by_lines()

    case Enum.at(lines, line_number - 1) do
      nil -> false
      {_y, text_list} ->
        Enum.any?(text_list, fn item -> String.contains?(item, text) end)
    end
  end

  @doc """
  Checks if text content spans multiple lines (appears on different Y coordinates).

  ## Parameters
  - `text_pattern`: Text pattern to search for across lines

  ## Returns
  Boolean indicating if the pattern appears on multiple distinct lines.

  ## Example
      iex> ScriptInspector.text_wraps_to_lines?("long")
      true  # If "long" appears on line 1 and line 2
  """
  def text_wraps_to_lines?(text_pattern) do
    text_items = get_text_with_positions()

    matching_items = Enum.filter(text_items, fn %{text: text} ->
      String.contains?(text, text_pattern)
    end)

    # Check if matching items have different Y coordinates
    y_coords = matching_items
    |> Enum.map(fn %{y: y} -> y end)
    |> Enum.uniq()

    length(y_coords) > 1
  end

  @doc """
  Gets the number of distinct lines (unique Y coordinates) in rendered content.

  ## Example
      iex> ScriptInspector.get_line_count()
      3  # Content spans 3 lines
  """
  def get_line_count() do
    get_text_by_lines() |> length()
  end

  # Private helper functions

  defp extract_text_primitives(script_data) do
    script_data
    |> Enum.filter(&is_text_primitive?/1)
  end

  defp extract_rect_primitives(script_data) do
    script_data
    |> Enum.filter(&is_rect_primitive?/1)
  end

  defp is_text_primitive?(entry) do
    case entry do
      {_id, :text, _data, _opts} -> true
      {:text, _data, _opts} -> true
      %{type: :text} -> true
      {:draw_text, _text} -> true
      _ -> false
    end
  end

  defp is_rect_primitive?(entry) do
    case entry do
      {_id, :rect, _data, _opts} -> true
      {:rect, _data, _opts} -> true
      %{type: :rect} -> true
      _ -> false
    end
  end

  defp extract_text_content(entry) do
    case entry do
      {_id, :text, text_data, _opts} when is_binary(text_data) -> text_data
      {:text, text_data, _opts} when is_binary(text_data) -> text_data
      %{type: :text, data: text_data} when is_binary(text_data) -> text_data
      {:draw_text, text} when is_binary(text) -> text
      _ -> ""
    end
  end

  defp extract_text_with_position(entry) do
    case entry do
      {_id, :text, text_data, opts} when is_binary(text_data) ->
        extract_position_and_text(text_data, opts)

      {:text, text_data, opts} when is_binary(text_data) ->
        extract_position_and_text(text_data, opts)

      %{type: :text, data: text_data, opts: opts} when is_binary(text_data) ->
        extract_position_and_text(text_data, opts)

      {:draw_text, text} ->
        # draw_text might not have position info, default to (0, 0)
        %{text: text, x: 0, y: 0}

      _ ->
        nil
    end
  end

  defp extract_position_and_text(text, opts) when is_list(opts) do
    # Extract translate coordinates from opts list
    {x, y} = case Keyword.get(opts, :translate, {0, 0}) do
      {x_val, y_val} -> {x_val, y_val}
      _ -> {0, 0}
    end

    %{text: text, x: x, y: y}
  end

  defp extract_position_and_text(text, _opts) do
    # Fallback if opts is not a keyword list
    %{text: text, x: 0, y: 0}
  end

  # Filter out Widget Workbench UI elements
  defp is_widget_workbench_ui?(text) when is_binary(text) do
    workbench_ui_patterns = [
      # Main UI text
      "Widget Workbench",
      "Design & test Scenic components",
      "New Widget",
      "Load Component",
      "Reset Scene",
      # Button/coordinate labels
      "A:", "B:", "C:", "D:",
      # Component modal text
      "Select Component",
      "Failed to load:",
      "function",
      "is undefined",
      "(module",
      "is not available)",
      "(Component isolation working!)",
      # Common error patterns
      "Error:",
      "undefined",
      "not available"
    ]

    # Check for exact or partial matches
    matches_pattern = Enum.any?(workbench_ui_patterns, fn pattern ->
      String.contains?(text, pattern) or text == pattern
    end)

    # Filter coordinate patterns like "(600, 545)"
    is_coordinate = String.match?(text, ~r/^\(\d+,\s*\d+\)$/)

    # Filter single special characters that are UI symbols
    is_symbol = String.length(text) == 1 and text in ["+", "×", "◊", "⋮", "|", "-", "=", "*"]

    result = matches_pattern or is_coordinate or is_symbol

    if result and String.length(text) > 10 do
      IO.puts("🔍 FILTERED OUT (workbench UI): '#{text}' (pattern=#{matches_pattern}, coord=#{is_coordinate}, symbol=#{is_symbol})")
    end

    result
  end

  defp is_widget_workbench_ui?(_), do: false

  # Filter out common GUI elements (similar to quillex)
  defp is_common_gui_element?(text) when is_binary(text) do
    # Font hashes (long alphanumeric strings with multiple underscores/dashes AND numbers)
    # Example: "Roboto_Mono_Regular_0abc123def456"
    has_multiple_separators = (String.split(text, "_") |> length() >= 3) or
                              (String.split(text, "-") |> length() >= 3)
    font_hash = String.length(text) > 30 and
                String.match?(text, ~r/^[A-Za-z0-9_-]+$/) and
                String.match?(text, ~r/[0-9]/) and
                has_multiple_separators

    # Script IDs (UUIDs or similar)
    script_id = String.contains?(text, "-") and
                String.length(text) > 10 and
                String.match?(text, ~r/^[A-Za-z0-9_-]+$/) and
                length(String.split(text, "-")) >= 3

    # Internal IDs (_something_)
    internal_id = String.starts_with?(text, "_") and String.ends_with?(text, "_")

    result = font_hash or script_id or internal_id

    if result and String.length(text) > 10 do
      IO.puts("🔍 FILTERED OUT (common GUI): '#{text}' (font=#{font_hash}, script=#{script_id}, internal=#{internal_id})")
    end

    result
  end

  defp is_common_gui_element?(_), do: false
end
