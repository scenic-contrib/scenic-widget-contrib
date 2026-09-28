# defmodule Flamelex.GUI.Component.InputModal do
#   @moduledoc """
#   A GUI component for InputModal.
#   """

#   use Scenic.Component
#   require Logger
#   alias Widgex.Frame
#   alias Scenic.Graph
#   alias Flamelex.Fluxus.RadixState
#   alias Flamelex.GUI.Component.InputModal
#   alias Flamelex.GUI.Component.InputModal.State
#   alias Flamelex.GUI.Component.InputModal.Render
#   alias Flamelex.GUI.Utils.Draw

#   # Validate function for Scenic component
#   def validate(%{frame: %Frame{}} = data) do
#     {:ok, data}
#   end

#   def init(scene, %{frame: %Frame{} = frame}, _opts) do
#     state = Flamelex.Fluxus.RadixStore.get().apps.inputmodal
#     graph = Render.go(frame, state)

#     init_scene =
#       scene
#       |> assign(frame: frame)
#       |> assign(graph: graph)
#       |> assign(state: state)
#       |> push_graph(graph)

#     Flamelex.Lib.Utils.PubSub.subscribe(topic: :radix_state_change)

#     {:ok, init_scene}
#   end

#   # Handle state changes where the state hasn't changed
#   def handle_info(
#         {:radix_state_change, %{apps: %{inputmodal: state}}},
#         %{assigns: %{frame: frame, state: state}} = scene
#       ) do
#     # State variables in pattern match are the same; no state change occurred
#     {:noreply, scene}
#   end

#   # Handle state changes where the state has changed
#   def handle_info(
#         {:radix_state_change, %{apps: %{inputmodal: new_state}}},
#         %{assigns: %{frame: frame, state: old_state}} = scene
#       ) do
#     # State has changed; raise an error as handling is app-specific
#     raise "State change handling not implemented in template"
#     {:noreply, scene}
#   end
# end

