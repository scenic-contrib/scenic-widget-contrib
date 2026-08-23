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

  # It has children now: its two fields are TextFields. Declared false, Scenic
  # takes the graph's component primitives at their word and never starts
  # them — the fields appear and every keystroke goes nowhere.
  use Scenic.Component, has_children: true
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

  # Seeded from outside — the word under the cursor, or the last thing
  # searched for. The field shows it SELECTED, so the next character typed
  # replaces the guess rather than being appended to it.
  def handle_put({:set_query, query}, scene) do
    state = State.set_query(scene.assigns.state, query)
    Scenic.Scene.put_child(scene, Renderer.field_id(:search), {:seed_text, query})
    {:noreply, redraw(scene, state)}
  end

  def handle_put({:update_frame, frame}, scene) do
    {:noreply, redraw(scene, %{scene.assigns.state | frame: frame})}
  end

  # The parent gives the bar the keyboard; the bar hands it to whichever of
  # its fields is current. Both halves are needed: the fields gate on their
  # own flags, so a bar that is blurred while a field still thinks it is
  # focused would go on eating keystrokes meant for the editor.
  def handle_put(:focus, scene) do
    state = %{scene.assigns.state | focused: true}
    {:noreply, focus_fields(redraw(scene, state), state)}
  end

  def handle_put(:blur, scene) do
    state = %{scene.assigns.state | focused: false}
    {:noreply, focus_fields(redraw(scene, state), state)}
  end

  def handle_put(:clear, scene) do
    state = State.clear(scene.assigns.state)
    Scenic.Scene.put_child(scene, Renderer.field_id(:search), {:seed_text, ""})
    {:noreply, redraw(scene, state)}
  end

  # Back to plain find. The replacement field goes with the row, so the graph
  # is rebuilt from nothing — which is exactly the case redraw/2 already
  # treats as "which fields exist has changed".
  def handle_put(:disable_replace_mode, scene) do
    state = %{scene.assigns.state | replace_mode: false, focused_field: :search}
    {:noreply, focus_fields(redraw(scene, state), state)}
  end

  def handle_put(:enable_replace_mode, scene) do
    state = State.enable_replace_mode(scene.assigns.state)
    new_scene = focus_fields(redraw(scene, state), state)
    register_replace_semantic_elements(new_scene, state, state.frame)
    {:noreply, new_scene}
  end

  # The fields are TextFields now, and they own the keyboard: typing, the
  # caret, backspace, Home and End, selection, the clipboard — all of it
  # arrives back here as events rather than being reimplemented one key at a
  # time. What is left below is only the chords that belong to the BAR rather
  # than to a field.

  # Escape closes the bar. Read here rather than taken from the field's
  # escape_pressed event, because closing is the BAR's affair: a field that
  # happens not to hold focus — after a click elsewhere, say — would
  # otherwise leave Escape doing nothing at all, and the bar unclosable
  # without the mouse.
  # Scenic delivers every keystroke here. On a Mac the command key arrives as
  # :meta, so it is rewritten to :ctrl once, at the door — the clauses below
  # then say what they mean on both platforms.
  def handle_input({:key, {key, action, mods}}, context, scene),
    do:
      route_input(
        {:key, {key, action, ScenicWidgets.PrimaryModifier.normalize(mods)}},
        context,
        scene
      )

  def handle_input(input, context, scene), do: route_input(input, context, scene)

  defp route_input({:key, {:key_esc, @key_pressed, _}}, _context, scene) do
    cast_parent(scene, {:search_close, scene.assigns.state.id})
    {:noreply, scene}
  end

  # Shift+Enter — the previous match. TextField reports a plain Enter as an
  # event; the modifier does not survive that, so this one is read directly.
  defp route_input({:key, {:key_enter, @key_pressed, [:shift]}}, _context, scene) do
    cast_parent(scene, {:search_prev, scene.assigns.state.id})
    {:noreply, scene}
  end

  # Ctrl+H while the bar owns the keyboard: the editor pane is blurred, so
  # its own Ctrl+H binding cannot fire. Ask the parent to grow the bar into
  # find-and-replace (a no-op if it already is) and move focus to the
  # replacement field, which is where the user is heading.
  defp route_input({:key, {:key_h, @key_pressed, [:ctrl]}}, _context, scene) do
    cast_parent(scene, {:replace_mode_requested, scene.assigns.state.id})
    {:noreply, focus_field(scene, :replace)}
  end

  # Undo and redo belong to the DOCUMENT, even while the bar holds the
  # keyboard. Replacing is the destructive thing this bar does, and the moment
  # you want to take it back is the moment right after — with the bar still
  # open and the query still in it. Nothing here handled the chord at all, so
  # it simply vanished.
  defp route_input({:key, {:key_z, @key_pressed, mods}}, _context, scene)
       when is_list(mods) do
    cond do
      :ctrl not in mods ->
        :ok

      :shift in mods ->
        cast_parent(scene, {:redo_requested, scene.assigns.state.id})

      true ->
        cast_parent(scene, {:undo_requested, scene.assigns.state.id})
    end

    {:noreply, scene}
  end

  defp route_input({:key, {:key_y, @key_pressed, [:ctrl]}}, _context, scene) do
    cast_parent(scene, {:redo_requested, scene.assigns.state.id})
    {:noreply, scene}
  end

  # Ctrl+F while already open: back to the search field.
  defp route_input({:key, {:key_f, @key_pressed, [:ctrl]}}, _context, scene) do
    {:noreply, focus_field(scene, :search)}
  end

  defp route_input({:cursor_button, {:btn_left, 1, _, coords}}, _context, scene) do
    handle_click(scene, coords)
  end

  defp route_input({:cursor_pos, coords}, _context, scene) do
    handle_hover(scene, coords)
  end

  # Ignore other inputs
  defp route_input(_input, _context, scene) do
    {:noreply, scene}
  end

  # ── Events from the fields ────────────────────────────────────────────────

  @impl Scenic.Scene
  def handle_event({:text_changed, id, text}, _from, scene) do
    state = put_field_text(scene.assigns.state, field_of(id), text)
    scene = assign(scene, state: state)

    # Only the query steers the search. The replacement is carried on the
    # action instead — typing it must not re-run anything.
    if field_of(id) == :search do
      cast_parent(scene, {:search_query_changed, state.id, state.query})
    end

    {:noreply, scene}
  end

  # Enter means "the next match", except in the replacement field where it
  # means "replace this one" — the only destructive thing the bar does from
  # the keyboard.
  def handle_event({:enter_pressed, id, _text}, _from, scene) do
    state = scene.assigns.state

    if field_of(id) == :replace do
      cast_parent(scene, {:replace_requested, state.id, state.replace_query})
    else
      cast_parent(scene, {:search_next, state.id})
    end

    {:noreply, scene}
  end

  # Escape is handled as a key above, so the field's own report of it is
  # already accounted for — acting on both would ask the parent to close
  # twice.
  def handle_event({:escape_pressed, _id}, _from, scene), do: {:noreply, scene}

  def handle_event({:tab_pressed, _id, _shift?}, _from, scene) do
    state = scene.assigns.state

    if state.replace_mode do
      {:noreply, focus_field(scene, other_field(state.focused_field))}
    else
      {:noreply, scene}
    end
  end

  # A click in a field gives it the keyboard; the bar's job is to take it off
  # the other one, and to remember which is current for Tab.
  def handle_event({:focus_taken, id}, _from, scene)
      when id in [:search_bar_query_field, :search_bar_replace_field] do
    # The field can focus itself after a direct click, but the host owns the
    # competing editor pane. Tell it synchronously through the normal parent
    # event path so it can revoke that pane before the next codepoint arrives.
    cast_parent(scene, {:search_bar_focus_taken, scene.assigns.state.id})
    {:noreply, focus_field(scene, field_of(id))}
  end

  def handle_event(_event, _from, scene), do: {:noreply, scene}

  defp field_of(:search_bar_query_field), do: :search
  defp field_of(:search_bar_replace_field), do: :replace

  defp other_field(:search), do: :replace
  defp other_field(:replace), do: :search

  defp put_field_text(state, :search, text), do: %{state | query: text}
  defp put_field_text(state, :replace, text), do: %{state | replace_query: text}

  # Exactly one field holds the keyboard, and only while the bar itself has
  # it. Told rather than derived, so a field cannot go on eating keystrokes
  # after the parent has taken the keyboard off the bar.
  defp focus_fields(scene, %State{} = state) do
    for field <- [:search, :replace] do
      focus? = state.focused and state.focused_field == field

      Scenic.Scene.put_child(
        scene,
        Renderer.field_id(field),
        if(focus?, do: :focus, else: :blur)
      )
    end

    scene
  end

  # A resize or a theme change moves and recolours the fields. They are told,
  # rather than redrawn: recreating a component throws away its cursor and its
  # selection.
  defp reframe_fields(scene, %State{} = old_state, %State{} = new_state) do
    if Renderer.geometry_changed?(old_state, new_state) do
      for field <- [:search, :replace],
          settings = Renderer.field_settings(new_state, field),
          settings != nil do
        Scenic.Scene.put_child(scene, Renderer.field_id(field), {:update_settings, settings})
      end
    end

    :ok
  end

  defp focus_field(scene, field) do
    state = %{scene.assigns.state | focused_field: field}
    focus_fields(redraw(scene, state), state)
  end

  # Handle clicks on different areas. Requested cursor_button input arrives
  # for EVERY click, in this component's local space; anything outside the
  # bar is somebody else's click (the parent decides whether it closes us),
  # not a press on whichever of our buttons the coordinates happen to fall
  # near — a click far to the left used to read as the close button.
  # Every click is matched against the SAME rectangles the renderer drew, so a
  # button cannot respond in one place and appear in another.
  defp handle_click(scene, coords) do
    state = scene.assigns.state

    case State.widget_at(state, coords) do
      # A click that missed every one of the bar's own controls is not the
      # bar's business — including a click in the document, which leaves the
      # bar exactly where it is.
      nil ->
        {:noreply, scene}

      %{id: :close} ->
        cast_parent(scene, {:search_close, state.id})
        {:noreply, scene}

      %{id: :prev} ->
        cast_parent(scene, {:search_prev, state.id})
        {:noreply, scene}

      %{id: :next} ->
        cast_parent(scene, {:search_next, state.id})
        {:noreply, scene}

      # TOGGLED, not requested. The caret is a disclosure control: it has to
      # close the row it opened. Asking for replace mode is what Ctrl+H does,
      # and that is a different message because it only ever opens.
      %{id: :toggle_replace} ->
        cast_parent(scene, {:replace_mode_toggled, state.id})
        {:noreply, scene}

      %{id: {:toggle, option}} ->
        new_state = State.toggle_option(state, option)

        # The search has to run again: the same query means something
        # different now.
        cast_parent(
          scene,
          {:search_options_changed, state.id, State.search_opts(new_state)}
        )

        {:noreply, redraw(scene, new_state)}

      %{id: :replace_one} ->
        cast_parent(scene, {:replace_requested, state.id, state.replace_query})
        {:noreply, scene}

      %{id: :replace_all} ->
        cast_parent(scene, {:replace_all_requested, state.id, state.replace_query})
        {:noreply, scene}

      %{id: :search_field} ->
        cast_parent(scene, {:search_bar_focus_taken, state.id})
        {:noreply, focus_field(scene, :search)}

      %{id: :replace_field} ->
        cast_parent(scene, {:search_bar_focus_taken, state.id})
        {:noreply, focus_field(scene, :replace)}

      %{id: :count} ->
        {:noreply, scene}
    end
  end

  # Hover, for the tooltips. Only the widgets that HAVE something to say get
  # tracked, so moving across the field does not blink a label on and off.
  defp handle_hover(scene, coords) do
    state = scene.assigns.state

    hovered =
      case State.widget_at(state, coords) do
        %{id: id, tooltip: tooltip} when is_binary(tooltip) -> id
        _ -> nil
      end

    if hovered == state.hovered do
      {:noreply, scene}
    else
      {:noreply, redraw(scene, %{state | hovered: hovered})}
    end
  end

  # Only what changed. The bar holds child components now, and a graph rebuilt
  # from scratch would take them with it on every keystroke — except when the
  # replace row appears or disappears, which changes which fields EXIST and so
  # is the one case that has to build from nothing.
  defp redraw(scene, state) do
    old_state = scene.assigns.state

    graph =
      if Renderer.fields_changed?(old_state, state) do
        Renderer.render(state)
      else
        reframe_fields(scene, old_state, state)
        Renderer.update_render(scene.assigns.graph, old_state, state)
      end

    scene |> assign(state: state, graph: graph) |> push_graph(graph)
  end

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
