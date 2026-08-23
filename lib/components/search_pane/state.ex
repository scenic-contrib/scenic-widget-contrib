defmodule ScenicWidgets.SearchPane.State do
  @moduledoc """
  Layout and interaction state for `ScenicWidgets.SearchPane`.

  The pane is two regions stacked in one frame:

    * a **header** that does not scroll — the query and replacement
      fields, the `Aa`/`.*` option toggles, Replace All, and a status line;
    * a **body** that does — the SCOPE tree and the results, grouped by file.

  Everything drawable is described here as a rectangle so that one list serves
  drawing, hit testing and semantic registration. `header_widgets/1` returns the
  header's rectangles in frame-local coordinates; `rows/1` returns the body's in
  *content* coordinates (i.e. before the scroll offset is applied), the same
  convention `SideNav` uses for `item_bounds`.

  The three text fields are owned here rather than by the parent. A field whose
  contents arrived from outside on every keystroke would fight the person
  typing into it; the parent is told what changed and does not tell the pane
  what it now holds.
  """

  alias Widgex.Scroll.ScrollState

  @default_theme %{
    background: {30, 30, 34},
    header_background: {38, 38, 44},
    border: {70, 70, 82},
    text: {220, 220, 228},
    dim_text: {150, 150, 162},
    heading: {160, 170, 200},
    field_background: {22, 22, 26},
    field_border: {80, 80, 96},
    field_focus_border: {90, 140, 220},
    match_highlight: {96, 78, 30},
    match_text: {255, 214, 120},
    row_hover: {48, 48, 58},
    menu_row_hover: {0, 150, 255},
    menu_row_hover_text: {255, 255, 255},
    menu_border: {70, 70, 82},
    button_background: {52, 52, 64},
    button_active: {70, 110, 180},
    button_text: {215, 220, 232},
    error_text: {240, 130, 130},
    scrollbar_color: {120, 120, 132},
    font: :roboto_mono,
    font_size: 13,
    small_font_size: 11,
    row_height: 20,
    field_height: 28,
    padding: 8,
    indent: 14
  }

  @fields [:query, :replace]

  # ── Sizes that follow the type ───────────────────────────────────────────
  #
  # These were pixel constants chosen against an 11pt label. The pane is sized
  # off the file navigator now, so its type moves with the chrome and a fixed
  # 74px slider is one that stops holding the word "tree" the moment anybody
  # zooms. Each is derived from what it has to contain.

  @doc "Wide enough for two four-letter labels at the pane's small type."
  def slider_width(theme), do: round(2 * (4 * theme.small_font_size * 0.6) + 16)

  @doc "A square control on the status bar: the cog, and the clear button."
  def button_size(theme), do: round(theme.row_height * 0.9)

  @doc "The disclosure column down the left of the query and replace rows."
  def caret_width(theme), do: round(theme.row_height * 0.67)

  @doc "One of the `Aa` / `.*` toggles inside the query field."
  def toggle_width(theme), do: round(theme.small_font_size * 1.6)

  # Air inside the settings box. IconMenu's dropdown_padding, because these
  # are the same kind of object and should not disagree about their margins.
  @settings_pad 4

  # How wide the panel is, as a fraction of the pane. Narrower than the pane
  # itself, so its edges land inside rather than on the pane's own — a panel
  # exactly as wide as what is behind it does not look like a panel.
  @settings_width_ratio 0.86

  # How many rows either side of the viewport are drawn anyway, so that
  # scrolling a notch does not rebuild the body.
  @overscan 6

  defstruct [
    :frame,
    :theme,
    :model,
    :scroll,
    query: "",
    replace: "",
    focused_field: :query,
    focused: false,
    hovered: nil,
    collapsed_files: MapSet.new(),
    expanded_scope: MapSet.new(),
    scope_open?: false,
    # The search-domain disclosure: which files this search is allowed to
    # look at. Shut by default — the default domain is right nearly always,
    # and the pane is mostly for reading results.
    domain_open?: false,
    # The replacement row, behind a disclosure like the find bar's. Most
    # searches are searches; the replacement field is a second job.
    replace_open?: false,
    # :tree groups matches under their file, :list gives one row per match.
    # Owned by the host, which saves it with its other settings.
    results_view: :tree,
    # How far down the settings panel is wound, in pixels. On the pane, not
    # inside the panel or one of its rows: the rows are rebuilt from the model
    # every time results land, so an offset kept in one of them would be
    # thrown away by the next search. `Menu.Dropdown` does all the arithmetic
    # on this number; the pane's only job is to still have it afterwards.
    settings_scroll: 0,
    # A drag of that panel's bar, as `{pointer_y, offset}`.
    settings_drag: nil,
    scrollbar_drag: nil,
    scrollbar_drag_start: nil,
    scrollbar_drag_offset: nil
  ]

  @doc "The theme every SearchPane starts from; parents override keys piecemeal."
  def default_theme, do: @default_theme

  @doc """
  Are the results on screen the answer to the query in the box, or the last
  one?

  True from the keystroke until the search that keystroke started comes back.
  The pane draws stale results faded rather than removing them: the debounce
  fires on every character, and a pane that empties itself between letters is
  a pane you cannot read while you type.
  """
  def stale?(%__MODULE__{model: %{status: status}}), do: status in [:debouncing, :searching]

  @doc "The names of the three editable fields, in Tab order."
  def fields, do: @fields

  def new(data) do
    theme = Map.merge(@default_theme, Map.get(data, :theme, %{}))
    model = normalize_model(Map.get(data, :model, %{}))
    query = Map.get(data, :query, "")

    state = %__MODULE__{
      frame: data.frame,
      theme: theme,
      model: model,
      query: query,
      replace: Map.get(data, :replace, ""),
      focused: Map.get(data, :focused, false),
      focused_field: Map.get(data, :focus_field, :query),
      scroll: ScrollState.new(data.frame, content_height: 0, direction: :vertical)
    }

    # The project row of the scope tree starts open here too, not only when a
    # later snapshot changes the root. The pane is now BORN with the right
    # project — it reads the store rather than a cache that cannot have caught
    # up — so "the root changed" never fires, and without this the tree opened
    # to a single row naming the directory you are already searching.
    state = %{state | expanded_scope: with_root_expanded(state.expanded_scope, state.model)}

    resync_scroll(state)
  end

  @doc """
  A model with every key the pane draws from, defaulted.

  The parent publishes results asynchronously, so the pane must be drawable
  before the first snapshot lands.
  """
  def normalize_model(model) do
    %{
      status: Map.get(model, :status, :idle),
      error: Map.get(model, :error),
      # What is being searched, so the pane can say so while it is empty.
      root: Map.get(model, :root),
      case_sensitive: Map.get(model, :case_sensitive, false),
      regex: Map.get(model, :regex, false),
      # Where the search is allowed to look. Hidden behind a disclosure,
      # because most searches want the default and a row of switches above
      # the results is a row of results you cannot see.
      open_buffers_only: Map.get(model, :open_buffers_only, false),
      show_ignored_files: Map.get(model, :show_ignored_files, false),
      apply_custom_excludes: Map.get(model, :apply_custom_excludes, true),
      active_match: Map.get(model, :active_match),
      skipped: Map.get(model, :skipped, MapSet.new()),
      total_matches: Map.get(model, :total_matches, 0),
      eligible_matches: Map.get(model, :eligible_matches, 0),
      eligible_files: Map.get(model, :eligible_files, 0),
      results_view: Map.get(model, :results_view, :tree),
      scope: Map.get(model, :scope, []),
      files: Map.get(model, :files, [])
    }
  end

  def put_model(%__MODULE__{} = state, model) do
    normalized = normalize_model(model)

    resync_scroll(%{
      state
      | model: normalized,
        results_view: normalized.results_view,
        expanded_scope: seed_root_expansion(state, normalized)
    })
  end

  # The project row at the top of the scope tree starts OPEN. Shut, the tree
  # is one row naming the directory you are already searching, which tells you
  # nothing and hides everything.
  #
  # Seeded once per project rather than on every snapshot, so that shutting it
  # yourself sticks: results land continuously while you type, and a default
  # reapplied on each one would prise the tree open again under your hand.
  defp seed_root_expansion(
         %__MODULE__{model: %{scope: [%{id: root} | _]}, expanded_scope: expanded},
         %{scope: [%{id: root} | _]}
       ),
       do: expanded

  defp seed_root_expansion(%__MODULE__{expanded_scope: expanded}, model),
    do: with_root_expanded(expanded, model)

  defp with_root_expanded(expanded, %{scope: [%{id: root} | _]}), do: MapSet.put(expanded, root)
  defp with_root_expanded(expanded, _model), do: expanded

  def put_frame(%__MODULE__{} = state, frame) do
    scroll = ScrollState.update_viewport_size(state.scroll, body_frame(frame, state.theme))
    resync_scroll(%{state | frame: frame, scroll: scroll})
  end

  # ── Geometry ──────────────────────────────────────────────────────────────

  @doc "Height of the fixed header, in pixels."
  # What the header currently IS, which depends on what it is showing: the
  # replacement row and the domain options are both behind disclosures.
  def header_height(%__MODULE__{theme: theme} = state),
    do: status_y(state) + theme.row_height + theme.padding

  # The shut-and-empty height, for callers holding a theme and no state.
  def header_height(theme) do
    pad = theme.padding

    pad + theme.row_height + theme.field_height + 4 + 6 + theme.row_height +
      theme.row_height + pad
  end

  @doc "The frame the scrolling body occupies, as its own Widgex.Frame."
  # The body starts under whatever the header currently is — which grows when
  # the domain section is open, so it cannot be measured from the theme alone.
  def body_frame(%__MODULE__{frame: frame} = state) do
    top = header_height(state)

    Widgex.Frame.new(%{
      pin: {0, top},
      size: {frame.size.width, max(frame.size.height - top, 0)}
    })
  end

  def body_frame(frame, theme) do
    Widgex.Frame.new(%{
      pin: {0, header_height(theme)},
      size: {frame.size.width, max(frame.size.height - header_height(theme), 0)}
    })
  end

  @doc """
  The header's clickable rectangles, in frame-local coordinates.

  Each is `%{id: term, x:, y:, w:, h:}`. Ids are what `handle_click` matches on
  and what the semantic layer publishes, so they double as the pane's API to
  anything driving it from outside.
  """
  def header_widgets(%__MODULE__{frame: frame, theme: theme} = state) do
    pad = theme.padding
    width = frame.size.width
    fh = theme.field_height
    caret_w = caret_width(theme)
    toggle_w = toggle_width(theme)
    button_w = button_size(theme) + 2
    gap = 6

    title_y = pad
    # Air under the title. At one row exactly, the heading's baseline sat four
    # pixels above the field and the two read as one crowded block.
    query_y = title_y + theme.row_height + 8
    replace_y = query_y + fh + 4
    # The query field, with its option toggles INSIDE its right-hand end —
    # the same arrangement as the find bar, where it reads that they modify
    # the query rather than the search. They used to sit outside it, which
    # made them look like two more buttons in a row of buttons.
    query_x = pad + caret_w + gap
    query_w = max(width - pad - query_x, 60)
    # Five pixels all around the pair: the same air above/below, between the
    # buttons, and against the field's right edge. The equality matters more
    # than any individual number; it makes them read as an intentional group.
    toggle_gap = round((fh - toggle_w) / 2)
    regex_x = query_x + query_w - toggle_gap - toggle_w
    case_x = regex_x - toggle_gap - toggle_w

    # SQUARE, and centred in the field they sit inside. They were
    # `toggle_width` wide by `field_height - 6` tall — 22 by 25 at the
    # current type — and the two numbers come from different places, so the
    # error changed size with the zoom rather than staying a constant wrongness
    # somebody had chosen. Everything else on this pane is square now; a pair
    # of bordered boxes in the most looked-at part of it should not be the
    # exception.
    toggle_y = query_y + round((fh - toggle_w) / 2)

    # The settings no longer have a row of their own to be opened from —
    # the cog on the status bar does that. What is left is the BOX, in the
    # place it always appeared: above the bar, so it opens upward out of
    # the button that opened it.
    header =
      [
        # A close button the size of the ones on the tabs, with room around it.
        # It was 18px square and unhighlighted — smaller than every other close
        # in the application and easy to miss entirely.
        %{
          id: :close,
          x: width - pad - button_w,
          y: title_y - 4,
          w: button_w,
          h: button_w
        },
        # The disclosure for the replacement row, on the left where a control
        # that opens another row belongs. It spans both rows when open, so its
        # highlight covers what it opened.
        %{
          id: :replace_caret,
          x: pad,
          y: query_y,
          w: caret_w,
          h: if(state.replace_open?, do: 2 * fh + 4, else: fh)
        },
        %{id: {:field, :query}, x: query_x, y: query_y, w: query_w, h: fh},
        %{id: {:toggle, :case_sensitive}, x: case_x, y: toggle_y, w: toggle_w, h: toggle_w},
        %{id: {:toggle, :regex}, x: regex_x, y: toggle_y, w: toggle_w, h: toggle_w}
      ] ++
        replace_widgets(state, query_x, replace_y, width, pad, fh, gap) ++
        domain_widgets(state, settings_top(state) + @settings_pad, width, pad, theme)

    status = status_y(state)
    button = button_size(theme)

    # `button_size/1` says "a square control on the status bar" and these were
    # drawn `button` wide by `row_height` tall — 18 by 20, which the cog shows
    # up plainly, because an OPEN cog fills its rectangle rather than merely
    # outlining a glyph inside it. Square, and centred in the row it sits on.
    button_y = status + round((theme.row_height - button) / 2)

    # Right to left along the bar: clear, the tree/list slider, and the cog
    # that opens the settings above them.
    clear_x = width - pad - button
    settings_x = settings_button_x(state)
    next_x = settings_x - 6 - button
    previous_x = next_x - 4 - button

    header ++
      [
        %{
          id: :status,
          x: pad,
          y: status,
          w: max(previous_x - pad - 8, 40),
          h: theme.row_height
        },
        # The settings, as a cog on the bar rather than a labelled row of its
        # own above it. A whole row saying "SEARCH SETTINGS" spent a line of a
        # narrow pane telling you that a thing you could not see was shut.
        %{id: :domain_header, x: settings_x, y: button_y, w: button, h: button},
        %{id: :previous_match, x: previous_x, y: button_y, w: button, h: button},
        %{id: :next_match, x: next_x, y: button_y, w: button, h: button},
        # And a way to put the pane back to empty without hunting for the
        # query field and selecting what is in it.
        %{id: :clear, x: clear_x, y: button_y, w: button, h: button}
      ]
  end

  defp replace_widgets(%__MODULE__{replace_open?: false}, _x, _y, _w, _pad, _fh, _gap),
    do: []

  # SQUARE, and the height of the field they sit beside — which is what the
  # find bar's are, and why they look right there and looked wrong here. They
  # were `button_size + 2` wide by `field_height` tall: 20 by 24, a rectangle
  # standing on end, holding a glyph drawn round its centre with more air
  # above and below it than either side. Two of them side by side made a pair
  # of tall thin slabs at the end of the row.
  defp replace_widgets(%__MODULE__{}, query_x, y, width, pad, fh, gap) do
    all_x = width - pad - fh
    one_x = all_x - gap - fh
    field_w = max(one_x - gap - query_x, 60)

    [
      %{id: {:field, :replace}, x: query_x, y: y, w: field_w, h: fh},
      # Replace this one, and replace all of them — the same pair the find bar
      # offers, because a project replace is the one that most wants doing an
      # occurrence at a time.
      #
      # A full gap between them, not the two pixels they had. Filled buttons
      # touching each other read as one control with a seam down it.
      %{id: :replace_one, x: one_x, y: y, w: fh, h: fh},
      %{id: :replace_all, x: all_x, y: y, w: fh, h: fh}
    ]
  end

  defp domain_widgets(%__MODULE__{domain_open?: false}, _y, _width, _pad, _theme), do: []

  # Laid out inside the PANEL, which starts in from the pane's own left edge
  # and runs past its right one. Positioned against the pane's padding
  # instead, every row began a couple of pixels outside the panel it is drawn
  # in — the scope tree most visibly, because it is the widest thing in there.
  defp domain_widgets(%__MODULE__{} = state, y, _width, _pad, theme) do
    row = theme.row_height
    x = settings_x(state)
    w = inner_width(state)

    [
      %{id: {:domain, :open_buffers_only}, x: x, y: y, w: w, h: row},
      %{id: {:domain, :show_ignored_files}, x: x, y: y + row, w: w, h: row},
      %{id: {:domain, :apply_custom_excludes}, x: x, y: y + 2 * row, w: w, h: row},
      # The excludes list is a file, and this opens it — right here, beside
      # the switch that says whether it is being honoured, rather than buried
      # in a menu three clicks away from the search it governs.
      %{id: :edit_excludes, x: x, y: y + 3 * row, w: w, h: row}
    ] ++ scope_widgets(state, y + 4 * row, theme)
  end

  defp settings_x(%__MODULE__{} = state) do
    {px, _py} = settings_frame(state).pin.point
    px + @settings_pad
  end

  @doc "The width available to a row inside the settings panel."
  def inner_width(%__MODULE__{} = state) do
    panel = settings_frame(state)
    max(panel.size.width - 2 * @settings_pad, 0)
  end

  # The scope tree lives in the settings section, which means the HEADER —
  # above the status line, which is the boundary between the settings and the
  # results. In the body it sat below that line, among the results it is
  # meant to narrow.
  #
  # A project's directories can run to hundreds. The panel they are drawn in
  # clamps to the room under the cog and scrolls; the tree itself is as long as
  # it is, and collapsible — that is what the disclosure triangles are for.
  defp scope_widgets(%__MODULE__{} = state, y, theme) do
    rows = state |> scope_rows() |> Enum.with_index()
    x = settings_x(state)
    w = inner_width(state)

    row_widgets =
      Enum.map(rows, fn {row, i} ->
        %{
          id: {:scope_row, row.id},
          row: row,
          x: x,
          y: y + i * theme.row_height,
          w: w,
          h: theme.row_height
        }
      end)

    # The disclosure triangle is its OWN control, laid over the row's
    # left-hand end — LAST, because `hit_test/2` walks the list backwards and
    # the thing drawn last is the thing on top.
    #
    # Expanding a directory and excluding it are different intentions, and one
    # rectangle cannot carry both. It used to: a scope row whose node had
    # children spent every click on expanding itself, so the one thing a scope
    # tree exists to do — "not that folder" — could not be done to any folder
    # with anything in it. Only empty directories and files could be unticked.
    expanders =
      for {row, i} <- rows, Map.get(row, :expandable?, false) do
        %{
          id: {:scope_expand, row.id},
          row: row,
          x: x + row.depth * theme.indent,
          y: y + i * theme.row_height,
          w: 16,
          h: theme.row_height
        }
      end

    row_widgets ++ expanders
  end

  @doc """
  The settings, as `ScenicWidgets.Menu.Model` rows.

  The panel is drawn by `ScenicWidgets.Menu.Dropdown` — the same code that
  draws the menubar's dropdowns — so what the pane supplies is rows, not
  rectangles. The scope tree is a `Tree` row, which is a menu row you can
  pick a set out of; it exists because this pane needed one, and it is
  generic because the next thing to need one should not have to write it
  again.
  """
  def settings_rows(%__MODULE__{model: model} = state) do
    alias ScenicWidgets.Menu.Model

    [
      %Model.Toggle{
        id: {:domain, :open_buffers_only},
        label: "Search only open buffers",
        checked?: model.open_buffers_only,
        tooltip: "Limit this search to files already open in the editor."
      },
      %Model.Toggle{
        id: {:domain, :show_ignored_files},
        label: "Show .gitignore files in search",
        checked?: model.show_ignored_files,
        tooltip: "Include files hidden by the project's .gitignore and .ignore rules."
      },
      %Model.Toggle{
        id: {:domain, :apply_custom_excludes},
        label: "Apply custom search excludes",
        checked?: model.apply_custom_excludes,
        tooltip: "Apply the patterns in Quillex's editable search-excludes file."
      },
      %Model.Item{
        id: :edit_excludes,
        label: "Edit the exclude list…",
        flush_left?: true,
        tooltip: "Open the custom search-excludes file in the editor."
      },
      # Tree or list: an either/or with both choices on show. It used to be a
      # slider on the status bar, taking a third of a narrow bar to say
      # something you change rarely — it is the same control, in the drawer
      # where settings live, and it is a menu row now so anything else can
      # have one.
      %Model.Segmented{
        id: :results_view,
        label: "Show results as",
        value: state.results_view,
        options: [:tree, :list]
      }
    ] ++ scope_row(state)
  end

  defp scope_row(%__MODULE__{model: %{scope: []}}), do: []

  defp scope_row(%__MODULE__{model: %{scope: scope}} = state) do
    [
      %ScenicWidgets.Menu.Model.Tree{
        id: :scope,
        label: "Choose search scope",
        tooltip: "Choose the project directories and files included in this search.",
        closed_caret: :left,
        expanded?: state.scope_open?,
        nodes: Enum.map(scope, &scope_node(&1, state))
      }
    ]
  end

  defp scope_node(node, state) do
    %ScenicWidgets.Menu.Model.TreeNode{
      id: node.id,
      label: node.label,
      checked?: node.included?,
      expanded?: MapSet.member?(state.expanded_scope, node.id),
      children: Enum.map(node.children, &scope_node(&1, state))
    }
  end

  @doc """
  The pane's theme, said in the words a menu dropdown uses.

  The pane and the menubar name their colours differently — one talks about
  panes and rows, the other about dropdowns and items — and the panel needs
  the second. Translated in one place rather than by giving the pane a second
  set of theme keys nobody else would ever set.
  """
  def dropdown_theme(%__MODULE__{theme: theme}) do
    %{
      font: theme.font,
      dropdown_bg: theme.header_background,
      dropdown_border: Map.get(theme, :menu_border, theme.border),
      dropdown_padding: @settings_pad,
      dropdown_item_height: theme.row_height,
      dropdown_font_size: theme.small_font_size,
      dropdown_divider_height: 13,
      dropdown_column_gap: 24,
      # What IconMenu lights ITS rows with — the accent — supplied by the host
      # so the two panels cannot drift apart. Two dead ends worth recording:
      # the pane's `row_hover` is the same colour as this panel's own
      # background and lit nothing at all, and a DAMPED accent was tried across
      # every palette and rejected on sight. The row under the pointer is the
      # one thing in an open menu you are addressing; quieter is not better.
      item_hover_bg: Map.get(theme, :menu_row_hover, theme.button_active),
      item_text_color: theme.text,
      item_hover_text_color: Map.get(theme, :menu_row_hover_text, theme.button_text)
    }
  end

  @doc """
  Where the settings panel goes, and where each row sits inside it.

  The pane supplies the ANCHOR and how much room there is under it; everything
  else — how tall the panel ends up, which rows are where, whether it needs a
  scrollbar — is `Menu.Dropdown`'s, and is where the menubar's dropdowns get it
  from too. The pane used to add its own rows up in `settings_height/1` and got
  a different answer, which is how a panel and the rows in it disagree.
  """
  def settings_layout(%__MODULE__{} = state) do
    {x, y, width} = settings_anchor(state)

    ScenicWidgets.Menu.Dropdown.layout(settings_rows(state), dropdown_theme(state),
      x: x,
      y: y,
      width: width,
      max_height: settings_max_height(state),
      scroll: state.settings_scroll
    )
  end

  # The room between the top of the panel and the bottom of the pane. A scope
  # tree of a project's directories is taller than any panel should be, and it
  # is no longer capped in NODES — so the panel clamps in pixels, and scrolls,
  # and says so with a bar. Below this the panel would have nothing left to
  # show a row in.
  @settings_min_height 3
  defp settings_max_height(%__MODULE__{frame: frame, theme: theme} = state) do
    max(
      frame.size.height - settings_top(state) - theme.padding,
      @settings_min_height * theme.row_height
    )
  end

  @doc """
  Which header widgets live inside the floating settings panel.

  They are in `header_widgets/1` like everything else — one list still serves
  drawing, hit testing and semantics — but they are DRAWN in a different piece
  of the graph, on top of the results rather than among the controls.
  """
  def settings_widget?(%{id: :edit_excludes}), do: true
  def settings_widget?(%{id: {:domain, _}}), do: true
  def settings_widget?(%{id: {:scope_row, _}}), do: true
  def settings_widget?(%{id: {:scope_expand, _}}), do: true
  def settings_widget?(%{}), do: false

  @doc """
  The wheel over the settings panel: wind it, by whatever a notch is worth.

  It used to wind the scope TREE, by nodes, through a cap the row kept on
  itself — so the same gesture over the same panel moved a different thing
  depending on which row it was over, and the panel's own overflow (the
  toggles above the tree, say) could not be reached at all.
  """
  def scroll_settings(%__MODULE__{} = state, dy) do
    layout = settings_layout(state)

    %{
      state
      | settings_scroll: ScenicWidgets.Menu.Dropdown.wheel(layout, state.settings_scroll, dy)
    }
  end

  @doc "The rows inside the settings panel, with where each one is drawn."
  def settings_row_bounds(%__MODULE__{} = state), do: settings_layout(state).items

  # The status line is the boundary between the controls and the results, so
  # it gets room above it and a rule to sit under — crowded up against the
  # settings it read as one more option.
  defp status_y(%__MODULE__{theme: theme} = state) do
    pad = theme.padding
    fh = theme.field_height

    pad + theme.row_height + 8 + fh + 4 +
      if(state.replace_open?, do: fh + 4, else: 0) + 10
  end

  @doc """
  How tall the settings box is, including the padding inside it.

  Zero when it is shut — which is most of the time, and a row the pane gets
  back for results. Asked of the LAYOUT rather than added up here: this used
  to count rows itself, against a scope tree capped at a number this module
  also owned, and two sums of the same panel are two panels.
  """
  def settings_height(%__MODULE__{domain_open?: false}), do: 0
  def settings_height(%__MODULE__{} = state), do: settings_layout(state).height

  @doc """
  The settings panel: a rectangle hanging under the cog, over the results.

  It FLOATS. Every inline arrangement of this moved something — above the bar
  it pushed the bar (and so the cog) down out from under the pointer that had
  just clicked it; below the bar it shoved the results about; and giving it a
  labelled row of its own was the row the cog was meant to replace. A panel
  that is drawn over the content, like a menu dropping out of a menubar,
  moves nothing at all, which is the only arrangement that has no cost.
  """
  def settings_frame(%__MODULE__{} = state) do
    {x, y, width} = settings_anchor(state)

    Widgex.Frame.new(%{pin: {x, y}, size: {width, settings_height(state)}})
  end

  # Where the panel hangs, and how wide — the one part of a dropdown that is
  # genuinely the host's business.
  #
  # Hung off the cog rather than off the pane: a third of it to the left of
  # the button, two thirds to the right. Flush with the pane's own edges it
  # read as part of the pane; offset like this it reads as something in front
  # of, and hanging from, the control that opened it — and it leaves the search
  # box above it and the results below it visible at the edges, which is most
  # of what tells you the pane is still there underneath.
  defp settings_anchor(%__MODULE__{frame: frame, theme: theme} = state) do
    # Plus room for a scrollbar if this panel is going to have one. The ratio
    # is chosen against the LABELS; a bar drawn inside it takes 16px back out
    # of every row, and "Use exclude settings & ignore files" is not a label
    # with 16px to spare.
    bar =
      ScenicWidgets.Menu.Dropdown.bar_lane(
        settings_rows(state),
        dropdown_theme(state),
        settings_max_height(state)
      )

    width = round(frame.size.width * @settings_width_ratio) + bar
    centre = settings_button_x(state) + button_size(theme) / 2

    {round(centre - width / 3), settings_top(state), width}
  end

  @doc "Where the cog sits on the status bar."
  # Computed here rather than read back out of `header_widgets/1`, which asks
  # for the panel's geometry itself — one would call the other forever.
  def settings_button_x(%__MODULE__{frame: frame, theme: theme}) do
    button = button_size(theme)
    frame.size.width - theme.padding - button - 6 - button
  end

  @doc "The top edge of the settings panel: just under the bar the cog is on."
  def settings_top(%__MODULE__{theme: theme} = state),
    do: status_y(state) + theme.row_height + 2

  @doc "Where the rule above the status line goes."
  def status_rule_y(%__MODULE__{theme: theme} = state),
    do: status_y(state) - 5 + 0 * theme.padding

  @doc """
  The body's rows, in content coordinates.

  Every row carries the actions drawn at its right edge, so the renderer, the
  hit test and the semantic registration cannot disagree about where a button
  is.

  This builds them ALL. Drawing does not go through here — see
  `visible_rows/1` — because a project search returns hundreds and the pane
  shows forty. This is for the callers that genuinely want the whole list.
  """
  def rows(%__MODULE__{} = state), do: rows_window(state, 0, row_count(state))

  @doc """
  The rows the body actually draws: those inside the viewport, plus
  `@overscan` either side.

  Rows are a uniform `theme.row_height`, so which ones those are is
  arithmetic. Nothing outside the window is built, never mind drawn, so a
  five-hundred-match search costs the same to draw as a five-match one — which
  is the whole of why the pane used to stall for a tenth of a second every
  time results landed.
  """
  def visible_rows(%__MODULE__{} = state) do
    {first, count} = visible_window(state)
    rows_window(state, first, count)
  end

  @doc """
  Which rows the body draws, as `{first_index, count}`.

  The overscan is what keeps an ordinary scroll cheap: a wheel notch or two
  lands inside the window that is already drawn, so the body moves by a
  transform and is only rebuilt once the pointer has run past the margin.
  """
  def visible_window(%__MODULE__{theme: theme, scroll: scroll} = state) do
    h = theme.row_height
    total = row_count(state)

    first = max(trunc(scroll.offset_y / h) - @overscan, 0)
    on_screen = ceil(body_frame(state).size.height / h)
    last = min(first + on_screen + 2 * @overscan, total)

    {first, max(last - first, 0)}
  end

  @doc "How many rows the body has, without building a single one of them."
  def row_count(%__MODULE__{} = state),
    do: state |> blocks() |> Enum.reduce(0, fn block, n -> n + block.count end)

  @doc "The row at `index`, or `nil` past the end. What hit testing asks."
  def row_at(%__MODULE__{} = state, index) when index >= 0 do
    case rows_window(state, index, 1) do
      [row] -> row
      [] -> nil
    end
  end

  def row_at(%__MODULE__{}, _index), do: nil

  @doc "Rows `first` up to (not including) `first + count`, and only those."
  def rows_window(%__MODULE__{theme: theme} = state, first, count) do
    h = theme.row_height
    last = first + count

    state
    |> blocks()
    |> Enum.map_reduce(0, fn block, idx ->
      next = idx + block.count

      if idx < last and next > first do
        lo = max(first - idx, 0)
        hi = min(last - idx, block.count)
        {Enum.with_index(block.slice.(lo, hi), idx + lo), next}
      else
        {[], next}
      end
    end)
    |> elem(0)
    |> Enum.concat()
    |> Enum.map(fn {row, i} -> Map.merge(row, %{y: i * h, height: h}) end)
  end

  # ── The two views ─────────────────────────────────────────────────────────
  #
  # A block is a run of rows that knows HOW MANY it is without building any of
  # them, and can build any sub-range on demand. That is what makes
  # `rows_window/3` proportional to the window rather than to the result set,
  # and both views provide it.
  #
  #   LIST  every matching file, one after another, its path shown in full,
  #         with its matches under it. One block per file.
  #
  #   TREE  the project's own shape — only the directories that contain a
  #         match — with the files inside them and the matches inside those.
  #         One block for the whole tree, sliced by walking it; the counts on
  #         each node let a subtree the window has passed be skipped whole.
  #
  # These used to be the same idea twice: what was called "tree" was this
  # list, and what was called "list" was the same rows again with the file
  # name repeated onto each one. Neither said where in the project anything
  # was, which is most of what you want a project search to tell you.
  defp blocks(%__MODULE__{results_view: :list, model: model} = state) do
    Enum.map(model.files, fn file ->
      collapsed? = MapSet.member?(state.collapsed_files, file.path)

      %{
        count: if(collapsed?, do: 1, else: 1 + length(file.matches)),
        slice: fn lo, hi -> file_slice(file, file.label, collapsed?, 0, lo, hi) end
      }
    end)
  end

  defp blocks(%__MODULE__{model: model} = state) do
    nodes = dir_nodes(model.files, state)

    [
      %{
        count: Enum.sum(Enum.map(nodes, & &1.count)),
        slice: fn lo, hi -> node_slice(nodes, 0, lo, hi) end
      }
    ]
  end

  # The results' directory tree, built from the paths they are already
  # labelled with. Directories sort before files at each level, the way a file
  # navigator shows them.
  defp dir_nodes(files, state) do
    files
    |> Enum.map(fn file -> {dir_segments(file.label), file} end)
    |> group_nodes("", state)
  end

  defp dir_segments(label) do
    case Path.dirname(label) do
      "." -> []
      dir -> Path.split(dir)
    end
  end

  defp group_nodes(entries, prefix, state) do
    {here, deeper} = Enum.split_with(entries, fn {segments, _file} -> segments == [] end)

    dirs =
      deeper
      |> Enum.group_by(fn {[seg | _], _f} -> seg end, fn {[_ | rest], f} -> {rest, f} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {segment, nested} ->
        path = if prefix == "", do: segment, else: prefix <> "/" <> segment
        children = group_nodes(nested, path, state)
        collapsed? = MapSet.member?(state.collapsed_files, path)

        %{
          kind: :dir,
          path: path,
          label: segment,
          collapsed?: collapsed?,
          children: children,
          count: if(collapsed?, do: 1, else: 1 + Enum.sum(Enum.map(children, & &1.count)))
        }
      end)

    files =
      Enum.map(here, fn {_segments, file} ->
        collapsed? = MapSet.member?(state.collapsed_files, file.path)

        %{
          kind: :file,
          file: file,
          # In a tree the folders above already say where the file is;
          # repeating the whole path on its own row says it twice.
          label: Path.basename(file.label),
          collapsed?: collapsed?,
          count: if(collapsed?, do: 1, else: 1 + length(file.matches))
        }
      end)

    dirs ++ files
  end

  # Rows `lo` up to `hi` of these nodes and everything open under them, at
  # `depth`. A node whose whole subtree falls outside the window costs a
  # subtraction — which is the point of carrying `count` on it.
  defp node_slice(nodes, depth, lo, hi) do
    nodes
    |> Enum.reduce({[], 0}, fn node, {acc, idx} ->
      next = idx + node.count

      if next <= lo or idx >= hi do
        {acc, next}
      else
        {acc ++ node_rows(node, depth, idx, lo, hi), next}
      end
    end)
    |> elem(0)
  end

  defp node_rows(%{kind: :dir} = node, depth, idx, lo, hi) do
    own = if idx >= lo and idx < hi, do: [dir_row(node, depth)], else: []

    children =
      if node.collapsed?,
        do: [],
        else: node_slice(node.children, depth + 1, max(lo - idx - 1, 0), hi - idx - 1)

    own ++ children
  end

  defp node_rows(%{kind: :file} = node, depth, idx, lo, hi) do
    file_slice(node.file, node.label, node.collapsed?, depth, max(lo - idx, 0), hi - idx)
  end

  # A file heading and its matches, as one run: local index 0 is the heading,
  # 1.. are the matches.
  defp file_slice(file, label, collapsed?, depth, lo, hi) do
    head = if lo <= 0 and hi > 0, do: [file_row(file, label, collapsed?, depth)], else: []

    matches =
      if collapsed? do
        []
      else
        m_lo = max(lo - 1, 0)

        file.matches
        |> Enum.slice(m_lo, max(hi - 1 - m_lo, 0))
        |> Enum.map(&match_row(&1, file.path, depth + 1))
      end

    head ++ matches
  end

  defp dir_row(node, depth) do
    %{
      id: {:dir, node.path},
      kind: :dir,
      label: node.label,
      path: node.path,
      depth: depth,
      collapsed?: node.collapsed?,
      expandable?: true,
      expanded?: not node.collapsed?,
      actions: []
    }
  end

  defp file_row(file, label, collapsed?, depth) do
    %{
      id: {:file, file.path},
      kind: :file,
      label: "#{label}  (#{length(file.matches)})",
      path: file.path,
      depth: depth,
      collapsed?: collapsed?,
      expandable?: true,
      expanded?: not collapsed?,
      actions: [{:replace_file, file.path}, {:dismiss_file, file.path}]
    }
  end

  defp match_row(match, path, depth) do
    %{
      id: {:match, path, match.line, match.col},
      kind: :match,
      label: "#{match.line}  #{match.text}",
      # Where the matched text sits inside `label`, in graphemes — the gutter
      # is the line number plus two spaces, so the offset shifts with it.
      match_start: String.length("#{match.line}  ") + match.match_start,
      match_len: match.match_len,
      current?: Map.get(match, :current?, false),
      skipped?: Map.get(match, :skipped?, false),
      path: path,
      line: match.line,
      col: match.col,
      depth: depth,
      actions: [
        {:replace_match, path, match.line, match.col},
        {:dismiss_match, path, match.line, match.col}
      ]
    }
  end

  @doc """
  The scope tree's rows — the summary line, and the tree under it when open.

  These are HEADER rows, not body rows: the scope belongs to the settings
  section, above the status line that separates the settings from the
  results.
  """
  def scope_rows(%__MODULE__{domain_open?: false}), do: []

  def scope_rows(%__MODULE__{model: %{scope: []}}), do: []

  def scope_rows(%__MODULE__{model: %{scope: scope}} = state) do
    header = %{
      id: :scope_header,
      kind: :scope_header,
      label: scope_summary(scope),
      # Indented: the scope tree is a section INSIDE the settings, its own
      # dropdown within them, rather than a sibling of the results.
      depth: 1,
      expanded?: state.scope_open?,
      actions: []
    }

    if state.scope_open? do
      [header | scope_nodes(scope, state, 2)]
    else
      [header]
    end
  end

  defp scope_nodes(nodes, state, depth) do
    Enum.flat_map(nodes, fn node ->
      expanded? = MapSet.member?(state.expanded_scope, node.id)
      expandable? = node.children != []
      mark = if node.included?, do: "[x] ", else: "[ ] "

      row = %{
        id: {:scope, node.id},
        kind: :scope,
        # No chevron in the text: it is DRAWN, like the file navigator's. A
        # triangle typed as a character is a triangle the font may not have,
        # and an empty box beside every folder is worse than no triangle.
        label: mark <> node.label,
        path: node.id,
        depth: depth,
        expandable?: expandable?,
        expanded?: expanded?,
        actions: []
      }

      if expanded? do
        [row | scope_nodes(node.children, state, depth + 1)]
      else
        [row]
      end
    end)
  end

  # The project row is the whole of the scope, so when it is unticked there is
  # nothing to count — saying "1 excluded" would be true and useless.
  defp scope_summary([%{included?: false} | _]),
    do: "Choose search scope  (nothing selected)"

  defp scope_summary(scope) do
    excluded = count_excluded(scope)

    if excluded == 0,
      do: "Choose search scope  (whole project)",
      else: "Choose search scope  (#{excluded} excluded)"
  end

  # An excluded directory counts ONCE, not once per thing inside it. Exclusion
  # is inherited, so a folder with forty files in it would otherwise report
  # itself as forty-one exclusions for one click.
  defp count_excluded(nodes) do
    Enum.reduce(nodes, 0, fn
      %{included?: false}, acc -> acc + 1
      node, acc -> acc + count_excluded(node.children)
    end)
  end

  @doc "The rectangles of a row's right-edge action buttons, in content space."
  def action_bounds(%__MODULE__{frame: frame, theme: theme} = state, row) do
    height = theme.row_height - 4
    # Leave a quiet lane between the action cluster and the body scrollbar.
    # Without it the rightmost button reads as though it touches the thumb.
    right = frame.size.width - theme.padding - 14

    actions =
      if state.replace_open?,
        do: row.actions,
        else: Enum.reject(row.actions, &replace_mode_action?/1)

    actions
    |> Enum.reverse()
    |> Enum.map_reduce(right, fn action, edge ->
      width = action_width(action, row, theme)
      bound = %{action: action, x: edge - width, y: row.y + 2, w: width, h: height}
      {bound, edge - width - 4}
    end)
    |> elem(0)
  end

  defp action_width({:replace_file, _}, _row, theme),
    do: round(theme.small_font_size * 6.2) + 20

  defp action_width({:replace_match, _, _, _}, _row, theme),
    do: round(theme.small_font_size * 4.2) + 12

  defp action_width({:dismiss_match, _, _, _}, %{skipped?: true}, theme),
    do: round(theme.small_font_size * 4.8) + 12

  defp action_width({:dismiss_match, _, _, _}, _row, theme),
    do: round(theme.small_font_size * 2.4) + 12

  defp action_width(_action, _row, theme), do: theme.row_height - 4

  defp replace_mode_action?({:replace_file, _}), do: true
  defp replace_mode_action?({:replace_match, _, _, _}), do: true
  defp replace_mode_action?({:dismiss_match, _, _, _}), do: true
  defp replace_mode_action?(_action), do: false

  # ── Hit testing ───────────────────────────────────────────────────────────

  @doc """
  What is under `{x, y}` (frame-local): a header widget id, a
  `{:row, row, action_or_nil}`, or `nil`.
  """
  # The panel is drawn over the results, so it is asked FIRST — otherwise a
  # click on it reaches the row underneath, which is not the thing the person
  # can see there. Asked of `Menu.Dropdown`, which is also what drew it: the
  # one map says where every row is, so drawing and hit testing cannot come
  # to different answers about it.
  def hit_test(%__MODULE__{domain_open?: true} = state, coords) do
    layout = settings_layout(state)

    # And the panel's own scrollbar before the panel's rows: it is drawn over
    # their right-hand end, so every point on the bar is also a point on a row.
    case ScenicWidgets.Menu.Dropdown.scrollbar_hit(layout, coords) do
      nil ->
        case ScenicWidgets.Menu.Dropdown.row_at(layout, coords) do
          nil -> unpanelled_hit_test(state, coords)
          :panel -> :settings_panel
          {row_id, local} -> {:settings_row, row_id, local}
        end

      bar ->
        {:settings_scrollbar, bar}
    end
  end

  def hit_test(%__MODULE__{} = state, coords), do: unpanelled_hit_test(state, coords)

  defp unpanelled_hit_test(%__MODULE__{} = state, {x, y}) do
    if y < header_height(state) do
      # REVERSE: the list is in drawing order and the thing drawn last is the
      # thing on top. The option toggles sit inside the query field's
      # right-hand end, so a forward search hands every click on them to the
      # field underneath — which is exactly what happened to the find bar
      # when its toggles moved inside its field.
      state
      |> header_widgets()
      |> Enum.reverse()
      |> Enum.find_value(fn w -> if inside?(w, x, y), do: w.id end)
    else
      body_hit(state, {x, y})
    end
  end

  # Which row is under the pointer is arithmetic — the rows are a uniform
  # height — so exactly one row is built to answer it. It used to build every
  # row in the pane and walk them looking for the one it had just computed the
  # index of.
  defp body_hit(%__MODULE__{theme: theme} = state, {x, y}) do
    content_y = y - header_height(state) + state.scroll.offset_y

    case state |> row_at(floor(content_y / theme.row_height)) do
      nil ->
        nil

      row ->
        action =
          Enum.find_value(action_bounds(state, row), fn b ->
            if x >= b.x and x < b.x + b.w and content_y >= b.y and content_y < b.y + b.h,
              do: b.action
          end)

        {:row, row, action || expander_hit(state, row, x)}
    end
  end

  # A scope directory carries its own disclosure triangle at the head of the
  # row: the triangle expands, the rest of the row ticks the directory in or
  # out. Ticking is much the commoner action, so it gets the wider target.
  defp expander_hit(%__MODULE__{theme: theme}, %{expandable?: true} = row, x) do
    left = theme.padding + row.depth * theme.indent

    if x >= left and x < left + 16, do: :expand
  end

  defp expander_hit(_state, _row, _x), do: nil

  defp inside?(%{x: bx, y: by, w: bw, h: bh}, x, y),
    do: x >= bx and x < bx + bw and y >= by and y < by + bh

  # ── Fields ────────────────────────────────────────────────────────────────
  #
  # The fields are TextField components. This module remembers WHAT is in them
  # and WHICH one the keyboard belongs to; it no longer implements typing —
  # there used to be a cursor, a backspace, a word-delete and a Home/End here,
  # all of them a worse version of what TextField already did, and none of
  # them offering selection or the clipboard at all.

  def field_value(%__MODULE__{} = state, field) when field in @fields,
    do: Map.fetch!(state, field)

  @doc "Record what a field now contains, as reported by the field itself."
  def put_field_value(%__MODULE__{} = state, field, text)
      when field in @fields and is_binary(text),
      do: Map.put(state, field, text)

  def focus_field(%__MODULE__{} = state, field) when field in @fields,
    do: %{state | focused_field: field}

  def next_field(%__MODULE__{focused_field: field} = state) do
    idx = Enum.find_index(@fields, &(&1 == field))
    %{state | focused_field: Enum.at(@fields, rem(idx + 1, length(@fields)))}
  end

  def prev_field(%__MODULE__{focused_field: field} = state) do
    idx = Enum.find_index(@fields, &(&1 == field))
    %{state | focused_field: Enum.at(@fields, rem(idx - 1 + length(@fields), length(@fields)))}
  end

  # ── Body state ────────────────────────────────────────────────────────────

  def toggle_scope_open(%__MODULE__{} = state),
    do: resync_scroll(%{state | scope_open?: not state.scope_open?})

  def toggle_scope_expand(%__MODULE__{} = state, id) do
    expanded =
      if MapSet.member?(state.expanded_scope, id),
        do: MapSet.delete(state.expanded_scope, id),
        else: MapSet.put(state.expanded_scope, id)

    resync_scroll(%{state | expanded_scope: expanded})
  end

  def toggle_file(%__MODULE__{} = state, path) do
    collapsed =
      if MapSet.member?(state.collapsed_files, path),
        do: MapSet.delete(state.collapsed_files, path),
        else: MapSet.put(state.collapsed_files, path)

    resync_scroll(%{state | collapsed_files: collapsed})
  end

  @doc "Recompute the scrollable content height after the rows changed."
  def resync_scroll(%__MODULE__{} = state) do
    content_height = row_count(state) * state.theme.row_height + state.theme.row_height
    body = body_frame(state)

    scroll =
      state.scroll
      |> ScrollState.update_viewport_size(body)
      |> ScrollState.update_content_size(body.size.width, content_height)
      |> show_scrollbar_if_scrollable()

    %{state | scroll: scroll}
  end

  # The pane's scrollbar is a permanent affordance, not a fade-in one: results
  # arrive in a burst and a bar that only appears once you already scrolled
  # cannot tell you there is more below.
  defp show_scrollbar_if_scrollable(scroll) do
    if ScrollState.scrollable_y?(scroll) do
      %{scroll | scrollbar_visible: true, scrollbar_opacity: 255}
    else
      %{scroll | scrollbar_visible: false, scrollbar_opacity: 0}
    end
  end
end
