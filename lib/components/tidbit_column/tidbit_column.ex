defmodule ScenicWidgets.TidbitColumn do
  @moduledoc """
  A scrollable column of tidbit cards.

  Demonstrates the Widgex.Scrollable system for reusable scroll behavior.
  Each tidbit is a card with title and preview text.

  ## Usage

      ScenicWidgets.TidbitColumn.add_to_graph(graph, %{frame: frame})

  ## Events

  Emits:
  - `{:tidbit_selected, tidbit_id}` when a tidbit is clicked
  - `{:tidbit_deselected, tidbit_id}` when a selected tidbit is clicked again
  """

  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions

  require Logger

  alias Scenic.Graph
  alias Widgex.Frame
  alias ScenicWidgets.TidbitColumn.{State, Reducer, Renderer}

  # ============================================================
  # Scenic Component Callbacks
  # ============================================================

  @impl Scenic.Component
  def validate(%{frame: %Frame{}} = data) do
    {:ok, data}
  end

  def validate(%Frame{} = frame) do
    {:ok, %{frame: frame}}
  end

  def validate(data) do
    {:error, "TidbitColumn requires %{frame: %Frame{}} or %Frame{}. Got: #{inspect(data)}"}
  end

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    state = State.new(data)
    graph = render_graph(state)

    scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    request_input(scene, [:cursor_pos, :cursor_button, :cursor_scroll])

    {:ok, scene}
  end

  @impl Scenic.Scene
  def handle_input({:cursor_scroll, _} = input, _context, scene) do
    state = scene.assigns.state

    case Reducer.process_input(state, input) do
      {:noop, ^state} ->
        {:noreply, scene}

      {:noop, new_state} ->
        new_graph = Renderer.update_render(scene.assigns.graph, state, new_state)
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)
        {:noreply, new_scene}
    end
  end

  def handle_input(input, _context, scene) do
    state = scene.assigns.state

    case Reducer.process_input(state, input) do
      {:noop, ^state} ->
        {:noreply, scene}

      {:noop, new_state} ->
        new_graph = Renderer.update_render(scene.assigns.graph, state, new_state)
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)
        {:noreply, new_scene}

      {:item_selected, item_id, new_state} ->
        Logger.info("[TidbitColumn] Selected: #{item_id}")
        notify_parent(scene, {:tidbit_selected, item_id})
        new_graph = Renderer.update_render(scene.assigns.graph, state, new_state)
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)
        {:noreply, new_scene}

      {:item_deselected, item_id, new_state} ->
        Logger.info("[TidbitColumn] Deselected: #{item_id}")
        notify_parent(scene, {:tidbit_deselected, item_id})
        new_graph = Renderer.update_render(scene.assigns.graph, state, new_state)
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)
        {:noreply, new_scene}
    end
  end

  # ============================================================
  # Private Functions
  # ============================================================

  defp render_graph(%State{} = state) do
    Graph.build(font: :roboto_mono)
    |> Renderer.initial_render(state)
  end

  defp notify_parent(scene, event) do
    send(scene.parent, {:tidbit_column_event, event})
  end
end