defmodule ScenicWidgets.InputModal do
  use Scenic.Component
  use ScenicWidgets.ScenicEventsDefinitions

  # Validate function for Scenic component
  def validate(%{id: _id, frame: %Widgex.Frame{}, prompt: p} = data) when is_binary(p) do
    {:ok, data}
  end

  def init(scene, %{frame: %Widgex.Frame{} = frame} = args, _opts) do
    graph = render(args |> Map.merge(%{input: ""}))

    init_scene =
      scene
      |> assign(frame: frame)
      |> assign(graph: graph)
      # |> assign(state: state)
      |> assign(prompt: args.prompt)
      |> assign(input: "")
      |> push_graph(graph)

    # Optionally register in an app-provided Registry so the host app can
    # look this modal up by id (pass registry: MyApp.Registry in args)
    case Map.get(args, :registry) do
      nil -> :ok
      registry -> Registry.register(registry, {args.id, __MODULE__}, nil)
    end

    {:ok, init_scene}
  end

  def handle_info({:fwd_user_input, input}, scene) when input in @all_letters do
    new_input = scene.assigns.input <> key2string(input)

    graph =
      render(%{
        frame: scene.assigns.frame,
        prompt: scene.assigns.prompt,
        input: new_input
      })

    new_scene =
      scene
      |> assign(input: new_input)
      |> push_graph(graph)

    {:noreply, new_scene}
  end

  def handle_info({:fwd_user_input, _input}, scene) do
    # ignore...
    {:noreply, scene}
  end

  # # Handle text input events
  # def handle_input({:text_input, text}, _context, state) do
  #   new_input = state.input <> text
  #   new_state = %{state | input: new_input}
  #   {:noreply, new_state, push: render(new_state)}
  # end

  # # Handle key events (e.g., backspace and enter)
  # def handle_input({:key, {:key, key, _, _}}, _context, state) do
  #   case key do
  #     :backspace ->
  #       new_input = String.slice(state.input, 0..-2)
  #       new_state = %{state | input: new_input}
  #       {:noreply, new_state, push: render(new_state)}

  #     :enter ->
  #       # Forward the input to the parent
  #       send(state.parent_pid, {:modal_input, state.input})
  #       {:noreply, state}

  #     _ ->
  #       {:noreply, state}
  #   end
  # end

  # def render(%{frame: %Widgex.Frame{} = frame, prompt: prompt}) do
  #   Scenic.Graph.build()
  #   |> Scenic.Primitives.group(fn graph ->
  #     graph
  #     |> Scenic.Primitives.rect({frame.size.width, frame.size.height}, fill: :white)
  #     |> Scenic.Primitives.text(prompt,
  #       translate: {20, 40},
  #       font: :roboto,
  #       font_size: 24,
  #       fill: :black
  #     )
  #     |> Scenic.Primitives.text("",
  #       translate: {20, 80},
  #       font: :roboto,
  #       font_size: 24,
  #       fill: :black,
  #       id: :input_text
  #     )
  #   end)
  # end

  # Render the component
  def render(%{frame: frame, prompt: prompt, input: input}) do
    # modal_width = frame.size.width * 0.6
    # modal_height = frame.size.height * 0.4
    # modal_x = (frame.size.width - modal_width) / 2
    # modal_y = (frame.size.height - modal_height) / 2
    modal_frame = modal_frame(frame)

    modal_width = modal_frame.size.width
    modal_height = modal_frame.size.height
    modal_x = modal_frame.pin.x
    # TODO need 60 here to offset for menu bar... no idea why lol
    modal_y = modal_frame.pin.y - 60

    Scenic.Graph.build()
    |> Scenic.Primitives.group(fn graph ->
      # Semi-transparent background
      graph
      |> Scenic.Primitives.rect(
        {frame.size.width, frame.size.height},
        fill: {:color, {255, 255, 255, 128}},
        translate: {0, 0}
      )
      # Rounded rectangle dialog box
      |> Scenic.Primitives.rounded_rectangle(
        {modal_frame.size.width, modal_frame.size.height, 10},
        fill: :white,
        stroke: {2, :dark_gray},
        # translate: modal_frame.pin.point
        translate: {modal_x, modal_y}
      )
      # Prompt text
      |> Scenic.Primitives.text(
        prompt,
        font_size: 24,
        fill: :black,
        text_align: :center,
        text_base: :top,
        translate: {modal_x + modal_width / 2, modal_y + 20}
      )
      # Input box
      |> Scenic.Primitives.rect(
        {modal_width - 40, 40},
        fill: :light_gray,
        stroke: {1, :dark_gray},
        translate: {modal_x + 20, modal_y + modal_height / 2 - 20}
      )
      # User input text
      |> Scenic.Primitives.text(
        input,
        id: :input_text,
        font_size: 18,
        fill: :black,
        text_align: :left,
        text_base: :middle,
        translate: {modal_x + 30, modal_y + modal_height / 2}
      )
      # Add the "Save" button
      |> Scenic.Components.button(
        "Save",
        id: :save_button,
        width: 80,
        height: 40,
        # theme: %{
        #   border: {:solid, 1, :dark_gray},
        #   fill: {:color, :blue},
        #   text: {:color, :white}
        # },
        translate: {modal_x + modal_width - 180, modal_y + modal_height - 60}
      )
      # Add the "Cancel" button
      |> Scenic.Components.button(
        "Cancel",
        id: :cancel_button,
        width: 80,
        height: 40,
        # theme: %{
        #   border: {:solid, 1, :dark_gray},
        #   fill: {:color, :gray},
        #   text: {:color, :white}
        # },
        translate: {modal_x + modal_width - 90, modal_y + modal_height - 60}
      )
    end)

    # |> Widgex.Frame.draw_guides(frame)
    # |> Widgex.Frame.draw_guidewires(modal_frame, color: :red)
  end

  def modal_frame(frame) do
    # Define a grid that splits the frame into three rows and three columns
    # Rows: Top 20%, Middle 60%, Bottom 20%
    # Columns: Left 20%, Middle 60%, Right 20%
    grid =
      Widgex.Frame.Grid.new(frame)
      |> Widgex.Frame.Grid.rows([0.2, 0.6, 0.2])
      |> Widgex.Frame.Grid.columns([0.2, 0.6, 0.2])
      |> Widgex.Frame.Grid.define_areas(%{
        modal_area: {1, 1, 1, 1}
      })

    cell_frames = Widgex.Frame.Grid.calculate(grid)
    Widgex.Frame.Grid.area_frame(grid, cell_frames, :modal_area)
  end

  # Handle button events
  def handle_event({:click, :save_button}, _from, scene) do
    # Send the input to the parent as the user clicked "Save"
    # send(state.parent_pid, {:modal_save, state.input})
    # TODO make a better job of referencing a specific buffer
    cast_parent(scene, {:modal_save, scene.assigns.input})
    {:noreply, scene}
  end

  def handle_event({:click, :cancel_button}, _from, scene) do
    # Send a cancel message to the parent
    # send(state.parent_pid, :modal_cancel)
    cast_parent(scene, :modal_cancel)
    {:noreply, scene}
  end

  # # Ignore other input events
  # def handle_input(_input, _context, state), do: {:noreply, state}
