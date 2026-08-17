defmodule ScenicWidgets.TabBar.State do
  @moduledoc """
  State management for the TabBar component.

  ## Tab Structure
  Each tab is represented as a map with:
  - `:id` - Unique identifier for the tab (required)
  - `:label` - Display text for the tab (required)
  - `:closeable` - Whether the tab can be closed (default: true)

  ## Example
      tabs = [
        %{id: :tab1, label: "main.ex"},
        %{id: :tab2, label: "README.md", closeable: false},
        %{id: :tab3, label: "very_long_filename_that_will_be_truncated.ex"}
      ]
  """

  @type tab :: %{
          id: atom() | String.t(),
          label: String.t(),
          closeable: boolean()
        }

  @type t :: %__MODULE__{
          frame: map(),
          tabs: [tab()],
          selected_id: atom() | String.t() | nil,
          scroll_offset: number(),
          hovered_tab_id: atom() | String.t() | nil,
          hovered_close_id: atom() | String.t() | nil,
          theme: map(),
          tab_widths: map()
        }

  defstruct [
    :frame,
    tabs: [],
    selected_id: nil,
    scroll_offset: 0,
    hovered_tab_id: nil,
    hovered_close_id: nil,
    dragging_tab_id: nil,
    drag_reordered?: false,
    theme: %{},
    tab_widths: %{}
  ]

  @default_theme %{
    # Colors
    # Dark gray background
    background: {45, 45, 45},
    # Same as bar
    tab_background: {45, 45, 45},
    # Slightly lighter on hover
    tab_hover_background: {60, 60, 60},
    # Darker for selected
    tab_selected_background: {30, 30, 30},
    # Light gray text
    text_color: {180, 180, 180},
    # White for selected
    text_selected_color: {255, 255, 255},
    # Gray X
    close_button_color: {150, 150, 150},
    # White X on hover
    close_button_hover_color: {255, 255, 255},
    # Bright blue stripe (VS Code style)
    selection_indicator_color: {0, 150, 255},
    # Subtle separator between tabs
    separator_color: {60, 60, 60},

    # Dimensions
    height: 35,
    min_tab_width: 100,
    max_tab_width: 200,
    # Horizontal padding inside tab
    tab_padding: 12,
    close_button_size: 16,
    close_button_margin: 8,
    selection_indicator_height: 3,

    # Typography
    font: :roboto_mono,
    font_size: 13
  }

  @doc """
  Create a new TabBar state from initialization data.

  ## Options
  - `:frame` - Widgex.Frame struct (required)
  - `:tabs` - List of tab maps (default: [])
  - `:selected_id` - Initially selected tab ID (default: first tab's ID)
  - `:theme` - Theme overrides (merged with defaults)
  """
  def new(%Widgex.Frame{} = frame) do
    new(%{frame: frame, tabs: []})
  end

  def new(%{frame: frame} = data) do
    tabs = normalize_tabs(Map.get(data, :tabs, []))
    theme = Map.merge(@default_theme, Map.get(data, :theme, %{}))

    # Default to first tab selected if not specified
    selected_id =
      Map.get(data, :selected_id) ||
        case tabs do
          [first | _] -> first.id
          [] -> nil
        end

    state = %__MODULE__{
      frame: frame,
      tabs: tabs,
      selected_id: selected_id,
      scroll_offset: 0,
      hovered_tab_id: nil,
      hovered_close_id: nil,
      dragging_tab_id: nil,
      drag_reordered?: false,
      theme: theme,
      tab_widths: %{}
    }

    # Calculate tab widths based on labels
    state = %{state | tab_widths: calculate_tab_widths(state)}
    ensure_selected_visible(state)
  end

  @doc """
  Normalize tab data to ensure all required fields exist.
  """
  def normalize_tabs(tabs) when is_list(tabs) do
    Enum.map(tabs, fn tab ->
      %{
        id: Map.fetch!(tab, :id),
        label: Map.get(tab, :label, "Untitled"),
        closeable: Map.get(tab, :closeable, true)
      }
    end)
  end

  @doc """
  Calculate the width of each tab based on its label.
  Uses a simple character-based estimate since we don't have access to font metrics.
  """
  def calculate_tab_widths(%__MODULE__{tabs: tabs, theme: theme}) do
    min_width = theme.min_tab_width
    max_width = theme.max_tab_width
    padding = theme.tab_padding * 2
    close_size = theme.close_button_size + theme.close_button_margin
    # Approximate character width
    char_width = theme.font_size * 0.6

    tabs
    |> Enum.map(fn tab ->
      text_width = String.length(tab.label) * char_width
      close_width = if tab.closeable, do: close_size, else: 0
      raw_width = text_width + padding + close_width

      width =
        raw_width
        |> max(min_width)
        |> min(max_width)

      {tab.id, width}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Get the total width of all tabs (for scroll calculations).
  """
  def total_tabs_width(%__MODULE__{tabs: tabs, tab_widths: widths}) do
    Enum.reduce(tabs, 0, fn tab, acc ->
      acc + Map.get(widths, tab.id, 100)
    end)
  end

  @doc """
  Get the maximum scroll offset (0 if tabs fit within frame).
  """
  def max_scroll_offset(%__MODULE__{frame: frame} = state) do
    total = total_tabs_width(state)
    visible_width = frame.size.width
    max(0, total - visible_width)
  end

  @doc """
  Get the X position of a tab (accounting for scroll offset).
  """
  def tab_x_position(%__MODULE__{tabs: tabs, tab_widths: widths, scroll_offset: offset}, tab_id) do
    # Sum widths of all tabs before this one
    x =
      Enum.reduce_while(tabs, 0, fn tab, acc ->
        if tab.id == tab_id do
          {:halt, acc}
        else
          {:cont, acc + Map.get(widths, tab.id, 100)}
        end
      end)

    x - offset
  end

  @doc """
  Get bounds for a specific tab (for hit testing).
  Returns {x, y, width, height} or nil if tab not found.
  """
  def get_tab_bounds(%__MODULE__{tab_widths: widths, theme: theme} = state, tab_id) do
    case Map.get(widths, tab_id) do
      nil ->
        nil

      width ->
        x = tab_x_position(state, tab_id)
        {x, 0, width, theme.height}
    end
  end

  @doc """
  Get bounds for a tab's close button.
  Returns {x, y, width, height} or nil if tab not found or not closeable.
  """
  def get_close_button_bounds(
        %__MODULE__{tabs: tabs, tab_widths: widths, theme: theme} = state,
        tab_id
      ) do
    tab = Enum.find(tabs, &(&1.id == tab_id))

    case {tab, Map.get(widths, tab_id)} do
      {nil, _} ->
        nil

      {%{closeable: false}, _} ->
        nil

      {_tab, tab_width} ->
        tab_x = tab_x_position(state, tab_id)
        size = theme.close_button_size
        margin = theme.close_button_margin

        # Position close button on the right side of the tab
        x = tab_x + tab_width - size - margin
        y = (theme.height - size) / 2

        {x, y, size, size}
    end
  end

  @doc """
  Find which tab (if any) is at the given coordinates.
  Returns {:tab, tab_id} or {:close, tab_id} or :none
  """
  def hit_test(%__MODULE__{tabs: tabs} = state, {px, py}) do
    # First check close buttons (they're on top)
    close_hit =
      Enum.find_value(tabs, fn tab ->
        if tab.closeable do
          case get_close_button_bounds(state, tab.id) do
            {x, y, w, h} when px >= x and px <= x + w and py >= y and py <= y + h ->
              {:close, tab.id}

            _ ->
              nil
          end
        end
      end)

    if close_hit do
      close_hit
    else
      # Then check tab bodies
      tab_hit =
        Enum.find_value(tabs, fn tab ->
          case get_tab_bounds(state, tab.id) do
            {x, _y, w, h} when px >= x and px <= x + w and py >= 0 and py <= h ->
              {:tab, tab.id}

            _ ->
              nil
          end
        end)

      tab_hit || :none
    end
  end

  @doc """
  Check if a point is inside the tab bar bounds.
  """
  def point_inside?(%__MODULE__{frame: frame, theme: theme}, {px, py}) do
    px >= 0 and px <= frame.size.width and py >= 0 and py <= theme.height
  end

  @doc "Clamp scroll so the selected tab is fully visible."
  @doc """
  Is this tab actually on screen right now?

  Tab positions are scroll-relative (`tab_x_position/2` subtracts the scroll
  offset), so once the tabs overflow the bar, tabs scrolled off the left sit
  at NEGATIVE x and tabs past the right edge sit beyond the frame. Such a tab
  is not clickable, and anything that treats it as clickable — automation,
  accessibility tooling, a test suite — ends up clicking empty space outside
  the bar.

  Requires the tab to be fully within the bar: a half-clipped tab is a
  coin-flip for whoever clicks its midpoint.
  """
  def tab_visible?(%__MODULE__{frame: frame} = state, tab_id) do
    case get_tab_bounds(state, tab_id) do
      nil ->
        false

      {x, _y, width, _height} ->
        x >= 0 and x + width <= frame.size.width
    end
  end

  def ensure_selected_visible(%__MODULE__{selected_id: nil} = state), do: state

  def ensure_selected_visible(state) do
    case get_tab_bounds(state, state.selected_id) do
      nil ->
        state

      {x, _y, width, _height} ->
        viewport_width = state.frame.size.width

        offset =
          cond do
            x < 0 -> state.scroll_offset + x
            x + width > viewport_width -> state.scroll_offset + x + width - viewport_width
            true -> state.scroll_offset
          end

        %{state | scroll_offset: offset |> max(0) |> min(max_scroll_offset(state))}
    end
  end
end
