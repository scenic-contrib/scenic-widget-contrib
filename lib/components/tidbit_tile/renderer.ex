defmodule ScenicWidgets.TidbitTile.Renderer do
  @moduledoc """
  Rendering functions for TidbitTile.

  Structure:
  - Shadow rect (subtle drop shadow effect)
  - Card background (rounded rectangle)
  - Title text
  """

  alias Scenic.Graph
  alias Scenic.Primitives
  alias ScenicWidgets.TidbitTile.State

  @doc """
  Initial render - create all UI elements.
  """
  def initial_render(graph, %State{} = state) do
    graph
    |> render_card(state)
    |> render_title(state)
  end

  @doc """
  Update render - only modify elements that changed.
  """
  def update_render(graph, %State{} = old_state, %State{} = new_state) do
    graph
    |> update_card_if_changed(old_state, new_state)
    |> update_title_if_changed(old_state, new_state)
  end

  # ===========================================================================
  # Initial Rendering
  # ===========================================================================

  defp render_card(graph, %State{frame: frame, theme: theme} = state) do
    width = State.get_width(frame)
    height = State.get_height(frame)

    bg_color = get_background_color(state)
    border_color = get_border_color(state)

    graph
    # Card background with border
    |> Primitives.rrect(
      {width, height, theme.border_radius},
      id: :card_bg,
      fill: bg_color,
      stroke: {theme.border_width, border_color}
    )
  end

  defp render_title(graph, %State{frame: frame, theme: theme, title: title}) do
    width = State.get_width(frame)
    padding = theme.padding

    # Truncate title if too long
    max_chars = trunc((width - padding * 2) / (theme.title_font_size * 0.6))
    display_title = truncate_text(title, max_chars)

    graph
    |> Primitives.text(
      display_title,
      id: :title_text,
      fill: theme.title_color,
      font: theme.font,
      font_size: theme.title_font_size,
      translate: {padding, padding + theme.title_font_size}
    )
  end

  # ===========================================================================
  # Update Rendering
  # ===========================================================================

  defp update_card_if_changed(graph, old_state, new_state) do
    hover_changed = old_state.hovered != new_state.hovered
    selected_changed = old_state.selected != new_state.selected

    if hover_changed or selected_changed do
      theme = new_state.theme
      bg_color = get_background_color(new_state)
      border_color = get_border_color(new_state)

      graph
      |> Graph.modify(:card_bg, fn p ->
        Primitives.update_opts(p,
          fill: bg_color,
          stroke: {theme.border_width, border_color}
        )
      end)
    else
      graph
    end
  end

  defp update_title_if_changed(graph, old_state, new_state) do
    if old_state.title != new_state.title do
      theme = new_state.theme
      width = State.get_width(new_state.frame)
      padding = theme.padding
      max_chars = trunc((width - padding * 2) / (theme.title_font_size * 0.6))
      display_title = truncate_text(new_state.title, max_chars)

      graph
      |> Graph.modify(:title_text, fn p ->
        Primitives.text(p, display_title)
      end)
    else
      graph
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp get_background_color(%State{selected: true, theme: theme}), do: theme.background_selected
  defp get_background_color(%State{hovered: true, theme: theme}), do: theme.background_hover
  defp get_background_color(%State{theme: theme}), do: theme.background

  defp get_border_color(%State{selected: true, theme: theme}), do: theme.border_selected_color
  defp get_border_color(%State{hovered: true, theme: theme}), do: theme.border_hover_color
  defp get_border_color(%State{theme: theme}), do: theme.border_color

  defp truncate_text(text, max_chars) when byte_size(text) <= max_chars, do: text
  defp truncate_text(text, max_chars) do
    if String.length(text) <= max_chars do
      text
    else
      String.slice(text, 0, max(0, max_chars - 3)) <> "..."
    end
  end
end