end

# defmodule Flamelex.GUI.Component.ModalForm do
#   use Scenic.Component

#   alias Scenic.Graph
#   alias Scenic.Primitives

#   @default_font :roboto
#   @default_font_size 24

#   # Render the component
#   def render(%__MODULE__{frame: frame, prompt: prompt, input: input}) do
#     Graph.build()
#     |> Primitives.group(fn graph ->
#       graph
#       |> Primitives.rect({frame.size.width, frame.size.height}, fill: :white)
#       |> Primitives.text(prompt,
#         translate: {20, 40},
#         font: @default_font,
#         font_size: @default_font_size,
#         fill: :black
#       )
#       |> Primitives.text(input,
#         translate: {20, 80},
#         font: @default_font,
#         font_size: @default_font_size,
#         fill: :black,
#         id: :input_text
#       )
#     end)
#   end

#   # Handle text input events
#   def handle_input({:text_input, text}, _context, state) do
#     new_input = state.input <> text
#     new_state = %{state | input: new_input}
#     {:noreply, new_state, push: render(new_state)}
#   end

#   # Handle key events (e.g., backspace and enter)
#   def handle_input({:key, {:key, key, _, _}}, _context, state) do
#     case key do
#       :backspace ->
#         new_input = String.slice(state.input, 0..-2)
#         new_state = %{state | input: new_input}
#         {:noreply, new_state, push: render(new_state)}

#       :enter ->
#         # Forward the input to the parent
#         send(state.parent_pid, {:modal_input, state.input})
#         {:noreply, state}

#       _ ->
#         {:noreply, state}
#     end
#   end

#   # Ignore other input events
#   def handle_input(_input, _context, state), do: {:noreply, state}
# end

# defmodule Flamelex.GUI.Component.ModalForm do
#   use Scenic.Component

#   alias Scenic.Graph
#   alias Scenic.Primitives

#   @default_font :roboto
#   @default_font_size 24

#   # Initialize the component with the frame and parent PID
#   def init(%{frame: frame, parent_pid: parent_pid} = opts, _scenic_opts) do
#     state = %__MODULE__{
#       frame: frame,
#       prompt: opts[:prompt] || "Enter filename:",
#       input: "",
#       parent_pid: parent_pid
#     }

#     # Request input events
#     request_input(state, [:text_input, :key])

#     # Render the initial state
#     {:ok, state, push: render(state)}
#   end

#   # Render the component
#   def render(%__MODULE__{frame: frame, prompt: prompt, input: input}) do
#     Graph.build()
#     |> Primitives.group(fn graph ->
#       graph
#       |> Primitives.rect({frame.size.width, frame.size.height}, fill: :white)
#       |> Primitives.text(prompt,
#         translate: {20, 40},
#         font: @default_font,
#         font_size: @default_font_size,
#         fill: :black
#       )
#       |> Primitives.text(input,
#         translate: {20, 80},
#         font: @default_font,
#         font_size: @default_font_size,
#         fill: :black,
#         id: :input_text
#       )
#     end)
#   end

#   # Handle text input events
#   def handle_input({:text_input, text}, _context, state) do
#     new_input = state.input <> text
#     new_state = %{state | input: new_input}
#     {:noreply, new_state, push: render(new_state)}
#   end

#   # Handle key events (e.g., backspace and enter)
#   def handle_input({:key, {:key, key, _, _}}, _context, state) do
#     case key do
#       :backspace ->
#         new_input = String.slice(state.input, 0..-2)
#         new_state = %{state | input: new_input}
#         {:noreply, new_state, push: render(new_state)}

#       :enter ->
#         # Forward the input to the parent
#         send(state.parent_pid, {:modal_input, state.input})
#         {:noreply, state}

#       _ ->
#         {:noreply, state}
#     end
#   end

#   # Ignore other input events
#   def handle_input(_input, _context, state), do: {:noreply, state}
# end
