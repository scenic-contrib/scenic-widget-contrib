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
    dragging_slider: nil,
    tooltip: nil,
    tooltip_delay_ms: 600,
    show_shortcuts: true,
    theme: %{},
    dropdown_bounds: %{},
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
    dropdown_column_gap: 24,
    dropdown_item_height: 28,
    dropdown_slider_height: 52,
    dropdown_padding: 4,

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
      active_menu: nil,
      hovered_menu: nil,
      hovered_item: nil,
      dragging_slider: nil,
      tooltip: nil,
      tooltip_delay_ms: Map.get(data, :tooltip_delay_ms, 600),
      show_shortcuts: Map.get(data, :show_shortcuts, true),
      theme: theme,
      dropdown_bounds: %{},
      align: align
    }

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
    padding = theme.dropdown_padding
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

      # Calculate dropdown height based on items
      dropdown_height = Enum.sum(Enum.map(menu.items, &item_height(&1, theme))) + 2 * padding

      # Calculate item bounds within dropdown (relative to dropdown origin)
      item_bounds =
        menu.items
        |> Enum.map_reduce(0, fn item, y_offset ->
          item_id = get_item_id(item)
          height = item_height(item, theme)

          entry =
            {item_id,
             %{
               x: dropdown_x + padding,
               y: y + padding + y_offset,
               width: dropdown_width - 2 * padding,
               height: height
             }}

          {entry, y_offset + height}
        end)
        |> elem(0)
        |> Enum.into(%{})

      {menu.id,
       %{
         x: dropdown_x,
         y: y,
         width: dropdown_width,
         height: dropdown_height,
         items: item_bounds
       }}
    end)
    |> Enum.into(%{})
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

  @doc """
  Extract the ID from a menu item tuple (supports all formats).
  """
  def get_item_id({id, _label}), do: id
  def get_item_id({id, _label, _opts_or_action}), do: id
  def get_item_id(%{id: id}), do: id

  @doc """
  Extract the label from a menu item tuple.
  """
  def get_item_label({_id, label}), do: label
  def get_item_label({_id, label, _opts_or_action}), do: label
  def get_item_label(%{label: label}), do: label

  def display_label(%ScenicWidgets.Menu.Model.Divider{}), do: ""
  def display_label(%ScenicWidgets.Menu.Model.Select{label: label}), do: label

  def display_label(%ScenicWidgets.Menu.Model.Slider{label: label, value: value}),
    do: "#{label}: #{value}"

  def display_label(%ScenicWidgets.Menu.Model.Submenu{label: label}), do: label <> "  ›"

  def display_label(item), do: get_item_label(item)

  @doc "Returns a menu item's shortcut as a separate, right-aligned column."
  def item_shortcut(item), do: item_shortcut(item, true)
  def item_shortcut(%{shortcut: shortcut}, true) when is_binary(shortcut), do: shortcut
  def item_shortcut(_item, _show_shortcuts), do: nil

  @doc "Returns the row height for an item; interactive sliders receive extra vertical space."
  def item_height(%ScenicWidgets.Menu.Model.Slider{}, theme),
    do: Map.get(theme, :dropdown_slider_height, 52)

  def item_height(%ScenicWidgets.Menu.Model.Divider{}, theme),
    do: Map.get(theme, :dropdown_divider_height, 13)

  def item_height(%ScenicWidgets.Menu.Model.Select{expanded?: true, options: options}, theme),
    do: theme.dropdown_item_height * (min(length(options), 4) + 1)

  def item_height(_item, theme), do: theme.dropdown_item_height

  @doc "Calculates a content-aware dropdown width, bounded by the component theme and frame."
  def dropdown_width(items, theme, state) do
    minimum = theme.dropdown_width
    maximum = min(Map.get(theme, :dropdown_max_width, 420), get_frame_width(state.frame))
    gap = Map.get(theme, :dropdown_column_gap, 24)
    font_opts = [font: theme.font, font_size: theme.dropdown_font_size]

    label_width =
      items |> Enum.map(&text_width(display_label(&1), font_opts)) |> Enum.max(fn -> 0 end)

    shortcut_width =
      items
      |> Enum.map(&(item_shortcut(&1, state.show_shortcuts) || ""))
      |> Enum.map(&text_width(&1, font_opts))
      |> Enum.max(fn -> 0 end)

    leading_space = if Enum.any?(items, &is_toggle_item?/1), do: 20, else: 8
    shortcut_space = if shortcut_width > 0, do: gap + shortcut_width, else: 0
    chrome = 2 * theme.dropdown_padding + leading_space + 8

    min(max(minimum, ceil(label_width + shortcut_space + chrome)), max(minimum, maximum))
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
  def get_item_opts({_id, _label}), do: %{}
  def get_item_opts({_id, _label, opts}) when is_map(opts), do: opts
  def get_item_opts({_id, _label, _action}), do: %{}

  def get_item_opts(%ScenicWidgets.Menu.Model.Toggle{checked?: checked, enabled?: enabled}),
    do: %{type: :toggle, checked: checked, enabled: enabled}

  def get_item_opts(%ScenicWidgets.Menu.Model.Radio{selected?: selected, enabled?: enabled}),
    do: %{type: :radio, checked: selected, enabled: enabled}

  def get_item_opts(%ScenicWidgets.Menu.Model.Slider{enabled?: enabled}),
    do: %{type: :slider, enabled: enabled}

  def get_item_opts(%{enabled?: enabled}), do: %{enabled: enabled}

  @doc "Returns optional explanatory text for a dropdown row."
  def item_tooltip({_id, _label, opts}) when is_map(opts), do: Map.get(opts, :tooltip)
  def item_tooltip(%{tooltip: tooltip}) when is_binary(tooltip), do: tooltip
  def item_tooltip(_item), do: nil

  @doc "Returns optional explanatory text for a top-level icon button."
  def menu_tooltip(%{tooltip: tooltip}) when is_binary(tooltip), do: tooltip
  def menu_tooltip(_menu), do: nil

  @doc """
  Check if a menu item is a toggle type.
  """
  def is_toggle_item?(item) do
    opts = get_item_opts(item)
    Map.get(opts, :type) in [:toggle, :radio]
  end

  @doc """
  Check if a toggle item is checked.
  """
  def is_item_checked?(item) do
    opts = get_item_opts(item)
    Map.get(opts, :checked, false)
  end

  def item_enabled?(item), do: Map.get(get_item_opts(item), :enabled, true)
end
