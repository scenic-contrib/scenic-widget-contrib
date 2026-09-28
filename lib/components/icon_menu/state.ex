defmodule ScenicWidgets.IconMenu.State do
  @moduledoc """
  State management for the IconMenu component.

  IconMenu displays a row of icon buttons that open dropdown menus when clicked.
  Similar to a toolbar with dropdown menus.

  ## Menu Structure
  Each menu is defined as:
  - `:id` - Unique identifier for the menu
  - `:icon` - Single character to display (letter, emoji, or unicode symbol)
  - `:items` - List of menu items [{id, label}] or [{id, label, action_fn}]

  ## Example
      menus = [
        %{id: :file, icon: "F", items: [
          {"new", "New File"},
          {"open", "Open..."},
          {"save", "Save"}
        ]},
        %{id: :edit, icon: "E", items: [
          {"undo", "Undo"},
          {"redo", "Redo"},
          {"cut", "Cut"},
          {"copy", "Copy"},
          {"paste", "Paste"}
        ]},
        %{id: :view, icon: "V", items: [
          {"zoom_in", "Zoom In"},
          {"zoom_out", "Zoom Out"}
        ]}
      ]
  """

  @type menu_item_opts :: %{
          optional(:type) => :toggle | :normal,
          optional(:checked) => boolean(),
          optional(:enabled) => boolean(),
          optional(:tooltip) => String.t()
        }

  @type menu_item ::
          {String.t(), String.t()}
          | {String.t(), String.t(), function()}
          | {String.t(), String.t(), menu_item_opts()}

  @type menu :: %{
          id: atom(),
          icon: String.t(),
          items: [menu_item()]
        }

  @type t :: %__MODULE__{
          frame: map(),
          menus: [menu()],
          active_menu: atom() | nil,
          hovered_menu: atom() | nil,
          hovered_item: String.t() | nil,
          hovered_select_option: term() | nil,
          dragging_slider: String.t() | atom() | nil,
          tooltip: map() | nil,
          tooltip_delay_ms: non_neg_integer(),
          show_shortcuts: boolean(),
          theme: map(),
          dropdown_bounds: map(),
          align: :left | :right
        }

  defstruct [
    :frame,
    menus: [],
    active_menu: nil,
    hovered_menu: nil,
    hovered_item: nil,
    hovered_select_option: nil,
    dragging_slider: nil,
    tooltip: nil,
    tooltip_delay_ms: 600,
    show_shortcuts: true,
    theme: %{},
    dropdown_bounds: %{},
    # How far the open dropdown is scrolled, in pixels. A menu taller than the
    # space beneath it is clamped and scrolls; rows past the bottom edge of the
    # window cannot be clicked, so a feature that is in the menu would still be
    # unreachable.
    dropdown_scroll: 0,
    # A drag of the dropdown's scrollbar in progress, as `{pointer_y, offset}`
    # — where the button went down and how far the panel was wound at that
    # moment. Both, because a drag measured as a running total of pointer
    # samples drifts away from the thumb under the finger.
    dropdown_drag: nil,
    # A stepper's value being typed, as `%{item_id: id, text: "150",
    # pristine?: true}`. `pristine?` is on until the first keystroke: the
    # field opens showing its current value selected, and typing replaces it.
    editing: nil,
    # Default to right alignment (flush with right edge of frame)
    align: :right
  ]

  @default_theme %{
    # Colors
    background: {45, 45, 45},
    icon_color: {180, 180, 180},
    icon_hover_color: {255, 255, 255},
    icon_active_color: {255, 255, 255},
    icon_hover_bg: {60, 60, 60},
    icon_active_bg: {70, 70, 70},
    dropdown_bg: {50, 50, 50},
    dropdown_border: {70, 70, 70},
    item_hover_bg: {0, 122, 204},
    item_text_color: {220, 220, 220},
    item_hover_text_color: {255, 255, 255},

    # Dimensions
    height: 35,
    icon_button_size: 35,
    icon_font_size: 16,
    dropdown_width: 180,
    dropdown_max_width: 420,
    # Widest a dropdown may be drawn. nil falls back to the component's own
    # frame width, which is only ever right when the icon bar spans the window.
    max_dropdown_width: nil,
    dropdown_column_gap: 24,
    dropdown_item_height: 28,
    dropdown_slider_height: 52,
    dropdown_padding: 4,
    # Tallest a dropdown may be drawn. nil means "as tall as its rows"; a host
    # that knows the window height should pass one.
    max_dropdown_height: nil,

    # Typography
    font: :roboto_mono,
    dropdown_font_size: 13
  }

  @doc """
  Create a new IconMenu state from initialization data.
  """
  def new(%Widgex.Frame{} = frame) do
    new(%{frame: frame, menus: demo_menus()})
  end

  def new(%{frame: frame} = data) do
    menus = Map.get(data, :menus, demo_menus())
    theme = Map.merge(@default_theme, Map.get(data, :theme, %{}))
    align = Map.get(data, :align, :right)

    state = %__MODULE__{
      frame: frame,
      menus: menus,
      active_menu: Map.get(data, :active_menu),
      hovered_menu: nil,
      hovered_item: nil,
      hovered_select_option: nil,
      dragging_slider: nil,
      tooltip: nil,
      tooltip_delay_ms: Map.get(data, :tooltip_delay_ms, 600),
      show_shortcuts: Map.get(data, :show_shortcuts, true),
      theme: theme,
      dropdown_bounds: %{},
      align: align
    }

    state = %{state | dropdown_scroll: Map.get(data, :dropdown_scroll, 0)}

    %{state | dropdown_bounds: calculate_dropdown_bounds(state)}
  end

  @doc """
  Demo menus for Widget Workbench testing.
  """
  def demo_menus do
    [
      %{
        id: :file,
        icon: "F",
        items: [
          {"new", "New File"},
          {"open", "Open..."},
          {"save", "Save"},
          {"save_as", "Save As..."},
          {"close", "Close"}
        ]
      },
      %{
        id: :edit,
        icon: "E",
        items: [
          {"undo", "Undo"},
          {"redo", "Redo"},
          {"cut", "Cut"},
          {"copy", "Copy"},
          {"paste", "Paste"}
        ]
      },
      %{
        id: :view,
        icon: "V",
        items: [
          {"zoom_in", "Zoom In"},
          {"zoom_out", "Zoom Out"},
          {"reset_zoom", "Reset Zoom"}
        ]
      },
      %{
        id: :help,
        icon: "?",
        items: [
          {"about", "About"},
          {"docs", "Documentation"}
        ]
      }
    ]
  end

  @doc """
  Calculate bounds for dropdown menus.
  For right-aligned menus, dropdowns extend leftward so they stay within the window.
  """
  def calculate_dropdown_bounds(%__MODULE__{menus: menus, theme: theme, align: align} = state) do
    button_size = theme.icon_button_size
    x_offset = alignment_offset(state)

    menus
    |> Enum.with_index()
    |> Enum.map(fn {menu, index} ->
      dropdown_width = dropdown_width(menu.items, theme, state)
      # Button x position
      button_x = x_offset + index * button_size
      y = theme.height

      # For right-aligned menus, dropdown extends leftward (right edge aligns with button's right edge)
      # For left-aligned menus, dropdown extends rightward (left edge aligns with button's left edge)
      dropdown_x =
        case align do
          :right -> button_x + button_size - dropdown_width
          :left -> button_x
        end

      # Everything below the anchor is Menu.Dropdown's arithmetic, not this
      # component's: the bar decides WHERE a panel hangs, and the panel
      # decides what is inside it. Two copies of that sum is how a menu and a
      # pane end up disagreeing about how tall a row is.
      scroll = if menu.id == state.active_menu, do: state.dropdown_scroll, else: 0

      bounds =
        ScenicWidgets.Menu.Dropdown.layout(menu.items, theme,
          x: dropdown_x,
          y: y,
          width: dropdown_width,
          max_height: Map.get(theme, :max_dropdown_height),
          scroll: scroll
        )

      {menu.id, bounds}
    end)
    |> Enum.into(%{})
  end

  defp max_dropdown_height(theme, content_height) do
    case Map.get(theme, :max_dropdown_height) do
      nil -> content_height
      max when is_number(max) and max > 0 -> max
      _ -> content_height
    end
  end

  @doc "How far the open dropdown can be scrolled; 0 when it all fits."
  def max_dropdown_scroll(%__MODULE__{active_menu: nil}), do: 0

  def max_dropdown_scroll(%__MODULE__{active_menu: menu_id, dropdown_bounds: bounds}) do
    case Map.get(bounds, menu_id) do
      nil -> 0
      dropdown -> ScenicWidgets.Menu.Dropdown.max_scroll(dropdown)
    end
  end

  @doc """
  Calculate the x offset for alignment within the frame.
  For :right alignment, icons are pushed to the right edge of the frame.
  """
  def alignment_offset(%__MODULE__{align: :left}), do: 0

  def alignment_offset(%__MODULE__{align: :right, frame: frame, menus: menus, theme: theme}) do
    total_width = length(menus) * theme.icon_button_size
    frame_width = get_frame_width(frame)
    max(0, frame_width - total_width)
  end

  defp get_frame_width(%Widgex.Frame{size: %{width: w}}), do: w
  defp get_frame_width(%{size: {w, _h}}), do: w
  defp get_frame_width(%{size: %{width: w}}), do: w
  defp get_frame_width(_), do: 0

  @doc """
  Get the bounds for a specific icon button.
  """
  def get_icon_button_bounds(%__MODULE__{menus: menus, theme: theme} = state, menu_id) do
    button_size = theme.icon_button_size
    x_offset = alignment_offset(state)

    case Enum.find_index(menus, &(&1.id == menu_id)) do
      nil ->
        nil

      index ->
        {x_offset + index * button_size, 0, button_size, theme.height}
    end
  end

  @doc """
  Check if a point is in the icon bar area.
  """
  def point_in_icon_bar?(%__MODULE__{menus: menus, theme: theme} = state, {px, py}) do
    total_width = length(menus) * theme.icon_button_size
    x_offset = alignment_offset(state)
    px >= x_offset and px <= x_offset + total_width and py >= 0 and py <= theme.height
  end

  @doc """
  Find which icon button is at the given coordinates.
  """
  def find_hovered_icon(%__MODULE__{menus: menus, theme: theme} = state, {px, _py}) do
    button_size = theme.icon_button_size
    x_offset = alignment_offset(state)

    menus
    |> Enum.with_index()
    |> Enum.find_value(fn {menu, index} ->
      x = x_offset + index * button_size

      if px >= x and px < x + button_size do
        menu.id
      end
    end)
  end

  @doc """
  Check if a point is inside a dropdown menu.
  Returns {true, item_id} or {false, nil}.
  """
  def point_in_dropdown?(%__MODULE__{active_menu: nil}, _coords), do: {false, nil}

  def point_in_dropdown?(%__MODULE__{active_menu: menu_id, dropdown_bounds: bounds}, {px, py}) do
    case Map.get(bounds, menu_id) do
      nil ->
        {false, nil}

      dropdown ->
        if px >= dropdown.x and px <= dropdown.x + dropdown.width and
             py >= dropdown.y and py <= dropdown.y + dropdown.height do
          # Find which item is hovered
          hovered =
            Enum.find_value(dropdown.items, fn {item_id, item_bounds} ->
              if px >= item_bounds.x and px <= item_bounds.x + item_bounds.width and
                   py >= item_bounds.y and py <= item_bounds.y + item_bounds.height do
                item_id
              end
            end)

          {true, hovered}
        else
          {false, nil}
        end
    end
  end

  @doc """
  Check if a point is completely outside the menu area (icon bar + dropdown).
  """
  def point_outside_menu_area?(%__MODULE__{} = state, {px, py}) do
    in_icon_bar = point_in_icon_bar?(state, {px, py})
    {in_dropdown, _} = point_in_dropdown?(state, {px, py})

    not in_icon_bar and not in_dropdown
  end

  @doc """
  Get menu item action callback if it exists.
  """
  def get_item_action(%__MODULE__{menus: menus, active_menu: active_menu}, item_id) do
    case Enum.find(menus, &(&1.id == active_menu)) do
      nil ->
        nil

      menu ->
        case Enum.find(menu.items, fn item -> get_item_id(item) == item_id end) do
          {_id, _label, action} when is_function(action, 0) -> action
          _ -> nil
        end
    end
  end

  def find_item(%__MODULE__{menus: menus, active_menu: active_menu}, item_id) do
    with %{items: items} <- Enum.find(menus, &(&1.id == active_menu)) do
      Enum.find(items, &(get_item_id(&1) == item_id))
    end
  end

  # ===========================================================================
  # Menu Item Helpers
  # ===========================================================================

  @doc "Calculates a content-aware dropdown width, bounded by the component theme and frame."
  def dropdown_width(items, theme, state) do
    minimum = theme.dropdown_width
    maximum = min(Map.get(theme, :dropdown_max_width, 420), available_width(theme, state))
    gap = Map.get(theme, :dropdown_column_gap, 24)
    font_opts = [font: theme.font, font_size: theme.dropdown_font_size]

    label_width =
      items |> Enum.map(&text_width(display_label(&1), font_opts)) |> Enum.max(fn -> 0 end)

    shortcut_width =
      items
      |> Enum.map(&(item_shortcut(&1, state.show_shortcuts) || ""))
      |> Enum.map(&text_width(&1, font_opts))
      |> Enum.max(fn -> 0 end)

    # Keep width measurement in lockstep with Dropdown's permanent checkbox
    # lane. Otherwise adding breathing room between the box and its label
    # steals those pixels back from the longest label as truncation.
    leading_space = if Enum.any?(items, &is_toggle_item?/1), do: 28, else: 8
    shortcut_space = if shortcut_width > 0, do: gap + shortcut_width, else: 0

    # A stepper draws its label at the left and its controls at the right, so
    # its row needs the widest label PLUS a full set of controls — otherwise
    # the buttons are laid out past the menu's edge and cannot be clicked. The
    # controls scale with the chrome, so this is measured, not a constant.
    stepper_space =
      if Enum.any?(items, &match?(%ScenicWidgets.Menu.Model.Stepper{}, &1)) do
        gap + ScenicWidgets.Menu.Dropdown.stepper_controls_width(theme)
      else
        0
      end

    # And room for the scrollbar, on a menu long enough to need one. Without
    # this the bar is drawn INTO the width that was measured for the labels, so
    # a menu truncates its own text at exactly the size that makes it scroll —
    # and only then, which makes it look like the window is at fault.
    bar = ScenicWidgets.Menu.Dropdown.bar_lane(items, theme, Map.get(theme, :max_dropdown_height))

    chrome = 2 * theme.dropdown_padding + leading_space + 8 + bar

    content = label_width + max(shortcut_space, stepper_space) + chrome
    min(max(minimum, ceil(content)), max(minimum, maximum))
  end

  # A dropdown hangs BELOW the icon bar and extends leftward from it; the bar's
  # own width is not what bounds it. Clamping to the frame made every dropdown
  # exactly `dropdown_width` wide — a 140px icon strip forced the maximum below
  # the minimum — and every label longer than that was truncated. Two pairs of
  # rows in Quillex's View menu ended up literally indistinguishable
  # ("Highlight Current…" twice, "Alchemical Dance …" twice).
  #
  # A host that knows the window width should pass `max_dropdown_width`. The
  # frame remains the fallback so no existing caller changes.
  defp available_width(theme, state) do
    Map.get(theme, :max_dropdown_width) || get_frame_width(state.frame)
  end

  defp text_width(text, opts) do
    case ScenicWidgets.MenuBar.TextHelper.measure_text(text, opts) do
      {:ok, width} -> width
      {:error, _} -> String.length(text) * Keyword.fetch!(opts, :font_size) * 0.6
    end
  end

  @doc """
  Extract options from a menu item. Returns empty map for simple items.
  """
  @doc "Returns optional explanatory text for a dropdown row."
  def item_tooltip({_id, _label, opts}) when is_map(opts), do: Map.get(opts, :tooltip)
  def item_tooltip(%{tooltip: tooltip}) when is_binary(tooltip), do: tooltip
  def item_tooltip(_item), do: nil

  @doc "Returns optional explanatory text for a top-level icon button."
  def menu_tooltip(%{tooltip: tooltip}) when is_binary(tooltip), do: tooltip
  def menu_tooltip(_menu), do: nil

  # ── Row helpers ───────────────────────────────────────────────────────────
  #
  # These describe a menu ROW, not this bar. They moved to
  # ScenicWidgets.Menu.Model when the dropdown was separated from the bar:
  # anything drawing menu rows needs them, and while they lived here only this
  # component could reach them — which is why the search pane could not draw a
  # menu row without reimplementing one. Delegated rather than deleted,
  # because they are called by name from a dozen places.

  defdelegate get_item_id(item), to: ScenicWidgets.Menu.Model
  defdelegate get_item_label(item), to: ScenicWidgets.Menu.Model
  defdelegate display_label(item), to: ScenicWidgets.Menu.Model
  defdelegate item_shortcut(item), to: ScenicWidgets.Menu.Model
  defdelegate item_shortcut(item, show?), to: ScenicWidgets.Menu.Model
  defdelegate item_height(item, theme), to: ScenicWidgets.Menu.Model
  defdelegate get_item_opts(item), to: ScenicWidgets.Menu.Model
  defdelegate is_toggle_item?(item), to: ScenicWidgets.Menu.Model
  defdelegate is_item_checked?(item), to: ScenicWidgets.Menu.Model
  defdelegate item_enabled?(item), to: ScenicWidgets.Menu.Model
end
