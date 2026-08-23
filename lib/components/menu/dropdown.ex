defmodule ScenicWidgets.Menu.Dropdown do
  @moduledoc """
  A panel of menu rows, drawn wherever you hang it.

  This was the second half of `ScenicWidgets.IconMenu.Renderer`, reachable
  only by that component — so anything else wanting a menu-shaped popover had
  to write its own, which is exactly what the search pane did. What made it
  un-reusable was never the drawing; it was that every function took the
  BAR's state and read `active_menu` out of it. A panel does not need to know
  it belongs to a bar.

  It takes rows (`ScenicWidgets.Menu.Model` structs, or the old
  `{id, label}` tuples), a `bounds` map saying where the panel goes and where
  each row sits inside it, and a theme. It returns a graph.

      Dropdown.render(graph, rows, bounds,
        theme: theme,
        hovered: hovered_item_id,
        show_shortcuts: true,
        id: :my_panel
      )

  `bounds` is `%{x:, y:, width:, height:, items: %{id => %{y:, height:}}}`,
  which is what `IconMenu.State.calculate_dropdown_bounds/1` already built —
  laid out by the caller, because where a panel can go depends on what it
  hangs off and how much room is under it, and that IS the caller's business.
  """

  alias Scenic.Primitives
  alias ScenicWidgets.Menu.Model
  alias ScenicWidgets.MenuBar.TextHelper
  alias Widgex.Scroll.{Drag, ScrollController, ScrollRenderer, ScrollState}

  # The lane a vertical scrollbar occupies, taken from the module that draws
  # one rather than guessed at again here.
  @bar_lane ScrollRenderer.inset()
  @bar_pad ScrollRenderer.padding()

  # One wheel notch. Pixels, not rows: a panel holds rows of several heights
  # (a slider is four times a divider), so "one row" is not a distance.
  @scroll_step 40

  # A floating panel hangs off its button and may well overhang whatever is
  # behind it. A host that asks Scenic for pointer input GLOBALLY (IconMenu
  # does) already hears about that; one that receives it through its own
  # primitives (SearchPane does) hears nothing at all where the panel is not
  # over the host — the rows drawn over the document simply do not answer.
  #
  # So it is asked for, by the hosts that need it. Not by default: adding it
  # where input is already requested globally is precisely the double-delivery
  # this codebase has been bitten by before.
  defp panel_input(opts) do
    if Keyword.get(opts, :input, false),
      do: [input: [:cursor_button, :cursor_pos]],
      else: []
  end

  @doc """
  Where the panel goes, and where each row sits inside it.

  The caller supplies the ANCHOR — `x`, `y` and `width` — because where a
  panel can appear depends on what it hangs off, and that is the one part of
  this that genuinely differs between a menubar and anything else. Everything
  below the anchor is the same arithmetic wherever the panel is, so it is
  here rather than copied.

  `:max_height` clamps a panel taller than the room under it; `:scroll` is
  then how far down it has been wound, clamped to the overflow. Both drawing
  and hit testing read the SAME map, which is what stops them disagreeing
  about where a row is.
  """
  def layout(rows, theme, opts) do
    x = Keyword.fetch!(opts, :x)
    y = Keyword.fetch!(opts, :y)
    width = Keyword.fetch!(opts, :width)
    padding = theme.dropdown_padding

    content_height = content_height(rows, theme)

    height =
      case Keyword.get(opts, :max_height) do
        max when is_number(max) and max > 0 -> min(content_height, max)
        _ -> content_height
      end

    scroll = min(Keyword.get(opts, :scroll, 0), max(content_height - height, 0))

    # A panel with a bar on it is that much narrower for its rows. Taken off
    # here rather than at drawing time so that the row a click lands on, the
    # row that is drawn, and the width a row lays its own controls out in are
    # one number — a segmented control that reached under the bar would be
    # missing the third of itself you could see.
    #
    # The caller is expected to have ASKED for that width (see `bar_lane/3`).
    # Where it has not, the rows simply get less room and their labels
    # truncate — which is what a menu wide enough for its longest label did
    # the moment it became a menu that also scrolls.
    row_width =
      width - 2 * padding - if(content_height > height, do: @bar_lane, else: 0)

    items =
      rows
      |> Enum.map_reduce(0, fn row, offset ->
        row_height = Model.item_height(row, theme)

        {{Model.get_item_id(row),
          %{
            x: x + padding,
            y: y + padding + offset - scroll,
            width: row_width,
            height: row_height
          }}, offset + row_height}
      end)
      |> elem(0)
      |> Enum.into(%{})

    %{
      x: x,
      y: y,
      width: width,
      height: height,
      content_height: content_height,
      scroll: scroll,
      items: items
    }
  end

  # ── Scrolling ─────────────────────────────────────────────────────────────
  #
  # A panel clamped by `:max_height` has rows below its bottom edge, and until
  # this section existed each host reached them its own way: `IconMenu` wound
  # the whole panel in pixels, the search pane wound the scope tree in NODES
  # from a field on the pane, and neither of them said on screen that it could
  # be done at all. One mechanism, in the module that already knows where every
  # row is — the hosts keep the number, because they are the ones with somewhere
  # durable to keep it, and do none of the arithmetic on it.

  @doc "How tall these rows come to, the panel's own padding included."
  def content_height(rows, theme),
    do: Enum.sum(Enum.map(rows, &Model.item_height(&1, theme))) + 2 * theme.dropdown_padding

  @doc """
  How much extra width a panel of these rows needs for its scrollbar: 16, or 0.

  For a caller deciding how WIDE to make a panel, before there is a layout to
  ask. A menu is sized to its longest label; the bar then takes that much room
  back out of every row, and every label in a menu long enough to scroll is
  truncated by exactly the width of the bar that made it scroll. The height
  does not depend on the width, so this can be answered first.
  """
  def bar_lane(rows, theme, max_height) when is_number(max_height) and max_height > 0,
    do: if(content_height(rows, theme) > max_height, do: @bar_lane, else: 0)

  def bar_lane(_rows, _theme, _max_height), do: 0

  @doc "How far this panel can be wound down; 0 when it all fits."
  def max_scroll(bounds), do: max(bounds.content_height - bounds.height, 0)

  @doc "Is there more panel than there is room for it?"
  def scrollable?(bounds), do: max_scroll(bounds) > 0

  @doc """
  Where one turn of the wheel leaves the panel.

  `dy` is Scenic's, unnegated: turning the wheel away from you (`dy > 0`) moves
  the content back towards the first row.
  """
  def wheel(bounds, scroll, dy) do
    step = if dy > 0, do: -@scroll_step, else: @scroll_step
    clamp(scroll + step, bounds)
  end

  @doc """
  Where a drag of the thumb leaves the panel.

  `start` is the offset the button went down at and `delta` how far the pointer
  has come since — the whole drag measured from one place, because accumulating
  it sample by sample drifts.
  """
  def drag(bounds, start, delta) do
    {_thumb_y, thumb_height} = thumb_span(bounds)

    ScrollController.drag_offset(
      start,
      delta,
      track_length(bounds),
      thumb_height,
      max_scroll(bounds)
    )
  end

  @doc """
  Where a click on the empty track leaves the panel: one panelful that way.

  `y` is measured along the track, as `scrollbar_hit/2` reports it.
  """
  def page(bounds, y) do
    {thumb_y, thumb_height} = thumb_span(bounds)

    ScrollController.page_offset(
      bounds.scroll,
      y,
      thumb_y,
      thumb_height,
      bounds.height,
      max_scroll(bounds)
    )
  end

  @doc """
  What a point hit on the scrollbar: `:thumb`, `{:track, y}`, or `nil`.

  Asked BEFORE `row_at/2`, because the bar is drawn over the right-hand end of
  the panel and a click there means the bar, not the row behind it. The rows
  are laid out narrower when there is a bar (see `layout/3`), so the two can
  never both claim the same pixel.
  """
  def scrollbar_hit(bounds, {x, y}) do
    on_bar? =
      scrollable?(bounds) and
        x >= bounds.x + bounds.width - @bar_lane and x <= bounds.x + bounds.width and
        y >= bounds.y and y <= bounds.y + bounds.height

    if on_bar? do
      along = y - bounds.y - @bar_pad
      {thumb_y, thumb_height} = thumb_span(bounds)

      if along >= thumb_y and along <= thumb_y + thumb_height,
        do: :thumb,
        else: {:track, along}
    end
  end

  @doc """
  Is this rectangle actually on show, or has it been wound off the edge?

  A clamped panel lays out every row it has, including the ones above and
  below what it can show — the scissor stops them being DRAWN. Anything
  publishing rows by name (a semantic layer, a test driving the menu) has to
  ask, or it offers to click rows that are not there.
  """
  def visible?(bounds, %{y: y, height: height}),
    do: y + height > bounds.y and y < bounds.y + bounds.height

  defp clamp(scroll, bounds), do: scroll |> max(0) |> min(max_scroll(bounds))

  # The panel said in the words `Widgex.Scroll` uses, so that the bar this
  # module draws, the bar `ScrollRenderer` draws for everything else, and the
  # arithmetic `ScrollController` does for both are the same three things.
  defp scroll_state(bounds) do
    %ScrollState{
      offset_y: bounds.scroll,
      content_height: bounds.content_height,
      viewport_height: bounds.height,
      content_width: bounds.width,
      viewport_width: bounds.width,
      direction: :vertical,
      scrollbar_visible: true,
      scrollbar_opacity: 255
    }
  end

  defp panel_frame(bounds),
    do: Widgex.Frame.new(%{pin: {0, 0}, size: {bounds.width, bounds.height}})

  defp track_length(bounds),
    do: Drag.track_length(panel_frame(bounds), scroll_state(bounds), :y)

  # Where the thumb is DRAWN — the same sum `ScrollRenderer` does, so what you
  # grab and what moves cannot disagree.
  defp thumb_span(bounds) do
    {thumb_y, thumb_height} = ScrollState.scrollbar_thumb(scroll_state(bounds), :y)
    scale = track_length(bounds) / bounds.height
    {thumb_y * scale, thumb_height * scale}
  end

  @doc """
  Which row is under a point, and where inside that row it landed.

  Returns `{row_id, {local_x, local_y}}` — local to the ROW, which is what
  every row type's behaviour is written in terms of — or `:panel` for a click
  that hit the panel but no row, or `nil` for one that missed entirely.
  """
  def row_at(bounds, {x, y}) do
    inside? =
      x >= bounds.x and x <= bounds.x + bounds.width and
        y >= bounds.y and y <= bounds.y + bounds.height

    cond do
      not inside? ->
        nil

      true ->
        Enum.find_value(bounds.items, :panel, fn {id, b} ->
          if y >= b.y and y < b.y + b.height, do: {id, {x - b.x, y - b.y}}
        end)
    end
  end

  @doc """
  Every node of a `Tree` row, with the rectangle it is drawn in.

  For anything that has to address the nodes from outside — a semantic layer,
  a test driving the panel by name — rather than by guessing at the
  arithmetic and drifting away from it.
  """
  def tree_node_bounds(%Model.Tree{} = tree, row_bounds, theme) do
    if tree.expanded? do
      row_height = theme.dropdown_item_height

      tree
      |> Model.visible_tree_nodes()
      |> Enum.with_index()
      |> Enum.map(fn {{node, depth}, i} ->
        {node,
         %{
           x: row_bounds.x,
           y: row_bounds.y + (i + 1) * row_height,
           width: row_bounds.width,
           height: row_height,
           # Where its triangle is, for anything that needs to press one.
           expander: %{
             x: row_bounds.x + 8 + depth * Model.tree_indent(),
             width: Model.tree_indent()
           }
         }}
      end)
    else
      []
    end
  end

  @doc """
  What a click inside a `Tree` row hit, given where it landed in that row.

  `:header` is the row itself, which opens and shuts the tree. Inside it, the
  TRIANGLE expands a branch and the rest of the row ticks it — two intentions,
  two targets, because one rectangle carrying both means the commonest thing
  you want from a tree ("not that one") cannot be done to anything that has
  children.
  """
  def tree_hit(%Model.Tree{} = tree, {x, y}, theme) do
    row_height = theme.dropdown_item_height

    if not tree.expanded? or y < row_height do
      :header
    else
      index = floor((y - row_height) / row_height)

      case Enum.at(Model.visible_tree_nodes(tree), index) do
        nil ->
          nil

        {node, depth} ->
          gutter = 8 + depth * Model.tree_indent()

          if node.children != [] and x >= gutter and x < gutter + Model.tree_indent(),
            do: {:expand, node.id},
            else: {:tick, node.id}
      end
    end
  end

  @doc """
  Draw a panel of rows.

  The panel is translated to `bounds.x/y`, so rows inside it are positioned
  relative to the panel and never have to know where on the screen it landed.
  """
  def render(graph, rows, bounds, opts) do
    theme = Keyword.fetch!(opts, :theme)
    hovered = Keyword.get(opts, :hovered)
    hovered_select_option = Keyword.get(opts, :hovered_select_option)
    hovered_node = Keyword.get(opts, :hovered_node)
    show_shortcuts = Keyword.get(opts, :show_shortcuts, true)
    id = Keyword.get(opts, :id, :dropdown_group)

    Primitives.group(
      graph,
      fn g ->
        g
        |> Primitives.rrect(
          {bounds.width, bounds.height, 4},
          [id: :dropdown_bg, fill: theme.dropdown_bg, stroke: {1, theme.dropdown_border}] ++
            panel_input(opts)
        )
        |> Primitives.group(
          fn inner ->
            render_rows(
              inner,
              rows,
              bounds,
              theme,
              hovered,
              hovered_node,
              hovered_select_option,
              show_shortcuts
            )
          end,
          id: :dropdown_items_group,
          # A clamped panel scrolls, so its rows have to be clipped to it.
          # Without this the overflow is simply drawn past the bottom edge —
          # over the document, and over nothing at all below the window.
          scissor: {bounds.width, bounds.height}
        )
        |> render_scrollbar(bounds, id)
      end,
      id: id,
      translate: {bounds.x, bounds.y}
    )
  end

  # The bar, when and only when there is something to scroll. Outside the
  # scissored group, so it does not scroll along with what it is scrolling,
  # and after it, so it is drawn on top of the rows it overhangs.
  #
  # A menu that clamps itself and then says nothing about it is a menu whose
  # last rows can be counted and not found. Both hosts had one; neither drew
  # anything at all.
  defp render_scrollbar(graph, bounds, id) do
    if scrollable?(bounds) do
      # No `input:` on the bar's own primitives. Both hosts find it through
      # `scrollbar_hit/2` on the way in — IconMenu because it has asked Scenic
      # for the pointer globally and would hear every press twice, the search
      # pane because its panel already claims the pointer over itself and the
      # bar is inside the panel.
      ScrollRenderer.render_scrollbars(graph, scroll_state(bounds), panel_frame(bounds),
        group_id: id,
        input: false
      )
    else
      graph
    end
  end

  defp render_rows(
         graph,
         items,
         dropdown,
         theme,
         hovered_item,
         hovered_node,
         hovered_select_option,
         show_shortcuts
       ) do
    padding = theme.dropdown_padding

    # Space reserved for checkmark on the left
    checkmark_width = 28

    Enum.reduce(items, graph, fn item, acc ->
      item_id = Model.get_item_id(item)
      label = Model.display_label(item)
      shortcut = Model.item_shortcut(item, show_shortcuts)
      is_toggle = Model.is_toggle_item?(item)
      is_checked = Model.is_item_checked?(item)
      item_bounds = Map.fetch!(dropdown.items, item_id)

      is_hovered = hovered_item == item_id

      # Position relative to dropdown origin. The WIDTH is the laid-out row's,
      # not the panel's less its padding: those differ by a scrollbar lane on
      # a panel that has one, and a row that draws itself the panel's width
      # puts its right-hand controls under the bar.
      item_x = padding
      item_y = item_bounds.y - dropdown.y
      row_height = item_bounds.height
      row_width = item_bounds.width

      # A Tree is one row holding many, so lighting the row would light the
      # whole tree when the pointer is on one node of it. Its nodes carry
      # their own highlight instead.
      bg_color =
        if is_hovered and not match?(%Model.Tree{}, item) and
             not match?(%Model.Select{}, item),
           do: theme.item_hover_bg,
           else: :clear

      enabled? = Model.item_enabled?(item)

      text_color =
        cond do
          not enabled? -> {120, 120, 120}
          is_hovered and not match?(%Model.Select{}, item) -> theme.item_hover_text_color
          true -> theme.item_text_color
        end

      if match?(%Model.Divider{}, item) do
        divider_y = row_height / 2

        acc
        |> Primitives.line(
          {{8, divider_y}, {row_width - 8, divider_y}},
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
                {row_width, row_height, 3},
                id: {:item_bg, item_id},
                fill: bg_color
              )

            # The tick on a checked toggle — DRAWN, like the tree's tick and
            # the disclosure triangles beside it. It was typed as "✓", and a
            # mono font that has no U+2713 substitutes: in the search pane's
            # panel it came out as a lower-case v, which is not a tick and is
            # not nothing either, so it reads as part of the label.
            g =
              if is_toggle,
                do: toggle_box(g, 8, row_height / 2, is_checked, text_color),
                else: g

            cond do
              match?(%Model.Tree{}, item) ->
                render_tree(g, item, row_width, text_color, theme, is_hovered, hovered_node)

              match?(%Model.Segmented{}, item) ->
                render_segmented(g, item, row_width, text_color, is_hovered, theme)

              match?(%Model.Select{}, item) ->
                render_select(
                  g,
                  item,
                  row_width,
                  text_color,
                  is_hovered,
                  hovered_select_option,
                  theme
                )

              match?(%Model.Stepper{}, item) ->
                render_stepper(g, item, row_width, text_color, theme)

              match?(%Model.Slider{}, item) ->
                render_slider(
                  g,
                  item,
                  row_width,
                  text_color,
                  is_hovered,
                  theme
                )

              true ->
                text_x =
                  if Map.get(item, :flush_left?, false) or not has_any_toggle_items?(items),
                    do: 8,
                    else: checkmark_width

                shortcut_right = row_width - 8
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
    |> minus_sign(controls_x + 14, center_y, text_color)
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
    |> plus_sign(controls_x + 102, center_y, text_color)
  end

  # A tree of tickable things, opening in place — the same arrangement as an
  # expanded Select, one level per indent. Its triangle and its tick are DRAWN
  # rather than typed: a font that has no ▸ draws an empty box instead, and a
  # box beside every folder is worse than no triangle at all.
  defp render_tree(graph, tree, row_width, text_color, theme, header_hovered?, hovered_node) do
    row_height = theme.dropdown_item_height
    baseline = row_height / 2 + theme.dropdown_font_size / 3

    graph
    |> then(fn g ->
      if header_hovered? and is_nil(hovered_node) do
        Primitives.rrect(g, {row_width, row_height, 3},
          id: {:tree_header_bg, tree.id},
          fill: theme.item_hover_bg
        )
      else
        g
      end
    end)
    |> Primitives.text(Model.display_label(tree),
      id: {:tree_label, tree.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      translate: {8, baseline}
    )
    |> caret(
      row_width - 16,
      row_height / 2,
      tree.expanded?,
      text_color,
      tree.closed_caret || :right
    )
    |> render_tree_nodes(tree, row_width, row_height, text_color, theme, hovered_node)
  end

  defp render_tree_nodes(graph, %{expanded?: false}, _w, _h, _colour, _theme, _hovered), do: graph

  defp render_tree_nodes(graph, tree, row_width, row_height, text_color, theme, hovered_node) do
    tree
    |> Model.visible_tree_nodes()
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {{node, depth}, i}, g ->
      y = (i + 1) * row_height
      x = 8 + depth * Model.tree_indent()

      g
      |> then(fn gg ->
        # The node under the pointer, not the row it is part of.
        if node.id == hovered_node do
          Primitives.rrect(gg, {row_width, row_height, 3},
            fill: theme.item_hover_bg,
            translate: {0, y}
          )
        else
          gg
        end
      end)
      |> then(fn gg ->
        if node.children == [],
          do: gg,
          else: caret(gg, x + 4, y + row_height / 2, node.expanded?, text_color)
      end)
      |> tick_box(x + Model.tree_indent(), y + row_height / 2, node.checked?, text_color, theme)
      |> Primitives.text(node.label,
        id: {:tree_node, tree.id, node.id},
        fill: text_color,
        font: theme.font,
        font_size: theme.dropdown_font_size,
        translate:
          {x + Model.tree_indent() + 16, y + row_height / 2 + theme.dropdown_font_size / 3}
      )
    end)
  end

  # A stepper's minus and plus, drawn. The minus was typed as U+2212 and the
  # Select's arrow as U+25BE, and IBM Plex Mono has neither — the arrow came
  # out as an empty box on the View menu's "Set Fold Level" row, which is the
  # same trap that gave the menus "Cmd" instead of "⌘" and the settings panel
  # a lower-case v for its tick. Nothing in a menu is typed if it is a shape.
  defp minus_sign(graph, x, y, colour) do
    Primitives.line(graph, {{x - 5, y}, {x + 5, y}}, stroke: {1.6, colour}, cap: :round)
  end

  defp plus_sign(graph, x, y, colour) do
    graph
    |> minus_sign(x, y, colour)
    |> Primitives.line({{x, y - 5}, {x, y + 5}}, stroke: {1.6, colour}, cap: :round)
  end

  # A disclosure triangle, drawn: right when shut, down when open.
  defp caret(graph, x, y, open?, colour, closed_direction \\ :right) do
    points =
      cond do
        open? -> [{x - 4, y - 2}, {x + 4, y - 2}, {x, y + 3}]
        closed_direction == :left -> [{x + 2, y - 4}, {x - 3, y}, {x + 2, y + 4}]
        true -> [{x - 2, y - 4}, {x + 3, y}, {x - 2, y + 4}]
      end

    Primitives.triangle(graph, List.to_tuple(points), fill: colour)
  end

  # A tick, drawn for the same reason. `x, y` is its top-left-ish anchor, the
  # same place the box below puts one.
  defp check_mark(graph, x, y, colour) do
    graph
    |> Primitives.line({{x + 2.5, y}, {x + 4.5, y + 3}}, stroke: {1.6, colour}, cap: :round)
    |> Primitives.line({{x + 4.5, y + 3}, {x + 8.5, y - 3.5}}, stroke: {1.6, colour}, cap: :round)
  end

  # A tick box, drawn for the same reason.
  defp tick_box(graph, x, y, checked?, colour, _theme) do
    graph
    |> Primitives.rrect({11, 11, 2},
      fill: :clear,
      stroke: {1, colour},
      translate: {x, y - 5.5}
    )
    |> then(fn g -> if checked?, do: check_mark(g, x, y, colour), else: g end)
  end

  # Boolean menu rows always reserve and draw the same box. The mark says
  # which state is in force; the label no longer jumps sideways when toggled.
  defp toggle_box(graph, x, y, checked?, colour) do
    graph =
      Primitives.rrect(graph, {11, 11, 2},
        fill: :clear,
        stroke: {1, colour},
        translate: {x, y - 5.5}
      )

    if checked? do
      check_mark(graph, x, y, colour)
    else
      graph
    end
  end

  # An either/or: one track with a position per choice, and the one in force
  # filled. The same control the search pane had on its status bar, which is
  # where this came from — it was a good control in the wrong place, and the
  # only reason it was not a menu row is that a menu row could not be one.
  defp render_segmented(graph, seg, row_width, text_color, hovered?, theme) do
    row_height = theme.dropdown_item_height
    baseline = row_height / 2 + theme.dropdown_font_size / 3
    segments = Model.segments(seg)
    count = length(segments)

    track_width = segmented_track_width(count, theme)
    track_x = row_width - track_width - 8
    track_height = row_height - 8
    seg_width = track_width / count

    graph
    |> Primitives.text(seg.label,
      id: {:segmented_label, seg.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      translate: {8, baseline}
    )
    |> Primitives.rrect({track_width, track_height, 4},
      id: {:segmented_track, seg.id},
      fill: :clear,
      stroke: {1, theme.dropdown_border},
      translate: {track_x, 4}
    )
    |> then(fn g ->
      index = Enum.find_index(segments, fn {value, _} -> value == seg.value end) || 0

      Primitives.rrect(g, {seg_width, track_height, 4},
        id: {:segmented_thumb, seg.id},
        fill: if(hovered?, do: theme.item_hover_text_color, else: theme.item_hover_bg),
        translate: {track_x + index * seg_width, 4}
      )
    end)
    |> then(fn g ->
      segments
      |> Enum.with_index()
      |> Enum.reduce(g, fn {{value, label}, i}, acc ->
        Primitives.text(acc, label,
          id: {:segmented_option, seg.id, value},
          fill:
            if(value == seg.value,
              do: if(hovered?, do: theme.item_hover_bg, else: theme.item_hover_text_color),
              else: text_color
            ),
          font: theme.font,
          font_size: theme.dropdown_font_size,
          text_align: :center,
          translate: {track_x + i * seg_width + seg_width / 2, baseline}
        )
      end)
    end)
  end

  @doc """
  Every choice of a `Segmented` row, with the rectangle it is drawn in.

  So the individual positions can be addressed from outside — by a semantic
  layer, or by anything driving the control by name rather than by working out
  which third of it to aim at.
  """
  def segment_bounds(%Model.Segmented{} = seg, row_bounds, theme) do
    segments = Model.segments(seg)
    count = length(segments)
    track_width = segmented_track_width(count, theme)
    track_x = row_bounds.x + row_bounds.width - track_width - 8
    seg_width = track_width / count
    row_height = theme.dropdown_item_height

    segments
    |> Enum.with_index()
    |> Enum.map(fn {{value, label}, i} ->
      {value, label,
       %{
         x: round(track_x + i * seg_width),
         y: row_bounds.y + 4,
         width: round(seg_width),
         height: row_height - 8
       }}
    end)
  end

  defp segmented_track_width(count, theme),
    do: round(count * 5 * theme.dropdown_font_size * 0.6 + count * 12)

  @doc """
  Which choice a click on a `Segmented` row landed on.

  `local` is measured from the row's own left edge, the way every row type's
  behaviour is written here.
  """
  def segmented_hit(%Model.Segmented{} = seg, {x, _y}, row_width, theme) do
    segments = Model.segments(seg)
    count = length(segments)
    track_width = segmented_track_width(count, theme)
    track_x = row_width - track_width - 8

    cond do
      x < track_x -> nil
      true -> Model.segment_at(seg, x - track_x, track_width)
    end
  end

  defp render_select(graph, select, row_width, text_color, hovered?, hovered_option, theme) do
    row_height = theme.dropdown_item_height
    box_width = select.option_width || 76
    box_x = row_width - box_width - 8
    baseline = row_height / 2 + theme.dropdown_font_size / 3

    graph
    |> Primitives.text(clip_select_row_label(select.label, box_x, theme),
      id: {:select_label, select.id},
      fill: text_color,
      font: theme.font,
      font_size: theme.dropdown_font_size,
      translate: {8, baseline}
    )
    |> Primitives.rrect({box_width, row_height - 8, 3},
      id: {:select_box, select.id},
      fill: if(hovered?, do: theme.item_hover_bg, else: :clear),
      stroke: {1, theme.dropdown_border},
      translate: {box_x, 4}
    )
    |> Primitives.text(clip_select_label(Model.select_label(select), box_width, theme),
      id: {:select_value, select.id},
      fill: if(hovered?, do: theme.item_hover_text_color, else: text_color),
      font: theme.font,
      font_size: theme.dropdown_font_size,
      text_align: :center,
      translate: {box_x + box_width / 2 - 7, baseline}
    )
    |> caret(
      box_x + box_width - 13,
      row_height / 2,
      select.expanded?,
      if(hovered?, do: theme.item_hover_text_color, else: text_color),
      select.closed_caret || :right
    )
    |> render_select_options(select, row_width, row_height, text_color, hovered_option, theme)
  end

  defp render_select_options(
         graph,
         %{expanded?: false},
         _width,
         _height,
         _color,
         _hovered,
         _theme
       ),
       do: graph

  defp render_select_options(
         graph,
         select,
         row_width,
         row_height,
         text_color,
         hovered_option,
         theme
       ) do
    select
    |> Model.select_options()
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {{value, label}, index}, acc ->
      y = row_height * (index + 1)
      {box_x, box_width} = select_option_box(select, row_width)
      swatches = Map.get(select.swatches || %{}, value, [])
      label_x = box_x + if(swatches == [], do: 7, else: 34)

      acc
      |> Primitives.rect({box_width, row_height},
        id: {:select_option_bg, select.id, value},
        fill:
          cond do
            value == hovered_option -> theme.item_hover_bg
            value == select.value -> Map.get(theme, :button_background, theme.dropdown_border)
            true -> theme.dropdown_bg
          end,
        translate: {box_x, y}
      )
      |> Primitives.text(label,
        id: {:select_option, select.id, value},
        fill: if(value == hovered_option, do: theme.item_hover_text_color, else: text_color),
        font: theme.font,
        font_size: theme.dropdown_font_size,
        translate: {label_x, y + row_height / 2 + theme.dropdown_font_size / 3}
      )
      |> render_select_swatches(swatches, box_x + 9, y + row_height / 2)
    end)
  end

  defp select_option_box(%{options_full_width?: true}, row_width), do: {0, row_width}

  defp select_option_box(select, row_width) do
    width = select.option_width || 76
    {row_width - width - 8, width}
  end

  defp clip_select_label(label, box_width, theme) do
    available = max(box_width - 30, 0)
    max_chars = trunc(available / max(theme.dropdown_font_size * 0.6, 1))

    if String.length(label) <= max_chars,
      do: label,
      else: String.slice(label, 0, max(max_chars - 1, 0)) <> "…"
  end

  defp clip_select_row_label(label, box_x, theme) do
    available = max(box_x - 16, 0)
    max_chars = trunc(available / max(theme.dropdown_font_size * 0.6, 1))

    if String.length(label) <= max_chars,
      do: label,
      else: String.slice(label, 0, max(max_chars - 1, 0)) <> "…"
  end

  defp render_select_swatches(graph, [], _x, _y), do: graph

  defp render_select_swatches(graph, colors, x, y) do
    [base, upper, lower | _] = Enum.take(colors ++ colors ++ colors, 3)

    graph
    |> Primitives.rect({18, 18}, fill: base, translate: {x, y - 9})
    |> Primitives.triangle({{x, y - 9}, {x + 18, y - 9}, {x + 18, y + 9}}, fill: upper)
    |> Primitives.triangle({{x, y + 9}, {x + 9, y}, {x + 18, y + 9}}, fill: lower)
    |> Primitives.rect({18, 18},
      fill: :clear,
      stroke: {1, {128, 128, 128}},
      translate: {x, y - 9}
    )
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
    Enum.any?(items, &Model.is_toggle_item?/1)
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
end
