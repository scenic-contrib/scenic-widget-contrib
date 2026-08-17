defmodule ScenicWidgets.SearchBar do
  @moduledoc """
  A reusable search bar component for Scenic applications.

  Provides a horizontal search bar with:
  - Text input field for search query
  - Previous/Next navigation buttons
  - Match count display (e.g., "3/10")
  - Close button

  ## Usage

      ScenicWidgets.SearchBar.add_to_graph(graph,
        %{
          id: :search_bar,
          frame: %Widgex.Frame{pin: {0, 0}, size: {400, 36}},
          query: "initial search"  # optional
        },
        id: :search_bar
      )

  ## Events Emitted

  The component sends events to its parent via `cast_parent/2`:

  - `{:search_query_changed, id, query}` - when user types in search field
  - `{:search_next, id}` - when clicking next button or pressing Enter
  - `{:search_prev, id}` - when clicking previous button or pressing Shift+Enter
  - `{:search_close, id}` - when clicking close button or pressing Escape
  - `{:replace_mode_requested, id}` - when pressing Ctrl+H while the bar has focus

  ## Updating Match Count

  To update the match count display, send a message to the component:

      Scenic.Scene.put_child(scene, :search_bar, {:set_matches, current, total})

  ## Keyboard Shortcuts

  - `Enter` - Navigate to next match
  - `Shift+Enter` - Navigate to previous match
  - `Escape` - Close the search bar
  - `Backspace` - Delete character before cursor
  - `Delete` - Delete character at cursor
  - `Left/Right` - Move cursor
  - `Home` - Move cursor to start
  - `End` - Move cursor to end
  """

  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions

  require Logger

  alias ScenicWidgets.SearchBar.State
  alias ScenicWidgets.SearchBar.Renderer
  alias Widgex.Frame

  # Key constants
  @key_pressed 1

  # Validate component data
  def validate(%{id: id, frame: %Frame{}} = data) when is_atom(id) do
    {:ok, data}
  end

  def validate(%{frame: %Frame{}} = data) do
    {:ok, Map.put(data, :id, :search_bar)}
  end

  def validate(data) do
    {:error, "SearchBar requires :id (atom) and :frame (Widgex.Frame), got: #{inspect(data)}"}
  end

  @doc """
  Add the SearchBar to a graph.
  """
  def add_to_graph(graph, data, opts \\ []) do
    # Use the default implementation provided by Scenic.Component
    super(graph, data, opts)
  end

  # Initialize the component
  def init(scene, data, opts) do
    id = opts[:id] || data[:id] || :search_bar

    state =
      State.new(%{
        id: id,
        frame: data.frame,
        query: data[:query] || "",
        font: data[:font],
        theme: data[:theme],
        replace_mode: data[:replace_mode] || false
      })

    graph = Renderer.render(state)

    init_scene =
      scene
      |> assign(id: id)
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # Request keyboard and mouse input
    request_input(init_scene, [:key, :codepoint, :cursor_button, :cursor_pos])

    # Register semantic elements if replace mode is active
    if state.replace_mode do
      register_replace_semantic_elements(init_scene, state, data.frame)
    end

    {:ok, init_scene}
  end

  # Handle external updates (e.g., set match count)
  def handle_put({:set_matches, current, total}, scene) do
    state = State.set_matches(scene.assigns.state, current, total)
    graph = Renderer.update_match_count(scene.assigns.graph, state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  def handle_put({:set_query, query}, scene) do
    state = State.set_query(scene.assigns.state, query)
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  def handle_put({:update_frame, frame}, scene) do
    state = %{scene.assigns.state | frame: frame}
    graph = Renderer.render(state)
    {:noreply, scene |> assign(state: state, graph: graph) |> push_graph(graph)}
  end

  def handle_put(:focus, scene) do
    state = %{scene.assigns.state | focused: true}
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  def handle_put(:clear, scene) do
    state = State.clear(scene.assigns.state)
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  def handle_put(:enable_replace_mode, scene) do
    state = State.enable_replace_mode(scene.assigns.state)
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    register_replace_semantic_elements(new_scene, state, state.frame)

    {:noreply, new_scene}
  end

  # Handle text input (codepoints)
  def handle_input({:codepoint, {char, _}}, _context, scene) when char != "" do
    state =
      if scene.assigns.state.replace_mode do
        State.insert_char_to_focused(scene.assigns.state, char)
      else
        State.insert_char(scene.assigns.state, char)
      end

    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # Only emit query changed when focused on search field
    if state.focused_field == :search do
      cast_parent(new_scene, {:search_query_changed, state.id, state.query})
    end

    {:noreply, new_scene}
  end

  # Handle Tab - switch focus between search and replace fields (when in replace mode)
  def handle_input({:key, {:key_tab, @key_pressed, _}}, _context, scene) do
    state = scene.assigns.state

    if state.replace_mode do
      new_state = State.toggle_focus(state)
      graph = Renderer.render(new_state)

      new_scene =
        scene
        |> assign(state: new_state)
        |> assign(graph: graph)
        |> push_graph(graph)

      {:noreply, new_scene}
    else
      {:noreply, scene}
    end
  end

  # Handle Enter in replace mode (focused on replace field) - trigger replace
  def handle_input({:key, {:key_enter, @key_pressed, []}}, _context, scene) do
    state = scene.assigns.state

    if state.replace_mode and state.focused_field == :replace do
      cast_parent(scene, {:replace_requested, state.id, state.replace_query})
      {:noreply, scene}
    else
      cast_parent(scene, {:search_next, state.id})
      {:noreply, scene}
    end
  end

  # Handle Shift+Enter - previous match
  def handle_input({:key, {:key_enter, @key_pressed, [:shift]}}, _context, scene) do
    cast_parent(scene, {:search_prev, scene.assigns.state.id})
    {:noreply, scene}
  end

  # Ctrl+H while the bar owns the keyboard: the editor pane is blurred, so
  # its own Ctrl+H binding cannot fire. Ask the parent to grow the bar into
  # find-and-replace (a no-op if it already is) and move focus to the
  # replacement field, which is where the user is heading.
  def handle_input({:key, {:key_h, @key_pressed, [:ctrl]}}, _context, scene) do
    cast_parent(scene, {:replace_mode_requested, scene.assigns.state.id})
    # Focus first, mode second: the parent's :enable_replace_mode keeps the
    # focused field, so the replace row appears already focused.
    {:noreply, focus_field(scene, :replace)}
  end

  # Ctrl+F while already open: back to the search field.
  def handle_input({:key, {:key_f, @key_pressed, [:ctrl]}}, _context, scene) do
    {:noreply, focus_field(scene, :search)}
  end

  # Handle Escape - close
  def handle_input({:key, {:key_esc, @key_pressed, _}}, _context, scene) do
    cast_parent(scene, {:search_close, scene.assigns.state.id})
    {:noreply, scene}
  end

  # Handle Backspace
  def handle_input({:key, {:key_backspace, @key_pressed, _}}, _context, scene) do
    state =
      if scene.assigns.state.replace_mode do
        State.delete_before_cursor_focused(scene.assigns.state)
      else
        State.delete_before_cursor(scene.assigns.state)
      end

    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    if state.focused_field == :search do
      cast_parent(new_scene, {:search_query_changed, state.id, state.query})
    end

    {:noreply, new_scene}
  end

  # Handle Delete
  def handle_input({:key, {:key_delete, @key_pressed, _}}, _context, scene) do
    state = State.delete_at_cursor(scene.assigns.state)
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    cast_parent(new_scene, {:search_query_changed, state.id, state.query})
    {:noreply, new_scene}
  end

  # Handle Left arrow
  def handle_input({:key, {:key_left, @key_pressed, _}}, _context, scene) do
    state = State.cursor_left(scene.assigns.state)
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  # Handle Right arrow
  def handle_input({:key, {:key_right, @key_pressed, _}}, _context, scene) do
    state = State.cursor_right(scene.assigns.state)
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  # Handle Home key
  def handle_input({:key, {:key_home, @key_pressed, _}}, _context, scene) do
    state = State.cursor_home(scene.assigns.state)
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  # Handle End key
  def handle_input({:key, {:key_end, @key_pressed, _}}, _context, scene) do
    state = State.cursor_end(scene.assigns.state)
    graph = Renderer.render(state)

    new_scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  # Handle mouse clicks on buttons
  def handle_input({:cursor_button, {:btn_left, 1, _, coords}}, _context, scene) do
    handle_click(scene, coords)
  end

  # Ignore other inputs
  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  defp focus_field(scene, field) do
    state = %{scene.assigns.state | focused_field: field}
    graph = Renderer.render(state)

    scene
    |> assign(state: state)
    |> assign(graph: graph)
    |> push_graph(graph)
  end

  # Handle clicks on different areas. Requested cursor_button input arrives
  # for EVERY click, in this component's local space; anything outside the
  # bar is somebody else's click (the parent decides whether it closes us),
  # not a press on whichever of our buttons the coordinates happen to fall
  # near — a click far to the left used to read as the close button.
  defp handle_click(scene, {click_x, click_y}) do
    state = scene.assigns.state
    %{frame: frame} = state
    # Handle both tuple and Dimensions struct for size
    width =
      case frame.size do
        %{width: w} -> w
        {w, _h} -> w
      end

    bar_height = 36
    height = if state.replace_mode, do: bar_height * 2, else: bar_height

    cond do
      click_x < 0 or click_x > width or click_y < 0 or click_y > height ->
        {:noreply, scene}

      # Click is in the replace row (y >= bar_height) when in replace mode
      state.replace_mode and click_y >= bar_height ->
        handle_replace_row_click(scene, click_x, width)

      true ->
        handle_search_row_click(scene, click_x, width)
    end
  end

  defp handle_search_row_click(scene, click_x, width) do
    button_width = Renderer.button_width()
    match_count_width = Renderer.match_count_width()
    nav_start_x = width - button_width * 2 - match_count_width

    cond do
      # Close button area (first 32px)
      click_x < button_width ->
        cast_parent(scene, {:search_close, scene.assigns.state.id})
        {:noreply, scene}

      # Previous button area
      click_x >= nav_start_x and click_x < nav_start_x + button_width ->
        cast_parent(scene, {:search_prev, scene.assigns.state.id})
        {:noreply, scene}

      # Next button area
      click_x >= nav_start_x + button_width + match_count_width ->
        cast_parent(scene, {:search_next, scene.assigns.state.id})
        {:noreply, scene}

      # Input field area - focus search
      true ->
        new_state = %{scene.assigns.state | focused_field: :search}
        graph = Renderer.render(new_state)
        new_scene = scene |> assign(state: new_state) |> assign(graph: graph) |> push_graph(graph)
        {:noreply, new_scene}
    end
  end

  defp handle_replace_row_click(scene, click_x, width) do
    state = scene.assigns.state
    replace_btn_width = 70
    all_btn_width = 40
    # button_width + input_padding
    input_x = 32 + 8
    nav_start_x = width - replace_btn_width - all_btn_width - 8

    cond do
      # Replace button
      click_x >= nav_start_x and click_x < nav_start_x + replace_btn_width ->
        cast_parent(scene, {:replace_requested, state.id, state.replace_query})
        {:noreply, scene}

      # All button
      click_x >= nav_start_x + replace_btn_width ->
        cast_parent(scene, {:replace_all_requested, state.id, state.replace_query})
        {:noreply, scene}

      # Replace input field area - focus replace
      click_x >= input_x ->
        new_state = %{state | focused_field: :replace}
        graph = Renderer.render(new_state)
        new_scene = scene |> assign(state: new_state) |> assign(graph: graph) |> push_graph(graph)
        {:noreply, new_scene}

      true ->
        {:noreply, scene}
    end
  end

  # Handle button click events from child components
  def handle_event({:click, :close_button}, _from, scene) do
    cast_parent(scene, {:search_close, scene.assigns.state.id})
    {:noreply, scene}
  end

  def handle_event({:click, :prev_button}, _from, scene) do
    cast_parent(scene, {:search_prev, scene.assigns.state.id})
    {:noreply, scene}
  end

  def handle_event({:click, :next_button}, _from, scene) do
    cast_parent(scene, {:search_next, scene.assigns.state.id})
    {:noreply, scene}
  end

  def handle_event(_event, _from, scene) do
    {:noreply, scene}
  end

  # ===========================================================================
  # Semantic Registration
  # ===========================================================================

  defp register_replace_semantic_elements(scene, %State{}, frame) do
    viewport = scene.viewport

    unless viewport.semantic_table && viewport.semantic_enabled do
      :ok
    else
      scene_name = scene.assigns[:id] || :search_bar

      # Get frame dimensions
      width =
        case frame.size do
          %{width: w} -> w
          {w, _h} -> w
        end

      {pin_x, pin_y} =
        case frame.pin do
          %{point: {x, y}} -> {x, y}
          {x, y} -> {x, y}
          _ -> {0, 0}
        end

      bar_height = 36
      replace_btn_width = 70
      all_btn_width = 40
      nav_start_x = width - replace_btn_width - all_btn_width - 8

      # Register "Replace All" button
      all_btn_x = pin_x + nav_start_x + replace_btn_width + 2
      all_btn_y = pin_y + bar_height + 2

      register_semantic_element(
        viewport,
        scene_name,
        :replace_all_btn_bg,
        "All",
        all_btn_x,
        all_btn_y,
        all_btn_width,
        bar_height - 4
      )

      # Register "Replace" button
      replace_btn_x = pin_x + nav_start_x
      replace_btn_y = pin_y + bar_height + 2

      register_semantic_element(
        viewport,
        scene_name,
        :replace_btn_bg,
        "Replace",
        replace_btn_x,
        replace_btn_y,
        replace_btn_width,
        bar_height - 4
      )

      :ok
    end
  end

  defp register_semantic_element(viewport, scene_name, id, label, x, y, w, h) do
    entry = %Scenic.Semantic.Compiler.Entry{
      id: id,
      type: :button,
      module: nil,
      parent_id: nil,
      children: [],
      local_bounds: %{left: x, top: y, width: w, height: h},
      screen_bounds: %{left: x, top: y, width: w, height: h},
      clickable: true,
      focusable: false,
      label: label,
      role: :button,
      value: nil,
      hidden: false,
      z_index: 5
    }

    :ets.insert(viewport.semantic_table, {{scene_name, id}, entry})
    :ets.insert(viewport.semantic_index, {id, {scene_name, id}})
  end
end
