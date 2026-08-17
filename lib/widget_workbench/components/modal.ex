defmodule WidgetWorkbench.Components.Modal do
  use Scenic.Component

  alias Scenic.Graph
  alias Scenic.Primitives
  alias Scenic.Components
  alias Scenic.Scene
  alias Widgex.Frame
  use ScenicWidgets.ScenicEventsDefinitions

  @moduledoc """
  A reusable modal component for displaying dialogs with input fields and buttons.
  """

  # Validate the data passed to the component
  def validate(%{id: id, frame: %Frame{} = _frame} = data), do: {:ok, data}
  def validate(_), do: {:error, "Invalid data for Modal component"}

  def init(scene, %{id: id, frame: frame, title: title, placeholder: placeholder}, _opts) do
    # Build the modal graph
    graph = render_modal(frame, title, placeholder)

    # Assign state to the scene
    scene =
      scene
      |> assign(id: id)
      |> assign(graph: graph)
      |> assign(frame: frame)
      |> assign(input_value: "")
      |> push_graph(graph)

    # Request input events
    Scene.request_input(scene, [:cursor_button, :key])

    {:ok, scene}
  end

  # Render the modal
  defp render_modal(%Frame{} = frame, title, placeholder) do
    modal_width = 400
    modal_height = 200
    modal_x = (frame.size.width - modal_width) / 2
    modal_y = (frame.size.height - modal_height) / 2

    Graph.build()
    |> Primitives.group(
      fn graph ->
        graph
        # Draw the semi-transparent background
        |> Primitives.rect(
          {frame.size.width, frame.size.height},
          fill: {:color, {0, 0, 0, 128}},
          translate: {0, 0}
        )
        # Draw the modal background
        |> Primitives.rounded_rectangle(
          {modal_width, modal_height, 10},
          fill: :white,
          stroke: {1, :dark_gray},
          translate: {modal_x, modal_y}
        )
        # Add the title
        |> Primitives.text(
          title,
          font_size: 24,
          fill: :black,
          text_align: :center,
          text_base: :top,
          translate: {modal_x + modal_width / 2, modal_y + 20}
        )
        # Add the input box
        |> Primitives.rect(
          {modal_width - 40, 40},
          fill: :light_gray,
          stroke: {1, :dark_gray},
          translate: {modal_x + 20, modal_y + 70}
        )
        # Display the placeholder or input value
        |> Primitives.text(
          "",
          id: :input_text,
          font_size: 18,
          fill: :black,
          text_align: :left,
          text_base: :middle,
          translate: {modal_x + 30, modal_y + 90}
        )
        # Add the "OK" button
        |> Components.button(
          "OK",
          id: :ok_button,
          width: 80,
          height: 30,
          translate: {modal_x + modal_width - 180, modal_y + modal_height - 50}
        )
        # Add the "Cancel" button
        |> Components.button(
          "Cancel",
          id: :cancel_button,
          width: 80,
          height: 30,
          translate: {modal_x + modal_width - 90, modal_y + modal_height - 50}
        )
      end,
      id: :modal_group
    )
  end

  # Handle input events
  def handle_input({:cursor_button, {:btn_left, 0, _, _}}, _context, scene), do: {:noreply, scene}

  def handle_input(@backspace, _context, scene) do
    input_value = String.slice(scene.assigns.input_value, 0..-2)
    update_input_text(scene, input_value)
  end

  def handle_input(@enter, _context, scene) do
    send_parent_event(scene, {:modal_submitted, scene.assigns.input_value})
    {:noreply, scene}
  end

  def handle_input({:key, {_k, @key_released, _meta}}, _context, scene) do
    {:noreply, scene}
  end

  def handle_input({:key, _k} = ii, _context, scene) when ii in @all_letters do
    input_value = scene.assigns.input_value <> key2string(ii)
    update_input_text(scene, input_value)
  end

  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  # Handle button clicks
  def handle_event({:click, :ok_button}, _from, scene) do
    send_parent_event(scene, {:modal_submitted, scene.assigns.input_value})
    {:noreply, scene}
  end

  def handle_event({:click, :cancel_button}, _from, scene) do
    send_parent_event(scene, :modal_cancelled)
    {:noreply, scene}
  end

  def handle_event(_event, _from, scene), do: {:noreply, scene}

  # Update the input text displayed
  defp update_input_text(scene, input_value) do
    graph =
      scene.assigns.graph
      |> Graph.modify(:input_text, &Primitives.text(&1, input_value))

    scene =
      scene
      |> assign(graph: graph)
      |> assign(input_value: input_value)
      |> push_graph(graph)

    {:noreply, scene}
  end

  # Send event to parent scene
  # defp send_parent_event(scene, event) do
  #   case scene.parent_pid do
  #     nil -> :ok
  #     pid -> send(pid, {event, self()})
  #   end
  # end
end
