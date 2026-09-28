defmodule ScenicWidgets.TextField.Reducer do
  @moduledoc """
  Pure state transition functions for TextField.

  Phase 2: Input handling (process_input/2)
  Phase 3: External actions (process_action/2)
  Phase 2: Input handling using ScenicEventsDefinitions
  Handles :key events and converts them to text using key2string/1

  Returns:
  - {:noop, state} - State changed, no parent notification needed
  - {:event, event_data, state} - State changed, notify parent
  """

  alias ScenicWidgets.TextField.State
  alias Widgex.Scroll.ScrollController
  use ScenicWidgets.ScenicEventsDefinitions
  use Widgex.Scrollable

  # The modifiers that turn a keystroke into a command rather than a
  # character. Shift and the lock keys are text modifiers — the driver has
  # already applied them by the time a codepoint exists — and :alt is
  # deliberately absent because on macOS Option composes characters
  # (Option+e -> é). See input_to_buffer_action/2 for the full account.
  @command_mods [:ctrl, :meta, :super]

  defp command_modified?(mods), do: Enum.any?(mods, &(&1 in @command_mods))

  # Debounce period (ms) to ignore keypresses right after gaining focus.
  # This prevents the key that triggered focus (e.g., "k" from space+k) from being inserted.
  @focus_debounce_ms 50

  # Double-click threshold in milliseconds
  @double_click_ms 400

  # ===== DIRECT INPUT PROCESSING =====

  @doc """
  Process raw Scenic input events (for direct input mode).
  Uses ScenicEventsDefinitions for key matching and conversion.
  """

  # ===== TEXT INPUT - Codepoint events ONLY =====

  # Handle codepoint events (direct character input from driver)
  # Codepoint is a string (single UTF-8 character)
  # NOTE: We ONLY handle codepoint events for text input to avoid duplicate insertions.
  # When a user presses a letter key, Scenic sends BOTH :codepoint and :key events.
  # We use :codepoint for text input and :key only for non-character keys (arrows, backspace, etc.)

  # Debounce: Ignore codepoints that arrive immediately after focus (e.g., "k" from space+k shortcut)
  def process_input(
        %State{focused: true, focus_time: focus_time} = state,
        {:codepoint, _} = _input
      )
      when is_integer(focus_time) do
    now = System.monotonic_time(:millisecond)

    if now - focus_time < @focus_debounce_ms do
      # Input arrived too soon after focus - ignore it (likely the focus-triggering key)
      {:noop, state}
    else
      # Past debounce window - process normally
      process_input_codepoint(state, _input)
    end
  end

  def process_input(%State{focused: true} = state, {:codepoint, {char, _mods}} = input)
      when is_bitstring(char) do
    process_input_codepoint(state, input)
  end

  # A command chord is reported by the driver twice: as the :key the chord
  # is bound to, and again as the codepoint of the letter under the finger.
  # The chord is handled from the :key. Its codepoint is not text, so it is
  # dropped here — otherwise Ctrl+V, having pasted, would also type a "v".
  # This is the direct-mode twin of the same rule in input_to_buffer_action/2.
  defp process_input_codepoint(state, {:codepoint, {char, mods}})
       when is_bitstring(char) and is_list(mods) do
    if command_modified?(mods) do
      {:noop, state}
    else
      insert_codepoint(state, char)
    end
  end

  defp insert_codepoint(state, char) do
    # Push undo before making changes
    state_with_undo = State.push_undo(state)
    # Delete selection first if any, then insert
    state_after_delete = delete_selection(state_with_undo)
    new_state = insert_char(state_after_delete, char)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # ===== TEXT INPUT - Using key2string conversion =====
  # REMOVED: We no longer handle text input via :key events to avoid duplicate insertions
  # See codepoint handler above - that's the only way text gets inserted now

  # # Handle all valid text input characters (letters, numbers, punctuation, space, enter)
  # def process_input(%State{focused: true} = state, input) when input in @valid_text_input_characters do
  #   char = key2string(input)
  #   # IO.puts("🔍 TEXT INPUT: '#{char}', selection: #{inspect(state.selection)}")
  #   # Delete selection first if any, then insert
  #   state_after_delete = delete_selection(state)
  #   # IO.puts("🔍 After delete_selection: cursor #{inspect(state_after_delete.cursor)}, lines: #{inspect(state_after_delete.lines)}")
  #   new_state = insert_char(state_after_delete, char)
  #   {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  # end

  # ===== SPECIAL KEYS =====

  # Enter key - insert newline in multi_line mode (doesn't send codepoint event, only key event)
  def process_input(
        %State{focused: true, mode: :multi_line} = state,
        {:key, {:key_enter, key_state, _mods}}
      )
      when key_state > 0 do
    # key_state > 0 matches both press (1) and repeat (2) events
    state_with_undo = State.push_undo(state)
    state_after_delete = delete_selection(state_with_undo)
    new_state = insert_char(state_after_delete, "\n")
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # Enter key - emit :enter_pressed event in single_line mode (for command bars, search fields, etc.)
  #
  # PLAIN Enter only. A modified Enter belongs to the host: Shift+Enter in a
  # search bar means "the previous match", and reporting it as an ordinary
  # Enter made the host do both — forward from the event, back from the key —
  # which nets out to the cursor never moving at all.
  def process_input(
        %State{focused: true, mode: :single_line} = state,
        {:key, {:key_enter, key_state, mods}}
      )
      when key_state > 0 and mods == [] do
    # Don't insert newline - emit event for parent to handle
    {:event, {:enter_pressed, state.id, State.get_text(state)}, state}
  end

  # Tab in a single-line field means "the next field", which only the host
  # knows about — a one-line input has nothing to indent.
  def process_input(
        %State{focused: true, mode: :single_line} = state,
        {:key, {:key_tab, key_state, mods}}
      )
      when key_state > 0 do
    {:event, {:tab_pressed, state.id, :shift in mods}, state}
  end

  # Escape key - emit :escape_pressed event for parent to handle (close dialogs, etc.)
  #
  # The key is `:key_esc`. That is what the driver emits (scenic_driver_local
  # maps X11 keysym 0xFF1B to :key_esc) and what
  # ScenicWidgets.ScenicEventsDefinitions declares as @escape_key. There is no
  # :key_escape — a clause matching it can only ever fire from a test harness
  # sending the wrong atom, which makes a passing test prove nothing about
  # what a user's keyboard does.
  def process_input(%State{focused: true} = state, {:key, {:key_esc, key_state, _mods}})
      when key_state > 0 do
    {:event, {:escape_pressed, state.id}, state}
  end

  # Backspace - delete selection or character before cursor
  # key_state > 0 matches both press (1) and repeat (2) for key-hold functionality
  def process_input(
        %State{focused: true, selection: selection} = state,
        {:key, {:key_backspace, key_state, _mods}}
      )
      when selection != nil and key_state > 0 do
    state_with_undo = State.push_undo(state)
    new_state = delete_selection(state_with_undo)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # Ctrl+Backspace and Ctrl+Delete take a word. This lives in the DIRECT input
  # path as well as the store-backed one — the two are separate, and a field
  # embedded in another component (the search pane's, say) runs through this
  # one. Wired into only half of them, the shortcut works in the document and
  # quietly does nothing in every dialog and pane.
  def process_input(%State{focused: true} = state, {:key, {:key_backspace, key_state, mods}})
      when key_state > 0 do
    state_with_undo = State.push_undo(state)

    new_state =
      if :ctrl in mods,
        do: delete_word_before_cursor(state_with_undo),
        else: delete_before_cursor(state_with_undo)

    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # Delete - delete selection or character at cursor
  # key_state > 0 matches both press (1) and repeat (2) for key-hold functionality
  def process_input(
        %State{focused: true, selection: selection} = state,
        {:key, {:key_delete, key_state, _mods}}
      )
      when selection != nil and key_state > 0 do
    state_with_undo = State.push_undo(state)
    new_state = delete_selection(state_with_undo)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  def process_input(%State{focused: true} = state, {:key, {:key_delete, key_state, mods}})
      when key_state > 0 do
    state_with_undo = State.push_undo(state)

    new_state =
      if :ctrl in mods,
        do: delete_word_at_cursor(state_with_undo),
        else: delete_at_cursor(state_with_undo)

    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # Arrow keys with Shift - text selection
  # key_state > 0 matches both press (1) and repeat (2) for key-hold functionality
  def process_input(%State{focused: true} = state, {:key, {:key_left, key_state, mods}})
      when key_state > 0 do
    if :shift in mods do
      {:noop, move_cursor_with_selection(state, :left)}
    else
      {:noop, move_cursor(state, :left) |> clear_selection()}
    end
  end

  def process_input(%State{focused: true} = state, {:key, {:key_right, key_state, mods}})
      when key_state > 0 do
    if :shift in mods do
      {:noop, move_cursor_with_selection(state, :right)}
    else
      {:noop, move_cursor(state, :right) |> clear_selection()}
    end
  end

  def process_input(%State{focused: true} = state, {:key, {:key_up, key_state, mods}})
      when key_state > 0 do
    if :shift in mods do
      {:noop, move_cursor_with_selection(state, :up)}
    else
      {:noop, move_cursor(state, :up) |> clear_selection()}
    end
  end

  def process_input(%State{focused: true} = state, {:key, {:key_down, key_state, mods}})
      when key_state > 0 do
    if :shift in mods do
      new_state = move_cursor_with_selection(state, :down)
      {:noop, new_state}
    else
      {:noop, move_cursor(state, :down) |> clear_selection()}
    end
  end

  # Home/End keys
  def process_input(%State{focused: true} = state, @home_key) do
    {:noop, state |> move_cursor(:line_start) |> clear_selection()}
  end

  def process_input(%State{focused: true} = state, @end_key) do
    {:noop, state |> move_cursor(:line_end) |> clear_selection()}
  end

  # Escape - lose focus and notify parent of escape (distinct from click-outside focus_lost)
  # Parents like HyperCard listen for {:escape_pressed, id} to cancel edit mode.
  def process_input(%State{focused: true} = state, @escape_key) do
    {:event, {:escape_pressed, state.id}, %{state | focused: false}}
  end

  # Tab - emit tab_pressed event so parent can handle field switching
  # (Inserting literal tab characters is rarely useful; parents like HyperCard
  #  use this event to cycle focus between title → content → title)
  def process_input(%State{focused: true} = state, @tab_key) do
    {:event, {:tab_pressed, state.id}, state}
  end

  # ===== KEYBOARD SHORTCUTS =====

  # Ctrl+A - Select all
  def process_input(%State{focused: true} = state, @ctrl_a) do
    {:noop, select_all(state)}
  end

  # Ctrl+C - Copy selection to clipboard (works even when unfocused)
  def process_input(%State{selection: selection} = state, @ctrl_c) when selection != nil do
    text = get_selected_text(state)
    # Send clipboard event to parent (Scenic doesn't have system clipboard access)
    {:event, {:clipboard_copy, state.id, text}, state}
  end

  def process_input(%State{} = state, @ctrl_c) do
    # No selection - do nothing
    {:noop, state}
  end

  # Ctrl+X - Cut selection to clipboard (works even when unfocused)
  def process_input(%State{selection: selection} = state, @ctrl_x) when selection != nil do
    text = get_selected_text(state)
    new_state = delete_selection(state)
    # Send clipboard event to parent
    {:event, {:clipboard_cut, state.id, text}, new_state}
  end

  def process_input(%State{} = state, @ctrl_x) do
    # No selection - do nothing
    {:noop, state}
  end

  # Ctrl+V - Paste from clipboard (works even when unfocused for testing)
  def process_input(%State{} = state, @ctrl_v) do
    # Emit event to request clipboard data from parent
    # Parent will call insert_text action with the clipboard content
    {:event, {:clipboard_paste_requested, state.id}, state}
  end

  # Ctrl+S - Save (emit event for parent to handle)
  def process_input(%State{focused: true} = state, @ctrl_s) do
    {:event, {:save_requested, state.id, State.get_text(state)}, state}
  end

  # Ctrl+F - Find (emit event to open search dialog)
  def process_input(%State{focused: true} = state, @ctrl_f) do
    {:event, {:find_requested, state.id}, state}
  end

  # Ctrl+H - Find & Replace (emit event to open replace bar)
  def process_input(%State{focused: true} = state, @ctrl_h) do
    {:event, {:replace_mode_requested, state.id}, state}
  end

  # Ctrl+G - Go to line (emit event; the parent owns the prompt).
  #
  # This key used to mean "next match", which is gedit's binding. It was moved
  # to F3 — the near-universal find-next key — so that Ctrl+G could take the
  # equally universal Go to Line. Note the old handler was guarded on
  # `length(matches) > 0`, so Ctrl+G did nothing at all unless a search was
  # already running; nothing that worked has been taken away.
  def process_input(%State{focused: true} = state, @ctrl_g) do
    {:event, {:goto_line_requested, state.id}, state}
  end

  # F3 - Go to next match (if searching)
  def process_input(
        %State{focused: true, search_matches: matches, search_current_index: idx} = state,
        {:key, {:key_f3, 1, []}}
      )
      when length(matches) > 0 do
    # Cycle to next match
    next_idx = rem(idx + 1, length(matches))
    {line, col, _text} = Enum.at(matches, next_idx)

    new_state =
      %{state | search_current_index: next_idx, cursor: {line, col}}
      |> State.ensure_cursor_visible()

    {:event, {:search_navigated, state.id, next_idx, length(matches)}, new_state}
  end

  # ===== SHIFT KEY TRACKING (for Shift+scroll horizontal scrolling) =====
  # NOTE: These MUST come BEFORE the key release catch-all so shift release is tracked

  # Track Shift key press - both left and right shift
  def process_input(%State{scroll: scroll} = state, {:key, {:key_leftshift, 1, _}}) do
    {:noop, %{state | scroll: set_scroll_shift(scroll, true)}}
  end

  def process_input(%State{scroll: scroll} = state, {:key, {:key_rightshift, 1, _}}) do
    {:noop, %{state | scroll: set_scroll_shift(scroll, true)}}
  end

  # Track Shift key release
  def process_input(%State{scroll: scroll} = state, {:key, {:key_leftshift, 0, _}}) do
    {:noop, %{state | scroll: set_scroll_shift(scroll, false)}}
  end

  def process_input(%State{scroll: scroll} = state, {:key, {:key_rightshift, 0, _}}) do
    {:noop, %{state | scroll: set_scroll_shift(scroll, false)}}
  end

  # ===== KEY RELEASE EVENTS - Ignore all others =====

  # Ignore other key release events (state: 0)
  def process_input(state, {:key, {_key, @key_released, _mods}}) do
    {:noop, state}
  end

  # ===== UNFOCUSED - Ignore all other keyboard input =====

  def process_input(%State{focused: false} = state, {:key, _}) do
    {:noop, state}
  end

  # ===== SCROLL INPUT =====

  # Handle scroll input with smart Shift+scroll support
  def process_input(%State{} = state, {:cursor_scroll, {{dx, dy}, {_x, _y}}}) do
    handle_scroll_input_smart(state, dx, dy)
  end

  def process_input(%State{} = state, {:cursor_scroll, {dx, dy, _x, _y}}) do
    handle_scroll_input_smart(state, dx, dy)
  end

  # ===== SCROLLBAR DRAG =====

  # Mouse button release - end scrollbar drag
  def process_input(
        %State{scrollbar_drag: drag} = state,
        {:cursor_button, {:btn_left, 0, _, _pos}}
      )
      when drag != nil do
    {:noop, %{state | scrollbar_drag: nil, scrollbar_drag_start: nil, scrollbar_drag_offset: nil}}
  end

  # Mouse move during scrollbar drag
  def process_input(
        %State{
          scrollbar_drag: :x,
          scrollbar_drag_start: {start_x, _},
          scrollbar_drag_offset: start_offset,
          scroll: scroll
        } = state,
        {:cursor_pos, {x, _y}}
      ) do
    # Calculate how far we've dragged in pixels
    drag_delta = x - start_x

    # Convert to scroll offset based on track/content ratio
    {_track_start, track_length, content_size, viewport_size} =
      State.scrollbar_track_info(state, :x)

    new_offset_x =
      drag_offset(start_offset, drag_delta, track_length, content_size, viewport_size)

    new_scroll = %{scroll | offset_x: new_offset_x}

    {:noop, %{state | scroll: new_scroll}}
  end

  def process_input(
        %State{
          scrollbar_drag: :y,
          scrollbar_drag_start: {_, start_y},
          scrollbar_drag_offset: start_offset,
          scroll: scroll
        } = state,
        {:cursor_pos, {_x, y}}
      ) do
    drag_delta = y - start_y

    {_track_start, track_length, content_size, viewport_size} =
      State.scrollbar_track_info(state, :y)

    new_offset_y =
      drag_offset(start_offset, drag_delta, track_length, content_size, viewport_size)

    new_scroll = %{scroll | offset_y: new_offset_y}

    {:noop, %{state | scroll: new_scroll}}
  end

  # ===== CLICK TO FOCUS =====

  # Click on scrollbar - start drag (check before focus handling)
  def process_input(%State{} = state, {:cursor_button, {:btn_left, 1, _, pos}}) do
    case State.scrollbar_hit_test(state, pos) do
      :x ->
        # Start horizontal scrollbar drag
        {:noop,
         %{
           state
           | scrollbar_drag: :x,
             scrollbar_drag_start: pos,
             scrollbar_drag_offset: state.scroll.offset_x
         }}

      :y ->
        # Start vertical scrollbar drag
        {:noop,
         %{
           state
           | scrollbar_drag: :y,
             scrollbar_drag_start: pos,
             scrollbar_drag_offset: state.scroll.offset_y
         }}

      nil ->
        # Not on scrollbar - handle focus
        handle_click_focus(state, pos)
    end
  end

  defp handle_click_focus(%State{focused: false} = state, pos) do
    inside = State.point_inside?(state, pos)
    # Only allow focus if editable - read-only TextFields should not gain focus
    if inside and state.editable do
      # Click to focus AND position cursor at click location
      {line, col} = State.click_to_cursor(state, pos)

      new_state = %{
        state
        | focused: true,
          focus_time: System.monotonic_time(:millisecond),
          cursor: {line, col},
          selection: nil
      }

      {:event, {:focus_gained, state.id}, new_state}
    else
      {:noop, state}
    end
  end

  defp handle_click_focus(%State{focused: true} = state, pos) do
    if State.point_inside?(state, pos) do
      # Click inside while focused - move cursor to click position
      {line, col} = State.click_to_cursor(state, pos)
      new_state = %{state | cursor: {line, col}, selection: nil}
      {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
    else
      {:event, {:focus_lost, state.id}, %{state | focused: false}}
    end
  end

  # ===== FALLBACK - Unhandled input =====

  def process_input(state, {:key, {:key_v, 1, [:ctrl]}} = _input) do
    # Fallback for Ctrl+V if not caught above
    {:noop, state}
  end

  # Catch-all for unhandled input
  def process_input(state, _input) do
    {:noop, state}
  end

  # ===== EXTERNAL ACTION PROCESSING (Phase 3) =====

  @doc """
  Process high-level actions (for external control mode).
  Phase 3 implementation.
  """
  def process_action(state, {:insert_text, text}) do
    # Push undo before making changes
    state_with_undo = State.push_undo(state)
    # Delete selection if any, then insert text
    state_after_delete = delete_selection(state_with_undo)
    new_state = insert_text_at_cursor(state_after_delete, text)
    {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}
  end

  # Undo action (from menu)
  def process_action(state, :undo) do
    case State.undo(state) do
      {:ok, new_state} ->
        {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}

      {:noop, state} ->
        {:noop, state}
    end
  end

  # Redo action (from menu)
  def process_action(state, :redo) do
    case State.redo(state) do
      {:ok, new_state} ->
        {:event, {:text_changed, state.id, State.get_text(new_state)}, new_state}

      {:noop, state} ->
        {:noop, state}
    end
  end

  def process_action(%State{} = state, {:toggle_fold, line}) when is_integer(line) do
    folds = ScenicWidgets.TextField.Folding.toggle(state.lines, state.folds, line)

    if folds == state.folds,
      do: {:noop, state},
      else: {:event, {:folds_changed, state.id, MapSet.to_list(folds)}, %{state | folds: folds}}
  end

  def process_action(%State{} = state, :unfold_all) do
    folds = ScenicWidgets.TextField.Folding.unfold_all()
    {:event, {:folds_changed, state.id, []}, %{state | folds: folds}}
  end

  def process_action(%State{} = state, {:fold_to_level, level}) when level in 1..5 do
    folds = ScenicWidgets.TextField.Folding.fold_to_level(state.lines, level)

    {:event, {:folds_changed, state.id, MapSet.to_list(folds)},
     %{state | folds: folds, fold_level: level}}
  end

  # Perform search across all lines.
  #
  # `opts` carries `case_sensitive:` and `regex:`, both defaulting to off —
  # the plain find everyone expects. A regex that does not compile finds
  # nothing rather than raising: a half-typed pattern is a normal thing to
  # have in a search box, not an error worth taking the editor down for.
  def process_action(%State{} = state, {:search, query}) when is_binary(query) and query != "",
    do: process_action(state, {:search, query, []})

  def process_action(%State{lines: lines} = state, {:search, query, opts})
      when is_binary(query) and query != "" do
    matches = find_all_matches(lines, query, opts)
    match_count = length(matches)

    new_state = %{state | search_query: query, search_matches: matches, search_current_index: 0}

    # Jump to first match if any
    new_state =
      if match_count > 0 do
        {line, col, _text} = hd(matches)

        %{
          new_state
          | cursor: {line, col},
            folds: ScenicWidgets.TextField.Folding.expand_to_line(state.lines, state.folds, line)
        }
        |> State.ensure_cursor_visible()
      else
        new_state
      end

    {:event, {:search_complete, state.id, query, match_count}, new_state}
  end

  # Clear search state
  def process_action(state, :clear_search) do
    new_state = %{state | search_query: nil, search_matches: [], search_current_index: 0}
    {:event, {:search_cleared, state.id}, new_state}
  end

  # Navigate to next search match
  def process_action(
        %State{search_matches: matches, search_current_index: idx} = state,
        :find_next
      )
      when length(matches) > 0 do
    next_idx = rem(idx + 1, length(matches))
    {line, col, _text} = Enum.at(matches, next_idx)

    new_state =
      %{
        state
        | search_current_index: next_idx,
          cursor: {line, col},
          folds: ScenicWidgets.TextField.Folding.expand_to_line(state.lines, state.folds, line)
      }
      |> State.ensure_cursor_visible()

    {:event, {:search_navigated, state.id, next_idx, length(matches)}, new_state}
  end

  def process_action(state, :find_next) do
    # No matches to navigate
    {:noop, state}
  end

  # Navigate to previous search match
  def process_action(
        %State{search_matches: matches, search_current_index: idx} = state,
        :find_prev
      )
      when length(matches) > 0 do
    prev_idx = if idx == 0, do: length(matches) - 1, else: idx - 1
    {line, col, _text} = Enum.at(matches, prev_idx)

    new_state =
      %{
        state
        | search_current_index: prev_idx,
          cursor: {line, col},
          folds: ScenicWidgets.TextField.Folding.expand_to_line(state.lines, state.folds, line)
      }
      |> State.ensure_cursor_visible()

    {:event, {:search_navigated, state.id, prev_idx, length(matches)}, new_state}
  end

  def process_action(state, :find_prev) do
    # No matches to navigate
    {:noop, state}
  end

  def process_action(state, _action) do
    {:noop, state}
  end

  # ===========================================================================
  # BUFFER-BACKED MODE: Input to Buffer Action Conversion
  # ===========================================================================

  @doc """
  Convert raw Scenic input events to buffer actions for store_backed mode.

  Returns:
  - nil - No action (unhandled input)
  - {:clipboard_copy, text} - Copy selected text (handled locally)
  - {:clipboard_cut, text} - Cut selected text (handled locally + buffer action)
  - {:clipboard_paste} - Paste from clipboard (fetches clipboard then sends to buffer)
  - {:local_update, new_state} - Local-only update (focus, scrollbar drag)
  - action - Buffer action tuple/atom to send to Buffer.Process
  """
  # Command-modified key presses are also reported by GLFW as codepoints. They
  # belong to the shortcut owner and must never become document text.
  #
  # Only COMMAND modifiers disqualify a codepoint. This used to reject any
  # non-empty mods list, which silently swallowed every shifted character —
  # capitals, and `!@#$%^&*()_+{}|:"<>?` with them — because the driver reports
  # Shift+a as {"A", [:shift]}. Shift and the lock keys are text modifiers: the
  # driver has ALREADY applied them to produce the character, so by the time a
  # codepoint exists the shift has done its job and carries no further meaning.
  #
  # :alt is deliberately absent. On macOS Option is a text modifier
  # (Option+e -> é, Option+3 -> #), and dropping those would break typing on the
  # platform we are about to support. Known gap: AltGr on X11/Windows is
  # reported as ctrl+alt, so AltGr characters are still swallowed by the :ctrl
  # clause below.
  def input_to_buffer_action(%State{focused: true}, {:codepoint, {char, mods}})
      when is_bitstring(char) and is_list(mods) do
    if command_modified?(mods) do
      nil
    else
      {:insert, char, :at_cursor}
    end
  end

  # Enter key - insert newline
  def input_to_buffer_action(
        %State{focused: true, mode: :multi_line} = state,
        {:key, {:key_enter, key_state, _mods}}
      )
      when key_state > 0 do
    # Two different actions rather than one action plus a flag: whether Enter
    # carries the indentation down is a decision the FRONTEND makes, and the
    # backend should only ever be told what to do.
    if state.auto_indent == false do
      {:newline, :no_indent}
    else
      {:newline, :at_cursor}
    end
  end

  # Shift+Tab - remove one indentation unit from the current line.
  def input_to_buffer_action(
        %State{focused: true, tab_width: tab_width},
        {:key, {:key_tab, key_state, mods}}
      )
      when key_state > 0 and mods == [:shift] do
    {:unindent, tab_width}
  end

  # Tab key - insert tab character
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_tab, key_state, _mods}})
      when key_state > 0 do
    {:insert, "\t", :at_cursor}
  end

  # Backspace, and Ctrl+Backspace for a whole word.
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_backspace, key_state, mods}})
      when key_state > 0 do
    if :ctrl in mods, do: {:delete, :prev_word}, else: {:delete, :before_cursor}
  end

  # Delete, and Ctrl+Delete for a whole word.
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_delete, key_state, mods}})
      when key_state > 0 do
    if :ctrl in mods, do: {:delete, :next_word}, else: {:delete, :at_cursor}
  end

  # Arrow keys - cursor movement
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_left, key_state, mods}})
      when key_state > 0 do
    cond do
      :ctrl in mods and :shift in mods -> {:select_text, :prev_word}
      :ctrl in mods -> {:move_cursor, :prev_word}
      :shift in mods -> {:select_text, :left, 1}
      true -> {:move_cursor, :left, 1}
    end
  end

  def input_to_buffer_action(%State{focused: true}, {:key, {:key_right, key_state, mods}})
      when key_state > 0 do
    cond do
      # Ctrl+Shift together: a word, WITH the text. Checked before plain ctrl,
      # which otherwise swallows it and moves the cursor selecting nothing.
      :ctrl in mods and :shift in mods -> {:select_text, :next_word}
      :ctrl in mods -> {:move_cursor, :next_word}
      :shift in mods -> {:select_text, :right, 1}
      true -> {:move_cursor, :right, 1}
    end
  end

  # Up/Down are the one movement whose meaning depends on the VIEW: under word
  # wrap "the line above" is the visual row above, which the store cannot know
  # — wrapping is a function of this widget's frame and font. So when display
  # and source disagree, the widget resolves the move itself and hands the
  # store an absolute position instead of a direction.
  #
  # `{:display_move, goal, action}` is not a store action: `handle_store_backed_input/2`
  # unwraps it, keeps the goal column locally, and dispatches `action`.
  def input_to_buffer_action(%State{focused: true} = state, {:key, {:key_up, key_state, mods}})
      when key_state > 0 do
    vertical_buffer_action(state, -1, :up, :shift in mods)
  end

  def input_to_buffer_action(%State{focused: true} = state, {:key, {:key_down, key_state, mods}})
      when key_state > 0 do
    vertical_buffer_action(state, 1, :down, :shift in mods)
  end

  # Home/End keys. With Shift they extend the selection, like every other
  # movement key.
  #
  # The target is sent as :line_start / :line_end rather than as coordinates
  # this component works out for itself. It is tempting to resolve it here —
  # the text is right there — but this component's copy of the document is a
  # MIRROR, and immediately after the host switches buffers it is a mirror of
  # the previous one. Resolving "the end of this line" against a stale mirror
  # produced a selection that reached into a line the person could not see,
  # and a copy that quietly took two lines instead of one. Where the end of a
  # line is, is a fact about the document, so the document answers it.
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_home, key_state, mods}})
      when key_state > 0 do
    if :shift in mods do
      {:select_to, :line_start}
    else
      {:move_cursor, :line_start}
    end
  end

  def input_to_buffer_action(%State{focused: true}, {:key, {:key_end, key_state, mods}})
      when key_state > 0 do
    if :shift in mods do
      {:select_to, :line_end}
    else
      {:move_cursor, :line_end}
    end
  end

  # Ctrl+A - Select all
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_a, 1, [:ctrl]}}) do
    :select_all
  end

  # Ctrl+C - Copy. In store_backed mode the store is the source of truth for
  # the selection shape; TextField's local `selection` mirror can lag behind a
  # mouse-drag by one publish. Route the action through unconditionally — the
  # store's reducer no-ops {:copy, :selection} when it has no selection.
  # (Regression origin: a host editor's mouse-drag + Ctrl+X data-loss bug.)
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_c, 1, [:ctrl]}}) do
    {:copy, :selection}
  end

  # Ctrl+X - Cut. Same rationale as Ctrl+C above — pass through to the buffer
  # and let the buffer decide whether there is anything to cut.
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_x, 1, [:ctrl]}}) do
    {:cut, :selection}
  end

  # Ctrl+V - Paste
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_v, 1, [:ctrl]}}) do
    {:clipboard_paste}
  end

  # Canonical undo/redo bindings.
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_z, 1, [:ctrl]}}) do
    :undo
  end

  def input_to_buffer_action(%State{focused: true}, {:key, {:key_z, 1, mods}})
      when mods in [[:ctrl, :shift], [:shift, :ctrl]] do
    :redo
  end

  # Ctrl+S - Save (pass through to parent)
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_s, 1, [:ctrl]}}) do
    :save
  end

  # Ctrl+F - Find (emit event to parent)
  def input_to_buffer_action(%State{focused: true} = state, {:key, {:key_f, 1, [:ctrl]}}) do
    {:find_requested, state.id}
  end

  # Ctrl+H - Find & Replace (emit event to parent)
  def input_to_buffer_action(%State{focused: true} = state, {:key, {:key_h, 1, [:ctrl]}}) do
    {:replace_mode_requested, state.id}
  end

  # Ctrl+G - Go to Line (emit event to parent; the parent owns the prompt).
  #
  # This must live here, not only in process_input/2: store_backed consumers
  # never reach process_input/2 at all — handle_store_backed_input/2 routes
  # every event through input_to_buffer_action/2 instead. A shortcut added only
  # to the other path is dead code for them.
  def input_to_buffer_action(%State{focused: true} = state, {:key, {:key_g, 1, [:ctrl]}}) do
    {:goto_line_requested, state.id}
  end

  # F3 - next search match, for store_backed consumers.
  def input_to_buffer_action(%State{focused: true}, {:key, {:key_f3, 1, []}}) do
    :find_next
  end

  # ===== SCROLLBAR DRAG (store_backed mode) =====

  # Mouse button release - end scrollbar drag
  def input_to_buffer_action(
        %State{scrollbar_drag: drag} = state,
        {:cursor_button, {:btn_left, 0, _, _pos}}
      )
      when drag != nil do
    {:local_update,
     %{state | scrollbar_drag: nil, scrollbar_drag_start: nil, scrollbar_drag_offset: nil}}
  end

  # Mouse move during horizontal scrollbar drag
  def input_to_buffer_action(
        %State{
          scrollbar_drag: :x,
          scrollbar_drag_start: {start_x, _},
          scrollbar_drag_offset: start_offset,
          scroll: scroll
        } = state,
        {:cursor_pos, {x, _y}}
      ) do
    drag_delta = x - start_x

    {_track_start, track_length, content_size, viewport_size} =
      State.scrollbar_track_info(state, :x)

    new_offset_x =
      drag_offset(start_offset, drag_delta, track_length, content_size, viewport_size)

    new_scroll = %{scroll | offset_x: new_offset_x}

    {:local_update, %{state | scroll: new_scroll}}
  end

  # Mouse move during vertical scrollbar drag
  def input_to_buffer_action(
        %State{
          scrollbar_drag: :y,
          scrollbar_drag_start: {_, start_y},
          scrollbar_drag_offset: start_offset,
          scroll: scroll
        } = state,
        {:cursor_pos, {_x, y}}
      ) do
    drag_delta = y - start_y

    {_track_start, track_length, content_size, viewport_size} =
      State.scrollbar_track_info(state, :y)

    new_offset_y =
      drag_offset(start_offset, drag_delta, track_length, content_size, viewport_size)

    new_scroll = %{scroll | offset_y: new_offset_y}

    {:local_update, %{state | scroll: new_scroll}}
  end

  # Mouse click - check for scrollbar hit first, then focus
  def input_to_buffer_action(%State{} = state, {:cursor_button, {:btn_left, 1, _mods, coords}}) do
    hit_result = State.scrollbar_hit_test(state, coords)

    case hit_result do
      :x ->
        # Start horizontal scrollbar drag
        {:local_update,
         %{
           state
           | scrollbar_drag: :x,
             scrollbar_drag_start: coords,
             scrollbar_drag_offset: state.scroll.offset_x
         }}

      :y ->
        # Start vertical scrollbar drag
        {:local_update,
         %{
           state
           | scrollbar_drag: :y,
             scrollbar_drag_start: coords,
             scrollbar_drag_offset: state.scroll.offset_y
         }}

      nil ->
        # Not on scrollbar - handle focus, cursor positioning, double-click, and text drag.
        # In :store_backed mode the TextField receives every click in the
        # viewport (request_input is non-positional), so a click that visually
        # targets a sibling overlay (e.g. an IconMenu dropdown rendered above
        # the buffer pane) still arrives here with point_inside? = true. Drop
        # such clicks before they translate to a buffer cursor mutation.
        # (Regression origin: a host editor bug where a dropdown click corrupted the cursor.)
        if State.point_inside?(state, coords) and
             not store_backed_overlay_click?(state, coords) do
          # Convert click position to cursor line/col
          {line, col} = State.click_to_cursor(state, coords)
          click_pos = {line, col}
          now = System.monotonic_time(:millisecond)

          # Check for double-click
          is_double_click =
            case {state.last_click_time, state.last_click_pos} do
              {last_time, last_pos} when is_integer(last_time) and last_pos == click_pos ->
                now - last_time < @double_click_ms

              _ ->
                false
            end

          if is_double_click do
            # Double-click: select word at click position
            case State.word_boundaries_at(state, click_pos) do
              {start_col, end_col} ->
                new_state = %{
                  state
                  | focused: true,
                    text_drag: nil,
                    text_drag_start: nil,
                    last_click_time: nil,
                    last_click_pos: nil
                }

                # The range is given END first. A store's cursor sits at the
                # second position of a range — that is how a drag works, the
                # cursor following the pointer — so a word given start-to-end
                # left the cursor after the word, jumping it away from where
                # the user had just clicked. Given end-to-start the whole word
                # is still selected (stores normalise a reversed range, as
                # they must for a right-to-left drag) and the cursor sits at
                # the word's start, the nearer of its two ends to the click.
                {:double_click_select, new_state,
                 {:select_range, {line, end_col}, {line, start_col}}}

              nil ->
                # No word at position - just move cursor (treat as single click)
                new_state = %{
                  state
                  | focused: true,
                    text_drag: true,
                    text_drag_start: click_pos,
                    last_click_time: now,
                    last_click_pos: click_pos
                }

                {:click_move_cursor, new_state, {:set_cursor, click_pos}}
            end
          else
            # Single click: focus, start text drag for potential selection, and move cursor
            new_state = %{
              state
              | focused: true,
                text_drag: true,
                text_drag_start: click_pos,
                last_click_time: now,
                last_click_pos: click_pos
            }

            # Use :set_cursor for absolute positioning (not :move_cursor which is for relative movement)
            {:click_move_cursor, new_state, {:set_cursor, click_pos}}
          end
        else
          nil
        end
    end
  end

  # Mouse button release - end text drag
  def input_to_buffer_action(
        %State{text_drag: true} = state,
        {:cursor_button, {:btn_left, 0, _, _pos}}
      ) do
    {:local_update, %{state | text_drag: nil, text_drag_start: nil}}
  end

  # Mouse move during text drag - update selection
  def input_to_buffer_action(
        %State{text_drag: true, text_drag_start: start_pos} = state,
        {:cursor_pos, coords}
      )
      when start_pos != nil do
    # Convert current position to line/col
    {line, col} = State.click_to_cursor(state, coords)
    current_pos = {line, col}

    # Only update if position changed
    if current_pos != state.cursor do
      # Send selection action to buffer
      {:drag_select, %{state | cursor: current_pos}, {:select_range, start_pos, current_pos}}
    else
      nil
    end
  end

  # Scroll handling - local update
  # Format: {{dx, dy}, {x, y}} - delta tuple and position tuple
  def input_to_buffer_action(%State{} = state, {:cursor_scroll, {{dx, dy}, {_x, _y}}}) do
    case handle_scroll_input_smart(state, dx, dy) do
      {:noop, new_state} -> {:local_update, new_state}
      _ -> nil
    end
  end

  # Format: {dx, dy, x, y} - 4-element tuple
  def input_to_buffer_action(%State{} = state, {:cursor_scroll, {dx, dy, _x, _y}}) do
    case handle_scroll_input_smart(state, dx, dy) do
      {:noop, new_state} -> {:local_update, new_state}
      _ -> nil
    end
  end

  # Shift key tracking for shift+scroll horizontal scrolling (store_backed mode)
  def input_to_buffer_action(%State{scroll: scroll} = state, {:key, {:key_leftshift, 1, _}}) do
    {:local_update, %{state | scroll: set_scroll_shift(scroll, true)}}
  end

  def input_to_buffer_action(%State{scroll: scroll} = state, {:key, {:key_rightshift, 1, _}}) do
    {:local_update, %{state | scroll: set_scroll_shift(scroll, true)}}
  end

  def input_to_buffer_action(%State{scroll: scroll} = state, {:key, {:key_leftshift, 0, _}}) do
    {:local_update, %{state | scroll: set_scroll_shift(scroll, false)}}
  end

  def input_to_buffer_action(%State{scroll: scroll} = state, {:key, {:key_rightshift, 0, _}}) do
    {:local_update, %{state | scroll: set_scroll_shift(scroll, false)}}
  end

  # Fallback - unhandled input
  def input_to_buffer_action(_state, _input) do
    nil
  end

  defp vertical_buffer_action(state, step, direction, shift?) do
    if display_equals_source?(state) do
      if shift?, do: {:select_text, direction, 1}, else: {:move_cursor, direction, 1}
    else
      alias ScenicWidgets.TextField.Renderer

      {row, goal} =
        active_display(state) || Renderer.source_to_display_cursor(state, state.cursor)

      target_row = row + step
      in_document? = target_row >= 1 and target_row <= Renderer.display_row_count(state)

      {cursor, landed_row} =
        if in_document?,
          do: {display_target(state, target_row, goal), target_row},
          else: {state.cursor, row}

      # A host that has not implemented {:select_to, _} still gets correct
      # unshifted movement; see the store-backed contract in TextField's docs.
      tag = if shift?, do: :select_to, else: :set_cursor
      {:display_move, {cursor, {landed_row, goal}}, {tag, cursor}}
    end
  end

  # In :store_backed mode, treat clicks whose local coordinates land far past
  # the rendered text content of the clicked line as belonging to a sibling
  # overlay (e.g. IconMenu dropdown). See click handler comment above.
  # Tolerance of 4× font size past the line text width permits the usual
  # "click past end of line → place cursor at EOL" affordance.
  # Should this click be ignored because it was meant for an overlay?
  #
  # TextField requests :cursor_button non-positionally, so it also receives
  # clicks aimed at things rendered ABOVE it (an IconMenu dropdown, a
  # dialog). Acting on those moves the cursor in the document underneath.
  #
  # The host TELLS us when an overlay owns the pointer (`overlay_open`).
  # This replaces a geometric heuristic that dropped any click landing right
  # of the clicked line's text — which also killed every click on a short or
  # BLANK line (the empty lines between paragraphs), leaving that whitespace
  # dead to the mouse. Clicking past the end of a line now places the cursor
  # at end-of-line, as it should.
  # Rect form: ignore clicks inside the overlay's area only. NOTE for anyone
  # wiring this up — the rect must be in THIS component's local coordinate
  # space. Passing an overlay's own local bounds silently never matches, and
  # the clicks it was meant to suppress fall through to the document
  # (observed: menu clicks moving the cursor). Quillex passes `true` for that
  # reason; converting IconMenu's bounds into pane space is unfinished work.
  defp store_backed_overlay_click?(
         %State{overlay_open: %{x: x0, y: y0, width: w, height: h}},
         {x, y}
       ) do
    x >= x0 and x <= x0 + w and y >= y0 and y <= y0 + h
  end

  defp store_backed_overlay_click?(%State{overlay_open: true}, _coords), do: true

  # Nothing else suppresses a click. The geometric predecessor — "this landed
  # past the end of the clicked line's text, so it must have been meant for
  # something drawn above us" — used to live here, and it was still live for
  # store_backed hosts long after the `overlay_open` signal replaced it.
  #
  # What that cost: a click anywhere in the empty part of a document was
  # discarded, and with it the FOCUS that click should have granted. Click
  # below the last line of a file and the editor went dead to the keyboard —
  # which is most of the surface of most new files. Blank lines between
  # paragraphs were dead to the mouse for the same reason.
  #
  # Guessing from geometry cannot be made right: only the host knows whether
  # something is drawn over the pane, and the host already says so.
  defp store_backed_overlay_click?(%State{}, _coords), do: false

  # ===== SEARCH HELPER =====

  @doc """
  Finds all occurrences of a query string in the lines.
  Returns list of {line_num, col_num, matched_text} tuples.
  Line and column numbers are 1-based.
  """
  defp find_all_matches(lines, query, opts \\ []) when is_list(lines) and is_binary(query) do
    case search_pattern(query, opts) do
      {:literal, needle} ->
        lines
        # 1-based line numbers
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {line, line_num} ->
          find_matches_in_line(line, needle, String.length(needle), line_num, 1, [])
        end)

      {:regex, regex} ->
        lines
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {line, line_num} -> regex_matches_in_line(line, regex, line_num) end)

      :no_matches ->
        []
    end
  end

  # Case-insensitive literal search is done by lowering both sides, which is
  # only correct because the column is counted in graphemes of the LOWERED
  # line — and downcasing does not change how many graphemes a line has for
  # any script this editor claims to support.
  defp search_pattern(query, opts) do
    cond do
      Keyword.get(opts, :regex, false) ->
        flags = if Keyword.get(opts, :case_sensitive, false), do: "", else: "i"

        case Regex.compile(query, flags) do
          {:ok, regex} -> {:regex, regex}
          {:error, _} -> :no_matches
        end

      Keyword.get(opts, :case_sensitive, false) ->
        {:literal, query}

      true ->
        {:regex, Regex.compile!(Regex.escape(query), "i")}
    end
  end

  defp regex_matches_in_line(line, regex, line_num) do
    regex
    |> Regex.scan(line, return: :index)
    |> Enum.reject(fn [{_start, len} | _] -> len == 0 end)
    |> Enum.map(fn [{start, len} | _] ->
      prefix = binary_part(line, 0, start)
      matched = binary_part(line, start, len)
      {line_num, String.length(prefix) + 1, matched}
    end)
  end

  # Recursively find all matches in a single line
  defp find_matches_in_line(line, query, query_len, line_num, col, acc) do
    case :binary.match(line, query) do
      :nomatch ->
        Enum.reverse(acc)

      {start, _len} ->
        # Convert byte offset to grapheme column (1-based)
        prefix = binary_part(line, 0, start)
        grapheme_col = col + String.length(prefix)

        # Get matched text
        matched_text = String.slice(line, String.length(prefix), query_len)

        # Continue searching in remainder
        remainder_start = start + byte_size(query)
        remainder = binary_part(line, remainder_start, byte_size(line) - remainder_start)
        new_col = grapheme_col + query_len

        find_matches_in_line(remainder, query, query_len, line_num, new_col, [
          {line_num, grapheme_col, matched_text} | acc
        ])
    end
  end

  # ===== HELPER FUNCTIONS =====

  @doc """
  Insert character at cursor position.
  Handles newlines (\n) by splitting the current line.
  Automatically ensures cursor remains visible after insertion.
  """
  defp insert_char(%State{lines: lines, cursor: {line_num, col}} = state, "\n") do
    # Handle Enter key - split current line
    current_line = Enum.at(lines, line_num - 1, "")
    {before, after_cursor} = String.split_at(current_line, col - 1)

    new_lines =
      lines
      |> List.replace_at(line_num - 1, before)
      |> List.insert_at(line_num, after_cursor)

    new_state = %{
      state
      | lines: new_lines,
        cursor: {line_num + 1, 1},
        folds: reconcile_folds(state, new_lines)
    }

    new_state
    |> update_scroll_content_size()
    |> State.ensure_cursor_visible()
  end

  defp insert_char(%State{lines: lines, cursor: {line_num, col}} = state, char)
       when is_binary(char) do
    current_line = Enum.at(lines, line_num - 1, "")
    {before, after_cursor} = String.split_at(current_line, col - 1)
    new_line = before <> char <> after_cursor

    new_lines = List.replace_at(lines, line_num - 1, new_line)

    new_state = %{state | lines: new_lines, cursor: {line_num, col + 1}}

    new_state
    |> update_scroll_content_size()
    |> State.ensure_cursor_visible()
  end

  @doc """
  Delete character before cursor (Backspace).
  """
  defp delete_before_cursor(%State{cursor: {1, 1}} = state) do
    # At start of document - nothing to delete
    state
  end

  defp delete_before_cursor(%State{lines: lines, cursor: {line_num, 1}} = state) do
    # At start of line - join with previous line
    if line_num > 1 do
      prev_line = Enum.at(lines, line_num - 2)
      current_line = Enum.at(lines, line_num - 1)
      new_line = prev_line <> current_line

      new_lines =
        lines
        |> List.replace_at(line_num - 2, new_line)
        |> List.delete_at(line_num - 1)

      new_col = String.length(prev_line) + 1

      %{
        state
        | lines: new_lines,
          cursor: {line_num - 1, new_col},
          folds: reconcile_folds(state, new_lines)
      }
      |> update_scroll_content_size()
    else
      state
    end
  end

  defp delete_before_cursor(%State{lines: lines, cursor: {line_num, col}} = state) do
    # Delete character before cursor in current line
    current_line = Enum.at(lines, line_num - 1, "")
    {before, after_cursor} = String.split_at(current_line, col - 1)
    new_before = String.slice(before, 0..-2//1)
    new_line = new_before <> after_cursor

    new_lines = List.replace_at(lines, line_num - 1, new_line)

    %{state | lines: new_lines, cursor: {line_num, max(1, col - 1)}}
    |> update_scroll_content_size()
  end

  @doc """
  Delete character at cursor (Delete key).
  """
  defp delete_at_cursor(%State{lines: lines, cursor: {line_num, col}} = state) do
    current_line = Enum.at(lines, line_num - 1, "")

    if col > String.length(current_line) do
      # At end of line - join with next line
      if line_num < length(lines) do
        next_line = Enum.at(lines, line_num)
        new_line = current_line <> next_line

        new_lines =
          lines
          |> List.replace_at(line_num - 1, new_line)
          |> List.delete_at(line_num)

        %{state | lines: new_lines, folds: reconcile_folds(state, new_lines)}
        |> update_scroll_content_size()
      else
        state
      end
    else
      # Delete character at cursor
      {before, after_cursor} = String.split_at(current_line, col - 1)
      new_after = String.slice(after_cursor, 1..-1//1)
      new_line = before <> new_after

      new_lines = List.replace_at(lines, line_num - 1, new_line)

      %{state | lines: new_lines}
      |> update_scroll_content_size()
    end
  end

  @doc """
  Move cursor in specified direction.
  Automatically ensures cursor remains visible after movement.
  """
  defp move_cursor(%State{cursor: {line, col}, lines: lines} = state, :left) do
    new_state =
      if col > 1 do
        %{state | cursor: {line, col - 1}}
      else
        # At start of line - move to end of previous line
        if line > 1 do
          prev_line = Enum.at(lines, line - 2)
          %{state | cursor: {line - 1, String.length(prev_line) + 1}}
        else
          state
        end
      end

    State.ensure_cursor_visible(new_state)
  end

  defp move_cursor(%State{cursor: {line, col}, lines: lines} = state, :right) do
    current_line = Enum.at(lines, line - 1, "")

    new_state =
      if col <= String.length(current_line) do
        %{state | cursor: {line, col + 1}}
      else
        # At end of line - move to start of next line
        if line < length(lines) do
          %{state | cursor: {line + 1, 1}}
        else
          state
        end
      end

    State.ensure_cursor_visible(new_state)
  end

  # Vertical movement happens in DISPLAY space.
  #
  # With word wrap on, one source line is several visual rows, and "the line
  # above" means the row above — not the previous numbered line. The cursor is
  # still stored as a source position (that is what the buffer, undo and search
  # speak), so each move is source → display, step one row, display → source.
  #
  # The same is true of folds: the row above a fold summary is the header, not
  # whichever hidden line happens to precede it numerically.
  #
  # Precedent: scrolling was taught this in Phase 4b, when computing scroll
  # targets from source line numbers made the end of a wrapped document
  # unreachable. This is the same lesson applied to the cursor itself.
  defp move_cursor(%State{} = state, :up), do: move_display_row(state, -1)
  defp move_cursor(%State{} = state, :down), do: move_display_row(state, 1)

  defp move_display_row(%State{cursor: {line, col}, lines: lines} = state, step) do
    if display_equals_source?(state) do
      target = line + step

      {_row, goal} = active_display(state) || {line, col}

      new_state =
        if target >= 1 and target <= length(lines) do
          target_text = Enum.at(lines, target - 1, "")
          cursor = {target, min(goal, String.length(target_text) + 1)}
          %{state | cursor: cursor, goal_display_col: {cursor, {target, goal}}}
        else
          state
        end

      State.ensure_cursor_visible(new_state)
    else
      move_display_row_wrapped(state, step)
    end
  end

  defp move_display_row_wrapped(%State{cursor: cursor} = state, step) do
    alias ScenicWidgets.TextField.Renderer

    {row, goal} = active_display(state) || Renderer.source_to_display_cursor(state, cursor)
    target_row = row + step

    new_state =
      if target_row >= 1 and target_row <= Renderer.display_row_count(state) do
        new_cursor = display_target(state, target_row, goal)
        %{state | cursor: new_cursor, goal_display_col: {new_cursor, {target_row, goal}}}
      else
        %{state | goal_display_col: {cursor, {row, goal}}}
      end

    State.ensure_cursor_visible(new_state)
  end

  # Where a run of vertical moves believes it is: the display ROW as well as
  # the goal column, stored WITH the cursor they produced.
  #
  # The row matters as much as the column. A cursor sitting at a wrap boundary
  # is genuinely ambiguous — it is both the end of one visual row and the start
  # of the next — and re-deriving the row from the cursor picks the earlier
  # one, so a second Down would compute the same target and the cursor would
  # stop dead at the boundary. Remembering the row settles it.
  #
  # Storing the cursor alongside is what makes this self-invalidating: anything
  # else that moves the cursor — a click, a word jump, an edit — leaves the two
  # disagreeing and the goal is silently forgotten. That beats clearing it from
  # every one of those call sites and missing one.
  defp active_display(%State{goal_display_col: {cursor, row_col}, cursor: cursor}), do: row_col
  defp active_display(_state), do: nil

  defp display_target(state, target_row, goal) do
    alias ScenicWidgets.TextField.Renderer

    row_text = Renderer.display_row_text(state, target_row)
    clamped = min(goal, String.length(row_text) + 1)
    Renderer.display_to_source_cursor(state, {target_row, clamped})
  end

  # The fast path: with no wrapping and no folds, a display row IS a source
  # line, and projecting the whole document on every arrow key would be pure
  # waste.
  defp display_equals_source?(%State{wrap_mode: :none} = state),
    do: state.folds == nil or MapSet.size(state.folds) == 0

  defp display_equals_source?(_state), do: false

  defp move_cursor(%State{cursor: {line, _col}} = state, :line_start) do
    new_state = %{state | cursor: {line, 1}}
    State.ensure_cursor_visible(new_state)
  end

  defp move_cursor(%State{cursor: {line, _col}, lines: lines} = state, :line_end) do
    current_line = Enum.at(lines, line - 1, "")
    new_state = %{state | cursor: {line, String.length(current_line) + 1}}
    State.ensure_cursor_visible(new_state)
  end

  # ===== SELECTION HELPERS =====

  @doc """
  Move cursor with selection (Shift+Arrow).
  If no selection exists, start one at current cursor position.
  """
  defp move_cursor_with_selection(%State{selection: nil, cursor: cursor} = state, direction) do
    # Start selection at current cursor
    new_state = move_cursor(state, direction)
    %{new_state | selection: {cursor, new_state.cursor}}
  end

  defp move_cursor_with_selection(%State{selection: {anchor, _head}} = state, direction) do
    # Extend existing selection
    new_state = move_cursor(state, direction)
    %{new_state | selection: {anchor, new_state.cursor}}
  end

  @doc """
  Clear selection.
  """
  defp clear_selection(%State{} = state) do
    %{state | selection: nil}
  end

  @doc """
  Select all text in the document.
  """
  defp select_all(%State{lines: lines} = state) do
    last_line_num = length(lines)
    last_line = Enum.at(lines, last_line_num - 1, "")
    last_col = String.length(last_line) + 1

    %{state | selection: {{1, 1}, {last_line_num, last_col}}, cursor: {last_line_num, last_col}}
  end

  # Word boundaries are the ones the word-wise cursor movement uses: skip any
  # run of spaces, then the run of non-spaces. Deleting a word and stepping
  # over one therefore agree about where words begin.
  defp delete_word_before_cursor(%State{cursor: {line, col}} = state) do
    text = Enum.at(state.lines, line - 1, "")
    target = word_start(String.graphemes(text), col - 1) + 1

    if target == col do
      state
    else
      replace_span(state, line, target, col)
    end
  end

  defp delete_word_at_cursor(%State{cursor: {line, col}} = state) do
    text = Enum.at(state.lines, line - 1, "")
    target = word_end(String.graphemes(text), col - 1) + 1

    if target == col do
      state
    else
      replace_span(state, line, col, target)
    end
  end

  defp replace_span(%State{} = state, line, from_col, to_col) do
    text = Enum.at(state.lines, line - 1, "")
    before = String.slice(text, 0, from_col - 1)
    rest = String.slice(text, to_col - 1, String.length(text) - to_col + 1)

    %{
      state
      | lines: List.replace_at(state.lines, line - 1, before <> rest),
        cursor: {line, from_col},
        selection: nil
    }
  end

  defp word_start(graphemes, cursor) do
    cursor
    |> skip_left(graphemes, &(&1 == " "))
    |> skip_left(graphemes, &(&1 != " "))
  end

  defp skip_left(cursor, graphemes, condition) do
    if cursor > 0 and condition.(Enum.at(graphemes, cursor - 1)),
      do: skip_left(cursor - 1, graphemes, condition),
      else: cursor
  end

  defp word_end(graphemes, cursor) do
    cursor
    |> skip_right(graphemes, &(&1 != " "))
    |> skip_right(graphemes, &(&1 == " "))
  end

  defp skip_right(cursor, graphemes, condition) do
    if cursor < length(graphemes) and condition.(Enum.at(graphemes, cursor)),
      do: skip_right(cursor + 1, graphemes, condition),
      else: cursor
  end

  @doc """
  Delete selected text if any.
  Returns state with selection deleted and cursor at selection start.
  """
  defp delete_selection(%State{selection: nil} = state), do: state

  defp delete_selection(%State{selection: {start_pos, end_pos}} = state) do
    # Ensure start comes before end
    {start_pos, end_pos} = normalize_selection(start_pos, end_pos)
    {start_line, start_col} = start_pos
    {end_line, end_col} = end_pos

    cond do
      # Same position - nothing to delete
      start_pos == end_pos ->
        %{state | selection: nil}

      # Selection within single line
      start_line == end_line ->
        current_line = Enum.at(state.lines, start_line - 1, "")
        {before, rest} = String.split_at(current_line, start_col - 1)
        {_selected, after_sel} = String.split_at(rest, end_col - start_col)
        new_line = before <> after_sel

        new_lines = List.replace_at(state.lines, start_line - 1, new_line)

        %{
          state
          | lines: new_lines,
            cursor: start_pos,
            selection: nil,
            folds: reconcile_folds(state, new_lines)
        }

      # Multi-line selection
      true ->
        start_line_text = Enum.at(state.lines, start_line - 1, "")
        end_line_text = Enum.at(state.lines, end_line - 1, "")

        # Keep text before selection start and after selection end
        before = String.slice(start_line_text, 0, start_col - 1)
        after_sel = String.slice(end_line_text, end_col - 1, String.length(end_line_text))
        merged_line = before <> after_sel

        # Remove all lines in selection range and replace with merged line
        new_lines =
          state.lines
          |> Enum.with_index(1)
          |> Enum.reject(fn {_line, idx} -> idx > start_line and idx <= end_line end)
          |> Enum.map(fn {line, idx} ->
            if idx == start_line, do: merged_line, else: line
          end)

        %{
          state
          | lines: new_lines,
            cursor: start_pos,
            selection: nil,
            folds: reconcile_folds(state, new_lines)
        }
    end
  end

  @doc """
  Normalize selection so start comes before end.
  """
  defp normalize_selection({line1, col1} = pos1, {line2, col2} = pos2) do
    cond do
      line1 < line2 -> {pos1, pos2}
      line1 > line2 -> {pos2, pos1}
      col1 <= col2 -> {pos1, pos2}
      true -> {pos2, pos1}
    end
  end

  @doc """
  Get the currently selected text as a string.
  """
  defp get_selected_text(%State{selection: nil}), do: ""

  defp get_selected_text(%State{selection: {start_pos, end_pos}, lines: lines}) do
    {start_pos, end_pos} = normalize_selection(start_pos, end_pos)
    {start_line, start_col} = start_pos
    {end_line, end_col} = end_pos

    cond do
      # Same position - empty selection
      start_pos == end_pos ->
        ""

      # Single line selection
      start_line == end_line ->
        line = Enum.at(lines, start_line - 1, "")
        String.slice(line, start_col - 1, end_col - start_col)

      # Multi-line selection
      true ->
        lines
        |> Enum.with_index(1)
        |> Enum.filter(fn {_line, idx} -> idx >= start_line and idx <= end_line end)
        |> Enum.map(fn {line, idx} ->
          cond do
            idx == start_line ->
              String.slice(line, start_col - 1, String.length(line))

            idx == end_line ->
              String.slice(line, 0, end_col - 1)

            true ->
              line
          end
        end)
        |> Enum.join("\n")
    end
  end

  @doc """
  Insert text at cursor position (used for paste).
  Unlike insert_char which handles single characters, this handles multi-line strings
  efficiently in a single operation.
  Returns the final cursor position after all text is inserted.
  """
  defp insert_text_at_cursor(%State{lines: lines, cursor: {line, col}} = state, text)
       when is_binary(text) do
    paste_lines = String.split(text, "\n")

    case paste_lines do
      # Single line - simple insertion
      [single_line] ->
        current_line = Enum.at(lines, line - 1, "")
        {left_text, right_text} = String.split_at(current_line, col - 1)
        updated_line = left_text <> single_line <> right_text
        new_lines = List.replace_at(lines, line - 1, updated_line)
        final_col = col + String.length(single_line)

        new_state = %{
          state
          | lines: new_lines,
            cursor: {line, final_col},
            folds: reconcile_folds(state, new_lines)
        }

        State.ensure_cursor_visible(new_state)

      # Multiple lines - efficient batch insertion
      [first_line | rest] ->
        current_line = Enum.at(lines, line - 1, "")
        {left_text, right_text} = String.split_at(current_line, col - 1)

        # First line: left_text + first_line
        first_updated = left_text <> first_line

        # Last line: last_line + right_text
        {middle_lines, [last_line]} = Enum.split(rest, -1)
        last_updated = last_line <> right_text

        # Build the new lines list
        {before_lines, after_lines} = Enum.split(lines, line - 1)
        [_current | remaining_after] = after_lines

        # Combine all parts
        new_lines =
          before_lines ++ [first_updated] ++ middle_lines ++ [last_updated] ++ remaining_after

        # Calculate final cursor position
        final_line = line + length(paste_lines) - 1
        final_col = String.length(last_line) + 1

        new_state = %{
          state
          | lines: new_lines,
            cursor: {final_line, final_col},
            folds: reconcile_folds(state, new_lines)
        }

        State.ensure_cursor_visible(new_state)
    end
  end

  # ===== SCROLL HELPERS =====

  @doc """
  Handle scroll input with smart Shift+scroll support using the Scrollable macro functions.
  When Shift is held, vertical scrolling is converted to horizontal scrolling.
  """
  defp handle_scroll_input_smart(%State{scroll: scroll} = state, delta_x, delta_y) do
    # Negate deltas for natural scrolling (scroll down = content moves up)
    new_scroll = handle_scroll_smart(scroll, -delta_x, -delta_y)

    if scroll_changed?(scroll, new_scroll) do
      {:noop, State.advance_render_window(%{state | scroll: new_scroll})}
    else
      {:noop, state}
    end
  end

  @doc """
  Handle 2D scroll input using the Scrollable macro functions.
  Supports both vertical and horizontal scrolling based on scroll direction setting.
  """
  defp handle_scroll_input_2d(%State{scroll: scroll} = state, delta_x, delta_y) do
    # Negate deltas for natural scrolling (scroll down = content moves up)
    new_scroll = handle_scroll_2d(scroll, -delta_x, -delta_y)

    if scroll_changed?(scroll, new_scroll) do
      {:noop, State.advance_render_window(%{state | scroll: new_scroll})}
    else
      {:noop, state}
    end
  end

  @doc """
  Update scroll content size based on current wrapped line count and max line width.
  Should be called after text changes that affect line count or line length.
  """
  def update_scroll_content_size(%State{} = state) do
    state = ScenicWidgets.TextField.Renderer.prepare_display_cache(state)
    %State{lines: lines, scroll: scroll, wrap_mode: wrap_mode} = state
    line_height = State.line_height(state)

    visible_lines =
      ScenicWidgets.TextField.Folding.projection(lines, state.folds || MapSet.new())
      |> Enum.flat_map(fn
        {_line, text, 0} -> [text]
        {_line, text, count} -> [text, fold_summary_line(text, count, state.tab_width || 2)]
      end)

    # Calculate content dimensions based on wrap mode
    {content_width, display_line_count} =
      case wrap_mode do
        :none ->
          # No wrapping: content width is the widest line, height is line count
          {max_line_width, _longest_line, _longest_line_chars} =
            visible_lines
            |> Enum.with_index()
            |> Enum.map(fn {line, idx} ->
              {State.string_width(state, line), idx + 1, String.length(line)}
            end)
            |> Enum.max_by(fn {w, _, _} -> w end, fn -> {0, 0, 0} end)

          # Add padding for cursor at end of line
          content_w = max(scroll.viewport_width, max_line_width + 40)
          {content_w, length(visible_lines)}

        _wrap ->
          # Word/char wrapping: content fits the viewport width; the height is
          # the projected row count. Ask the display cache rather than
          # wrapping the document here and again at render time.
          {scroll.viewport_width, length(state.display_lines)}
      end

    # Add half line height of bottom padding so last line isn't jammed against frame edge
    bottom_padding = div(line_height, 2)
    content_height = display_line_count * line_height + bottom_padding

    new_scroll =
      Widgex.Scroll.ScrollState.update_content_size(scroll, content_width, content_height)

    # Update gutter width if line count changed significantly (different number of digits)
    %{state | scroll: new_scroll}
    |> State.maybe_update_gutter_width()
  end

  defp reconcile_folds(state, new_lines) do
    ScenicWidgets.TextField.Folding.reconcile_after_edit(
      state.folds || MapSet.new(),
      state.lines,
      new_lines
    )
  end

  defp fold_summary_line(text, count, tab_width) do
    leading =
      case Regex.run(~r/^[\t ]*/, text) do
        [indent] -> indent
        _ -> ""
      end

    leading <> String.duplicate(" ", tab_width) <> "… #{count} lines"
  end

  defp drag_offset(start_offset, pointer_delta, track_length, content_size, viewport_size) do
    thumb_length = ScrollController.thumb_length(track_length, content_size, viewport_size)
    max_offset = max(content_size - viewport_size, 0)

    ScrollController.drag_offset(
      start_offset,
      pointer_delta,
      track_length,
      thumb_length,
      max_offset
    )
  end
end
