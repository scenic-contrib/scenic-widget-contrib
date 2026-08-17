defmodule ScenicWidgets.IconMenu.Renderer do
  @moduledoc """
  Rendering functions for IconMenu.

  Structure:
  - Background rect
  - Icon button groups (one per menu)
  - Dropdown group (shown when a menu is active)
  """

  alias Scenic.Graph
  alias Scenic.Primitives
  alias ScenicWidgets.IconMenu.State
  alias ScenicWidgets.MenuBar.TextHelper

  @doc """
  Initial render - create all UI elements.
  """
  def initial_render(graph, %State{} = state) do
    graph
    |> render_background(state)
    |> render_icon_buttons(state)
    |> render_dropdown(state)
    |> render_tooltip(state)
  end

  @doc """
  Update render - only modify elements that changed.
  """
  def update_render(graph, %State{} = old_state, %State{} = new_state) do
    if old_state.tooltip != new_state.tooltip do
      initial_render(Graph.build(), new_state)
    else
      graph
      |> update_icon_buttons(old_state, new_state)
      |> update_dropdown(old_state, new_state)
    end
  end

  # ===========================================================================
  # Initial Rendering
  # ===========================================================================

  defp render_background(graph, %State{frame: frame, theme: theme}) do
    # Draw background across the full frame width
    frame_width = get_frame_width(frame)

    graph
    |> Primitives.rect(
      {frame_width, theme.height},
      id: :icon_menu_background,
      fill: theme.background
    )
  end

  defp get_frame_width(%Widgex.Frame{size: %{width: w}}), do: w
  defp get_frame_width(%{size: {w, _h}}), do: w
  defp get_frame_width(%{size: %{width: w}}), do: w
  defp get_frame_width(_), do: 0

  defp render_tooltip(graph, %State{tooltip: nil}), do: graph

  defp render_tooltip(
         graph,
         %State{tooltip: %{text: text, at: {x, y}}, theme: theme, frame: frame}
       ) do
    font_size = Map.get(theme, :tooltip_font_size, 12)
    padding = 7
    width = tooltip_width(text, theme.font, font_size, padding)
    height = font_size + padding * 2
    tooltip_x = fit_tooltip_x(x + 10, width, get_frame_width(frame))

    Primitives.group(
      graph,
      fn g ->
        g
        |> Primitives.rect({width, height},
          fill: Map.get(theme, :tooltip_bg, {25, 25, 25}),
          stroke: {1, Map.get(theme, :tooltip_border, {95, 95, 95})},
          id: :menu_tooltip_bg
        )
        |> Primitives.text(text,
          fill: Map.get(theme, :tooltip_text, :white),
          font: theme.font,
          font_size: font_size,
          translate: {padding, font_size + div(padding, 2)},
          id: :menu_tooltip_text
        )
      end,
      id: :menu_tooltip,
      translate: {tooltip_x, y + 4}
    )
  end

  @doc false
  def fit_tooltip_x(preferred_x, tooltip_width, component_width) do
    min(preferred_x, component_width - tooltip_width - 4)
  end

  @doc false
  def tooltip_width(text, font, font_size, padding) do
    measured =
      case TextHelper.measure_text(text, font: font, font_size: font_size) do
        {:ok, width} -> width
        {:error, _} -> String.length(text) * font_size * 0.6
      end

    ceil(measured) + padding * 2
  end

  defp render_icon_buttons(graph, %State{menus: menus} = state) do
    Enum.reduce(menus, graph, fn menu, acc ->
      build_icon_button(acc, state, menu)
    end)
  end

  defp build_icon_button(graph, %State{theme: theme} = state, menu) do
    {x, y, width, height} = State.get_icon_button_bounds(state, menu.id)

    is_active = state.active_menu == menu.id
    is_hovered = state.hovered_menu == menu.id

    bg_color =
      cond do
        is_active -> theme.icon_active_bg
        is_hovered -> theme.icon_hover_bg
        true -> theme.background
      end

    # Hover is communicated by the subtle button background; the glyph itself
    # stays steady. Active/open menus may still use the stronger active colour.
    icon_color = if is_active, do: theme.icon_active_color, else: theme.icon_color

    graph
    |> Primitives.group(
      fn g ->
        g
        # Button background
        |> Primitives.rect(
          {width, height},
          id: {:icon_bg, menu.id},
          fill: bg_color
        )
        |> render_icon(menu.icon, menu.id, icon_color, theme, width, height)
      end,
      id: {:icon_button, menu.id},
      translate: {x, y}
    )
  end

  # Primitive-drawn toolbar icons remain crisp at any scale and avoid the
  # placeholder F/E/V letters that made the control look unfinished.
  #
  # EVERY primitive of an icon carries the same {:icon_text, id}. Graph.modify/3
  # applies to all primitives sharing an id, and recolouring on hover has to
  # move the whole glyph — when only the first stroke was tagged, hovering
  # recoloured one line of the pencil and left the other two behind.
  defp render_icon(graph, :file, id, color, _theme, width, height) do
    x = width / 2 - 7.5
    y = height / 2 - 9.5

    graph
    |> Primitives.rrect({15, 19, 1},
      id: {:icon_text, id},
      stroke: {1.8, color},
      fill: :clear,
      translate: {x, y}
    )
    |> Primitives.line({{x + 3, y + 6}, {x + 12, y + 6}},
      id: {:icon_text, id},
      stroke: {1.2, color}
    )
    |> Primitives.line({{x + 3, y + 10}, {x + 12, y + 10}},
      id: {:icon_text, id},
      stroke: {1.2, color}
    )
    |> Primitives.line({{x + 3, y + 14}, {x + 10, y + 14}},
      id: {:icon_text, id},
      stroke: {1.2, color}
    )
  end

  defp render_icon(graph, :edit, id, color, _theme, width, height) do
    x = width / 2
    y = height / 2

    # Classic sharpened wooden pencil: hexagonal outlined body, eraser band,
    # exposed wooden tip, graphite point, and a center facet. The silhouette is
    # intentionally broad enough to survive a 35px toolbar.
    graph
    |> Primitives.path(
      [
        :begin,
        {:move_to, x - 11, y + 10},
        {:line_to, x - 8, y + 4},
        {:line_to, x + 4, y - 8},
        {:line_to, x + 8, y - 4},
        {:line_to, x - 4, y + 8},
        :close_path
      ],
      id: {:icon_text, id},
      stroke: {2.2, color},
      fill: :clear,
      join: :round
    )
    |> Primitives.line({{x + 2, y - 6}, {x + 6, y - 2}},
      id: {:icon_text, id},
      stroke: {2, color}
    )
    |> Primitives.line({{x - 8, y + 4}, {x - 4, y + 8}},
      id: {:icon_text, id},
      stroke: {1.6, color}
    )
    |> Primitives.line({{x - 7, y + 6}, {x + 5, y - 6}},
      id: {:icon_text, id},
      stroke: {1.3, color}
    )
    |> Primitives.line({{x - 11, y + 10}, {x - 9, y + 8}},
      id: {:icon_text, id},
      stroke: {2.2, color},
      cap: :round
    )
  end

  defp render_icon(graph, :view, id, color, _theme, width, height) do
    x = width / 2
    y = height / 2

    # Spectacles communicate display/view controls without the surveillance
    # connotation of an eye or the search connotation of a magnifying glass.
    graph
    |> Primitives.circle(5.5,
      id: {:icon_text, id},
      stroke: {2, color},
      fill: :clear,
      translate: {x - 6, y + 1}
    )
    |> Primitives.circle(5.5,
      id: {:icon_text, id},
      stroke: {2, color},
      fill: :clear,
      translate: {x + 6, y + 1}
    )
    |> Primitives.line({{x - 1, y}, {x + 1, y}},
      id: {:icon_text, id},
      stroke: {2, color}
    )
    |> Primitives.line({{x - 11, y - 1}, {x - 14, y - 3}},
      id: {:icon_text, id},
      stroke: {2, color}
    )
    |> Primitives.line({{x + 11, y - 1}, {x + 14, y - 3}},
      id: {:icon_text, id},
      stroke: {2, color}
    )
  end

  defp render_icon(graph, :help, id, color, _theme, width, height) do
    x = width / 2
    y = height / 2

    graph
    |> Primitives.path(
      [
        :begin,
        {:move_to, x - 5, y - 4},
        {:bezier_to, x - 4, y - 9, x + 6, y - 9, x + 6, y - 3},
        {:bezier_to, x + 6, y + 1, x, y + 1, x, y + 4}
      ],
      id: {:icon_text, id},
      stroke: {2.2, color},
      fill: :clear,
      cap: :round,
      join: :round
    )
    |> Primitives.circle(1.5,
      id: {:icon_text, id},
      fill: color,
      translate: {x, y + 8.5}
    )
  end

  defp render_icon(graph, icon, id, color, theme, width, height) do
    label = if is_atom(icon), do: icon |> Atom.to_string() |> String.first(), else: icon

    Primitives.text(graph, label,
      id: {:icon_text, id},
      fill: color,
      font: theme.font,
      font_size: theme.icon_font_size,
      text_align: :center,
      translate: {width / 2, height / 2 + theme.icon_font_size / 3}
    )
  end

  # Recolour one primitive of an icon, in whatever way that primitive is
  # actually drawn.
  #
  # The previous code set `fill:` on everything. Most of these icons are
  # *stroked* outlines with `fill: :clear` — so hovering the File icon did not
  # recolour its outline, it filled the page shape in solid, and the Edit
  # pencil (pure lines) changed weight rather than colour. Hover should change
  # colour and nothing else.
  defp recolor_icon(primitive, color) do
    primitive
    |> restroke(color)
    |> refill(color)
  end

  # Preserve the stroke WIDTH each primitive chose; swap only its colour.
  defp restroke(primitive, color) do
    case Scenic.Primitive.get_style(primitive, :stroke) do
      {width, _old_color} -> Scenic.Primitive.put_style(primitive, :stroke, {width, color})
      _ -> primitive
    end
  end

  # `fill: :clear` is load-bearing — it is what makes an outline an outline.
  defp refill(primitive, color) do
    case Scenic.Primitive.get_style(primitive, :fill) do
      nil -> primitive
      :clear -> primitive
      {:color, {:color_rgba, {_r, _g, _b, 0}}} -> primitive
      _ -> Scenic.Primitive.put_style(primitive, :fill, color)
    end
  end

  defp render_dropdown(graph, %State{active_menu: nil}), do: graph

  defp render_dropdown(
         graph,
         %State{active_menu: menu_id, menus: menus, theme: theme, dropdown_bounds: bounds} = state
       ) do
    menu = Enum.find(menus, &(&1.id == menu_id))
    dropdown = Map.get(bounds, menu_id)

    if menu && dropdown do
      graph
      |> Primitives.group(
        fn g ->
          g
          # Dropdown background with border
          |> Primitives.rrect(
            {dropdown.width, dropdown.height, 4},
            id: :dropdown_bg,
            fill: theme.dropdown_bg,
            stroke: {1, theme.dropdown_border}
          )
          # Render menu items
          |> render_dropdown_items(menu.items, state)
        end,
        id: :dropdown_group,
        translate: {dropdown.x, dropdown.y}
      )
    else
      graph
    end
  end

  defp render_dropdown_items(
         graph,
         items,
         %State{
           theme: theme,
           active_menu: menu_id,
           dropdown_bounds: bounds,
           hovered_item: hovered_item
         } = state
       ) do
    dropdown = Map.get(bounds, menu_id)
    padding = theme.dropdown_padding

    # Space reserved for checkmark on the left
    checkmark_width = 20

    Enum.reduce(items, graph, fn item, acc ->
      item_id = State.get_item_id(item)
      label = State.display_label(item)
      shortcut = State.item_shortcut(item, state.show_shortcuts)
      is_toggle = State.is_toggle_item?(item)
      is_checked = State.is_item_checked?(item)
      item_bounds = Map.fetch!(dropdown.items, item_id)

      is_hovered = hovered_item == item_id

      # Position relative to dropdown origin
      item_x = padding
      item_y = item_bounds.y - dropdown.y
      row_height = item_bounds.height

      bg_color = if is_hovered, do: theme.item_hover_bg, else: :clear
      enabled? = State.item_enabled?(item)

      text_color =
        cond do
          not enabled? -> {120, 120, 120}
          is_hovered -> theme.item_hover_text_color
          true -> theme.item_text_color
        end

      if match?(%ScenicWidgets.Menu.Model.Divider{}, item) do
        divider_y = row_height / 2

        acc
        |> Primitives.line(
          {{8, divider_y}, {dropdown.width - 2 * padding - 8, divider_y}},
          id: {:menu_divider, item_id},
          stroke: {1, Map.get(theme, :dropdown_border, {70, 70, 70})},
          translate: {item_x, item_y}
        )
      else
        acc
        |> Primitives.group(
          fn g ->
            g =
              g
              # Item background (for hover)
              |> Primitives.rrect(
                {dropdown.width - 2 * padding, row_height, 3},
                id: {:item_bg, item_id},
                fill: bg_color
              )

            # Checkmark for toggle items (only if checked)
            g =
              if is_toggle and is_checked do
                g
                |> Primitives.text(
                  "✓",
                  id: {:item_check, item_id},
                  fill: text_color,
                  font: theme.font,
                  font_size: theme.dropdown_font_size,
                  translate: {6, theme.dropdown_item_height / 2 + theme.dropdown_font_size / 3}
                )
              else
                g
              end

            cond do
              match?(%ScenicWidgets.Menu.Model.Select{}, item) ->
                render_select(g, item, dropdown.width - 2 * padding, text_color, theme)

              match?(%ScenicWidgets.Menu.Model.Stepper{}, item) ->
                render_stepper(g, item, dropdown.width - 2 * padding, text_color, theme)

              match?(%ScenicWidgets.Menu.Model.Slider{}, item) ->
                render_slider(
                  g,
                  item,
                  dropdown.width - 2 * padding,
                  text_color,
                  is_hovered,
                  theme
                )

              true ->
                text_x = if has_any_toggle_items?(items), do: checkmark_width, else: 8
                shortcut_right = dropdown.width - 2 * padding - 8
                column_gap = Map.get(theme, :dropdown_column_gap, 24)
                available_width = shortcut_right - text_x
                measured_shortcut_width = measure_width(shortcut || "", theme)

                shortcut_width =
                  if shortcut do
                    min(measured_shortcut_width, max(40, available_width * 0.55))
                  else
                    0
                  end

                label_max_width =
                  max(
                    0,
                    shortcut_right - text_x -
                      if(shortcut, do: shortcut_width + column_gap, else: 0)
                  )

                display_label = truncate(label, label_max_width, theme)
                display_shortcut = shortcut && truncate(shortcut, shortcut_width, theme)

                g =
                  Primitives.text(g, display_label,
                    id: {:item_text, item_id},
                    fill: text_color,
                    font: theme.font,
                    font_size: theme.dropdown_font_size,
                    translate:
                      {text_x, theme.dropdown_item_height / 2 + theme.dropdown_font_size / 3}
                  )

                if display_shortcut do
                  Primitives.text(g, display_shortcut,
                    id: {:item_shortcut, item_id},
                    fill: text_color,
                    font: theme.font,
                    font_size: theme.dropdown_font_size,
                    text_align: :right,
                    translate: {
                      shortcut_right,
                      theme.dropdown_item_height / 2 + theme.dropdown_font_size / 3
                    }
                  )
                else
                  g
                end
            end
          end,
          id: {:dropdown_item, item_id},
          translate: {item_x, item_y}
        )
      end
    end)
  end

  defp render_stepper(graph, stepper, row_width, text_color, theme) do
    baseline = theme.dropdown_item_height / 2 + theme.dropdown_font_size / 3
    center_y = theme.dropdown_item_height / 2
    controls_width = 116
    controls_x = row_width - controls_width - 8
    button_fill = Map.get(theme, :stepper_button_bg, {72, 78, 92})

    graph
    |> Primitives.text(stepper.label,
      id: {:stepper_label, stepper.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      translate: {8, baseline}
    )
    |> Primitives.rrect({28, 22, 4},
      id: {:stepper_minus_bg, stepper.id},
      fill: button_fill,
      stroke: {1, theme.dropdown_border},
      translate: {controls_x, center_y - 11}
    )
    |> Primitives.text("−",
      id: {:stepper_minus, stepper.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      text_align: :center,
      text_base: :middle,
      translate: {controls_x + 14, center_y}
    )
    |> Primitives.text("#{stepper.value}%",
      id: {:stepper_value, stepper.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      text_align: :center,
      text_base: :middle,
      translate: {controls_x + 58, center_y}
    )
    |> Primitives.rrect({28, 22, 4},
      id: {:stepper_plus_bg, stepper.id},
      fill: button_fill,
      stroke: {1, theme.dropdown_border},
      translate: {controls_x + 88, center_y - 11}
    )
    |> Primitives.text("+",
      id: {:stepper_plus, stepper.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      text_align: :center,
      text_base: :middle,
      translate: {controls_x + 102, center_y}
    )
  end

  defp render_select(graph, select, row_width, text_color, theme) do
    row_height = theme.dropdown_item_height
    box_width = 76
    box_x = row_width - box_width - 8
    baseline = row_height / 2 + theme.dropdown_font_size / 3

    graph
    |> Primitives.text(select.label,
      id: {:select_label, select.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      translate: {8, baseline}
    )
    |> Primitives.rrect({box_width, row_height - 8, 3},
      id: {:select_box, select.id},
      fill: :clear,
      stroke: {1, theme.dropdown_border},
      translate: {box_x, 4}
    )
    |> Primitives.text(to_string(select.value),
      id: {:select_value, select.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      text_align: :center,
      translate: {box_x + box_width / 2 - 7, baseline}
    )
    |> Primitives.text("▾",
      id: {:select_arrow, select.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      text_align: :center,
      translate: {box_x + box_width - 13, baseline}
    )
    |> render_select_options(select, row_width, row_height, text_color, theme)
  end

  defp render_select_options(graph, %{expanded?: false}, _width, _height, _color, _theme),
    do: graph

  defp render_select_options(graph, select, row_width, row_height, text_color, theme) do
    select.options
    |> Enum.drop(select.scroll_offset)
    |> Enum.take(4)
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {value, index}, acc ->
      y = row_height * (index + 1)

      acc
      |> Primitives.rect({76, row_height},
        id: {:select_option_bg, select.id, value},
        fill: if(value == select.value, do: theme.item_hover_bg, else: theme.dropdown_bg),
        translate: {row_width - 84, y}
      )
      |> Primitives.text(to_string(value),
        id: {:select_option, select.id, value},
        fill: text_color,
        font: theme.font,
        font_size: theme.dropdown_font_size,
        text_align: :center,
        translate: {row_width - 46, y + row_height / 2 + theme.dropdown_font_size / 3}
      )
    end)
  end

  defp render_slider(graph, slider, row_width, text_color, hovered?, theme) do
    track_x = 10
    track_width = max(1, row_width - 20)
    track_y = Map.get(theme, :dropdown_slider_height, 52) - 13
    ratio = (slider.value - slider.min) / max(slider.max - slider.min, 1)
    thumb_x = track_x + ratio * track_width
    font_y = theme.dropdown_font_size + 5

    {track_color, fill_color, thumb_color} =
      if hovered? do
        {
          Map.get(theme, :item_hover_text_color, {255, 255, 255}),
          Map.get(theme, :dropdown_bg, {50, 50, 50}),
          Map.get(theme, :dropdown_bg, {50, 50, 50})
        }
      else
        {
          Map.get(theme, :dropdown_border, {70, 70, 70}),
          Map.get(theme, :item_hover_bg, {0, 122, 204}),
          text_color
        }
      end

    graph
    |> Primitives.text(slider.label,
      id: {:slider_label, slider.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      translate: {8, font_y}
    )
    |> Primitives.text(to_string(slider.value),
      id: {:slider_value, slider.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      text_align: :right,
      translate: {row_width - 8, font_y}
    )
    |> Primitives.rrect({track_width, 4, 2},
      id: {:slider_track, slider.id},
      fill: track_color,
      translate: {track_x, track_y}
    )
    |> Primitives.rrect({max(0, thumb_x - track_x), 4, 2},
      id: {:slider_fill, slider.id},
      fill: fill_color,
      translate: {track_x, track_y}
    )
    |> Primitives.circle(6,
      id: {:slider_thumb, slider.id},
      fill: thumb_color,
      translate: {thumb_x, track_y + 2}
    )
  end

  # Check if any item in the list is a toggle type (to align text consistently)
  defp has_any_toggle_items?(items) do
    Enum.any?(items, &State.is_toggle_item?/1)
  end

  defp measure_width("", _theme), do: 0

  defp measure_width(text, theme) do
    case TextHelper.measure_text(text, font: theme.font, font_size: theme.dropdown_font_size) do
      {:ok, width} -> width
      {:error, _} -> String.length(text) * theme.dropdown_font_size * 0.6
    end
  end

  defp truncate(text, width, theme) do
    case TextHelper.truncate_text(text, width,
           font: theme.font,
           font_size: theme.dropdown_font_size,
           ellipsis: "…"
         ) do
      {:ok, value} -> value
      {:truncated, value} -> value
      {:error, _} -> text
    end
  end

  # ===========================================================================
  # Update Rendering
  # ===========================================================================

  defp update_icon_buttons(graph, old_state, new_state) do
    # Check if hover or active state changed
    hover_changed = old_state.hovered_menu != new_state.hovered_menu
    active_changed = old_state.active_menu != new_state.active_menu

    if hover_changed or active_changed do
      theme = new_state.theme

      # Update old hovered button (if any)
      graph =
        if old_state.hovered_menu && old_state.hovered_menu != new_state.hovered_menu do
          is_active = old_state.hovered_menu == new_state.active_menu
          bg_color = if is_active, do: theme.icon_active_bg, else: theme.background

          graph
          |> Graph.modify({:icon_bg, old_state.hovered_menu}, fn p ->
            Primitives.update_opts(p, fill: bg_color)
          end)
        else
          graph
        end

      # Update new hovered button (if any)
      graph =
        if new_state.hovered_menu && old_state.hovered_menu != new_state.hovered_menu do
          is_active = new_state.hovered_menu == new_state.active_menu
          bg_color = if is_active, do: theme.icon_active_bg, else: theme.icon_hover_bg

          graph
          |> Graph.modify({:icon_bg, new_state.hovered_menu}, fn p ->
            Primitives.update_opts(p, fill: bg_color)
          end)
        else
          graph
        end

      # Update active state changes
      graph =
        if active_changed do
          # Update old active (now inactive)
          graph =
            if old_state.active_menu && old_state.active_menu != new_state.active_menu do
              is_hovered = old_state.active_menu == new_state.hovered_menu
              bg_color = if is_hovered, do: theme.icon_hover_bg, else: theme.background
              icon_color = theme.icon_color

              graph
              |> Graph.modify({:icon_bg, old_state.active_menu}, fn p ->
                Primitives.update_opts(p, fill: bg_color)
              end)
              |> Graph.modify({:icon_text, old_state.active_menu}, fn p ->
                recolor_icon(p, icon_color)
              end)
            else
              graph
            end

          # Update new active
          if new_state.active_menu do
            graph
            |> Graph.modify({:icon_bg, new_state.active_menu}, fn p ->
              Primitives.update_opts(p, fill: theme.icon_active_bg)
            end)
            |> Graph.modify({:icon_text, new_state.active_menu}, fn p ->
              recolor_icon(p, theme.icon_active_color)
            end)
          else
            graph
          end
        else
          graph
        end

      graph
    else
      graph
    end
  end

  defp update_dropdown(graph, old_state, new_state) do
    cond do
      # Dropdown opened or changed
      old_state.active_menu != new_state.active_menu ->
        # Need to rebuild the dropdown - remove old and add new
        graph =
          if old_state.active_menu do
            Graph.delete(graph, :dropdown_group)
          else
            graph
          end

        if new_state.active_menu do
          render_dropdown(graph, new_state)
        else
          graph
        end

      # Interactive controls (notably sliders) update their model while the
      # dropdown remains open. Rebuild that small overlay so thumb and value
      # feedback track the pointer in real time.
      new_state.active_menu && old_state.menus != new_state.menus ->
        graph
        |> Graph.delete(:dropdown_group)
        |> render_dropdown(new_state)

      # Hover affects every part of compound rows (slider label, value, track,
      # fill, and thumb), so rebuild the small dropdown to restore all colours
      # symmetrically when the pointer leaves.
      new_state.active_menu && old_state.hovered_item != new_state.hovered_item ->
        graph
        |> Graph.delete(:dropdown_group)
        |> render_dropdown(new_state)

      true ->
        graph
    end
  end
end
