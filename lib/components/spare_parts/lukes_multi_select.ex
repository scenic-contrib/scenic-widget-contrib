defmodule ScenicWidgets.SpareParts.LukesMultiSelect do
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  alias Scenic.Scene
  alias Scenic.Primitive.Style.Theme
  import Scenic.Primitives
  alias Scenic.Assets.Static

  require Logger

  @default_direction :down
  @default_font :roboto_mono
  @default_font_size 20
  @border_width 2
  @checkbox_size 16

  @caret {{0, 0}, {12, 0}, {6, 6}}
  @text_id :_dropbox_text_
  @caret_id :_caret_
  @dropbox_id :_dropbox_
  @button_id :_dropbox_btn_
  @rotate_neutral :math.pi() / 2
  @rotate_down 0
  @rotate_up :math.pi()
  @drop_click_window_ms 400

  # --------------------------------------------------------
  @impl Scenic.Component
  def validate({items, _initial_selected_ids} = data) when is_list(items) do
    Enum.reduce(items, {:ok, data}, fn
      _, {:error, _} = error -> error
      {text, _}, acc when is_bitstring(text) -> acc
      item, _ -> err_bad_item(item, data)
    end)
  end

  def validate(data) do
    {:error,
     """
     Invalid MultiSelect specification
     Received: #{inspect(data)}
     MultiSelect data must be a list of text/id pairs and initial selected ids.
     """}
  end

  # --------------------------------------------------------
  @doc false
  @impl Scenic.Scene
  def init(scene, {items, initial_selected_ids}, opts) do
    id = opts[:id]
    theme = (opts[:theme] || Theme.preset(:dark)) |> Theme.normalize()

    {:ok, {Static.Font, fm}} = Static.meta(@default_font)
    ascent = FontMetrics.ascent(@default_font_size, fm)
    descent = FontMetrics.descent(@default_font_size, fm)

    # Calculate width and height
    fm_width =
      Enum.reduce(items, 0, fn {text, _}, w ->
        width = FontMetrics.width(text, @default_font_size, fm)
        max(w, width)
      end)

    width =
      case opts[:width] || opts[:w] do
        nil -> fm_width + ascent * 3
        :auto -> fm_width + ascent * 3
        width when is_number(width) and width > 0 -> width
      end

    height =
      case opts[:height] || opts[:h] do
        nil -> @default_font_size + ascent
        :auto -> @default_font_size + ascent
        height when is_number(height) and height > 0 -> height
      end

    # Calculate the drop box measures
    item_count = Enum.count(items)
    drop_height = item_count * height

    # Get the drop direction
    direction = opts[:direction] || @default_direction

    # Calculate where to put the drop box
    translate_menu =
      case direction do
        :down -> {0, height + 1}
        :up -> {0, height * -item_count - 1}
      end

    # Get the direction to rotate the caret
    rotate_caret =
      case direction do
        :down -> @rotate_down
        :up -> -@rotate_up
      end

    text_vpos = height / 2 + ascent / 2 + descent / 3
    dx = @border_width / 2
    dy = @border_width / 2

    # Build the graph
    graph =
      Graph.build(font: @default_font, font_size: @default_font_size, t: {dx, dy})
      |> rect(
        {width, height},
        fill: theme.background,
        stroke: {@border_width, theme.border},
        id: @button_id,
        input: :cursor_button
      )
      |> text("Select options",
        fill: theme.text,
        translate: {8, text_vpos},
        text_align: :left,
        id: @text_id
      )
      |> triangle(@caret,
        fill: theme.text,
        translate: {width - 18, height * 0.5},
        pin: {6, 0},
        rotate: @rotate_neutral,
        id: @caret_id
      )
      # Build the dropbox group
      |> group(
        fn g ->
          g = rect(g, {width, drop_height}, fill: theme.background, stroke: {2, theme.border})

          {g, _} =
            Enum.reduce(items, {g, 0}, fn {text, id}, {g, i} ->
              is_selected = id in initial_selected_ids
              checkbox_y = (height - @checkbox_size) / 2

              g =
                group(
                  g,
                  fn g ->
                    # Each item's background
                    rect(
                      g,
                      {width, height},
                      fill: theme.background,
                      id: {:item_background, id}
                    )
                    |> rect({@checkbox_size, @checkbox_size},
                      fill: if(is_selected, do: theme.active, else: theme.background),
                      stroke: {@border_width, theme.border},
                      id: {:checkbox, id},
                      input: :cursor_button,
                      translate: {8, checkbox_y}
                    )
                    |> text(text,
                      fill: theme.text,
                      translate: {@checkbox_size + 16, text_vpos},
                      id: {:label, id}
                    )
                  end,
                  translate: {0, height * i}
                )

              {g, i + 1}
            end)

          g
        end,
        translate: translate_menu,
        id: @dropbox_id,
        hidden: true
      )

    scene =
      scene
      |> assign(
        graph: graph,
        selected_ids: initial_selected_ids,
        theme: theme,
        id: id,
        down: false,
        hover_id: nil,
        items: items,
        rotate_caret: rotate_caret,
        drop_time: 0
      )
      |> push_graph(graph)

    {:ok, scene}
  end

  # Handle input when the dropdown is closed and button is pressed
  def handle_input(
        {:cursor_button, {:btn_left, 1, _, _}},
        @button_id,
        %Scene{assigns: %{down: false, graph: graph, rotate_caret: rotate_caret}} = scene
      ) do
    # Capture input
    :ok = capture_input(scene, [:cursor_button, :cursor_pos])

    # Send focus to parent
    cast_parent(scene, {:focus, scene.id})

    # Show the dropdown and rotate the caret
    graph =
      graph
      |> Graph.modify(@caret_id, &update_opts(&1, rotate: rotate_caret))
      |> Graph.modify(@dropbox_id, &update_opts(&1, hidden: false))

    scene =
      scene
      |> assign(down: true, graph: graph, drop_time: :os.system_time(:milli_seconds))
      |> push_graph(graph)

    {:noreply, scene}
  end

  # Handle input when the dropdown is open and button is pressed (close it)
  def handle_input(
        {:cursor_button, {:btn_left, 1, _, _}},
        @button_id,
        %Scene{
          assigns: %{
            down: true,
            theme: theme,
            graph: graph
          }
        } = scene
      ) do
    # Hide the dropdown and rotate the caret back
    graph =
      graph
      |> Graph.modify(@caret_id, &update_opts(&1, rotate: @rotate_neutral))
      |> Graph.modify(@dropbox_id, &update_opts(&1, hidden: true))

    :ok = release_input(scene)

    scene =
      scene
      |> assign(down: false, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  # Handle checkbox click events
  def handle_input({:cursor_button, {:btn_left, 1, _, _}}, {:checkbox, item_id}, scene) do
    %{selected_ids: selected_ids, graph: graph, theme: theme} = scene.assigns

    new_selected_ids =
      if item_id in selected_ids do
        List.delete(selected_ids, item_id)
      else
        [item_id | selected_ids]
      end

    # Update the checkbox fill
    graph =
      graph
      |> Graph.modify(
        {:checkbox, item_id},
        &update_opts(&1,
          fill: if(item_id in new_selected_ids, do: theme.active, else: theme.background)
        )
      )

    send_parent_event(scene, {:value_changed, scene.assigns.id, new_selected_ids})

    scene =
      scene
      |> assign(selected_ids: new_selected_ids, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  # Handle click outside the dropdown to close it
  def handle_input(
        {:cursor_button, {:btn_left, _, _, _}},
        _,
        %Scene{
          assigns: %{
            down: true,
            graph: graph
          }
        } = scene
      ) do
    # Hide the dropdown and rotate the caret back
    graph =
      graph
      |> Graph.modify(@caret_id, &update_opts(&1, rotate: @rotate_neutral))
      |> Graph.modify(@dropbox_id, &update_opts(&1, hidden: true))

    :ok = release_input(scene)

    scene =
      scene
      |> assign(down: false, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_input(_, _, scene), do: {:noreply, scene}

  def handle_cast({:set_scroll, _coords}, scene) do
    {:noreply, scene}
  end
  # --------------------------------------------------------
  defp err_bad_item(item, data) do
    {:error,
     """
     Invalid MultiSelect specification
     Received: #{inspect(data)}
     Invalid Item: #{inspect(item)}
     """}
  end
end
