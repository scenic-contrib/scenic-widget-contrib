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
  alias ScenicWidgets.Menu.Dropdown

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

  # The tooltip itself lives in ScenicWidgets.Tooltip — every component with
  # buttons wants one, and this was the only one that had it.
  defp render_tooltip(graph, %State{tooltip: tooltip, theme: theme, frame: frame}) do
    ScenicWidgets.Tooltip.add(graph, tooltip, theme, get_frame_width(frame), id: :menu_tooltip)
  end

  @doc false
  def fit_tooltip_x(preferred_x, tooltip_width, component_width),
    do: ScenicWidgets.Tooltip.fit_x(preferred_x, tooltip_width, component_width)

  @doc false
  def tooltip_width(text, font, font_size, _padding),
    do: ScenicWidgets.Tooltip.width(text, font, font_size)

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

  # The dropdown itself lives in ScenicWidgets.Menu.Dropdown now — it is a
  # panel of menu rows, which is a thing in its own right and not a thing only
  # a bar can have. This component supplies the anchor and the state; the
  # drawing is the same drawing wherever it hangs from.
  defp render_dropdown(graph, %State{active_menu: nil}), do: graph

  defp render_dropdown(graph, %State{active_menu: menu_id, menus: menus} = state) do
    menu = Enum.find(menus, &(&1.id == menu_id))
    dropdown = Map.get(state.dropdown_bounds, menu_id)

    if menu && dropdown do
      Dropdown.render(graph, menu.items, dropdown,
        theme: state.theme,
        hovered: state.hovered_item,
        hovered_select_option: state.hovered_select_option,
        show_shortcuts: state.show_shortcuts,
        id: :dropdown_group
      )
    else
      graph
    end
  end

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

      # The panel was WOUND: every row moved, and so did the scrollbar thumb.
      # Nothing else in the state changes when the wheel turns — not the menus,
      # not the hovered row — so without this the menu scrolled in
      # `dropdown_bounds` and stayed put on the screen, until the next pixel of
      # pointer movement happened to change `hovered_item` and rebuild it. With
      # a mouse that is instant and invisible; from a trackpad gesture that
      # does not move the pointer, the menu simply does not scroll.
      #
      # Comparing the BOUNDS rather than the scroll offset, because a resize
      # moves the rows too and arrives the same way.
      new_state.active_menu && old_state.dropdown_bounds != new_state.dropdown_bounds ->
        graph
        |> Graph.delete(:dropdown_group)
        |> render_dropdown(new_state)

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
      new_state.active_menu &&
          {old_state.hovered_item, old_state.hovered_select_option} !=
            {new_state.hovered_item, new_state.hovered_select_option} ->
        graph
        |> Graph.delete(:dropdown_group)
        |> render_dropdown(new_state)

      true ->
        graph
    end
  end
end
