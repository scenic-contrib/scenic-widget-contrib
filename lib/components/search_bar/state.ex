defmodule ScenicWidgets.SearchBar.State do
  @moduledoc """
  State struct for the SearchBar component.

  The SearchBar provides a text input for search queries with:
  - Search text input field
  - Previous/Next navigation buttons
  - Match count display (e.g., "3 of 10")
  - Close button

  ## Events Emitted

  - `{:search_query_changed, id, query}` - when user types in search field
  - `{:search_next, id}` - when clicking next or pressing Enter
  - `{:search_prev, id}` - when clicking previous or pressing Shift+Enter
  - `{:search_close, id}` - when clicking close or pressing Escape
  """

  alias Widgex.Frame

  defstruct [
    # Component ID
    :id,
    # Widgex.Frame for positioning
    :frame,
    # Current search query string
    :query,
    # Current match index (1-based for display)
    :current_match,
    # Total number of matches
    :total_matches,
    # Whether the search input is focused
    :focused,
    # Cursor position in query string
    :cursor_pos,
    # Font settings
    :font,
    # Color theme
    :theme,
    # If true, next input clears query (mimics select-all)
    :replace_on_next_input,
    # Replace mode fields
    # Whether replace row is visible
    replace_mode: false,
    # Current replacement text
    replace_query: "",
    # Cursor position in replace string
    replace_cursor_pos: 0,
    # Which field has focus: :search or :replace
    focused_field: :search,
    # Find options. The same two the project-search pane offers, because a
    # find that can only match literally and only exactly is a different
    # feature from the one in the sidebar, and nobody wants to learn two.
    case_sensitive: false,
    regex: false,
    # Which widget the pointer is over, for the tooltip. An icon that cannot
    # say what it does has to be guessed at.
    hovered: nil
  ]

  @type t :: %__MODULE__{
          id: atom(),
          frame: Frame.t(),
          query: String.t(),
          current_match: non_neg_integer(),
          total_matches: non_neg_integer(),
          focused: boolean(),
          cursor_pos: non_neg_integer(),
          font: map(),
          theme: map(),
          replace_on_next_input: boolean(),
          replace_mode: boolean(),
          replace_query: String.t(),
          replace_cursor_pos: non_neg_integer(),
          focused_field: :search | :replace
        }

  @doc """
  Creates a new SearchBar state.

  ## Options
  - `:id` - Component ID (required)
  - `:frame` - Widgex.Frame for positioning (required)
  - `:query` - Initial search query (default: "")
  - `:font` - Font settings map with :name and :size
  - `:theme` - Color theme map
  """
  def new(opts) do
    id = opts[:id] || raise ArgumentError, "SearchBar requires :id"
    frame = opts[:frame] || raise ArgumentError, "SearchBar requires :frame"

    default_font = %{
      name: :roboto_mono,
      size: 16,
      metrics: nil
    }

    default_theme = %{
      # Dark gray background
      background: {45, 45, 45},
      # Slightly lighter input area
      input_background: {60, 60, 60},
      # White text (explicit RGB)
      text: {255, 255, 255},
      # Gray placeholder
      placeholder: {128, 128, 128},
      # Border color
      border: {80, 80, 80},
      # Button background
      button_bg: {70, 70, 70},
      # Button hover
      button_hover: {90, 90, 90},
      # Yellow for match count
      match_highlight: {255, 200, 0},
      # The ring around the field that has the keyboard.
      focus_border: {100, 150, 255},
      # A find option that is ON. Off is drawn as nothing at all: two lit
      # buttons among two unlit ones say which is which better than four
      # boxes of slightly different greys.
      option_on: {70, 90, 130},
      option_on_border: {110, 150, 220},
      tooltip_bg: {25, 25, 25},
      tooltip_border: {95, 95, 95},
      tooltip_text: {255, 255, 255},
      tooltip_font_size: 12,
      font: :roboto_mono
    }

    %__MODULE__{
      id: id,
      frame: frame,
      query: opts[:query] || "",
      current_match: 0,
      total_matches: 0,
      focused: true,
      cursor_pos: String.length(opts[:query] || ""),
      font: Map.merge(default_font, opts[:font] || %{}),
      theme: Map.merge(default_theme, opts[:theme] || %{}),
      replace_on_next_input: false,
      replace_mode: opts[:replace_mode] || false,
      replace_query: "",
      replace_cursor_pos: 0,
      focused_field: :search,
      case_sensitive: opts[:case_sensitive] || false,
      regex: opts[:regex] || false,
      hovered: nil
    }
  end

  @doc "Flip one of the find options."
  def toggle_option(%__MODULE__{} = state, :case_sensitive),
    do: %{state | case_sensitive: not state.case_sensitive}

  def toggle_option(%__MODULE__{} = state, :regex), do: %{state | regex: not state.regex}

  @doc "The find options, in the shape the search action takes them."
  def search_opts(%__MODULE__{} = state),
    do: [case_sensitive: state.case_sensitive, regex: state.regex]

  # ── Layout ────────────────────────────────────────────────────────────────
  #
  # One list of rectangles, used by BOTH the renderer and the hit test. They
  # used to be worked out twice, in two places, from the same handful of
  # constants — which is the kind of duplication that ends with a button that
  # draws in one place and responds in another.
  #
  # The arrangement follows the one every editor has settled on: the
  # disclosure caret on the far left, the close on the far right, and the
  # option toggles tucked inside the right-hand end of the field they apply
  # to.

  # Metrics, in one place, so the bar has a rhythm rather than a collection of
  # magic numbers. The two that matter: @pad is the air between the card's
  # edge and anything in it, and @gap is the air between groups of controls.
  # Everything else is sized to sit comfortably inside those.
  @bar_height 38
  @field_height 30
  @caret_width 22
  @button_width 30
  @toggle_width 22
  # The option pair sits inside the field. Four pixels on every edge — top,
  # bottom, between the buttons, and at the field's right side — makes that
  # containment deliberate instead of looking like two labels touching.
  @toggle_gap 4
  # Enough for "1238/1238" at 13px mono without being a canyon at "1/3".
  @match_count_width 66
  @pad 10
  @gap 6

  def bar_height, do: @bar_height
  def button_width, do: @button_width
  def match_count_width, do: @match_count_width

  @doc "Total height, which depends on whether the replace row is showing."
  def height(%__MODULE__{replace_mode: true}), do: @bar_height * 2
  def height(%__MODULE__{}), do: @bar_height

  @doc """
  Every clickable rectangle, in component-local coordinates.

  `%{id:, x:, y:, w:, h:, tooltip:}`. The id is what the hit test matches on
  and what the renderer draws; the tooltip is what the thing says it does.
  """
  def widgets(%__MODULE__{} = state) do
    width = frame_width(state)

    # Laid out from the right: the close button anchors the row, and
    # everything else is measured back from it.
    close_x = width - @pad - @button_width
    next_x = close_x - @gap - @button_width
    count_x = next_x - @match_count_width
    prev_x = count_x - @button_width

    input_x = @pad + @caret_width + @gap
    input_w = max(prev_x - @gap - input_x, 60)

    field_y = round((@bar_height - @field_height) / 2)

    # Square, like every other box in this bar and in the search pane. It was
    # `@field_height - 6` tall against `@toggle_width` wide — 20 by 22, wrong
    # the OTHER way from the pane's, which is why neither looked square and
    # neither looked like a mistake.
    toggle_h = @toggle_width
    toggle_y = round((@bar_height - toggle_h) / 2)
    regex_x = input_x + input_w - @toggle_gap - @toggle_width
    case_x = regex_x - @toggle_gap - @toggle_width

    search_row = [
      # The caret spans every row the bar has. Open, the bar is two rows tall
      # and a one-row caret leaves its hover highlight covering half of what
      # the tooltip is pointing at — the button should look like the handle
      # for the whole thing, because that is what it is.
      %{
        id: :toggle_replace,
        x: @pad,
        y: 0,
        w: @caret_width,
        h: height(state),
        tooltip: "Toggle Replace"
      },
      %{id: :search_field, x: input_x, y: field_y, w: input_w, h: @field_height, tooltip: nil},
      %{
        id: {:toggle, :case_sensitive},
        x: case_x,
        y: toggle_y,
        w: @toggle_width,
        h: toggle_h,
        tooltip: "Match Case"
      },
      %{
        id: {:toggle, :regex},
        x: regex_x,
        y: toggle_y,
        w: @toggle_width,
        h: toggle_h,
        tooltip: "Use Regular Expression"
      },
      %{
        id: :prev,
        x: prev_x,
        y: 0,
        w: @button_width,
        h: @bar_height,
        tooltip: "Previous Match (Shift+Enter)"
      },
      %{id: :count, x: count_x, y: 0, w: @match_count_width, h: @bar_height, tooltip: nil},
      %{
        id: :next,
        x: next_x,
        y: 0,
        w: @button_width,
        h: @bar_height,
        tooltip: "Next Match (Enter)"
      },
      %{id: :close, x: close_x, y: 0, w: @button_width, h: @bar_height, tooltip: "Close (Esc)"}
    ]

    search_row ++ replace_row(state, width, input_x, field_y)
  end

  defp replace_row(%__MODULE__{replace_mode: false}, _width, _input_x, _field_y), do: []

  defp replace_row(%__MODULE__{}, width, input_x, field_y) do
    y = @bar_height

    # Replace All sits directly under Close, and Replace under Next, so the
    # two rows share a right-hand edge instead of each finding their own.
    all_x = width - @pad - @button_width
    one_x = all_x - @gap - @button_width
    input_w = max(one_x - @gap - input_x, 60)

    [
      %{
        id: :replace_field,
        x: input_x,
        y: y + field_y,
        w: input_w,
        h: @field_height,
        tooltip: nil
      },
      %{
        id: :replace_one,
        x: one_x,
        y: y,
        w: @button_width,
        h: @bar_height,
        tooltip: "Replace (Enter)"
      },
      %{
        id: :replace_all,
        x: all_x,
        y: y,
        w: @button_width,
        h: @bar_height,
        tooltip: "Replace All"
      }
    ]
  end

  @doc """
  Which widget, if any, is under a point.

  Searched in REVERSE, because the list is in drawing order and the thing
  drawn last is the thing on top. The option toggles sit inside the search
  field's right-hand end, so a forward search hands every click on them to
  the field underneath — which is exactly what happened.
  """
  def widget_at(%__MODULE__{} = state, {x, y}) do
    state
    |> widgets()
    |> Enum.reverse()
    |> Enum.find(fn w ->
      x >= w.x and x <= w.x + w.w and y >= w.y and y <= w.y + w.h
    end)
  end

  @doc "The bar's width, however its frame chose to express it."
  def frame_width(%__MODULE__{frame: frame}) do
    case frame.size do
      %{width: w} -> w
      {w, _h} -> w
    end
  end

  @doc """
  Enable replace mode (show the replace row).
  """
  def enable_replace_mode(%__MODULE__{} = state) do
    %{state | replace_mode: true}
  end

  @doc """
  Toggle focus between search and replace fields (Tab key).
  """
  def toggle_focus(%__MODULE__{focused_field: :search} = state) do
    %{state | focused_field: :replace}
  end

  def toggle_focus(%__MODULE__{focused_field: :replace} = state) do
    %{state | focused_field: :search}
  end

  @doc """
  Insert a character into whichever field is currently focused.
  """
  def insert_char_to_focused(%__MODULE__{focused_field: :search} = state, char) do
    insert_char(state, char)
  end

  def insert_char_to_focused(
        %__MODULE__{focused_field: :replace, replace_query: rq, replace_cursor_pos: pos} = state,
        char
      ) do
    {before, after_cursor} = String.split_at(rq, pos)
    new_query = before <> char <> after_cursor
    %{state | replace_query: new_query, replace_cursor_pos: pos + String.length(char)}
  end

  @doc """
  Delete character before cursor in the focused field.
  """
  def delete_before_cursor_focused(%__MODULE__{focused_field: :search} = state) do
    delete_before_cursor(state)
  end

  def delete_before_cursor_focused(
        %__MODULE__{focused_field: :replace, replace_query: rq, replace_cursor_pos: pos} = state
      )
      when pos > 0 do
    graphemes = String.graphemes(rq)
    new_graphemes = List.delete_at(graphemes, pos - 1)
    %{state | replace_query: Enum.join(new_graphemes), replace_cursor_pos: pos - 1}
  end

  def delete_before_cursor_focused(%__MODULE__{} = state), do: state

  @doc """
  Updates the match count display.
  """
  def set_matches(%__MODULE__{} = state, current, total) do
    %{state | current_match: current, total_matches: total}
  end

  @doc """
  Sets the search query and resets cursor to end.
  Sets replace_on_next_input to true so that the next typed character
  replaces the query (mimics select-all behavior).
  """
  def set_query(%__MODULE__{} = state, query) when is_binary(query) do
    %{
      state
      | query: query,
        cursor_pos: String.length(query),
        # Only replace if there's a query to replace
        replace_on_next_input: query != ""
    }
  end

  @doc """
  Appends a character to the query at cursor position.
  If replace_on_next_input is true, clears the query first (mimics select-all replacement).
  """
  def insert_char(%__MODULE__{replace_on_next_input: true} = state, char) when is_binary(char) do
    # Clear query and insert the new character
    %{state | query: char, cursor_pos: String.length(char), replace_on_next_input: false}
  end

  def insert_char(%__MODULE__{query: query, cursor_pos: pos} = state, char)
      when is_binary(char) do
    {before, after_cursor} = String.split_at(query, pos)
    new_query = before <> char <> after_cursor
    %{state | query: new_query, cursor_pos: pos + String.length(char)}
  end

  @doc """
  Deletes character before cursor (backspace).
  Also resets replace_on_next_input flag (user wants to edit, not replace).
  """
  def delete_before_cursor(%__MODULE__{query: query, cursor_pos: pos} = state) when pos > 0 do
    graphemes = String.graphemes(query)
    new_graphemes = List.delete_at(graphemes, pos - 1)
    new_query = Enum.join(new_graphemes)
    %{state | query: new_query, cursor_pos: pos - 1, replace_on_next_input: false}
  end

  def delete_before_cursor(%__MODULE__{} = state), do: %{state | replace_on_next_input: false}

  @doc """
  Deletes character at cursor (delete key).
  """
  def delete_at_cursor(%__MODULE__{query: query, cursor_pos: pos} = state) do
    graphemes = String.graphemes(query)

    if pos < length(graphemes) do
      new_graphemes = List.delete_at(graphemes, pos)
      new_query = Enum.join(new_graphemes)
      %{state | query: new_query}
    else
      state
    end
  end

  @doc """
  Moves cursor left.
  Also resets replace_on_next_input flag (user wants to edit, not replace).
  """
  def cursor_left(%__MODULE__{cursor_pos: pos} = state) when pos > 0 do
    %{state | cursor_pos: pos - 1, replace_on_next_input: false}
  end

  def cursor_left(%__MODULE__{} = state), do: %{state | replace_on_next_input: false}

  @doc """
  Moves cursor right.
  Also resets replace_on_next_input flag (user wants to edit, not replace).
  """
  def cursor_right(%__MODULE__{query: query, cursor_pos: pos} = state) do
    max_pos = String.length(query)

    if pos < max_pos do
      %{state | cursor_pos: pos + 1, replace_on_next_input: false}
    else
      %{state | replace_on_next_input: false}
    end
  end

  @doc """
  Moves cursor to start of query.
  Also resets replace_on_next_input flag (user wants to edit, not replace).
  """
  def cursor_home(%__MODULE__{} = state) do
    %{state | cursor_pos: 0, replace_on_next_input: false}
  end

  @doc """
  Moves cursor to end of query.
  Also resets replace_on_next_input flag (user wants to edit, not replace).
  """
  def cursor_end(%__MODULE__{query: query} = state) do
    %{state | cursor_pos: String.length(query), replace_on_next_input: false}
  end

  @doc """
  Clears the search query.
  """
  def clear(%__MODULE__{} = state) do
    %{state | query: "", cursor_pos: 0, current_match: 0, total_matches: 0}
  end
end
