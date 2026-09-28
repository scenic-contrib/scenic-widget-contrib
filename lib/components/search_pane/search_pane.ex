defmodule ScenicWidgets.SearchPane do
  @moduledoc """
  A project-search pane: query and replacement fields over a
  scrollable list of matches grouped by file.

  It is generic over its data the way `SideNav` and `TabBar` are. The pane
  owns the three text fields and everything about how results are *presented*
  — which files are collapsed, what the pointer is over, where the scroll sits.
  It owns nothing about what a search *means*: the parent supplies results and
  performs every action the pane asks for.

  ## Data

      %{
        frame: %Widgex.Frame{},
        theme: %{},              # optional, merged over State.default_theme/0
        query: "needle",         # optional initial field contents
        replace: "",
        model: %{
          status: :idle | :searching | {:done, matches, files, ms} | {:error, term},
          error: nil | String.t(),          # e.g. a regex that does not compile
          case_sensitive: boolean(),
          regex: boolean(),
          scope: [scope_node],
          files: [file_group]
        }
      }

      scope_node: %{id: term, label: String.t(), included?: boolean(), children: [scope_node]}
      file_group: %{path: term, label: String.t(), matches: [match]}
      match:      %{line: pos_integer(), col: pos_integer(), text: String.t(),
                    match_start: non_neg_integer(), match_len: non_neg_integer()}

  `match_start` is a 0-based grapheme offset into `text`. Keeping it — rather
  than handing over a pre-flattened string — is what lets a row mark the
  matched text inside the line.

  ## Events

  All events are `{:search_pane, ...}` tuples sent to the parent scene:

  - `{:search_pane, :close}`
  - `{:search_pane, :query_changed, query}`
  - `{:search_pane, :toggle_option, :case_sensitive | :regex}`
  - `{:search_pane, :toggle_scope, id}`
  - `{:search_pane, :open_match, path, line, col}`
  - `{:search_pane, :dismiss_match, path, line, col}`
  - `{:search_pane, :dismiss_file, path}`
  - `{:search_pane, :replace_match, path, line, col, replacement}`
  - `{:search_pane, :replace_file, path, replacement}`
  - `{:search_pane, :replace_all, replacement}`

  ## Messages in

  - `{:update_model, model}` — new results, status or options
  - `{:update_frame, frame}`
  - `{:set_query, query}` — set the query field from outside (e.g. the word
    under the cursor when the pane is opened)
  - `{:focus_field, :query | :replace}`
  - `{:set_theme, theme}` — repaint, merging over the current theme
  - `:focus` / `:blur` — keyboard focus, granted by the parent
  """

  # It has children now: its two editable fields are TextFields. Declared
  # false, Scenic takes the graph's component primitives at their word and
  # simply never starts them — the fields appear in the graph, are never
  # instantiated, and every keystroke goes nowhere.
  use Scenic.Component, has_children: true
  require Logger

  alias ScenicWidgets.SearchPane.{Renderizer, State}
  alias Widgex.Scroll.Drag
  alias ScenicWidgets.Menu.{Dropdown, Model}
  alias Widgex.Scroll.{ScrollReducer, ScrollState}

  @key_pressed 1

  @impl Scenic.Component
  def validate(%{frame: %{pin: _, size: _}} = data), do: {:ok, data}
  def validate(_data), do: {:error, "SearchPane requires :frame"}

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    state = State.new(data)
    graph = Renderizer.render(state)

    scene =
      scene
      |> assign(state: state, graph: graph, id: :search_pane, settings_leave_timer: nil)
      |> push_graph(graph)

    # Keyboard for the fields, scroll for the results. Clicks arrive through
    # the background primitive's `input:` list — requesting :cursor_button here
    # as well would deliver every press twice.
    request_input(scene, [:key, :codepoint, :cursor_scroll])
    register_semantic_elements(scene, state)

    {:ok, scene}
  end

  # ── Messages from the parent ──────────────────────────────────────────────

  @doc """
  New params from the parent's graph.

  Defining this at all is the point: without it Scenic re-runs `init/3` on the
  same process, which re-requests keyboard input and re-seeds the fields — the
  observed symptom was every character arriving twice, and the query field
  reading "needleneedle".

  The fields are deliberately NOT taken from the params. The pane owns them;
  the parent seeds them once at creation and sets them explicitly afterwards
  with `{:set_query, _}`.
  """
  @impl Scenic.Scene
  def handle_update(data, _opts, scene) do
    state =
      scene.assigns.state
      |> State.put_model(Map.get(data, :model, %{}))
      |> State.put_frame(data.frame)

    {:ok, redraw(scene, state)}
  end

  @impl Scenic.Scene
  def handle_put({:update_model, model}, scene) do
    {:noreply, redraw(scene, State.put_model(scene.assigns.state, model))}
  end

  def handle_put({:update_frame, frame}, scene) do
    {:noreply, redraw(scene, State.put_frame(scene.assigns.state, frame))}
  end

  def handle_put({:set_theme, theme}, scene) when is_map(theme) do
    state = scene.assigns.state

    {:noreply,
     redraw(scene, State.resync_scroll(%{state | theme: Map.merge(state.theme, theme)}))}
  end

  # Seeded from outside — the word under the cursor, or the last thing
  # searched for. The field shows it SELECTED so the next character typed
  # replaces it, rather than appending to a guess you then have to notice and
  # delete.
  # An echo of what the field already holds is not a new query. The host
  # mirrors the store's query back to the pane so that a search set off from
  # anywhere else shows up here — but the pane is usually where it came from,
  # and re-seeding on every keystroke would select the text just typed and
  # let the next character replace it. Which is a field that only ever holds
  # one letter.
  def handle_put({:set_query, query}, %{assigns: %{state: %State{query: query}}} = scene),
    do: {:noreply, scene}

  def handle_put({:set_query, query}, scene) do
    state = scene.assigns.state
    Scenic.Scene.put_child(scene, Renderizer.field_id(:query), {:seed_text, query})

    new_state = %{state | query: query, focused_field: :query}

    {:noreply, redraw(scene, new_state)}
  end

  def handle_put({:focus_field, field}, scene) do
    state = State.focus_field(scene.assigns.state, field)
    {:noreply, focus_fields(redraw(scene, state), state)}
  end

  # The parent gives the pane the keyboard; the pane hands it to whichever of
  # its fields is current. Both halves are needed: the fields gate on their own
  # flags, so a pane that is blurred while a field still thinks it is focused
  # would go on eating every keystroke meant for the editor.
  def handle_put(:focus, scene) do
    state = %{scene.assigns.state | focused: true}
    {:noreply, focus_fields(redraw(scene, state), state)}
  end

  def handle_put(:blur, scene) do
    state = %{scene.assigns.state | focused: false}
    {:noreply, focus_fields(redraw(scene, state), state)}
  end

  def handle_put(_value, scene), do: {:noreply, scene}

  # ── Input ─────────────────────────────────────────────────────────────────

  @impl Scenic.Scene
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

  # The scrollbar, BEFORE the catch-all that treats every left click as a click
  # on the pane. Routed by the id ScrollRenderer gave the primitive, the way
  # SideNav routes its own — these clauses were simply absent, so every press
  # on the pane's bar fell through to `route_input/3`, found no row under it
  # and was dropped. The bar could be looked at and not moved.
  #
  # By the BODY's group id, not by the shape of the tuple: the settings panel
  # draws a bar of its own, through the same renderer and so under the same
  # kind of id, and it moves a different number. Matched loosely, pressing the
  # panel's bar dragged the results out from under it.
  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, at}},
        {:scrollbar_y_thumb, :search_pane},
        scene
      ),
      do: grab_scrollbar(scene, :y, at)

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, at}},
        {:scrollbar_x_thumb, :search_pane},
        scene
      ),
      do: grab_scrollbar(scene, :x, at)

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, {_x, y}}},
        {:scrollbar_y_track, :search_pane},
        scene
      ),
      do: page_scrollbar(scene, :y, y)

  def handle_input(
        {:cursor_button, {:btn_left, 1, _mods, {x, _y}}},
        {:scrollbar_x_track, :search_pane},
        scene
      ),
      do: page_scrollbar(scene, :x, x)

  # While a drag is on, the pointer belongs to the bar and nothing else — the
  # input is captured, so this sees moves from anywhere on the screen.
  def handle_input({:cursor_pos, {_x, y} = at}, _context, %{assigns: %{state: state}} = scene) do
    cond do
      Drag.dragging?(state) ->
        {:noreply, redraw(scene, Drag.move(state, State.body_frame(state), at))}

      # The settings panel's bar has its own drag: it moves a different number
      # (the panel's offset, not the results'), and `Widgex.Scroll.Drag` moves
      # whatever is in `state.scroll`, which is the results.
      state.settings_drag ->
        {start_y, start_offset} = state.settings_drag
        scrolled = Dropdown.drag(State.settings_layout(state), start_offset, y - start_y)
        {:noreply, redraw(scene, %{state | settings_scroll: scrolled})}

      true ->
        route_input({:cursor_pos, at}, nil, scene)
    end
  end

  def handle_input(
        {:cursor_button, {:btn_left, 0, _mods, _at}},
        _context,
        %{assigns: %{state: state}} = scene
      ) do
    cond do
      Drag.dragging?(state) ->
        :ok = release_input(scene, [:cursor_pos, :cursor_button])
        {:noreply, assign(scene, state: Drag.stop(state))}

      state.settings_drag ->
        :ok = release_input(scene, [:cursor_pos, :cursor_button])
        {:noreply, assign(scene, state: %{state | settings_drag: nil})}

      true ->
        {:noreply, scene}
    end
  end

  def handle_input(input, context, scene), do: route_input(input, context, scene)

  defp grab_scrollbar(scene, axis, at) do
    :ok = capture_input(scene, [:cursor_pos, :cursor_button])
    {:noreply, assign(scene, state: Drag.start(scene.assigns.state, axis, at))}
  end

  defp page_scrollbar(scene, axis, pointer) do
    state = scene.assigns.state
    {:noreply, redraw(scene, Drag.page(state, State.body_frame(state), axis, pointer))}
  end

  # Escape puts away one thing: the settings if they are open, the pane if they
  # are not. Shutting the whole pane because a menu happened to be open throws
  # away the search as well as the menu.
  defp route_input({:key, {:key_esc, 1, _mods}}, _context, %{assigns: %{state: state}} = scene) do
    cond do
      state.domain_open? ->
        {:noreply, close_settings(scene, state)}

      true ->
        send_parent_event(scene, {:search_pane, :close})
        {:noreply, scene}
    end
  end

  defp route_input({:cursor_button, {:btn_left, 1, _mods, coords}}, _context, scene) do
    click(scene, coords)
  end

  defp route_input({:cursor_pos, coords}, _context, scene) do
    hover(scene, coords)
  end

  # Scenic reports the wheel in two shapes depending on driver; both mean the
  # same thing here.
  defp route_input({:cursor_scroll, {{_dx, dy}, {x, y}}}, _context, scene),
    do: wheel(scene, dy, {x, y})

  defp route_input({:cursor_scroll, {_dx, dy, x, y}}, _context, scene),
    do: wheel(scene, dy, {x, y})

  # The keyboard belongs to the fields, and they are TextFields now — they
  # gate on their own focus flag and report what happened. Everything this
  # pane used to reimplement (a cursor, backspace, word deletion, Home and
  # End) it now simply has, along with selection and the clipboard, which it
  # never had at all.
  defp route_input(_input, _context, scene), do: {:noreply, scene}

  # ── Events from the fields ────────────────────────────────────────────────

  @impl Scenic.Scene
  def handle_event({:text_changed, id, text}, _from, scene) do
    state = State.put_field_value(scene.assigns.state, field_of(id), text)
    {:noreply, scene |> assign(state: state) |> announce_field(field_of(id), state)}
  end

  # Enter in the replacement field means "replace everything", the only
  # destructive thing the pane can do from the keyboard. From the query field
  # it means nothing, because the search already ran as it was typed.
  def handle_event({:enter_pressed, id, _text}, _from, scene) do
    if field_of(id) == :replace do
      state = scene.assigns.state
      send_parent_event(scene, {:search_pane, :replace_all, state.replace})
      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  # Escape is handled ONCE, in route_input/3 below, because the pane asks
  # Scenic for :key itself and so hears about it whatever has focus. A field
  # reports it too — but only while it has the keyboard, and by the time you
  # have been clicking around a menu it does not. Acting on both would close
  # the menu and then the pane, on one press.
  def handle_event({:escape_pressed, _id}, _from, scene), do: {:noreply, scene}

  # Tab cycles between the fields — when there are two. With the replacement
  # row shut there is only the query, and moving focus to a field that has not
  # been built would hand the keyboard to nothing at all.
  def handle_event(
        {:tab_pressed, _id, _shift?},
        _from,
        %{assigns: %{state: %State{replace_open?: false}}} = scene
      ),
      do: {:noreply, scene}

  def handle_event({:tab_pressed, _id, shift?}, _from, scene) do
    state = scene.assigns.state
    next = if shift?, do: State.prev_field(state), else: State.next_field(state)
    {:noreply, focus_fields(redraw(scene, next), next)}
  end

  # A click in a field gives it the keyboard; the pane's job is to take it off
  # the other one, and to remember which is current for Tab.
  def handle_event({:focus_taken, id}, _from, scene)
      when id in [:search_pane_query_field, :search_pane_replace_field] do
    state = State.focus_field(scene.assigns.state, field_of(id))
    {:noreply, focus_fields(redraw(scene, state), state)}
  end

  def handle_event(_event, _from, scene), do: {:noreply, scene}

  # A resize or a theme change moves and recolours the fields. They are told,
  # rather than redrawn: dragging the sidebar divider delivers a new frame on
  # every mouse move, and recreating a component that often would throw away
  # its cursor and its selection sixty times a second.
  defp reframe_fields(scene, %State{} = old_state, %State{} = new_state) do
    if old_state.frame != new_state.frame or old_state.theme != new_state.theme do
      for field <- State.fields(),
          settings = Renderizer.field_settings(new_state, field),
          settings != nil do
        Scenic.Scene.put_child(scene, Renderizer.field_id(field), {:update_settings, settings})
      end
    end

    :ok
  end

  defp field_of(:search_pane_query_field), do: :query
  defp field_of(:search_pane_replace_field), do: :replace

  # Exactly one field holds the keyboard, and only while the pane itself has
  # it. Told rather than derived, so a field cannot keep the keyboard after
  # the parent has taken it off the pane.
  defp focus_fields(scene, %State{} = state) do
    for field <- State.fields() do
      focus? = state.focused and state.focused_field == field

      Scenic.Scene.put_child(
        scene,
        Renderizer.field_id(field),
        if(focus?, do: :focus, else: :blur)
      )
    end

    scene
  end

  defp wheel(scene, dy, {x, y}) do
    state = scene.assigns.state

    cond do
      # The wheel belongs to whatever is under it, and the settings panel is
      # drawn over the results — so a panel with more in it than it can show
      # scrolls, rather than the results sliding about behind it.
      state.domain_open? and over_settings?(state, {x, y}) ->
        {:noreply, redraw(scene, State.scroll_settings(state, dy))}

      # And scrolling ANYWHERE ELSE puts it away. Scrolling the thing behind a
      # menu is a person having finished with the menu; leaving it open means
      # it hangs over what they are now reading.
      state.domain_open? ->
        {:noreply, close_settings(scene, state)}

      true ->
        wheel_body(scene, state, dy, {x, y})
    end
  end

  defp over_settings?(state, {x, y}) do
    panel = State.settings_frame(state)
    {px, py} = panel.pin.point

    x >= px and x <= px + panel.size.width and y >= py and y <= py + panel.size.height
  end

  defp wheel_body(scene, state, dy, {x, y}) do
    if inside_frame?(state, {x, y}) do
      # NEGATED, the way SideNav negates it: a wheel turned down means the
      # content moves up. Unnegated, the pane in the sidebar scrolled the
      # opposite way to the file navigator directly above it in the same
      # sidebar — which is only invisible while the results fit on one screen.
      new_state = %{state | scroll: ScrollReducer.handle_wheel(state.scroll, -dy)}
      graph = Renderizer.scroll_to(scene.assigns.graph, state, new_state)

      scene = scene |> assign(state: new_state, graph: graph) |> push_graph(graph)
      register_semantic_elements(scene, new_state)
      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  # A field's contents changed: tell the parent, but only for the query. The
  # replacement is carried on the action instead — it must not re-run anything
  # by being typed.
  defp announce_field(scene, :query, %State{} = state) do
    send_parent_event(scene, {:search_pane, :query_changed, state.query})
    scene
  end

  defp announce_field(scene, _field, _state), do: scene

  # ── Pointer ───────────────────────────────────────────────────────────────

  defp click(scene, coords) do
    state = scene.assigns.state
    hit = State.hit_test(state, coords)

    # An open menu closes when you click away from it — including on a result,
    # which then does its own job as well. Only the cog is exempt, because it
    # is the toggle and would otherwise close and reopen on one click.
    scene =
      if state.domain_open? and dismisses_settings?(hit),
        do: close_settings(scene, state),
        else: scene

    state = scene.assigns.state

    case hit do
      nil ->
        {:noreply, scene}

      :close ->
        send_parent_event(scene, {:search_pane, :close})
        {:noreply, scene}

      :status ->
        {:noreply, scene}

      :replace_all ->
        send_parent_event(scene, {:search_pane, :replace_all, state.replace})
        {:noreply, scene}

      {:field, field} ->
        # Clicking a field means the keyboard belongs to this pane now. The
        # host is the only thing that can take it off the editor, and the
        # click never reaches the host — so tell it.
        unless state.focused, do: send_parent_event(scene, {:focus_taken, :project_search_pane})

        # The field itself handles placing the caret — it gets the click too,
        # and reports back with {:focus_taken, id}. All this has to do is
        # remember which field Tab should move on from.
        new_state = State.focus_field(state, field)
        {:noreply, focus_fields(redraw(scene, new_state), new_state)}

      {:toggle, option} ->
        send_parent_event(scene, {:search_pane, :toggle_option, option})
        {:noreply, scene}

      # Clearing is the START of a search, not the end of one, so the keyboard
      # belongs back in the query field afterwards. Without this the × emptied
      # the box and took the keyboard with it: the next thing typed went
      # nowhere at all, and the pane sat there saying "Type to search the
      # project" while somebody did exactly that.
      :clear ->
        send_parent_event(scene, {:search_pane, :clear})
        new_state = State.focus_field(state, :query)
        {:noreply, focus_fields(redraw(scene, new_state), new_state)}

      :edit_excludes ->
        send_parent_event(scene, {:search_pane, :edit_excludes})
        {:noreply, scene}

      :replace_one ->
        send_parent_event(scene, {:search_pane, :replace_one, state.replace})
        {:noreply, scene}

      :previous_match ->
        send_parent_event(scene, {:search_pane, :previous_match})
        {:noreply, scene}

      :next_match ->
        send_parent_event(scene, {:search_pane, :next_match})
        {:noreply, scene}

      # A scope row in the header: the summary line opens the tree, a node
      # with children expands, and anything else ticks or unticks.
      {:scope_row, :scope_header} ->
        {:noreply, redraw(scene, State.toggle_scope_open(state))}

      # The triangle expands. Nothing else does, and it does nothing else.
      {:scope_expand, {:scope, path}} ->
        {:noreply, redraw(scene, State.toggle_scope_expand(state, path))}

      # And the row TICKS — always, whether or not the directory has anything
      # in it. This used to expand instead whenever the node had children,
      # which meant no directory you would ever want to exclude could be
      # excluded.
      {:scope_row, {:scope, path}} ->
        send_parent_event(scene, {:search_pane, :toggle_scope, path})
        {:noreply, scene}

      :replace_caret ->
        {:noreply, redraw(scene, %{state | replace_open?: not state.replace_open?})}

      # The cog. A panel always opens at its top: reopening one where the last
      # visit left it would hide the first settings behind an offset nobody
      # asked for.
      :domain_header ->
        open? = not state.domain_open?
        send_parent_event(scene, {:search_pane, :settings_open, open?})

        {:noreply,
         redraw(scene, %{
           state
           | domain_open?: open?,
             settings_scroll: 0,
             settings_drag: nil
         })}

      # The panel's own background: clicking the gaps between its options is
      # not a request to close it.
      :settings_panel ->
        {:noreply, scene}

      # The panel's bar. Pressing the thumb starts a drag and CAPTURES the
      # pointer, so the rest of it arrives here however far off the panel the
      # hand wanders; pressing the empty track pages, once, with no drag.
      {:settings_scrollbar, :thumb} ->
        :ok = capture_input(scene, [:cursor_pos, :cursor_button])
        {_x, y} = coords
        {:noreply, assign(scene, state: %{state | settings_drag: {y, state.settings_scroll}})}

      {:settings_scrollbar, {:track, along}} ->
        scrolled = Dropdown.page(State.settings_layout(state), along)
        {:noreply, redraw(scene, %{state | settings_scroll: scrolled})}

      {:settings_row, row_id, local} ->
        settings_click(scene, state, row_id, local)

      {:domain, option} ->
        send_parent_event(scene, {:search_pane, :toggle_option, option})
        {:noreply, scene}

      {:row, row, nil} ->
        row_click(scene, state, row)

      # The triangle on a RESULTS row opens and shuts the same thing its row
      # does, so it needs no separate meaning. Only the scope tree's triangle
      # is a second control, because there the row itself ticks.
      {:row, %{kind: kind} = row, :expand} when kind in [:dir, :file] ->
        {:noreply, redraw(scene, State.toggle_file(state, row.path))}

      {:row, row, :expand} ->
        {:noreply, redraw(scene, State.toggle_scope_expand(state, row.path))}

      {:row, _row, action} ->
        act(scene, state, action)
    end
  end

  # A row in the settings panel. The two switches and the excludes link mean
  # what they always meant; the scope tree is a Menu.Model.Tree now, so where
  # inside it the click landed is worked out by the same module that drew it.
  # What the pointer is over inside the panel: the row, and for the scope tree
  # the node within it — a tree is one menu ROW holding many, so lighting the
  # row would light the whole tree.
  defp settings_hover_target(state, :scope, local) do
    tree = Enum.find(State.settings_rows(state), &match?(%Model.Tree{}, &1))

    case Dropdown.tree_hit(tree, local, State.dropdown_theme(state)) do
      {_action, node_id} -> {:settings, :scope, node_id}
      _header_or_nil -> {:settings, :scope, nil}
    end
  end

  defp settings_hover_target(_state, row_id, _local), do: {:settings, row_id, nil}

  defp settings_click(scene, state, :results_view, local) do
    seg = Enum.find(State.settings_rows(state), &match?(%Model.Segmented{id: :results_view}, &1))
    width = Map.fetch!(State.settings_row_bounds(state), :results_view).width

    case Dropdown.segmented_hit(seg, local, width, State.dropdown_theme(state)) do
      nil ->
        next = seg |> Model.segments() |> Enum.map(&elem(&1, 0)) |> Enum.find(&(&1 != seg.value))
        send_parent_event(scene, {:search_pane, :set_results_view, next})
        {:noreply, scene}

      value when value == seg.value ->
        {:noreply, scene}

      value ->
        send_parent_event(scene, {:search_pane, :set_results_view, value})
        {:noreply, scene}
    end
  end

  defp settings_click(scene, _state, {:domain, option}, _local) do
    send_parent_event(scene, {:search_pane, :toggle_option, option})
    {:noreply, scene}
  end

  defp settings_click(scene, _state, :edit_excludes, _local) do
    send_parent_event(scene, {:search_pane, :edit_excludes})
    {:noreply, scene}
  end

  defp settings_click(scene, state, :scope, local) do
    tree = Enum.find(State.settings_rows(state), &match?(%Model.Tree{}, &1))

    case Dropdown.tree_hit(tree, local, State.dropdown_theme(state)) do
      :header ->
        {:noreply, redraw(scene, State.toggle_scope_open(state))}

      {:expand, node_id} ->
        {:noreply, redraw(scene, State.toggle_scope_expand(state, node_id))}

      {:tick, node_id} ->
        send_parent_event(scene, {:search_pane, :toggle_scope, node_id})
        {:noreply, scene}

      nil ->
        {:noreply, scene}
    end
  end

  defp settings_click(scene, _state, _row_id, _local), do: {:noreply, scene}

  defp dismisses_settings?({:settings_row, _, _}), do: false
  defp dismisses_settings?({:settings_scrollbar, _}), do: false
  defp dismisses_settings?(:settings_panel), do: false
  defp dismisses_settings?(:domain_header), do: false
  defp dismisses_settings?({:domain, _}), do: false
  defp dismisses_settings?({:scope_row, _}), do: false
  defp dismisses_settings?({:scope_expand, _}), do: false
  defp dismisses_settings?(:edit_excludes), do: false
  defp dismisses_settings?(_hit), do: true

  defp close_settings(scene, state) do
    send_parent_event(scene, {:search_pane, :settings_open, false})
    scene |> cancel_settings_leave() |> redraw(%{state | domain_open?: false})
  end

  defp row_click(scene, state, %{kind: :scope_header}),
    do: {:noreply, redraw(scene, State.toggle_scope_open(state))}

  # A scope row is a checkbox with a disclosure triangle sharing one line: the
  # left edge expands, the rest ticks. Clicking the label to toggle inclusion
  # is the common case, so it gets the larger target.
  defp row_click(scene, _state, %{kind: :scope} = row) do
    send_parent_event(scene, {:search_pane, :toggle_scope, row.path})
    {:noreply, scene}
  end

  # A directory and a file both shut and open the same way, and both are keyed
  # by their path — `collapsed_files` is a set of paths, and a directory has
  # one too.
  defp row_click(scene, state, %{kind: :dir} = row),
    do: {:noreply, redraw(scene, State.toggle_file(state, row.path))}

  defp row_click(scene, state, %{kind: :file} = row),
    do: {:noreply, redraw(scene, State.toggle_file(state, row.path))}

  defp row_click(scene, _state, %{kind: :match} = row) do
    send_parent_event(scene, {:search_pane, :open_match, row.path, row.line, row.col})
    {:noreply, scene}
  end

  defp act(scene, state, {:replace_file, path}) do
    send_parent_event(scene, {:search_pane, :replace_file, path, state.replace})
    {:noreply, scene}
  end

  defp act(scene, state, {:replace_match, path, line, col}) do
    send_parent_event(scene, {:search_pane, :replace_match, path, line, col, state.replace})
    {:noreply, scene}
  end

  defp act(scene, _state, {:dismiss_file, path}) do
    send_parent_event(scene, {:search_pane, :dismiss_file, path})
    {:noreply, scene}
  end

  defp act(scene, _state, {:dismiss_match, path, line, col}) do
    send_parent_event(scene, {:search_pane, :dismiss_match, path, line, col})
    {:noreply, scene}
  end

  defp hover(scene, coords) do
    state = scene.assigns.state

    scene = track_settings_leave(scene, state, coords)
    # Header controls light up under the pointer too. A button that gives no
    # sign it is a button is one people click twice to check.
    hovered =
      case State.hit_test(state, coords) do
        {:row, row, action} ->
          action || row.id

        # A row of the settings panel. Kept as the ROW's id (and, in the scope
        # tree, the NODE under the pointer) and never the pointer position, or
        # every pixel of movement would be a different hover and a redraw with
        # it.
        {:settings_row, row_id, local} ->
          settings_hover_target(state, row_id, local)

        id
        when id in [:close, :replace_caret, :replace_all, :replace_one, :clear, :edit_excludes] ->
          id

        :results_view ->
          :results_view

        :domain_header ->
          :domain_header

        _other ->
          nil
      end

    if hovered == state.hovered do
      {:noreply, scene}
    else
      {:noreply, redraw(scene, %{state | hovered: hovered})}
    end
  end

  defp track_settings_leave(scene, %State{domain_open?: false}, _coords), do: scene

  defp track_settings_leave(scene, state, coords) do
    cond do
      over_settings?(state, coords) ->
        cancel_settings_leave(scene)

      scene.assigns.settings_leave_timer ->
        scene

      true ->
        timer = Process.send_after(self(), :close_settings_after_leave, 220)
        assign(scene, settings_leave_timer: timer)
    end
  end

  defp cancel_settings_leave(scene) do
    if timer = scene.assigns.settings_leave_timer, do: Process.cancel_timer(timer)
    assign(scene, settings_leave_timer: nil)
  end

  @impl Scenic.Scene
  def handle_info(:close_settings_after_leave, scene) do
    state = scene.assigns.state
    scene = assign(scene, settings_leave_timer: nil)

    if state.domain_open?,
      do: {:noreply, close_settings(scene, state)},
      else: {:noreply, scene}
  end

  # Requested positional input arrives already transformed into this
  # component's LOCAL coordinates — the same space `State.hit_test/2` works
  # in, which is why clicking a row works at all. It was compared against the
  # frame's PIN, which is expressed in the parent's space: with the pane
  # pinned below the top bar, that quietly refused the wheel over its
  # top-most rows and accepted nothing past its bottom edge.
  defp inside_frame?(%State{frame: frame}, {x, y}) do
    x >= 0 and x <= frame.size.width and y >= 0 and y <= frame.size.height
  end

  # ── Plumbing ──────────────────────────────────────────────────────────────

  # Only what changed. The pane holds child components now, and a graph built
  # from scratch would take them with it on every keystroke.
  defp redraw(scene, state) do
    old_state = scene.assigns.state

    # Opening or closing the replacement row changes which FIELDS exist, and a
    # field is a component: it has to be built, not drawn. That is the one
    # case that rebuilds from nothing.
    if old_state.replace_open? != state.replace_open? do
      graph = Renderizer.render(state)
      scene = scene |> assign(state: state, graph: graph) |> push_graph(graph)
      register_semantic_elements(scene, state)

      # Both fields are new processes, and a new field does not know whether
      # it has the keyboard. Without this the pane looks focused and answers
      # to nothing.
      focus_fields(scene, state)
    else
      do_redraw(scene, old_state, state)
    end
  end

  defp do_redraw(scene, old_state, state) do
    graph = Renderizer.update_render(scene.assigns.graph, old_state, state)
    reframe_fields(scene, old_state, state)

    scene = scene |> assign(state: state, graph: graph) |> push_graph(graph)
    register_semantic_elements(scene, state)
    scene
  end

  defp settings_semantics(%State{domain_open?: false}), do: []

  defp settings_semantics(%State{} = state) do
    rows = State.settings_rows(state)
    layout = State.settings_layout(state)
    bounds = layout.items
    theme = State.dropdown_theme(state)

    # Only what is on show. The panel clamps to the room under the cog and
    # scrolls, so it lays out rows above and below its own edges — publishing
    # those offers a name for something that is not there, and a click by that
    # name lands on the document behind the pane.
    visible? = &Dropdown.visible?(layout, &1)

    Enum.flat_map(rows, fn row ->
      b = Map.fetch!(bounds, Model.get_item_id(row))

      case row do
        %Model.Tree{} = tree ->
          header = %{b | height: theme.dropdown_item_height}

          if(visible?.(header),
            do: [
              {:search_pane_scope, b.x, b.y, b.width, theme.dropdown_item_height, "Search scope"}
            ],
            else: []
          ) ++
            (Dropdown.tree_node_bounds(tree, b, theme)
             |> Enum.filter(fn {_node, nb} -> visible?.(nb) end)
             |> Enum.flat_map(fn {node, nb} ->
               mark = if node.checked?, do: "[x] ", else: "[ ] "

               [
                 {:"search_pane_scope_#{node.id}", nb.x, nb.y, nb.width, nb.height,
                  mark <> node.label}
                 | if node.children == [] do
                     []
                   else
                     [
                       {:"search_pane_scope_expand_#{node.id}", nb.expander.x, nb.y,
                        nb.expander.width, nb.height,
                        if(node.expanded?, do: "Collapse ", else: "Expand ") <> node.label}
                     ]
                   end
               ]
             end))

        %Model.Segmented{} = seg ->
          # Each position by name, so "show me a list" is one instruction
          # rather than arithmetic on which third of a control to aim at.
          if visible?.(b) do
            [{semantic_id(seg.id), b.x, b.y, b.width, b.height, Model.display_label(seg)}] ++
              Enum.map(Dropdown.segment_bounds(seg, b, theme), fn {value, label, sb} ->
                {:"#{semantic_id(seg.id)}_#{value}", sb.x, sb.y, sb.width, sb.height, label}
              end)
          else
            []
          end

        _ ->
          if visible?.(b) do
            [
              {semantic_id(Model.get_item_id(row)), b.x, b.y, b.width, b.height,
               Model.display_label(row)}
            ]
          else
            []
          end
      end
    end)
  end

  # Everything the pane draws is published to the semantic layer under a
  # printable id, so a test (or any other tool) can click a row or a button by
  # name rather than by guessing at coordinates.
  defp register_semantic_elements(scene, %State{} = state) do
    viewport = scene.viewport

    if viewport.semantic_table && viewport.semantic_enabled do
      {pin_x, pin_y} = state.frame.pin.point
      header_h = State.header_height(state)
      {_tx, ty} = ScrollState.translate_offset(state.scroll)

      header =
        State.header_widgets(state)
        |> Enum.reject(&State.settings_widget?/1)
        |> Enum.map(fn w ->
          {semantic_id(w.id), w.x, w.y, w.w, w.h, header_label(w, state)}
        end)

      # The settings are menu rows now, so where they are comes from the panel
      # that draws them rather than from a parallel set of rectangles this
      # component keeps for the purpose. Same ids as before: they are the
      # pane's API to anything driving it.
      settings = settings_semantics(state)

      # The rows that are DRAWN, which is the window around the viewport and no
      # more. Registering the whole result set would publish five hundred
      # entries for forty visible rows, and advertise as clickable a row that
      # is nowhere on the screen.
      body =
        Enum.flat_map(State.visible_rows(state), fn row ->
          row_entry =
            {semantic_id(row.id), 0, header_h + ty + row.y, state.frame.size.width, row.height,
             row.label}

          actions =
            Enum.map(State.action_bounds(state, row), fn b ->
              {semantic_id(b.action), b.x, header_h + ty + b.y, b.w, b.h, action_label(b.action)}
            end)

          [row_entry | actions]
        end)

      :ets.match_delete(viewport.semantic_table, {{:search_pane, :_}, :_})
      :ets.match_delete(viewport.semantic_index, {:_, {:search_pane, :_}})

      elements = header ++ settings ++ body

      Enum.each(elements, fn {id, x, y, w, h, label} ->
        entry = %Scenic.Semantic.Compiler.Entry{
          id: id,
          type: :button,
          module: nil,
          parent_id: nil,
          children: [],
          local_bounds: %{left: x, top: y, width: w, height: h},
          screen_bounds: %{left: pin_x + x, top: pin_y + y, width: w, height: h},
          clickable: true,
          focusable: false,
          label: label,
          role: :button,
          value: nil,
          hidden: false,
          z_index: 0
        }

        :ets.insert(viewport.semantic_table, {{:search_pane, id}, entry})
        :ets.insert(viewport.semantic_index, {id, {:search_pane, id}})
      end)
    end

    :ok
  end

  defp semantic_id(:replace_caret), do: :search_pane_replace_caret
  defp semantic_id({:scope_row, :scope_header}), do: :search_pane_scope
  defp semantic_id({:scope_row, {:scope, id}}), do: :"search_pane_scope_#{id}"
  defp semantic_id({:scope_expand, {:scope, id}}), do: :"search_pane_scope_expand_#{id}"
  defp semantic_id(:clear), do: :search_pane_clear
  defp semantic_id(:edit_excludes), do: :search_pane_edit_excludes
  defp semantic_id(:replace_one), do: :search_pane_replace_one
  defp semantic_id(:previous_match), do: :search_pane_previous
  defp semantic_id(:next_match), do: :search_pane_next
  defp semantic_id(:results_view), do: :search_pane_view
  defp semantic_id(:domain_header), do: :search_pane_domain
  defp semantic_id({:domain, option}), do: :"search_pane_domain_#{option}"
  defp semantic_id(:close), do: :search_pane_close
  defp semantic_id(:replace_all), do: :search_pane_replace_all
  defp semantic_id(:status), do: :search_pane_status
  defp semantic_id(:scope_header), do: :search_pane_scope
  defp semantic_id({:field, field}), do: :"search_pane_field_#{field}"
  defp semantic_id({:toggle, option}), do: :"search_pane_toggle_#{option}"
  defp semantic_id({:scope, id}), do: :"search_pane_scope_#{id}"
  defp semantic_id(:expand), do: :search_pane_expand
  defp semantic_id({:dir, path}), do: :"search_pane_dir_#{path}"
  defp semantic_id({:file, path}), do: :"search_pane_file_#{path}"
  defp semantic_id({:match, path, line, col}), do: :"search_pane_match_#{line}_#{col}_#{path}"
  defp semantic_id({:dismiss_file, path}), do: :"search_pane_dismiss_file_#{path}"
  defp semantic_id({:replace_file, path}), do: :"search_pane_replace_file_#{path}"

  defp semantic_id({:dismiss_match, path, line, col}),
    do: :"search_pane_dismiss_match_#{line}_#{col}_#{path}"

  defp semantic_id({:replace_match, path, line, col}),
    do: :"search_pane_replace_match_#{line}_#{col}_#{path}"

  # The scope rows carry their own row, so they can say WHICH directory they
  # are and whether it is being searched — every one of them used to publish
  # the same "Search scope", which is no use to anything reading the pane.
  defp header_label(%{id: {:scope_row, {:scope, _}}, row: row}, _state), do: row.label

  defp header_label(%{id: {:scope_expand, _}, row: row}, _state) do
    name = row.label |> String.replace_prefix("[x] ", "") |> String.replace_prefix("[ ] ", "")
    if row.expanded?, do: "Collapse #{name}", else: "Expand #{name}"
  end

  defp header_label(%{id: id}, state), do: header_label(id, state)

  defp header_label({:field, field}, state), do: State.field_value(state, field)
  defp header_label(:close, _state), do: "Close project search"
  defp header_label(:replace_all, _state), do: "Replace all"
  defp header_label({:toggle, :case_sensitive}, _state), do: "Match case"
  defp header_label({:toggle, :regex}, _state), do: "Regular expression"
  defp header_label(:status, _state), do: "Search status"
  defp header_label(:domain_header, _state), do: "Search domain"
  defp header_label(:replace_caret, _state), do: "Toggle replace"
  defp header_label({:scope_row, _id}, _state), do: "Search scope"
  defp header_label(:clear, _state), do: "Clear the search"
  defp header_label(:edit_excludes, _state), do: "Edit the exclude list"
  defp header_label(:replace_one, _state), do: "Replace this occurrence"
  defp header_label(:previous_match, _state), do: "Previous project match"
  defp header_label(:next_match, _state), do: "Next project match"
  defp header_label(:results_view, _state), do: "Show results as a tree or a list"

  defp header_label({:domain, :open_buffers_only}, _state), do: "Search only open buffers"

  defp header_label({:domain, :show_ignored_files}, _state),
    do: "Show .gitignore files in search"

  defp header_label({:domain, :apply_custom_excludes}, _state),
    do: "Apply custom search excludes"

  defp action_label({:replace_file, path}), do: "Replace all in #{path}"
  defp action_label({:dismiss_file, path}), do: "Remove #{path} from search scope"
  defp action_label({:replace_match, _path, line, col}), do: "Replace match #{line}:#{col}"
  defp action_label({:dismiss_match, _path, line, col}), do: "Skip replacement at #{line}:#{col}"
end
