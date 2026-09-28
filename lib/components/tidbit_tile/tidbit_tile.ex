defmodule ScenicWidgets.TidbitTile do
  @moduledoc """
  A card-like component for displaying a tidbit.

  TidbitTile is designed for use in Kanban/Trello-like interfaces where
  tidbits (similar to TiddlyWiki's tiddlers) are organized into columns.

  ## Features
  - Clean card appearance with rounded corners
  - Hover highlighting
  - Selection state
  - Click events

  ## Usage

      tidbit = %{
        id: "tidbit_123",
        title: "My First Tidbit"
      }

      graph
      |> ScenicWidgets.TidbitTile.add_to_graph(
        %{frame: frame, id: tidbit.id, title: tidbit.title},
        id: :my_tidbit
      )

  ## Events

  TidbitTile sends these events to the parent scene:
  - `{:tidbit_clicked, tidbit_id}` - When the tile is clicked
  - `{:tidbit_selected, tidbit_id}` - When the tile is selected (could be same as clicked)

  ## Theme Customization

      %{
        frame: frame,
        title: "My Tidbit",
        theme: %{
          background: {255, 255, 240},  # Light yellow
          border_radius: 8
        }
      }
  """

  use Scenic.Component, has_children: false
  require Logger

  alias ScenicWidgets.TidbitTile.{State, Renderer}
  alias Scenic.Graph

  @impl Scenic.Component
  def validate(%Widgex.Frame{} = frame) do
    {:ok, %{frame: frame, title: "Demo Tidbit"}}
  end

  def validate(%{frame: %Widgex.Frame{}} = data) do
    {:ok, data}
  end

  def validate(%{frame: %{pin: _, size: _}} = data) do
    {:ok, data}
  end

  def validate(_) do
    {:error, "TidbitTile requires :frame (Widgex.Frame) and optional :title"}
  end

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    state = State.new(data)
    graph = Renderer.initial_render(Graph.build(), state)

    scene =
      scene
      |> assign(state: state, graph: graph)
      |> push_graph(graph)

    # Request input for mouse interaction
    request_input(scene, [:cursor_pos, :cursor_button])

    {:ok, scene}
  end

  @impl Scenic.Scene
  def handle_input({:cursor_pos, coords}, _context, scene) do
    state = scene.assigns.state
    inside = State.point_inside?(state, coords)

    if inside != state.hovered do
      new_state = %{state | hovered: inside}
      graph = Renderer.update_render(scene.assigns.graph, state, new_state)

      scene = scene
        |> assign(state: new_state, graph: graph)
        |> push_graph(graph)

      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  def handle_input({:cursor_button, {:btn_left, 1, [], coords}}, _context, scene) do
    state = scene.assigns.state

    if State.point_inside?(state, coords) do
      # Toggle selection and notify parent
      new_state = %{state | selected: not state.selected}
      graph = Renderer.update_render(scene.assigns.graph, state, new_state)

      send_parent_event(scene, {:tidbit_clicked, state.id})

      scene = scene
        |> assign(state: new_state, graph: graph)
        |> push_graph(graph)

      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  @impl Scenic.Scene
  def handle_put({:update_title, new_title}, scene) do
    state = scene.assigns.state
    new_state = %{state | title: new_title}
    graph = Renderer.update_render(scene.assigns.graph, state, new_state)

    scene = scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_put({:set_selected, selected}, scene) do
    state = scene.assigns.state
    new_state = %{state | selected: selected}
    graph = Renderer.update_render(scene.assigns.graph, state, new_state)

    scene = scene
      |> assign(state: new_state, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_put(_msg, scene) do
    {:noreply, scene}
  end
end
