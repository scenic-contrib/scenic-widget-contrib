defmodule ScenicWidgets.TextField do
  @moduledoc """
  A multi-line text field component with support for both direct and external input modes.

  ## Features
  - Multi-line and single-line modes
  - Optional line numbers
  - Blinking cursor
  - Configurable fonts and colors
  - Transparent background support
  - Undo/redo support
  - Text selection and clipboard operations

  ## Input Modes - IMPORTANT!

  TextField supports three input modes that fundamentally change how it receives input.
  **Choosing the wrong mode will cause input routing problems!**

  ### `:direct` (default)

  TextField calls `request_input/2` and handles all keyboard input directly.
  The component receives `:key` and `:codepoint` events from Scenic.

  **Use when:** TextField is the primary/only text input in your scene.
  **Examples:** Simple forms, standalone text editors, Widget Workbench demos.

  ```elixir
  %{frame: frame, input_mode: :direct}  # or just omit, it's the default
  ```

  **⚠️ WARNING:** In `:direct` mode, TextField will intercept ALL keyboard input,
  including keyboard shortcuts! If your app has shortcuts like `space+k` that should
  be handled at the root scene level, those shortcuts will NOT work while TextField
  has focus because TextField grabs the keystrokes first.

  ### `:external`

  TextField does NOT request or handle keyboard input. It only renders text.
  The parent application is responsible for:
  1. Receiving keyboard input at a higher level (e.g., RootScene)
  2. Processing that input through its own state management (e.g., Fluxus/Redux)
  3. Updating the underlying buffer
  4. TextField re-renders when it receives buffer updates via PubSub

  **Use when:** Your app has its own input routing/state management system.
  **Examples:** Flamelex Kommander, Vim-mode editors, apps with global keyboard shortcuts.

  ```elixir
  %{frame: frame, input_mode: :external}
  ```

  **Flow in external mode:**
  ```
  Keyboard → RootScene → Fluxus/Redux → store → PubSub → TextField (render only)
  ```

  ### `:store_backed`

  TextField is a pure view over an external *store*: it captures raw input,
  translates it to semantic actions, dispatches them, and re-renders from the
  store's published snapshots. It holds no document state of its own (no local
  undo stacks) — render is a function of the snapshot.

  **Use when:** Document state lives outside the widget — an editor buffer
  process, a form store, anything that can publish snapshots.

  ```elixir
  %{frame: frame, input_mode: :store_backed,
    source: :my_source,             # Scenic.PubSub source publishing snapshots
    dispatch: pid_or_via_tuple}     # GenServer.cast target for actions
  ```

  #### The store contract

  This is the entire coupling between the widget (frontend) and the store
  (backend). Raw input never crosses this line — only semantic actions out,
  and snapshots in.

  **Snapshots** — whatever `source` publishes (and `Scenic.PubSub.get/1`
  returns) must be a map/struct with:

  - `data` — list of line strings
  - `cursor` — `%{line: pos_integer, col: pos_integer}`
  - `selection` — `%{start: %{line:, col:}, end: %{line:, col:}}`,
    `%{start: {l, c}, end: {l, c}}`, or `nil`
  - optional: `search_query`, `search_matches`, `search_current_index`

  **Actions** — the widget casts `{:action, [action]}` to `dispatch`, where
  action is one of the editing vocabulary, e.g.:

  - `{:insert, text, :at_cursor}` / `{:delete, :selection}` /
    `{:delete, :before_cursor}` / `{:delete, :after_cursor}`
  - `{:set_cursor, {line, col}}` / `{:move_cursor, direction}`
  - `{:select, ...}` / `:select_all` / `:clear_selection`
  - `:undo` / `:redo`
  - `{:search, query}` / `:find_next` / `:find_prev` / `:clear_search`
  - `{:replace, text}` / `{:replace_all, text}`

  Any store that speaks this contract can back a TextField; the widget knows
  nothing about how the store is implemented. The reference implementation is
  quillex's per-buffer store process.

  ## Line Modes

  - `:multi_line` (default) - Enter key inserts newline
  - `:single_line` - Enter key emits `{:enter_pressed, id, text}` event (for command bars)

  ## Basic Usage

      # Simple text editor (direct mode)
      graph
      |> TextField.add_to_graph(
        %{
          frame: Widgex.Frame.new(pin: {100, 100}, size: {400, 300}),
          initial_text: "Hello World!",
          input_mode: :direct
        },
        id: :my_editor
      )

      # Command bar in an app with global shortcuts (external mode)
      graph
      |> TextField.add_to_graph(
        %{
          frame: frame,
          mode: :single_line,
          input_mode: :external  # App routes input through its own system
        },
        id: :command_bar
      )

  ## Events (direct/store_backed modes only)

  - `{:text_changed, id, full_text}` - Text content changed
  - `{:focus_gained, id}` - TextField gained focus
  - `{:focus_lost, id}` - TextField lost focus
  - `{:enter_pressed, id, text}` - Enter pressed (single-line mode only)
  - `{:escape_pressed, id}` - Escape pressed
  - `{:save_requested, id, text}` - Ctrl+S pressed
  """

  use Scenic.Component, has_children: false
  require Logger

  alias ScenicWidgets.TextField.{State, Renderer, Reducer}
  alias Scenic.Graph

  # ===== VALIDATION =====

  @doc """
  Validate TextField initialization data.

  Accepts:
  - Widgex.Frame directly (Widget Workbench passes this)
  - Map with :frame key containing Widgex.Frame
  """
  def validate(%Widgex.Frame{} = frame) do
    # Widget Workbench passes frame directly - wrap it in a map
    {:ok, %{frame: frame}}
  end

  def validate(%{frame: %Widgex.Frame{}} = data) do
    {:ok, data}
  end

  def validate(data) do
    {:error, "TextField requires Widgex.Frame or map with :frame. Got: #{inspect(data)}"}
  end

  # ===== LIFECYCLE =====

  @doc """
  Initialize the TextField component.
  """
  def init(scene, data, _opts) do
    # Create initial state
    state = State.new(data)

    # For store_backed mode, hydrate from the store's retained Scenic.PubSub
    # snapshot (instant ETS read — no blocking GenServer call) and subscribe
    # for pushes. Subscribing also delivers the current retained value, so a
    # publish racing this init cannot be missed.
    state =
      if state.input_mode == :store_backed and state.source do
        state =
          case Scenic.PubSub.get(state.source) do
            nil ->
              state

            buf_state ->
              cursor =
                case buf_state.cursor do
                  %{line: l, col: c} -> {l, c}
                  _ -> {1, 1}
                end

              # Convert selection from buffer format %{start: ..., end: ...} to TextField format {start, end}
              selection =
                case buf_state.selection do
                  %{start: start_pos, end: end_pos} -> {start_pos, end_pos}
                  nil -> nil
                  # Pass through if already in tuple format
                  other -> other
                end

              %{
                state
                | lines: buf_state.data,
                  cursor: cursor,
                  selection: selection,
                  # In store_backed mode, we don't need local undo stacks
                  undo_stack: [],
                  redo_stack: []
              }
          end

        Scenic.PubSub.subscribe(state.source)
        state
      else
        state
      end

    # Build the expensive folded/wrapped projection once. Wheel events reuse
    # it; document or layout changes invalidate it through its cache key.
    state = Renderer.prepare_display_cache(state)

    # Render initial graph
    graph = Renderer.initial_render(Graph.build(), state)

    # Start cursor blink timer (only if editable)
    {:ok, timer} =
      if state.editable do
        :timer.send_interval(state.cursor_blink_rate, :blink)
      else
        {:ok, nil}
      end

    # Update state with timer reference
    state = %{state | cursor_timer: timer}

    # An optional second store: token spans for the document being shown.
    # Retained values arrive on subscribe like any other source.
    if state.highlight_source, do: Scenic.PubSub.subscribe(state.highlight_source)

    # Request input for direct mode or store_backed mode
    # Only request keyboard input if editable - otherwise just register for mouse/scroll
    # This prevents read-only TextFields from stealing keyboard input
    if state.input_mode in [:direct, :store_backed] do
      if state.editable do
        # Full input for editable fields
        request_input(scene, [:cursor_button, :cursor_pos, :key, :codepoint, :cursor_scroll])
      else
        # Only mouse/scroll for read-only fields (allows clicking, scrolling, but no typing)
        request_input(scene, [:cursor_button, :cursor_pos, :cursor_scroll])
      end
    end

    scene =
      scene
      |> assign(state: state, graph: graph)
      |> push_graph(graph)

    # Note: We don't use capture_input here because it steals input globally,
    # preventing shortcuts like space+k from reaching RootScene.
    # request_input (called above) is sufficient for normal TextField operation.

    {:ok, scene}
  end

  # ===== INPUT HANDLING (Phase 2) =====

  def handle_input(input, _context, scene) do
    state = scene.assigns.state

    # CRITICAL: Only process keyboard input if focused AND editable
    # This prevents unfocused/read-only TextFields from stealing input
    # (e.g., buffer pane shouldn't receive input when search bar is open,
    #  read-only HyperCards shouldn't capture keyboard input)
    case input do
      {:cursor_pos, {x, y}} when state.show_line_numbers == true ->
        handle_fold_hover(input, scene, state, x, y)

      {:cursor_button, {:btn_left, 1, _mods, {x, y}}}
      when state.show_line_numbers == true ->
        # Scenic has already transformed pointer coordinates into the
        # component's local space. Subtracting frame.pin here made gutter
        # controls work only when the TextField happened to sit at {0, 0}.
        if x >= 0 and x <= state.line_number_width do
          local_y = y + state.scroll.offset_y
          display_line = max(1, div(max(trunc(local_y), 0), State.line_height(state)) + 1)
          source_line = Renderer.display_to_source_line(state, display_line)

          case Reducer.process_action(state, {:toggle_fold, source_line}) do
            {:event, event, new_state} ->
              send_parent_event(scene, event)
              new_state = Reducer.update_scroll_content_size(new_state)
              maybe_persist_view(state, new_state)
              update_scene(scene, state, new_state)

            {:noop, _} ->
              {:noreply, scene}
          end
        else
          do_handle_input(input, scene)
        end

      # An overlay owns the keyboard — ignore ALL key input regardless of our
      # own focus flag. This is a second, independent guard: focus is granted
      # and revoked by asynchronous messages, so during the window in which an
      # overlay is opening, a still-focused editor would otherwise apply the
      # user's keystrokes to the DOCUMENT. That is how typing a search query
      # (and the backspaces clearing it) silently edited the open file.
      {:key, _} when state.overlay_open != false and state.overlay_open != nil ->
        {:noreply, scene}

      {:codepoint, _} when state.overlay_open != false and state.overlay_open != nil ->
        {:noreply, scene}

      # Keyboard input - only process if focused AND editable
      {:key, _} when not state.focused or not state.editable ->
        {:noreply, scene}

      {:codepoint, _} when not state.focused or not state.editable ->
        {:noreply, scene}

      # Scroll is positional: only act on it when the pointer is inside this
      # component's frame. request_input delivers every scroll event globally,
      # so without this bound-check two components on screen (e.g. an editor
      # beside a sidebar) would BOTH scroll on a single wheel event.
      {:cursor_scroll, {{_dx, _dy}, {x, y}}} ->
        if point_in_frame?(state.frame, x, y) do
          input = coalesce_scroll_input(input, state.frame)
          do_handle_input(input, scene)
        else
          {:noreply, scene}
        end

      {:cursor_scroll, {_dx, _dy, x, y}} ->
        if point_in_frame?(state.frame, x, y) do
          do_handle_input(input, scene)
        else
          {:noreply, scene}
        end

      # Mouse input - always process (for clicks)
      # But don't allow gaining focus if not editable
      _ ->
        do_handle_input(input, scene)
    end
  end

  # Scenic's requested positional input is transformed into this child scene's
  # local coordinate space. frame.pin belongs to the parent layout and must not
  # be subtracted or included here.
  defp point_in_frame?(%{size: %{width: w, height: h}}, x, y) do
    x >= 0 and x <= w and y >= 0 and y <= h
  end

  # Scenic delivers requested input as ordinary process messages. A high-rate
  # wheel can therefore enqueue hundreds of frames while this component is
  # rendering the first few. Collapse a bounded burst into one accumulated
  # movement. Selective receive intentionally leaves non-scroll messages (for
  # example a buffer-store snapshot) at the front of the queue, giving control
  # changes a chance to pre-empt the remaining wheel backlog.
  defp coalesce_scroll_input({:cursor_scroll, {{dx, dy}, position}}, frame) do
    {dx, dy, position} = drain_scroll_inputs(dx, dy, position, frame, 128)
    {:cursor_scroll, {{dx, dy}, position}}
  end

  defp drain_scroll_inputs(dx, dy, position, _frame, 0), do: {dx, dy, position}

  defp drain_scroll_inputs(dx, dy, position, frame, remaining) do
    receive do
      {:_input, {:cursor_scroll, {{next_dx, next_dy}, {x, y} = next_position}}, _raw, _id} ->
        if point_in_frame?(frame, x, y) do
          drain_scroll_inputs(
            dx + next_dx,
            dy + next_dy,
            next_position,
            frame,
            remaining - 1
          )
        else
          drain_scroll_inputs(dx, dy, position, frame, remaining - 1)
        end
    after
      0 -> {dx, dy, position}
    end
  end

  defp do_handle_input(input, scene) do
    state = scene.assigns.state

    # For store_backed mode, translate input to actions and dispatch to the store
    if state.input_mode == :store_backed do
      handle_store_backed_input(input, scene)
    else
      # Original direct mode handling
      handle_direct_mode_input(input, scene)
    end
  end

  # Handle input for store_backed mode - dispatch semantic actions to the store
  defp handle_store_backed_input(input, scene) do
    state = scene.assigns.state

    action = Reducer.input_to_buffer_action(state, input)

    case action do
      nil ->
        # No action to send (e.g., unhandled key)
        {:noreply, scene}

      {:clipboard_copy, _text} ->
        if state.dispatch, do: GenServer.cast(state.dispatch, {:action, [{:copy, :selection}]})
        {:noreply, scene}

      {:clipboard_cut, _text} ->
        if state.dispatch, do: GenServer.cast(state.dispatch, {:action, [{:cut, :selection}]})
        {:noreply, scene}

      {:clipboard_paste} ->
        if state.dispatch, do: GenServer.cast(state.dispatch, {:action, [{:paste, :at_cursor}]})
        {:noreply, scene}

      {:local_update, new_state} ->
        # Some updates (like focus, scrollbar drag) are handled locally
        maybe_persist_view(state, new_state)
        update_scene(scene, state, new_state)

      {:click_move_cursor, new_state, action} ->
        # Click updates focus locally and sends cursor move to buffer
        if state.dispatch do
          GenServer.cast(state.dispatch, {:action, [action]})
        end

        update_scene(scene, state, new_state)

      {:drag_select, new_state, action} ->
        # Drag selection updates cursor locally and sends selection to buffer
        if state.dispatch do
          GenServer.cast(state.dispatch, {:action, [action]})
        end

        update_scene(scene, state, new_state)

      {:double_click_select, new_state, action} ->
        # Double-click word selection - send selection action to buffer
        if state.dispatch do
          GenServer.cast(state.dispatch, {:action, [action]})
        end

        update_scene(scene, state, new_state)

      {:find_requested, id} ->
        # Emit find_requested event to parent scene
        send_parent_event(scene, {:find_requested, id})
        {:noreply, scene}

      {:replace_mode_requested, id} ->
        # Emit replace_mode_requested event to parent scene (Ctrl+H)
        send_parent_event(scene, {:replace_mode_requested, id})
        {:noreply, scene}

      :save ->
        # Emit save_requested event to parent scene
        send_parent_event(scene, {:save_requested, state.id, State.get_text(state)})
        {:noreply, scene}

      action when is_tuple(action) or is_atom(action) ->
        # Send action to buffer controller
        if state.dispatch do
          GenServer.cast(state.dispatch, {:action, [action]})
        end

        # Wait for buffer broadcast to update
        {:noreply, scene}
    end
  end

  # Handle input for direct mode (original implementation)
  defp handle_direct_mode_input(input, scene) do
    state = scene.assigns.state

    case Reducer.process_input(state, input) do
      {:noop, ^state} ->
        {:noreply, scene}

      {:noop, new_state} ->
        update_scene(scene, state, new_state)

      {:event, {:clipboard_copy, _id, text}, new_state} ->
        case clipboard_copy(text) do
          :ok ->
            send_parent_event(scene, {:clipboard_copy, state.id, text})
            update_scene(scene, state, new_state)

          {:error, reason} ->
            clipboard_error(scene, :copy, reason)
        end

      {:event, {:clipboard_cut, _id, text}, new_state} ->
        case clipboard_copy(text) do
          :ok ->
            send_parent_event(scene, {:clipboard_cut, state.id, text})
            update_scene(scene, state, new_state)

          {:error, reason} ->
            clipboard_error(scene, :cut, reason)
        end

      {:event, {:clipboard_paste_requested, _id}, new_state} ->
        case clipboard_paste() do
          {:ok, clipboard_text} ->
            {:event, event_data, final_state} =
              Reducer.process_action(new_state, {:insert_text, clipboard_text})

            send_parent_event(scene, event_data)
            update_scene(scene, state, final_state)

          {:error, reason} ->
            clipboard_error(scene, :paste, reason)
        end

      {:event, event_data, new_state} ->
        send_parent_event(scene, event_data)
        update_scene(scene, state, new_state)
    end
  end

  # ===== EXTERNAL CONTROL (Phase 3) =====

  @doc """
  Handle action messages from parent scene.
  Actions are processed by the Reducer and may emit events.
  In store_backed mode, actions are forwarded to the store.
  """
  def handle_put({:action, action}, scene) do
    state = scene.assigns.state

    if fold_action?(action) do
      case Reducer.process_action(state, action) do
        {:noop, new_state} ->
          update_scene(scene, state, new_state)

        {:event, event_data, new_state} ->
          send_parent_event(scene, event_data)
          maybe_persist_view(state, new_state)
          update_scene(scene, state, Reducer.update_scroll_content_size(new_state))
      end
    else
      if state.input_mode == :store_backed and state.dispatch do
        # Forward action to the store - the published snapshot updates us
        GenServer.cast(state.dispatch, {:action, [action]})
        {:noreply, scene}
      else
        # Direct mode - process locally
        case Reducer.process_action(state, action) do
          {:noop, new_state} ->
            update_scene(scene, state, new_state)

          {:event, event_data, new_state} ->
            send_parent_event(scene, event_data)
            update_scene(scene, state, new_state)
        end
      end
    end
  end

  defp fold_action?({:toggle_fold, line}) when is_integer(line), do: true
  defp fold_action?({:fold_to_level, level}) when level in 1..4, do: true
  defp fold_action?(:unfold_all), do: true
  defp fold_action?(_), do: false

  defp handle_fold_hover(input, scene, state, x, y) do
    hover_line =
      if x >= 0 and x <= state.line_number_width do
        local_y = y + state.scroll.offset_y
        display_line = max(1, div(max(trunc(local_y), 0), State.line_height(state)) + 1)
        source_line = Renderer.display_to_source_line(state, display_line)
        if ScenicWidgets.TextField.Folding.foldable?(state.lines, source_line), do: source_line
      end

    if hover_line == state.fold_hover_line do
      if is_nil(hover_line), do: do_handle_input(input, scene), else: {:noreply, scene}
    else
      new_state = %{state | fold_hover_line: hover_line}
      graph = Renderer.update_render(scene.assigns.graph, state, new_state)
      new_scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
      if is_nil(hover_line), do: do_handle_input(input, new_scene), else: {:noreply, new_scene}
    end
  end

  def handle_put(text, scene) when is_bitstring(text) do
    # Text replacement - also move cursor to end of text
    lines = String.split(text, "\n")
    last_line = length(lines)
    last_col = String.length(List.last(lines) || "") + 1

    state = %{
      scene.assigns.state
      | lines: lines,
        # Move cursor to end
        cursor: {last_line, last_col}
    }

    send_parent_event(scene, {:text_changed, scene.assigns.state.id, text})
    update_scene(scene, scene.assigns.state, state)
  end

  def handle_put(:focus, scene) do
    # Focus the text field
    # Being told to focus means this field owns the keyboard now, so any
    # "an overlay owns it" gate is by definition stale — clear it. Without
    # this, a single missed clear latches the gate and the editor silently
    # ignores everything typed into it.
    state = %{scene.assigns.state | focused: true, overlay_open: false}
    update_scene(scene, scene.assigns.state, state)
  end

  def handle_put(:blur, scene) do
    # Blur the text field
    state = %{scene.assigns.state | focused: false}
    update_scene(scene, scene.assigns.state, state)
  end

  @doc """
  Apply editor settings (and/or a new frame) IN PLACE.

  Rebuilds this component's graph from scratch while keeping the process
  alive — so its input registration, focus and cursor survive. Hosts should
  prefer this over delete-and-recreate: during a recreation there is a
  window in which the old component has died and the new one has not yet
  requested input, and any keystroke or click arriving in that window is
  lost. (Symptom: a character vanishes if you type while toggling a setting.)

  Recognised keys include line numbers, matching braces, current-line/current-column
  highlights, wrapping, tab width, frame, colors, and font. Unknown keys are ignored.
  """
  @doc """
  Set the "an overlay owns the pointer" flag.

  Deliberately does NOT re-render: the flag only gates click handling, and
  hosts toggle it on every menu open/close — including hover-switching
  between menus. Routing it through `{:update_settings, ...}` rebuilds the
  whole graph, which on a large document is slow enough to block the
  component and time out the caller.
  """
  def handle_put({:set_overlay_open, open?}, scene)
      when is_boolean(open?) or is_map(open?) or is_nil(open?) do
    {:noreply, assign(scene, state: %{scene.assigns.state | overlay_open: open? || false})}
  end

  def handle_put({:update_settings, settings}, scene) when is_map(settings) do
    old_state = scene.assigns.state

    new_state =
      Enum.reduce(
        [
          :show_line_numbers,
          :show_matching_brace,
          :highlight_current_line,
          :highlight_current_column,
          :wrap_mode,
          :tab_width,
          :frame,
          :colors,
          :font,
          :overlay_open,
          :highlight_styles
        ],
        old_state,
        fn
          key, acc ->
            case Map.fetch(settings, key) do
              {:ok, value} -> Map.put(acc, key, value)
              :error -> acc
            end
        end
      )

    # Recompute EVERY frame-derived value, in dependency order. Missing one
    # is subtle and severe: leaving the scroll's viewport dimensions stale
    # after a frame change made the content area compute an empty visible
    # region, so the gutter drew and the text did not.
    new_state =
      new_state
      |> State.recalculate_line_number_width()
      |> State.recalculate_scroll_viewport()
      |> Reducer.update_scroll_content_size()
      |> Map.put(:render_window, nil)
      |> State.advance_render_window()

    new_state = Renderer.prepare_display_cache(new_state)

    graph = Renderer.initial_render(Scenic.Graph.build(), new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_put(%{editable: editable} = opts, scene) do
    # Update editable and optionally focused state
    state = scene.assigns.state

    # Handle cursor blink timer when editable changes
    new_timer =
      if editable != state.editable do
        if editable and state.cursor_timer == nil do
          # Becoming editable - start blink timer
          {:ok, timer} = :timer.send_interval(state.cursor_blink_rate, :blink)
          timer
        else
          if not editable and state.cursor_timer != nil do
            # Becoming read-only - stop blink timer
            :timer.cancel(state.cursor_timer)
            nil
          else
            state.cursor_timer
          end
        end
      else
        state.cursor_timer
      end

    # When entering edit mode, ensure cursor starts visible
    cursor_visible =
      if editable and not state.editable do
        # Always start with cursor visible when entering edit mode
        true
      else
        state.cursor_visible
      end

    new_state = %{
      state
      | editable: editable,
        focused: Map.get(opts, :focused, state.focused),
        cursor_timer: new_timer,
        cursor_visible: cursor_visible
    }

    # CRITICAL: When editable changes, update input registration
    # If becoming editable, request keyboard input; if becoming read-only, release it
    if editable != state.editable and state.input_mode in [:direct, :store_backed] do
      if editable do
        # Now editable - request keyboard input
        request_input(scene, [:cursor_button, :cursor_pos, :key, :codepoint, :cursor_scroll])
      else
        # Now read-only - only need mouse/scroll (release keyboard)
        # Note: Scenic doesn't have release_input, but re-requesting with fewer types works
        request_input(scene, [:cursor_button, :cursor_pos, :cursor_scroll])
      end
    end

    update_scene(scene, state, new_state)
  end

  # ===== CURSOR BLINK TIMER =====

  @doc """
  Handle cursor blink timer message.
  """
  def handle_info(:blink, scene) do
    state = scene.assigns.state

    # Toggle cursor visibility
    new_state = %{state | cursor_visible: !state.cursor_visible}

    # Update only the cursor (efficient partial update)
    graph = Renderer.update_cursor_visibility(scene.assigns.graph, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  @doc """
  Handle buffer state snapshots pushed by the buffer's Scenic.PubSub source
  (store_backed mode). Delegates to the :buf_state_changes update path.
  """
  # Highlight-source snapshots: token spans for one document. Applied only
  # when they describe the document currently shown; the per-row text guard
  # in the renderer covers any lag between typing and re-lexing.
  def handle_info(
        {{Scenic.PubSub, :data}, {source, %{buffer_id: buffer_id, lines: lines}, _ts}},
        %{assigns: %{state: %State{highlight_source: source} = state}} = scene
      )
      when source != nil do
    if buffer_id == state.buffer_id and lines != state.highlights do
      update_scene(scene, state, %{state | highlights: lines})
    else
      {:noreply, scene}
    end
  end

  def handle_info({{Scenic.PubSub, :data}, {source, buf_state, _ts}}, scene) do
    if source == scene.assigns.state.source do
      handle_info({:buf_state_changes, buf_state}, scene)
    else
      {:noreply, scene}
    end
  end

  # Scenic.PubSub lifecycle notifications — deliberately specific clauses, a
  # catch-all on {{Scenic.PubSub, _}, _} would swallow :data updates.
  def handle_info({{Scenic.PubSub, :registered}, _}, scene), do: {:noreply, scene}
  def handle_info({{Scenic.PubSub, :unregistered}, _}, scene), do: {:noreply, scene}

  @doc """
  Handle buffer state updates (for store_backed mode).
  When the store publishes a new snapshot, update TextField to match.
  """
  def handle_info({:buf_state_changes, buf_state}, scene) do
    state = scene.assigns.state

    # Only process if we're in store_backed mode
    if state.input_mode == :store_backed do
      # Extract cursor from buffer state
      cursor =
        case buf_state.cursor do
          %{line: l, col: c} -> {l, c}
          _ -> state.cursor
        end

      # Convert selection from buffer format %{start: ..., end: ...} to TextField format {{line, col}, {line, col}}.
      # Buffer mutators may store selection in two different map formats:
      #   - %{start: %{line: l, col: c}, end: ...}  (cursor struct format)
      #   - %{start: {l, c}, end: {l, c}}            (buffer_mutator.ex tuple format)
      # Both must be normalised to the {{line, col}, {line, col}} tuple that
      # get_selected_text/1 and delete_selection/1 expect.
      selection =
        case buf_state.selection do
          %{start: %{line: sl, col: sc}, end: %{line: el, col: ec}} ->
            {{sl, sc}, {el, ec}}

          %{start: {sl, sc}, end: {el, ec}} ->
            {{sl, sc}, {el, ec}}

          nil ->
            nil

          # Already in {{line, col}, {line, col}} tuple format
          other ->
            other
        end

      # Get new search state
      new_search_query = Map.get(buf_state, :search_query, state.search_query)
      new_search_matches = Map.get(buf_state, :search_matches, state.search_matches)
      new_search_index = Map.get(buf_state, :search_current_index, state.search_current_index)

      # Update local state from buffer
      new_state = %{
        state
        | lines: buf_state.data,
          cursor: cursor,
          selection: selection,
          search_query: new_search_query,
          search_matches: new_search_matches,
          search_current_index: new_search_index
      }

      pane_view = Map.get(buf_state, :pane_view, %{})
      incoming_folds = Map.get(pane_view, :folds, MapSet.to_list(state.folds || MapSet.new()))
      new_state = %{new_state | folds: MapSet.new(incoming_folds)}
      incoming_uuid = Map.get(buf_state, :uuid)
      buffer_switched? = is_binary(incoming_uuid) and incoming_uuid != state.buffer_id
      cursor_or_content_changed? = cursor != state.cursor or buf_state.data != state.lines

      # Update scroll content size when lines change (critical for horizontal scrolling)
      # This ensures the scroll state knows the actual content dimensions
      new_state =
        if state.lines != buf_state.data do
          Reducer.update_scroll_content_size(new_state)
        else
          new_state
        end

      # A buffer SWITCH (a different document behind the stable pane source)
      # must not inherit the previous document's scroll position — the view
      # would open scrolled to wherever the last buffer happened to be, and
      # every click would land offset by the stale scroll. Reset to origin.
      # Same-document updates keep scroll: typing must not yank the view.
      new_state =
        case incoming_uuid do
          nil ->
            new_state

          uuid when uuid == state.buffer_id ->
            new_state

          uuid ->
            restored_scroll = %{
              new_state.scroll
              | offset_x: Map.get(pane_view, :offset_x, 0),
                offset_y: Map.get(pane_view, :offset_y, 0)
            }

            switched =
              new_state
              |> Map.put(:buffer_id, uuid)
              # The previous document's spans do not describe this one; the
              # highlight source republishes for the new document shortly.
              |> Map.put(:highlights, nil)
              |> Map.put(:scroll, Widgex.Scroll.ScrollState.clamp(restored_scroll))
              |> State.reset_render_window()

            # A document with no remembered viewport (never shown before) has
            # nothing to restore: show its cursor — which is wherever the
            # opener put it, e.g. on a project-search match — not its top.
            if Map.get(pane_view, :viewed?, true),
              do: switched,
              else: State.reveal_cursor_centered(switched)
        end

      # Emit search_complete if search results changed
      old_matches = state.search_matches || []
      new_matches = new_search_matches || []
      # Always emit when we have a search query and match count changes
      if new_search_query != nil do
        old_count = length(old_matches)
        new_count = length(new_matches)

        if old_count != new_count do
          send_parent_event(scene, {:search_complete, state.id, new_search_query, new_count})
        end
      end

      # Emit search_navigated if index changed
      if new_search_index != state.search_current_index and new_search_query != nil do
        total = length(new_matches)
        send_parent_event(scene, {:search_navigated, state.id, new_search_index, total})
      end

      # A document switch restores that document's independent viewport. Wheel
      # scrolling intentionally does not move the text cursor, so forcing the
      # cursor visible here would immediately destroy the restored offset.
      # Same-document cursor moves and edits still keep the live cursor on
      # screen. Retained PubSub snapshots and metadata-only republishes are
      # deliberately inert: a duplicate snapshot commonly follows a pane
      # switch and must not destroy the viewport we just restored.
      search_jump? =
        new_search_query != nil and
          (new_search_index != state.search_current_index or
             new_search_matches != state.search_matches)

      new_state =
        cond do
          buffer_switched? or not cursor_or_content_changed? -> new_state
          search_jump? -> State.reveal_cursor_centered(new_state)
          true -> State.ensure_cursor_visible(new_state)
        end

      update_scene(scene, state, new_state)
    else
      {:noreply, scene}
    end
  end

  defp maybe_persist_view(old_state, new_state) do
    old_scroll = old_state.scroll
    new_scroll = new_state.scroll

    if old_state.dispatch &&
         (old_scroll.offset_x != new_scroll.offset_x or old_scroll.offset_y != new_scroll.offset_y or
            old_state.folds != new_state.folds) do
      GenServer.cast(old_state.dispatch, {
        :view_state,
        %{
          offset_x: new_scroll.offset_x,
          offset_y: new_scroll.offset_y,
          folds: MapSet.to_list(new_state.folds)
        }
      })
    end
  end

  # ===== HANDLE CAST (for Scenic input routing) =====

  @doc """
  Handle input sent via GenServer.cast from Scenic.
  This is how Scenic delivers input when a component requests it.
  """
  def handle_cast({:user_input, input}, scene) do
    # Forward to handle_input
    handle_input(input, nil, scene)
  end

  @doc """
  Handle direct buffer state push from parent scene.
  Delegates to handle_info to reuse the PubSub update path.

  Called by `dispatch_to_active_buffer/2` in the root scene after a
  synchronous buffer action — allows the root scene to push state
  directly to the TextField without waiting for a PubSub broadcast.
  """
  def handle_cast({:state_change, buf_state}, scene) do
    handle_info({:buf_state_changes, buf_state}, scene)
  end

  # ===== HELPER FUNCTIONS =====

  defp update_scene(scene, old_state, new_state) do
    old_state = Renderer.prepare_display_cache(old_state)

    # Whatever moved the scroll (wheel, cursor-follow, a jump to a search
    # match) the render window must cover the viewport before drawing, or the
    # rows the user just scrolled to have no primitives. A no-op when the
    # viewport is still inside the buffered window.
    new_state =
      new_state
      |> State.advance_render_window()
      |> Renderer.prepare_display_cache()

    graph = Renderer.update_render(scene.assigns.graph, old_state, new_state)

    scene =
      scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  # ===== CLIPBOARD HELPERS =====

  defp clipboard_copy(text), do: ScenicWidgets.Clipboard.adapter().copy(text)
  defp clipboard_paste, do: ScenicWidgets.Clipboard.adapter().paste()

  defp clipboard_error(scene, operation, reason) do
    send_parent_event(scene, {:clipboard_error, operation, reason})
    {:noreply, scene}
  end

  # ===== SCENIC CALLBACKS =====

  @doc """
  Handle fetch requests - returns the full TextField state.
  This allows parent scenes to retrieve the TextField's current state
  before rebuilding graphs (e.g., on window resize).

  Returns: `{:ok, %ScenicWidgets.TextField.State{}}`
  """
  @impl Scenic.Scene
  def handle_fetch(_from, scene) do
    {:reply, {:ok, scene.assigns.state}, scene}
  end
end
