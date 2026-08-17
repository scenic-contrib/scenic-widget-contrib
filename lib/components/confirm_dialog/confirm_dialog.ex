defmodule ScenicWidgets.ConfirmDialog do
  @moduledoc """
  A modal confirmation dialog component for Scenic.

  Renders a centred dialog with a title, message, and a row of action buttons.
  Each button fires a `{:confirm_dialog_response, id, action}` event to the
  parent scene when clicked. The same events are fired by keyboard shortcuts:

  - `s` / `Enter` on `:save` buttons — saves and closes
  - `d`           on `:discard` buttons — discards and closes
  - `Escape`      — equivalent to `:cancel`

  ## Usage

      graph
      |> ScenicWidgets.ConfirmDialog.add_to_graph(
        %{
          frame:   scene_frame,
          title:   "Unsaved Changes",
          message: "Save changes to \\"my_file.txt\\" before closing?",
          buttons: [{:save, "Save"}, {:discard, "Discard"}, {:cancel, "Cancel"}]
        },
        id: :unsaved_prompt
      )

  ## Events

  `{:confirm_dialog_response, id, action}` — where `action` is one of the
  atoms given in the `:buttons` list (e.g. `:save`, `:discard`, `:cancel`).

  ## Layout constants

  - Dialog width: 420px
  - Button width: 100px, height: 32px, spacing: 16px
  - Dialog is centred in the viewport
  """

  use Scenic.Component, has_children: false
  require Logger

  import Scenic.Primitives

  alias Scenic.Graph

  # ─────────────────────────────────────────────────
  # Layout constants
  # ─────────────────────────────────────────────────

  @dialog_width 420
  @dialog_height 200
  @button_width 100
  @button_height 32
  @button_spacing 16
  # y inside the dialog box where the button row starts
  @button_y_offset 140

  # ─────────────────────────────────────────────────
  # Validation
  # ─────────────────────────────────────────────────

  @doc """
  Validate ConfirmDialog initialisation data.

  Expects a map with:
  - `:frame`   — a map (viewport/scene frame; used to centre the dialog)
  - `:title`   — binary title string
  - `:message` — binary body string
  - `:buttons` — non-empty list of `{atom, binary}` tuples

  Extra keys are passed through unchanged.
  """
  @impl Scenic.Component
  def validate(%{frame: frame, title: title, message: message, buttons: buttons} = data)
      when is_map(frame) and is_binary(title) and is_binary(message) do
    case validate_buttons(buttons) do
      :ok -> {:ok, data}
      {:error, msg} -> {:error, msg}
    end
  end

  def validate(%{frame: frame} = _data) when not is_map(frame) do
    {:error, "ConfirmDialog :frame must be a map, got: #{inspect(frame)}"}
  end

  def validate(%{title: title} = _data) when not is_binary(title) do
    {:error, "ConfirmDialog :title must be a binary string, got: #{inspect(title)}"}
  end

  def validate(%{message: msg} = _data) when not is_binary(msg) do
    {:error, "ConfirmDialog :message must be a binary string, got: #{inspect(msg)}"}
  end

  def validate(data) do
    missing =
      [:frame, :title, :message, :buttons]
      |> Enum.reject(&Map.has_key?(data, &1))

    {:error, "ConfirmDialog missing required keys: #{inspect(missing)}"}
  end

  defp validate_buttons([]), do: {:error, "ConfirmDialog :buttons must be a non-empty list"}

  defp validate_buttons(buttons) when is_list(buttons) do
    Enum.reduce_while(buttons, :ok, fn
      {action, label}, :ok when is_atom(action) and is_binary(label) ->
        {:cont, :ok}

      {action, _label}, :ok when not is_atom(action) ->
        {:halt, {:error, "ConfirmDialog button action must be an atom, got: #{inspect(action)}"}}

      {_action, label}, :ok when not is_binary(label) ->
        {:halt, {:error, "ConfirmDialog button label must be a string, got: #{inspect(label)}"}}

      _other, :ok ->
        {:halt, {:error, "ConfirmDialog each button must be a 2-tuple {atom, binary}"}}
    end)
  end

  defp validate_buttons(_), do: {:error, "ConfirmDialog :buttons must be a list"}

  # ─────────────────────────────────────────────────
  # Public helpers (pure, testable without Scenic)
  # ─────────────────────────────────────────────────

  @doc """
  Return the fill colour for a button based on its action atom.

  Colour semantics:
  - `:save`    → green  (positive / primary action)
  - `:discard` → orange (destructive action — caution colour)
  - anything else (`:cancel`, unknown) → grey (neutral)
  """
  def button_color(:save), do: {60, 130, 70}
  def button_color(:discard), do: {170, 100, 30}
  def button_color(_), do: {80, 80, 85}

  @doc """
  Compute layout bounds for a list of buttons.

  Returns a list of `{action, x, y, width, height}` tuples (one per button),
  positioned so the entire row is horizontally centred within `@dialog_width`.

  The `x` and `y` offsets are *relative to the dialog box origin* (not the
  full viewport).
  """
  def button_bounds(buttons) do
    n = length(buttons)
    row_width = n * @button_width + (n - 1) * @button_spacing
    start_x = (@dialog_width - row_width) / 2

    buttons
    |> Enum.with_index()
    |> Enum.map(fn {{action, _label}, idx} ->
      x = start_x + idx * (@button_width + @button_spacing)
      {action, x, @button_y_offset, @button_width, @button_height}
    end)
  end

  # ─────────────────────────────────────────────────
  # Lifecycle
  # ─────────────────────────────────────────────────

  @impl Scenic.Scene
  def init(scene, data, opts) do
    id = Keyword.get(opts, :id, :confirm_dialog)
    graph = render_graph(data, id)

    scene =
      scene
      |> assign(data: data, id: id)
      |> push_graph(graph)

    request_input(scene, [:key, :cursor_button])

    {:ok, scene}
  end

  # ─────────────────────────────────────────────────
  # Input handling
  # ─────────────────────────────────────────────────

  @impl Scenic.Scene
  def handle_input({:key, {:key_esc, 1, _mods}}, _ctx, scene) do
    emit_response(scene, :cancel)
  end

  def handle_input({:key, {:key_s, 1, _mods}}, _ctx, scene) do
    data = scene.assigns.data

    if action_present?(data.buttons, :save) do
      emit_response(scene, :save)
    else
      {:noreply, scene}
    end
  end

  def handle_input({:key, {:key_d, 1, _mods}}, _ctx, scene) do
    data = scene.assigns.data

    if action_present?(data.buttons, :discard) do
      emit_response(scene, :discard)
    else
      {:noreply, scene}
    end
  end

  def handle_input({:cursor_button, {:btn_left, 1, _mods, coords}}, _ctx, scene) do
    data = scene.assigns.data
    {vw, vh} = viewport_size(data.frame)
    # Dialog is rendered at the centre of the viewport
    dlg_x = (vw - @dialog_width) / 2
    dlg_y = (vh - @dialog_height) / 2

    # Check if click lands on a button
    bounds = button_bounds(data.buttons)

    clicked =
      Enum.find(bounds, fn {_action, bx, by, bw, bh} ->
        {cx, cy} = coords
        abs_x = dlg_x + bx
        abs_y = dlg_y + by
        cx >= abs_x and cx <= abs_x + bw and cy >= abs_y and cy <= abs_y + bh
      end)

    case clicked do
      {action, _, _, _, _} -> emit_response(scene, action)
      nil -> {:noreply, scene}
    end
  end

  def handle_input(_input, _ctx, scene), do: {:noreply, scene}

  # ─────────────────────────────────────────────────
  # Private rendering
  # ─────────────────────────────────────────────────

  defp render_graph(data, id) do
    {vw, vh} = viewport_size(data.frame)
    dlg_x = (vw - @dialog_width) / 2
    dlg_y = (vh - @dialog_height) / 2

    bounds = button_bounds(data.buttons)

    shell_bounds = ScenicWidgets.ModalShell.bounds(data.frame, {@dialog_width, @dialog_height})

    Graph.build()
    |> ScenicWidgets.ModalShell.overlay(data.frame, :"#{id}_overlay")
    |> ScenicWidgets.ModalShell.panel(shell_bounds, :"#{id}_bg")
    # Title
    |> text(data.title,
      translate: {dlg_x + 20, dlg_y + 36},
      fill: :white,
      font_size: 18,
      font_weight: :bold,
      id: :"#{id}_title"
    )
    # Message
    |> text(data.message,
      translate: {dlg_x + 20, dlg_y + 76},
      fill: {200, 200, 205},
      font_size: 14,
      id: :"#{id}_msg"
    )
    # Buttons
    |> render_buttons(data.buttons, bounds, dlg_x, dlg_y, id)
  end

  defp render_buttons(graph, buttons, bounds, dlg_x, dlg_y, id) do
    Enum.zip(buttons, bounds)
    |> Enum.reduce(graph, fn {{_action, label}, {action, bx, by, bw, bh}}, g ->
      color = button_color(action)
      btn_id = :"#{id}_btn_#{action}"

      g
      |> rrect({bw, bh, 4},
        fill: color,
        translate: {dlg_x + bx, dlg_y + by},
        input: :cursor_button,
        id: btn_id
      )
      |> text(label,
        translate: {dlg_x + bx + bw / 2, dlg_y + by + bh - 8},
        fill: :white,
        font_size: 13,
        text_align: :center,
        id: :"#{btn_id}_lbl"
      )
    end)
  end

  defp emit_response(scene, action) do
    id = scene.assigns.id
    Scenic.Scene.send_parent_event(scene, {:confirm_dialog_response, id, action})
    {:noreply, scene}
  end

  defp action_present?(buttons, action) do
    Enum.any?(buttons, fn {a, _} -> a == action end)
  end

  # A %Widgex.Frame{} matches the first clause (its :size has width/height).
  # No fabricated fallback — an unrecognised frame shape is a caller bug and
  # should crash here, not mis-centre the dialog against an invented 800x600.
  defp viewport_size(%{size: %{width: w, height: h}}), do: {w, h}
  defp viewport_size({w, h}) when is_number(w) and is_number(h), do: {w, h}
end
