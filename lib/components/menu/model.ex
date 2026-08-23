defmodule ScenicWidgets.Menu.Model do
  @moduledoc "Typed data-only menu/popover contract."

  defmodule Item do
    @enforce_keys [:id, :label]
    defstruct [:id, :label, :icon, :shortcut, :tooltip, flush_left?: false, enabled?: true]
  end

  defmodule Toggle do
    @enforce_keys [:id, :label, :checked?]
    defstruct [:id, :label, :checked?, :tooltip, enabled?: true]
  end

  defmodule Radio do
    @enforce_keys [:id, :label, :group, :value, :selected?]
    defstruct [:id, :label, :group, :value, :selected?, :tooltip, enabled?: true]
  end

  defmodule Slider do
    @enforce_keys [:id, :label, :value, :min, :max]
    defstruct [:id, :label, :value, :min, :max, :tooltip, step: 1, enabled?: true]
  end

  defmodule Divider do
    @moduledoc "A non-interactive horizontal separator between groups of menu rows."
    @enforce_keys [:id]
    defstruct [:id, enabled?: false]
  end

  defmodule Select do
    @moduledoc "An inline dropdown selector with a finite set of choices."
    @enforce_keys [:id, :label, :value, :options]
    defstruct [
      :id,
      :label,
      :value,
      :options,
      :tooltip,
      :option_width,
      :swatches,
      :closed_caret,
      options_full_width?: false,
      expanded?: false,
      enabled?: true
    ]
  end

  defmodule Stepper do
    @moduledoc "A numeric menu control with reusable decrement and increment buttons."
    @enforce_keys [:id, :label, :value, :min, :max]
    defstruct [:id, :label, :value, :min, :max, :tooltip, step: 1, enabled?: true]
  end

  defmodule Segmented do
    @moduledoc """
    An either/or, as one control with a position per choice.

    Two or three things you are picking BETWEEN, where the choices are worth
    showing at once — tree or list, on or off-or-auto. A row of buttons would
    say "here are three things you can do"; this says "here is one setting,
    and it is currently that", which is what it is.

    `Select` is the other shape: a value out of a list too long to show, behind
    a box you open. Past three or four choices, use that one.
    """
    @enforce_keys [:id, :label, :value, :options]
    defstruct [:id, :label, :value, :options, :tooltip, enabled?: true]
  end

  defmodule TreeNode do
    @moduledoc """
    One thing in a `Tree`: tickable, and possibly holding more of them.

    `children` being empty is what makes a node a leaf — there is no separate
    kind for it, because a directory with nothing in it and a file are the
    same thing as far as picking them goes.
    """
    @enforce_keys [:id, :label]
    defstruct [:id, :label, checked?: true, expanded?: false, children: []]
  end

  defmodule Tree do
    @moduledoc """
    A tree of things you can tick, inside a menu row.

    The same shape as `Select` — a row that expands in place rather than
    flying out sideways — but with more than one level and a tick on every
    node instead of one value out of a list. Anything a person needs to
    pick a SET out of, where the set has structure, fits here: which
    directories a search may look in, which buffers to act on, which of a
    project's targets to build.

    An open tree is as tall as it has nodes. It used to cap itself at
    `max_visible` and scroll inside its own row, which meant a panel holding
    one had two scrolling mechanisms in it — the row's, in units of nodes, and
    the panel's, in pixels — and a person turning the wheel could not tell
    which of them they had. The panel scrolls; a row is just a row, however
    tall it is.
    """
    @enforce_keys [:id, :label, :nodes]
    defstruct [
      :id,
      :label,
      :nodes,
      :tooltip,
      :closed_caret,
      expanded?: false,
      enabled?: true
    ]
  end

  defmodule Submenu do
    @enforce_keys [:id, :label, :rows]
    defstruct [:id, :label, :rows, :tooltip, enabled?: true]
  end

  defmodule Section do
    @enforce_keys [:id, :label]
    defstruct [:id, :label, enabled?: false]
  end

  @enforce_keys [:id, :rows]
  defstruct [:id, :rows, autohide?: true]

  def validate(%__MODULE__{id: id, rows: rows} = model) when is_atom(id) and is_list(rows) do
    with :ok <- unique_ids(rows), :ok <- valid_rows(rows), do: {:ok, model}
  end

  def validate(_), do: {:error, :invalid_menu}

  def event(%__MODULE__{id: menu_id}, %{id: item_id}, value \\ :activate),
    do: {:menu_action, menu_id, item_id, value}

  defp unique_ids(rows) do
    ids = Enum.flat_map(rows, &row_ids/1)
    if length(ids) == length(Enum.uniq(ids)), do: :ok, else: {:error, :duplicate_id}
  end

  defp row_ids(%Submenu{id: id, rows: rows}), do: [id | Enum.flat_map(rows, &row_ids/1)]
  defp row_ids(%{id: id}), do: [id]
  defp row_ids(_), do: []

  defp valid_rows(rows),
    do: if(Enum.all?(rows, &valid_row?/1), do: :ok, else: {:error, :invalid_row})

  defp valid_row?(%Submenu{rows: rows}), do: valid_rows(rows) == :ok

  defp valid_row?(%Slider{min: min, max: max, value: value, step: step}),
    do: is_number(value) and is_number(step) and step > 0 and value >= min and value <= max

  defp valid_row?(%module{})
       when module in [Item, Toggle, Radio, Section, Divider, Select, Stepper],
       do: true

  defp valid_row?(row) when row in [:divider, :space], do: true
  defp valid_row?(_), do: false

  # ── Working with a Tree ─────────────────────────────────────────────────
  #
  # Every part of a menu that deals with a tree — how tall the row is, what to
  # draw, what was clicked — needs the same thing: the nodes that are actually
  # showing, in order, each with how deep it is. So it is computed in one
  # place and handed out.

  @doc """
  A `Segmented` row's choices, as `{value, label}` pairs.

  Written either as bare values (`[:tree, :list]`, labelled by their own
  names) or as pairs when the label should differ from the value.
  """
  def segments(%Segmented{options: options}) do
    Enum.map(options, fn
      {value, label} -> {value, label}
      value -> {value, to_string(value)}
    end)
  end

  @doc "A Select's choices, normalised to `{value, label}` pairs."
  def select_options(%Select{options: options}) do
    Enum.map(options, fn
      {value, label} -> {value, label}
      value -> {value, to_string(value)}
    end)
  end

  @doc "The label shown for a Select's current value."
  def select_label(%Select{value: value} = select) do
    case Enum.find(select_options(select), fn {option, _label} -> option == value end) do
      {_value, label} -> label
      nil -> to_string(value)
    end
  end

  @doc "Which segment a point along the control's width falls in."
  def segment_at(%Segmented{} = seg, x, width) do
    all = segments(seg)
    count = length(all)
    index = min(trunc(x / max(width / count, 1)), count - 1)

    case Enum.at(all, max(index, 0)) do
      {value, _label} -> value
      nil -> nil
    end
  end

  @doc """
  How far one level of a tree is indented, in pixels.

  Defined ONCE and read by both the renderer and the reducer: it is what
  decides where a triangle is drawn AND what counts as a click on it, and the
  two disagreeing means a triangle you cannot hit.
  """
  def tree_indent, do: 12

  @doc "The nodes on screen, top to bottom, as `{node, depth}`."
  def visible_tree_nodes(%Tree{nodes: nodes}), do: visible_tree_nodes(nodes, 0)

  def visible_tree_nodes(nodes, depth) when is_list(nodes) do
    Enum.flat_map(nodes, fn %TreeNode{} = node ->
      if node.expanded? and node.children != [] do
        [{node, depth} | visible_tree_nodes(node.children, depth + 1)]
      else
        [{node, depth}]
      end
    end)
  end

  @doc "How many rows the tree shows, with its shut branches shut."
  def tree_node_count(%Tree{} = tree), do: length(visible_tree_nodes(tree))

  @doc """
  Replace a node anywhere in the tree, by id.

  `fun` receives the node and returns the new one. Nodes it does not match
  come back untouched, so a caller never has to walk the tree itself.
  """
  def update_tree_node(%Tree{nodes: nodes} = tree, node_id, fun) when is_function(fun, 1),
    do: %{tree | nodes: update_nodes(nodes, node_id, fun)}

  defp update_nodes(nodes, node_id, fun) do
    Enum.map(nodes, fn
      %TreeNode{id: ^node_id} = node -> fun.(node)
      %TreeNode{} = node -> %{node | children: update_nodes(node.children, node_id, fun)}
    end)
  end

  @doc "Tick or untick a node. Ticking is the caller's business below that."
  def toggle_tree_node(%Tree{} = tree, node_id),
    do: update_tree_node(tree, node_id, &%{&1 | checked?: not &1.checked?})

  @doc "Open or shut a node, which only means anything if it has children."
  def toggle_tree_expanded(%Tree{} = tree, node_id),
    do: update_tree_node(tree, node_id, &%{&1 | expanded?: not &1.expanded?})

  @doc "Find a node by id, or nil."
  def find_tree_node(%Tree{} = tree, node_id) do
    Enum.find_value(visible_tree_nodes(tree), fn {node, _depth} ->
      if node.id == node_id, do: node
    end)
  end

  # ── Reading a row ───────────────────────────────────────────────────────
  #
  # A row's id, its label, how tall it is — what anything drawing menu rows
  # needs to know. These lived in IconMenu.State, reachable by one component
  # only, which is why a second thing wanting to draw a menu row had to
  # reimplement one instead.

  @doc """
  Extract the ID from a menu item tuple (supports all formats).
  """
  def get_item_id({id, _label}), do: id
  def get_item_id({id, _label, _opts_or_action}), do: id
  def get_item_id(%{id: id}), do: id

  @doc """
  Extract the label from a menu item tuple.
  """
  def get_item_label({_id, label}), do: label
  def get_item_label({_id, label, _opts_or_action}), do: label
  def get_item_label(%{label: label}), do: label

  def display_label(%ScenicWidgets.Menu.Model.Divider{}), do: ""
  def display_label(%ScenicWidgets.Menu.Model.Select{label: label}), do: label
  def display_label(%ScenicWidgets.Menu.Model.Segmented{label: label}), do: label

  def display_label(%ScenicWidgets.Menu.Model.Slider{label: label, value: value}),
    do: "#{label}: #{value}"

  def display_label(%ScenicWidgets.Menu.Model.Submenu{label: label}), do: label <> "  ›"

  # How much of the tree is unticked, on the row you open it from — the whole
  # reason to look at it is usually to check whether anything is switched off.
  def display_label(%ScenicWidgets.Menu.Model.Tree{label: label} = tree) do
    case unchecked_count(tree.nodes) do
      0 -> label
      n -> "#{label}  (#{n} off)"
    end
  end

  def display_label(item), do: get_item_label(item)

  # An unticked branch counts ONCE, not once per thing inside it: a folder
  # with forty files in it is one decision, not forty-one.
  defp unchecked_count(nodes) do
    Enum.reduce(nodes, 0, fn node, acc ->
      if node.checked?, do: acc + unchecked_count(node.children), else: acc + 1
    end)
  end

  @doc "Returns a menu item's shortcut as a separate, right-aligned column."
  def item_shortcut(item), do: item_shortcut(item, true)
  def item_shortcut(%{shortcut: shortcut}, true) when is_binary(shortcut), do: shortcut
  def item_shortcut(_item, _show_shortcuts), do: nil

  @doc "Returns the row height for an item; interactive sliders receive extra vertical space."
  def item_height(%ScenicWidgets.Menu.Model.Slider{}, theme),
    do: Map.get(theme, :dropdown_slider_height, 52)

  def item_height(%ScenicWidgets.Menu.Model.Divider{}, theme),
    do: Map.get(theme, :dropdown_divider_height, 13)

  # An open Select or Tree is its header row plus everything under it. Neither
  # caps itself any more: a row that hid its own tail behind its own scroll
  # offset put a second scrolling mechanism inside a panel that already had
  # one, and the panel is the one with a scrollbar on it.
  def item_height(%ScenicWidgets.Menu.Model.Select{expanded?: true, options: options}, theme),
    do: theme.dropdown_item_height * (length(options) + 1)

  def item_height(%ScenicWidgets.Menu.Model.Tree{expanded?: true} = tree, theme),
    do: theme.dropdown_item_height * (ScenicWidgets.Menu.Model.tree_node_count(tree) + 1)

  def item_height(_item, theme), do: theme.dropdown_item_height

  def get_item_opts({_id, _label}), do: %{}
  def get_item_opts({_id, _label, opts}) when is_map(opts), do: opts
  def get_item_opts({_id, _label, _action}), do: %{}

  def get_item_opts(%ScenicWidgets.Menu.Model.Toggle{checked?: checked, enabled?: enabled}),
    do: %{type: :toggle, checked: checked, enabled: enabled}

  def get_item_opts(%ScenicWidgets.Menu.Model.Radio{selected?: selected, enabled?: enabled}),
    do: %{type: :radio, checked: selected, enabled: enabled}

  def get_item_opts(%ScenicWidgets.Menu.Model.Slider{enabled?: enabled}),
    do: %{type: :slider, enabled: enabled}

  def get_item_opts(%{enabled?: enabled}), do: %{enabled: enabled}

  @doc """
  Check if a menu item is a toggle type.
  """
  def is_toggle_item?(item) do
    opts = get_item_opts(item)
    Map.get(opts, :type) in [:toggle, :radio]
  end

  @doc """
  Check if a toggle item is checked.
  """
  def is_item_checked?(item) do
    opts = get_item_opts(item)
    Map.get(opts, :checked, false)
  end

  @doc "Whether a row can be interacted with at all."
  def item_enabled?(item), do: Map.get(get_item_opts(item), :enabled, true)
end
