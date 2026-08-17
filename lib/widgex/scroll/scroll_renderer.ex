defmodule Widgex.Scroll.ScrollRenderer do
  @moduledoc """
  Rendering helpers for scrollable content.

  Provides functions to create scrollable groups with scissor clipping,
  update scroll transforms efficiently, and render scrollbars.

  ## Example

      def initial_render(graph, state) do
        graph
        |> ScrollRenderer.scrollable_group(state.scroll, state.frame, fn g ->
          render_items(g, state)
        end, id: :content)
        |> ScrollRenderer.render_scrollbars(state.scroll, state.frame)
      end

      def update_render(graph, old_state, new_state) do
        graph
        |> ScrollRenderer.update_scroll_transform(:content, old_state.scroll, new_state.scroll)
        |> ScrollRenderer.update_scrollbars(old_state.scroll, new_state.scroll, new_state.frame)
      end
  """

  alias Scenic.Graph
  alias Scenic.Primitives
  alias Widgex.Frame
  alias Widgex.Scroll.ScrollState

  # Scrollbar styling
  @scrollbar_width 12
  @scrollbar_padding 2
  @scrollbar_track_opacity 0x80
  # @scrollbar_thumb_opacity 0x80  # Currently using scroll state opacity
  # Gray scrollbar color
  @scrollbar_color {160, 160, 160}
  @scrollbar_inset @scrollbar_width + @scrollbar_padding * 2

  @doc """
  Create a scrollable group with scissor clipping.

  The group is clipped to the frame bounds and translated by the scroll offset.
  The content function receives the graph and should add content primitives.

  ## Options

    * `:id` - ID for the scroll group (required for updates)
    * Other options are passed to `Scenic.Primitives.group/3`

  ## Example

      graph
      |> scrollable_group(scroll, frame, fn g ->
        g
        |> Primitives.text("Item 1", translate: {0, 20})
        |> Primitives.text("Item 2", translate: {0, 40})
      end, id: :content_group)
  """
  @spec scrollable_group(
          Graph.t(),
          ScrollState.t(),
          Frame.t(),
          (Graph.t() -> Graph.t()),
          keyword()
        ) ::
          Graph.t()
  def scrollable_group(graph, %ScrollState{} = scroll, %Frame{} = frame, content_fn, opts \\ []) do
    overlay_scrollbars? = Keyword.get(opts, :overlay_scrollbars, false)

    content_width =
      if ScrollState.scrollable_y?(scroll) and not overlay_scrollbars?,
        do: scroll.viewport_width - @scrollbar_inset,
        else: scroll.viewport_width

    content_height =
      if ScrollState.scrollable_x?(scroll) and not overlay_scrollbars?,
        do: scroll.viewport_height - @scrollbar_inset,
        else: scroll.viewport_height

    {tx, ty} = ScrollState.translate_offset(scroll)

    # Get the ID for the inner scrolling group
    inner_id = Keyword.get(opts, :id, :scroll_content)
    outer_id = :"#{inner_id}_scissor"

    # Outer group: fixed position with scissor (clips content)
    # Inner group: translates for scrolling (content moves)
    Primitives.group(
      graph,
      fn outer_g ->
        Primitives.group(outer_g, content_fn,
          id: inner_id,
          translate: {tx, ty}
        )
      end,
      id: outer_id,
      # Keep content (and, importantly, its pointer hit areas) out from under
      # the scrollbar lanes. After an incremental scroll transform Scenic can
      # compile the moved content above the unchanged bars in its input list;
      # this clip guarantees the scrollbar remains the owner of that space.
      scissor: {max(content_width, 0), max(content_height, 0)}
    )
  end

  @doc """
  Update the scroll transform on an existing group.

  Uses `Graph.modify/3` for efficient updates without re-rendering content.
  Only updates if the offset actually changed.
  """
  @spec update_scroll_transform(Graph.t(), atom(), ScrollState.t(), ScrollState.t()) :: Graph.t()
  def update_scroll_transform(
        graph,
        group_id,
        %ScrollState{} = old_scroll,
        %ScrollState{} = new_scroll
      ) do
    if old_scroll.offset_x != new_scroll.offset_x || old_scroll.offset_y != new_scroll.offset_y do
      {tx, ty} = ScrollState.translate_offset(new_scroll)

      Graph.modify(graph, group_id, fn primitive ->
        Scenic.Primitive.put_style(primitive, :translate, {tx, ty})
      end)
    else
      graph
    end
  end

  @doc """
  Render scrollbars based on current scroll state.

  Renders vertical scrollbar if content is taller than viewport,
  horizontal scrollbar if content is wider than viewport.
  """
  @spec render_scrollbars(Graph.t(), ScrollState.t(), Frame.t(), keyword()) :: Graph.t()
  def render_scrollbars(graph, %ScrollState{} = scroll, %Frame{} = frame, opts \\ []) do
    {width, height} = frame.size.box
    {r, g, b} = Keyword.get(opts, :color, @scrollbar_color)
    opacity = scroll.scrollbar_opacity

    group_id = Keyword.get(opts, :group_id, :default)

    graph
    |> maybe_render_scrollbar_y(scroll, width, height, {r, g, b}, opacity, group_id)
    |> maybe_render_scrollbar_x(scroll, width, height, {r, g, b}, opacity, group_id)
  end

  @doc """
  Update scrollbar visibility and position.

  Efficiently updates scrollbar primitives when scroll state changes.
  """
  @spec update_scrollbars(Graph.t(), ScrollState.t(), ScrollState.t(), Frame.t(), keyword()) ::
          Graph.t()
  def update_scrollbars(
        graph,
        %ScrollState{} = old_scroll,
        %ScrollState{} = new_scroll,
        %Frame{} = frame,
        opts \\ []
      ) do
    group_id = Keyword.get(opts, :group_id, :default)
    color = Keyword.get(opts, :color, @scrollbar_color)

    graph
    |> update_scrollbar_y(old_scroll, new_scroll, frame, group_id, color)
    |> update_scrollbar_x(old_scroll, new_scroll, frame, group_id, color)
  end

  @doc """
  Update only the scrollbar visibility/opacity.
  """
  @spec update_scrollbar_visibility(Graph.t(), ScrollState.t(), keyword()) :: Graph.t()
  def update_scrollbar_visibility(graph, %ScrollState{} = scroll, opts \\ []) do
    group_id = Keyword.get(opts, :group_id, :default)
    {r, g, b} = @scrollbar_color
    opacity = scroll.scrollbar_opacity

    graph
    |> try_modify({:scrollbar_y_thumb, group_id}, fn primitive ->
      Scenic.Primitive.put_style(primitive, :fill, {r, g, b, opacity})
    end)
    |> try_modify({:scrollbar_x_thumb, group_id}, fn primitive ->
      Scenic.Primitive.put_style(primitive, :fill, {r, g, b, opacity})
    end)
  end

  # Render vertical scrollbar if needed
  defp maybe_render_scrollbar_y(
         graph,
         %ScrollState{} = scroll,
         width,
         height,
         color,
         opacity,
         group_id
       ) do
    if ScrollState.scrollable_y?(scroll) do
      # Calculate actual track height (accounting for padding)
      track_height = height - @scrollbar_padding * 2

      # Get thumb size ratio and scale to actual track
      {thumb_y_ratio, thumb_height_ratio} = ScrollState.scrollbar_thumb(scroll, :y)
      scale = track_height / scroll.viewport_height
      thumb_height = thumb_height_ratio * scale
      thumb_y = thumb_y_ratio * scale

      track_x = width - @scrollbar_width - @scrollbar_padding
      track_opacity = if opacity > 0, do: @scrollbar_track_opacity, else: 0
      {r, g, b} = color

      graph
      |> Primitives.group(
        fn grp ->
          grp
          # Track background
          |> Primitives.rrect(
            {@scrollbar_width, track_height, 4},
            id: {:scrollbar_y_track, group_id},
            fill: {r, g, b, track_opacity},
            input: [:cursor_button, :cursor_pos]
          )
          # Thumb
          |> Primitives.rrect(
            {@scrollbar_width, thumb_height, 4},
            id: {:scrollbar_y_thumb, group_id},
            fill: {r, g, b, opacity},
            translate: {0, thumb_y},
            input: [:cursor_button, :cursor_pos]
          )
        end,
        id: {:scrollbar_y_group, group_id},
        translate: {track_x, @scrollbar_padding}
      )
    else
      graph
    end
  end

  # Render horizontal scrollbar if needed
  defp maybe_render_scrollbar_x(
         graph,
         %ScrollState{} = scroll,
         width,
         height,
         color,
         opacity,
         group_id
       ) do
    if ScrollState.scrollable_x?(scroll) do
      # Account for vertical scrollbar if present
      track_width =
        if ScrollState.scrollable_y?(scroll) do
          width - @scrollbar_width - @scrollbar_padding * 3
        else
          width - @scrollbar_padding * 2
        end

      # Get thumb size ratio and scale to actual track
      {thumb_x_ratio, thumb_width_ratio} = ScrollState.scrollbar_thumb(scroll, :x)
      scale = track_width / scroll.viewport_width
      thumb_width = thumb_width_ratio * scale
      thumb_x = thumb_x_ratio * scale

      track_y = height - @scrollbar_width - @scrollbar_padding
      track_opacity = if opacity > 0, do: @scrollbar_track_opacity, else: 0
      {r, g, b} = color

      graph
      |> Primitives.group(
        fn grp ->
          grp
          # Track background
          |> Primitives.rrect(
            {track_width, @scrollbar_width, 4},
            id: {:scrollbar_x_track, group_id},
            fill: {r, g, b, track_opacity},
            input: [:cursor_button, :cursor_pos]
          )
          # Thumb
          |> Primitives.rrect(
            {thumb_width, @scrollbar_width, 4},
            id: {:scrollbar_x_thumb, group_id},
            fill: {r, g, b, opacity},
            translate: {thumb_x, 0},
            input: [:cursor_button, :cursor_pos]
          )
        end,
        id: {:scrollbar_x_group, group_id},
        translate: {@scrollbar_padding, track_y}
      )
    else
      graph
    end
  end

  # Update vertical scrollbar
  defp update_scrollbar_y(graph, old_scroll, new_scroll, frame, group_id, color) do
    if ScrollState.scrollable_y?(new_scroll) do
      {old_thumb_y, _} = ScrollState.scrollbar_thumb(old_scroll, :y)
      {new_thumb_y_ratio, _new_thumb_height} = ScrollState.scrollbar_thumb(new_scroll, :y)

      # Scale to actual track height
      {_width, height} = frame.size.box
      track_height = height - @scrollbar_padding * 2
      scale = track_height / new_scroll.viewport_height
      new_thumb_y = new_thumb_y_ratio * scale

      if old_thumb_y != new_thumb_y_ratio ||
           old_scroll.scrollbar_opacity != new_scroll.scrollbar_opacity do
        {r, g, b} = color

        graph
        |> try_modify({:scrollbar_y_thumb, group_id}, fn primitive ->
          primitive
          |> Scenic.Primitive.put_style(:translate, {0, new_thumb_y})
          |> Scenic.Primitive.put_style(:fill, {r, g, b, new_scroll.scrollbar_opacity})
        end)
        |> try_modify({:scrollbar_y_track, group_id}, fn primitive ->
          track_opacity =
            if new_scroll.scrollbar_opacity > 0, do: @scrollbar_track_opacity, else: 0

          Scenic.Primitive.put_style(primitive, :fill, {r, g, b, track_opacity})
        end)
      else
        graph
      end
    else
      graph
    end
  end

  # Update horizontal scrollbar
  defp update_scrollbar_x(graph, old_scroll, new_scroll, frame, group_id, color) do
    if ScrollState.scrollable_x?(new_scroll) do
      {old_thumb_x, _} = ScrollState.scrollbar_thumb(old_scroll, :x)
      {new_thumb_x_ratio, _new_thumb_width} = ScrollState.scrollbar_thumb(new_scroll, :x)

      # Scale to actual track width
      {width, _height} = frame.size.box

      track_width =
        if ScrollState.scrollable_y?(new_scroll) do
          width - @scrollbar_width - @scrollbar_padding * 3
        else
          width - @scrollbar_padding * 2
        end

      scale = track_width / new_scroll.viewport_width
      new_thumb_x = new_thumb_x_ratio * scale

      if old_thumb_x != new_thumb_x_ratio ||
           old_scroll.scrollbar_opacity != new_scroll.scrollbar_opacity do
        {r, g, b} = color

        graph
        |> try_modify({:scrollbar_x_thumb, group_id}, fn primitive ->
          primitive
          |> Scenic.Primitive.put_style(:translate, {new_thumb_x, 0})
          |> Scenic.Primitive.put_style(:fill, {r, g, b, new_scroll.scrollbar_opacity})
        end)
        |> try_modify({:scrollbar_x_track, group_id}, fn primitive ->
          track_opacity =
            if new_scroll.scrollbar_opacity > 0, do: @scrollbar_track_opacity, else: 0

          Scenic.Primitive.put_style(primitive, :fill, {r, g, b, track_opacity})
        end)
      else
        graph
      end
    else
      graph
    end
  end

  # Try to modify a primitive, returning graph unchanged if ID not found
  defp try_modify(graph, id, update_fn) do
    try do
      Graph.modify(graph, id, update_fn)
    rescue
      # ID not found or other error
      _ -> graph
    end
  end
end
