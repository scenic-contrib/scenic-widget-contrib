defmodule ScenicWidgets.FilePicker do
  @moduledoc """
  A graphical file picker modal component for Scenic.

  Displays a navigable file system browser with:
  - Current directory path display
  - Clickable directory navigation
  - File selection with keyboard and mouse
  - Scrollable file list
  - Open/Cancel buttons

  ## Usage

      # Add to your scene's graph
      graph
      |> FilePicker.add_to_graph(
        %{
          frame: scene_frame,
          start_path: "/home/user",
          show_hidden: false
        },
        id: :file_picker
      )

  ## Events

  The FilePicker casts events to its parent:
  - `{:file_picker, :file_selected, path}` - User selected a file
  - `{:file_picker, :cancelled}` - User cancelled the picker

  ## Keyboard Navigation

  - Up/Down arrows: Navigate file list
  - Enter: Open selected folder or select file
  - Backspace: Go to parent directory
  - Escape: Cancel and close picker

  ## Options

  - `:start_path` - Initial directory (default: user home)
  - `:show_hidden` - Show hidden files starting with "." (default: false)
  - `:filter` - File extension filter, e.g. ".txt" (default: nil = all files)
  """

  use Scenic.Component, has_children: true
  require Logger

  alias Scenic.Graph
  alias ScenicWidgets.FilePicker.{State, Renderer, Reducer}

  # ===== VALIDATION =====

  @doc """
  Validate FilePicker initialization data.
  """
  def validate(%{frame: %Widgex.Frame{}} = data) do
    {:ok, data}
  end

  def validate(data) do
    {:error, "FilePicker requires map with :frame. Got: #{inspect(data)}"}
  end

  # ===== LIFECYCLE =====

  @doc """
  Initialize the FilePicker component.
  """
  def init(scene, data, _opts) do
    state = State.new(data)
    graph = Renderer.initial_render(Graph.build(), state)

    scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    # Request input for keyboard navigation
    # In save mode, also request codepoint for typing filename
    input_types =
      if state.mode == :save do
        [:cursor_scroll, :cursor_button]
      else
        [:key, :cursor_scroll, :cursor_button]
      end

    request_input(scene, input_types)

    if state.mode == :save, do: send(self(), :focus_filename)

    {:ok, scene}
  end

  # ===== INPUT HANDLING =====

  @doc """
  Handle keyboard and scroll input.
  """
  def handle_input({:key, _} = input, _context, scene) do
    handle_reducer_result(scene, Reducer.process_input(scene.assigns.state, input))
  end

  # Handle character input for filename in save mode
  def handle_input({:codepoint, _} = input, _context, scene) do
    handle_reducer_result(scene, Reducer.process_input(scene.assigns.state, input))
  end

  def handle_input({:cursor_scroll, _} = input, _context, scene) do
    handle_reducer_result(scene, Reducer.process_input(scene.assigns.state, input))
  end

  # Handle mouse click on file list or overlay
  def handle_input({:cursor_button, {:btn_left, 1, _mods, coords}}, _context, scene) do
    cond do
      # Check if click is on the overlay (outside modal) - cancel
      click_on_overlay?(scene.assigns.state, coords) ->
        handle_reducer_result(scene, {:action, :cancel})

      # Check if click is on any button
      button = click_on_button?(scene.assigns.state, coords) ->
        handle_reducer_result(scene, Reducer.process_event(button, scene.assigns.state))

      # Check if click is within the file list area
      match?({:ok, _}, click_in_list_area?(scene.assigns.state, coords)) ->
        {:ok, local_coords} = click_in_list_area?(scene.assigns.state, coords)

        # Check for double-click (activate on double-click)
        now = System.monotonic_time(:millisecond)
        last_click = Map.get(scene.assigns, :last_click_time, 0)
        last_coords = Map.get(scene.assigns, :last_click_coords, {0, 0})

        is_double_click = now - last_click < 400 and coords_close?(coords, last_coords)

        scene =
          scene
          |> assign(last_click_time: now)
          |> assign(last_click_coords: coords)

        if is_double_click do
          handle_reducer_result(
            scene,
            Reducer.process_double_click(scene.assigns.state, local_coords)
          )
        else
          handle_reducer_result(scene, Reducer.process_click(scene.assigns.state, local_coords))
        end

      true ->
        # Click somewhere else in modal (header/footer area)
        {:noreply, scene}
    end
  end

  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  # ===== EVENT HANDLING =====

  @doc """
  Handle button click events from child components.
  """
  def handle_event({:click, button_id}, _from, scene) do
    handle_reducer_result(scene, Reducer.process_event(button_id, scene.assigns.state))
  end

  def handle_event({:text_changed, :filename_input, text}, _from, scene) do
    state = %{scene.assigns.state | filename: text, filename_cursor: String.length(text)}
    {:noreply, assign(scene, state: state)}
  end

  def handle_event({:enter_pressed, :filename_input, text}, _from, scene) do
    state = %{scene.assigns.state | filename: text, filename_cursor: String.length(text)}
    handle_reducer_result(scene, Reducer.process_event(:save_button, state))
  end

  def handle_event({:escape_pressed, :filename_input}, _from, scene) do
    handle_reducer_result(scene, {:action, :cancel})
  end

  def handle_event(_event, _from, scene) do
    {:noreply, scene}
  end

  def handle_info(:focus_filename, scene) do
    Scenic.Scene.put_child(scene, :filename_input, :focus)
    {:noreply, scene}
  end

  # ===== PRIVATE HELPERS =====

  # Process reducer results and update scene accordingly
  defp handle_reducer_result(scene, result) do
    case result do
      {:state, new_state} ->
        new_graph = Renderer.update_render(scene.assigns.graph, scene.assigns.state, new_state)

        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        {:noreply, new_scene}

      {:action, {:file_selected, path}} ->
        # Notify parent that a file was selected (open mode)
        cast_parent(scene, {:file_picker, :file_selected, path})
        {:noreply, scene}

      {:action, {:file_saved, path}} ->
        # Notify parent that a file save path was chosen (save mode)
        cast_parent(scene, {:file_picker, :file_saved, path})
        {:noreply, scene}

      {:action, :cancel} ->
        # Notify parent that picker was cancelled
        cast_parent(scene, {:file_picker, :cancelled})
        {:noreply, scene}

      :noop ->
        {:noreply, scene}
    end
  end

  # Check if a click is within the file list area and return local coordinates
  defp click_in_list_area?(%State{frame: frame, mode: mode}, {click_x, click_y}) do
    {frame_width, frame_height} = frame.size.box

    # Modal dimensions
    modal_width = frame_width * 0.7
    modal_height = frame_height * 0.7
    modal_x = (frame_width - modal_width) / 2
    modal_y = (frame_height - modal_height) / 2

    # Footer height depends on mode
    footer_height = if mode == :save, do: 110, else: 70
    header_height = 60

    # List area dimensions (inside modal)
    list_x = modal_x + 20
    # After header
    list_y = modal_y + header_height
    list_width = modal_width - 40
    list_height = modal_height - header_height - footer_height

    # Check if click is within list bounds
    if click_x >= list_x and click_x <= list_x + list_width and
         click_y >= list_y and click_y <= list_y + list_height do
      # Return coordinates relative to list area
      {:ok, {click_x - list_x, click_y - list_y}}
    else
      :outside
    end
  end

  # Check if two coordinates are close enough to be considered a double-click
  defp coords_close?({x1, y1}, {x2, y2}) do
    abs(x1 - x2) < 10 and abs(y1 - y2) < 10
  end

  # Check if click is on the overlay (outside the modal)
  defp click_on_overlay?(%State{frame: frame}, {click_x, click_y}) do
    {frame_width, frame_height} = frame.size.box

    # Modal dimensions
    modal_width = frame_width * 0.7
    modal_height = frame_height * 0.7
    modal_x = (frame_width - modal_width) / 2
    modal_y = (frame_height - modal_height) / 2

    # Click is on overlay if it's outside the modal bounds
    click_x < modal_x or click_x > modal_x + modal_width or
      click_y < modal_y or click_y > modal_y + modal_height
  end

  # Check if click is on any button, returns button id or nil
  defp click_on_button?(%State{frame: frame, mode: mode}, {click_x, click_y}) do
    {frame_width, frame_height} = frame.size.box

    # Modal dimensions
    modal_width = frame_width * 0.7
    modal_height = frame_height * 0.7
    modal_x = (frame_width - modal_width) / 2
    modal_y = (frame_height - modal_height) / 2

    # Footer height depends on mode (must match renderer)
    footer_height = if mode == :save, do: 110, else: 70

    # Button y position in footer (save mode has buttons lower due to filename input)
    button_y_offset = if mode == :save, do: 72, else: 15

    # Button definitions: {id, x, y, width, height}
    # The action button is either :open_button or :save_button based on mode
    action_button_id = if mode == :save, do: :save_button, else: :open_button

    buttons = [
      # Up button in header
      {:up_button, modal_x + 15, modal_y + 12, 60, 36},
      # Cancel button in footer
      {:cancel_button, modal_x + modal_width - 200,
       modal_y + modal_height - footer_height + button_y_offset, 85, 36},
      # Open/Save button in footer
      {action_button_id, modal_x + modal_width - 100,
       modal_y + modal_height - footer_height + button_y_offset, 85, 36}
    ]

    # Find which button (if any) was clicked
    Enum.find_value(buttons, fn {id, bx, by, bw, bh} ->
      if click_x >= bx and click_x <= bx + bw and
           click_y >= by and click_y <= by + bh do
        id
      else
        nil
      end
    end)
  end
end
