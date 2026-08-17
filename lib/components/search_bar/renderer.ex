defmodule ScenicWidgets.SearchBar.Renderer do
  @moduledoc """
  Renderer for the SearchBar component.

  Renders a horizontal search bar with:
  - Text input field with cursor
  - Previous/Next navigation buttons (< >)
  - Match count display (e.g., "3 of 10")
  - Close button (X)

  Layout:
  [Close X] [    Search input field    ] [< Prev] [3/10] [Next >]
  """

  alias ScenicWidgets.SearchBar.State
  alias ScenicWidgets.FloatingPanel
  alias Scenic.Graph
  alias Scenic.Primitives

  # Layout constants
  @bar_height 36
  @button_width 32
  @input_padding 8
  # Text inset inside both input fields
  @text_inset 8
  # Wide enough for "1238/1238" in 14px mono; the count is centred in it.
  @match_count_width 84

  @doc "Layout constants shared with the component's hit-testing."
  def button_width, do: @button_width
  def match_count_width, do: @match_count_width

  @doc """
  Renders the complete search bar (optionally with replace row).
  """
  def render(%State{} = state) do
    %{
      frame: frame,
      theme: theme,
      query: query,
      current_match: current,
      total_matches: total,
      font: font,
      focused: focused,
      cursor_pos: cursor_pos
    } = state

    # Handle both tuple and Dimensions struct for size
    width =
      case frame.size do
        %{width: w} -> w
        {w, _h} -> w
      end

    # Component renders at {0, 0} - Scenic positions the component at frame.pin
    # All coordinates are relative to component origin

    # Calculate component positions (relative to {0, 0})
    close_x = 0
    input_x = @button_width + @input_padding
    nav_start_x = width - @button_width * 2 - @match_count_width
    input_width = nav_start_x - input_x - @input_padding

    # Match count text
    match_text = if total > 0, do: "#{current}/#{total}", else: "0/0"
    match_color = if total > 0, do: theme.match_highlight, else: theme.placeholder

    # Query text to display
    search_focused = state.focused_field == :search
    query_text = if query == "", do: "Search...", else: query
    query_color = if query == "", do: theme.placeholder, else: theme.text

    # Cursor position
    cursor_x = if cursor_pos == 0, do: 0, else: cursor_pos * font.size * 0.6

    panel_height = if state.replace_mode, do: @bar_height * 2, else: @bar_height

    graph =
      Graph.build()
      |> FloatingPanel.add_card({width, panel_height},
        id: :search_bar_bg,
        fill: theme.background,
        border: theme.border
      )
      # Close button background
      |> Primitives.rect({@button_width, @bar_height},
        fill: theme.button_bg,
        translate: {close_x, 0}
      )
      # Close button X lines
      |> Primitives.line({{close_x + 8, 10}, {close_x + 24, 26}},
        stroke: {2, theme.text},
        cap: :round
      )
      |> Primitives.line({{close_x + 24, 10}, {close_x + 8, 26}},
        stroke: {2, theme.text},
        cap: :round
      )
      # Input field background
      |> Primitives.rounded_rectangle({input_width, @bar_height - 8, 4},
        fill: theme.input_background,
        stroke: {1, if(focused and search_focused, do: {100, 150, 255}, else: theme.border)},
        translate: {input_x, 4}
      )
      # Query text
      |> Primitives.text(query_text,
        id: :query_text,
        font: font.name,
        font_size: font.size,
        fill: query_color,
        translate: {input_x + @text_inset, @bar_height / 2 + 5}
      )
      # Cursor line (if focused on search)
      |> maybe_add_cursor(focused and search_focused, input_x + @text_inset + cursor_x, 0, theme)
      # Prev button
      |> Primitives.rect({@button_width, @bar_height},
        fill: theme.button_bg,
        translate: {nav_start_x, 0}
      )
      |> Primitives.text("<",
        font: :roboto_mono,
        font_size: 18,
        fill: theme.text,
        translate: {nav_start_x + @button_width / 2 - 5, @bar_height / 2 + 6}
      )
      # Match count
      |> Primitives.text(match_text,
        id: :match_count,
        font: :roboto_mono,
        font_size: 14,
        fill: match_color,
        text_align: :center,
        translate: {nav_start_x + @button_width + @match_count_width / 2, @bar_height / 2 + 5}
      )
      # Next button
      |> Primitives.rect({@button_width, @bar_height},
        fill: theme.button_bg,
        translate: {nav_start_x + @button_width + @match_count_width, 0}
      )
      |> Primitives.text(">",
        font: :roboto_mono,
        font_size: 18,
        fill: theme.text,
        translate:
          {nav_start_x + @button_width + @match_count_width + @button_width / 2 - 5,
           @bar_height / 2 + 6}
      )

    # Conditionally add replace row
    if state.replace_mode do
      render_replace_row(graph, state, width)
    else
      graph
    end
  end

  @doc """
  Renders the replace row (second row shown when replace_mode is true).
  """
  def render_replace_row(graph, %State{} = state, width) do
    %{theme: theme, font: font, replace_query: rq, replace_cursor_pos: rcp} = state
    replace_focused = state.focused_field == :replace

    # Replace row is offset by @bar_height (below the search row)
    row_y = @bar_height

    # Replace button width
    replace_btn_width = 70
    all_btn_width = 40

    input_x = @button_width + @input_padding
    nav_start_x = width - replace_btn_width - all_btn_width - @input_padding
    input_width = nav_start_x - input_x - @input_padding

    # Replace text
    replace_display = if rq == "", do: "Replace...", else: rq
    replace_color = if rq == "", do: theme.placeholder, else: theme.text
    replace_cursor_x = if rcp == 0, do: 0, else: rcp * font.size * 0.6

    graph
    # Close button placeholder (same width as search row close button)
    |> Primitives.rect({@button_width, @bar_height},
      fill: theme.button_bg,
      translate: {0, row_y}
    )
    # Replace input field background
    |> Primitives.rounded_rectangle({input_width, @bar_height - 8, 4},
      fill: theme.input_background,
      stroke: {1, if(replace_focused, do: {100, 150, 255}, else: theme.border)},
      translate: {input_x, row_y + 4}
    )
    # Replace text (placeholder or actual)
    |> Primitives.text(replace_display,
      id: :replace_text,
      font: font.name,
      font_size: font.size,
      fill: replace_color,
      translate: {input_x + @text_inset, row_y + @bar_height / 2 + 5}
    )
    # Cursor in replace field
    |> maybe_add_replace_cursor(
      replace_focused,
      input_x + @text_inset + replace_cursor_x,
      row_y,
      theme
    )
    # "Replace" button
    |> Primitives.rect({replace_btn_width, @bar_height - 4},
      id: :replace_btn_bg,
      fill: theme.button_bg,
      translate: {nav_start_x, row_y + 2}
    )
    |> Primitives.text("Replace",
      font: :roboto_mono,
      font_size: 12,
      fill: theme.text,
      translate: {nav_start_x + 5, row_y + @bar_height / 2 + 4}
    )
    # "All" button
    |> Primitives.rect({all_btn_width, @bar_height - 4},
      id: :replace_all_btn_bg,
      fill: theme.button_bg,
      translate: {nav_start_x + replace_btn_width + 2, row_y + 2}
    )
    |> Primitives.text("All",
      font: :roboto_mono,
      font_size: 12,
      fill: theme.text,
      translate:
        {nav_start_x + replace_btn_width + 2 + all_btn_width / 2 - 8, row_y + @bar_height / 2 + 4}
    )
  end

  defp maybe_add_replace_cursor(graph, false, _x, _row_y, _theme), do: graph

  defp maybe_add_replace_cursor(graph, true, x, row_y, theme) do
    graph
    |> Primitives.line({{x, row_y + 8}, {x, row_y + @bar_height - 8}},
      id: :replace_cursor,
      stroke: {2, theme.text}
    )
  end

  defp maybe_add_cursor(graph, false, _x, _y, _theme), do: graph

  defp maybe_add_cursor(graph, true, x, _y, theme) do
    graph
    |> Primitives.line({{x, 8}, {x, @bar_height - 8}},
      id: :cursor,
      stroke: {2, theme.text}
    )
  end

  @doc """
  Updates the match count display.
  """
  def update_match_count(graph, %State{current_match: current, total_matches: total, theme: theme}) do
    display_text =
      if total > 0 do
        "#{current}/#{total}"
      else
        "0/0"
      end

    text_color = if total > 0, do: theme.match_highlight, else: theme.placeholder

    Graph.modify(graph, :match_count, fn primitive ->
      Primitives.text(primitive, display_text, fill: text_color)
    end)
  end
end
