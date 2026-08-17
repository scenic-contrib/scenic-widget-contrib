defmodule ScenicWidgets.TidbitColumn.Renderer do
  @moduledoc """
  Rendering logic for the TidbitColumn component.

  Uses the Scrollable macro for scroll rendering helpers.
  """

  use Widgex.Scrollable

  alias Scenic.Graph
  alias Scenic.Primitives
  alias ScenicWidgets.TidbitColumn.State

  @doc """
  Perform initial render of the tidbit column.
  """
  def initial_render(graph, %State{} = state) do
    {width, height} = state.frame.size.box
    theme = state.theme

    graph
    |> Primitives.group(
      fn g ->
        g
        # Background
        |> Primitives.rect({width, height},
          fill: theme.background,
          stroke: {1, theme.border}
        )
        # Scrollable content area
        |> scrollable_group(state.scroll, state.frame, fn sg ->
          render_items(sg, state)
        end, id: :tidbit_content)
        # Scrollbars on top
        |> render_scrollbars(state.scroll, state.frame)
      end,
      translate: {0, 0}
    )
  end

  @doc """
  Update render - efficiently update changed elements.
  """
  def update_render(graph, %State{} = old_state, %State{} = new_state) do
    cond do
      # Items changed - full re-render
      old_state.items != new_state.items ->
        initial_render(Graph.build(font: :roboto_mono), new_state)

      # Scroll changed
      scroll_changed?(old_state.scroll, new_state.scroll) ->
        graph
        |> update_scroll_transform(:tidbit_content, old_state.scroll, new_state.scroll)
        |> update_scrollbars(old_state.scroll, new_state.scroll, new_state.frame)

      # Hover or selection changed
      old_state.hovered_id != new_state.hovered_id ||
      old_state.selected_id != new_state.selected_id ->
        update_item_states(graph, old_state, new_state)

      # No changes
      true ->
        graph
    end
  end

  # Render all items
  defp render_items(graph, %State{items: items} = state) do
    bounds = State.item_bounds(state)

    Enum.reduce(items, graph, fn item, g ->
      item_bounds = Map.get(bounds, item.id)
      render_item(g, item, item_bounds, state)
    end)
  end

  # Render a single item card
  defp render_item(graph, item, bounds, %State{} = state) when is_map(bounds) do
    theme = state.theme
    is_hovered = state.hovered_id == item.id
    is_selected = state.selected_id == item.id

    # Determine card color
    card_fill = cond do
      is_selected -> theme.card_selected
      is_hovered -> theme.card_hover
      true -> theme.card_background
    end

    # Card border
    border_color = if is_selected, do: {100, 150, 255}, else: theme.border

    card_id = String.to_atom("tidbit_card_#{item.id}")
    title_id = String.to_atom("tidbit_title_#{item.id}")

    graph
    |> Primitives.group(
      fn g ->
        g
        # Card background
        |> Primitives.rrect(
          {bounds.width, bounds.height, 6},
          id: card_id,
          fill: card_fill,
          stroke: {1, border_color}
        )
        # Title
        |> Primitives.text(
          item.title,
          id: title_id,
          fill: theme.text,
          font: :roboto_mono,
          font_size: 16,
          translate: {12, 24}
        )
        # Preview text
        |> Primitives.text(
          truncate(item.preview, 50),
          fill: theme.text_secondary,
          font: :roboto_mono,
          font_size: 12,
          translate: {12, 48}
        )
      end,
      id: String.to_atom("tidbit_item_#{item.id}"),
      translate: {bounds.x, bounds.y}
    )
  end

  defp render_item(graph, _item, nil, _state), do: graph

  # Update item visual states (hover/selection)
  defp update_item_states(graph, old_state, new_state) do
    theme = new_state.theme

    # Find changed items
    changed_ids = [
      old_state.hovered_id,
      new_state.hovered_id,
      old_state.selected_id,
      new_state.selected_id
    ]
    |> Enum.filter(& &1)
    |> Enum.uniq()

    Enum.reduce(changed_ids, graph, fn item_id, g ->
      is_hovered = new_state.hovered_id == item_id
      is_selected = new_state.selected_id == item_id

      card_fill = cond do
        is_selected -> theme.card_selected
        is_hovered -> theme.card_hover
        true -> theme.card_background
      end

      border_color = if is_selected, do: {100, 150, 255}, else: theme.border

      card_id = String.to_atom("tidbit_card_#{item_id}")

      try do
        g
        |> Graph.modify(card_id, fn primitive ->
          primitive
          |> Scenic.Primitive.put_style(:fill, card_fill)
          |> Scenic.Primitive.put_style(:stroke, {1, border_color})
        end)
      rescue
        _ -> g
      end
    end)
  end

  # Truncate text with ellipsis
  defp truncate(text, max_length) when byte_size(text) > max_length do
    String.slice(text, 0, max_length - 3) <> "..."
  end
  defp truncate(text, _max_length), do: text
end
