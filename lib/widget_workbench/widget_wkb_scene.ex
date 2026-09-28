defmodule WidgetWorkbench.Scene do
  use Scenic.Scene
  require Logger

  alias Scenic.Graph
  alias Scenic.Primitives
  alias Scenic.Components
  alias Widgex.Frame
  alias Widgex.Frame.Grid
  alias Scenic.ViewPort
  alias WidgetWorkbench.Components.Modal
  use ScenicWidgets.ScenicEventsDefinitions

  @grid_color :light_gray
  # Customize the grid spacing
  @grid_spacing 40.0

  @type component_spec :: {String.t(), module(), term()}

  @moduledoc """
  A scene that serves as a widget workbench for designing and testing GUI components.
  """

  def load_component(name, module, opts) do
    component_spec = {name, module, opts}
    GenServer.cast(:_widget_workbench_scene_, {:load_and_select_component, component_spec})
  end

  @impl Scenic.Scene
  def init(scene, _params, _opts) do
    # Register this process so hot reload can find it
    Process.register(self(), :_widget_workbench_scene_)

    # Logger.info("🚀 WidgetWorkbench.Scene init called!")

    # Try to get stored window size first (from previous resize events)
    {width, height} =
      try do
        case :ets.lookup(:widget_workbench_state, :current_size) do
          [{:current_size, stored_size}] ->
            Logger.info("🔍 Using stored window size: #{inspect(stored_size)}")
            stored_size

          [] ->
            # Table exists but no size stored yet
            size = scene.viewport.size
            :ets.insert(:widget_workbench_state, {:current_size, size})
            Logger.info("📐 Storing initial window size: #{inspect(size)}")
            size
        end
      rescue
        ArgumentError ->
          # Table doesn't exist - create it and use viewport size
          :ets.new(:widget_workbench_state, [:set, :public, :named_table])
          size = scene.viewport.size
          :ets.insert(:widget_workbench_state, {:current_size, size})
          Logger.info("📐 Created ETS table with initial window size: #{inspect(size)}")
          size
      end

    # Logger.info("📏 Using window size: #{width}x#{height}")

    # Create a frame for the scene
    frame = Frame.new(%{pin: {0, 0}, size: {width, height}})

    # Build the initial graph
    graph = render(frame, nil, false, nil, 0)

    # Assign the graph and state to the scene
    scene =
      scene
      |> assign(graph: graph)
      |> assign(frame: frame)
      |> assign(modal_visible: false)
      |> assign(current_file_index: 0)
      |> assign(component_files: [])
      |> assign(selected_component: nil)
      |> assign(selected_component_module: nil)
      |> assign(component_modal_visible: false)
      |> assign(click_visualization: nil)
      |> assign(modal_scroll_offset: 0)
      |> push_graph(graph)

    # Request input events including cursor events and scroll
    # We need to request cursor_button to receive it, but we won't consume it in handle_input
    # Added :codepoint for TextField support
    request_input(scene, [:cursor_pos, :cursor_button, :cursor_scroll, :key, :codepoint, :viewport])

    {:ok, scene}
  end

  # Render function to build the graph using Widgex Grid
  defp render(
         %Frame{} = frame,
         selected_component_spec,
         show_modal,
         click_viz,
         modal_scroll_offset
       ) do
    # Create a grid with 2 columns: 2/3 for main area, 1/3 for constructor pane
    grid =
      Grid.new(frame)
      # Two columns: main area (2/3) and constructor pane (1/3)
      |> Grid.columns([2 / 3, 1 / 3])
      # Single row that takes full height
      |> Grid.rows([1.0])

    # Calculate cell frames
    cell_frames = Grid.calculate(grid)

    # Get the main area (left 2/3) and constructor pane (right 1/3)
    main_area = Grid.cell_frame(cell_frames, 0, 0)
    constructor_area = Grid.cell_frame(cell_frames, 0, 1)

    # Build the graph
    graph =
      Graph.build()
      # Render the main drawing area
      |> render_main_area(main_area, selected_component_spec)
      # Render the constructor pane
      |> render_constructor_pane(constructor_area)

    # Add modal if needed
    graph =
      if show_modal do
        graph |> render_component_selection_modal(frame, modal_scroll_offset)
      else
        graph
      end

    # Add click visualization if present
    graph =
      if click_viz do
        render_click_visualization(graph, click_viz)
      else
        graph
      end

    # Add an empty modal container group for later use
    graph =
      graph
      |> Primitives.group(fn g -> g end, id: :modal_container)

    graph
  end

  # Render the main drawing area
  defp render_main_area(graph, %Frame{} = frame, selected_component_spec) do
    graph
    # Main area background - make it more visible
    |> Primitives.rect(
      {frame.size.width, frame.size.height},
      fill: {:color, {250, 250, 250}},
      stroke: {2, :dark_gray},
      translate: frame.pin.point
    )
    # Draw grid background
    |> draw_grid_background(frame)
    # Render content based on selection
    |> render_main_content(frame, selected_component_spec)
  end

  # Render content in the main area
  defp render_main_content(graph, frame, nil) do
    # No component selected - show the yellow circle
    center_point = Frame.center(frame)

    graph
    |> Primitives.circle(30, fill: :green, translate: {center_point.x, center_point.y})
  end

  defp render_main_content(graph, frame, {component_name, component_module, component_opts}) do
    # Also calculate center for error messages
    center_point = Frame.center(frame)

    Logger.info("   Main area frame: pin=#{inspect(frame.pin)}, size=#{inspect(frame.size)}")

    # Try different component loading strategies with better isolation
    try do
      # Convert pin to tuple for Scenic compatibility
      # Handle both direct Frame and map containing :frame key
      translate_pin =
        case component_opts do
          %Widgex.Frame{} = component_frame ->
            case component_frame.pin do
              %Widgex.Structs.Coordinates{x: x, y: y} -> {x, y}
              {x, y} -> {x, y}
            end

          %{frame: %Widgex.Frame{} = inner_frame} ->
            # Map with :frame key (e.g., SideNav, MenuBar)
            case inner_frame.pin do
              %Widgex.Structs.Coordinates{x: x, y: y} -> {x, y}
              {x, y} -> {x, y}
            end

          _ ->
            center_point.point
        end

      # Draw anchor point indicator UNDER the component (rendered first, so it appears below)
      graph =
        graph
        # Cornflower blue with 50% opacity
        |> Primitives.circle(15,
          fill: {:color, {100, 149, 237, 128}},
          id: :anchor_point_indicator,
          translate: translate_pin
        )

      if not function_exported?(component_module, :add_to_graph, 3) do
        raise "Component must define add_to_graph to be compatible (checked #{inspect(component_module)})"
      end

      graph
      |> component_module.add_to_graph(
        component_opts,
        id: :loaded_component,
        translate: translate_pin
      )
    rescue
      error ->
        Logger.warning("Failed to load component #{component_name}: #{Exception.message(error)}")
        Logger.warning("Error details: #{inspect(error)}")

        # Show detailed error message
        error_text =
          case error do
            %FunctionClauseError{} -> "Invalid component format"
            %ArgumentError{} -> "Invalid arguments"
            _ -> Exception.message(error)
          end

        graph
        |> Primitives.text(
          "Failed to load: #{component_name}",
          font_size: 16,
          fill: :red,
          translate: {center_point.x, center_point.y - 20},
          text_align: :center
        )
        |> Primitives.text(
          error_text,
          font_size: 12,
          fill: :red,
          translate: {center_point.x, center_point.y + 10},
          text_align: :center
        )
        |> Primitives.text(
          "(Component isolation working!)",
          font_size: 10,
          fill: :green,
          translate: {center_point.x, center_point.y + 40},
          text_align: :center
        )
    catch
      :exit, reason ->
        Logger.warning("Component #{component_name} exited: #{inspect(reason)}")

        graph
        |> Primitives.text(
          "Component crashed: #{component_name}",
          font_size: 16,
          fill: :red,
          translate: {center_point.x, center_point.y},
          text_align: :center
        )
        |> Primitives.text(
          "(Workbench protected from crash)",
          font_size: 10,
          fill: :green,
          translate: {center_point.x, center_point.y + 30},
          text_align: :center
        )
    end
  end

  # Catch-all for unexpected selected_component values
  defp render_main_content(graph, frame, unexpected_value) do
    Logger.warning("Unexpected selected_component value: #{inspect(unexpected_value)}")
    center_point = Frame.center(frame)
    graph
    |> Primitives.text(
      "Error: Invalid component state",
      font_size: 16,
      fill: :orange,
      translate: {center_point.x, center_point.y},
      text_align: :center
    )
    |> Primitives.text(
      "(Please select a component from the list)",
      font_size: 12,
      fill: :gray,
      translate: {center_point.x, center_point.y + 25},
      text_align: :center
    )
  end

  # Prepare component data based on the component type
  defp prepare_component_data(component_module, component_frame) do
    case component_module do
      ScenicWidgets.MenuBar ->
        # MenuBar needs menu_map and frame - use (0,0) pin since translate handles positioning
        better_frame =
          Frame.new(%{
            # Start at origin - translate will position it
            pin: {0, 0},
            # 4 menus * 150px width, taller 60px menubar height
            size: {600, 60}
          })

        # Build menu_map with optional action callbacks for testing
        menu_map = build_menu_map()

        # Custom theme with height 60 and Scenic's dark theme colors
        custom_theme = %{
          # Scenic's dark theme colors
          background: :black,
          text: :white,
          # Scenic dark active color
          hover_bg: {40, 40, 40},
          hover_text: :white,
          dropdown_bg: :black,
          dropdown_text: :white,
          dropdown_hover_bg: {40, 40, 40},
          dropdown_hover_text: :white,
          border: :light_grey,

          # Custom dimensions for taller menu
          menu_height: 60,
          item_width: 150,
          # 60% wider than main menus (150 * 1.6)
          sub_menu_width: 240,
          # Slightly taller dropdown items
          item_height: 35,
          padding: 8,

          # Typography
          font: :ibm_plex_mono,
          # Larger font for better readability
          font_size: 18,

          # Text Overflow
          text_overflow: :ellipsis,
          # Wider for sub-menus
          max_text_width: 200,
          ellipsis_char: "..."
        }

        %{
          frame: better_frame,
          menu_map: menu_map,
          theme: custom_theme
        }

      ScenicWidgets.SideNav ->
        # SideNav needs frame with actual screen position for semantic registration
        {pin_x, pin_y} =
          case component_frame.pin do
            %Widgex.Structs.Coordinates{x: x, y: y} -> {x, y}
            {x, y} -> {x, y}
          end

        sidenav_frame =
          Frame.new(%{
            pin: {pin_x, pin_y},
            size: {280, 600}  # Standard sidebar width x height
          })

        # Use the DEEP test tree with 4 levels of nesting
        # Some items have :action callbacks, others rely on parent message
        tree = ScenicWidgets.SideNav.Item.deep_test_tree()

        %{
          frame: sidenav_frame,
          tree: tree,
          active_id: nil  # No initial selection
        }

      ScenicWidgets.IconButton ->
        # Convert Coordinates struct to tuple format for IconButton
        {pin_x, pin_y} =
          case component_frame.pin do
            %Widgex.Structs.Coordinates{x: x, y: y} -> {x, y}
            {x, y} -> {x, y}
          end

        # Create a new frame with tuple pin for IconButton
        icon_frame =
          Frame.new(%{
            pin: {pin_x, pin_y},
            size: component_frame.size
          })

        %{frame: icon_frame, text: "Icon Button"}

      ScenicWidgets.TextButton ->
        # TextButton might also need frame in a map
        %{frame: component_frame, text: "Text Button"}

      ScenicWidgets.Sidebar ->
        # Sidebar needs frame with (0,0) pin since we position via translate
        sidebar_frame =
          Frame.new(%{
            # Start at origin - translate will position it
            pin: {0, 0},
            size: component_frame.size
          })

        %{
          frame: sidebar_frame,
          items: [
            %{
              id: :file,
              label: "File",
              children: [
                %{id: :new, label: "New", children: []},
                %{id: :open, label: "Open", children: []}
              ]
            },
            %{
              id: :edit,
              label: "Edit",
              children: [
                %{id: :copy, label: "Copy", children: []},
                %{id: :paste, label: "Paste", children: []}
              ]
            },
            %{
              id: :view,
              label: "View",
              children: [
                %{id: :zoom_in, label: "Zoom In", children: []},
                %{id: :zoom_out, label: "Zoom Out", children: []},
                %{id: :fullscreen, label: "Toggle Fullscreen", children: []}
              ]
            }
          ]
        }

      ScenicWidgets.TextField ->
        # TextField needs frame - use the component_frame pin for positioning
        text_field_frame = Frame.new(%{
          pin: component_frame.pin,  # Use the anchor point
          size: component_frame.size
        })

        # For demo: Add long text to test scrolling
        %{
          frame: text_field_frame,
          initial_text: "This is a very long line of text that definitely exceeds the width and should scroll horizontally when wrap_mode is :none\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10",
          wrap_mode: :none  # :none for horizontal scroll, :word for wrapping
        }

      _ ->
        # Default: try frame parameter
        component_frame
    end
  end

  # Render the constructor pane on the right side
  defp render_constructor_pane(graph, %Frame{} = frame) do
    # Create a grid layout for the constructor pane
    pane_grid =
      Grid.new(frame)
      # Top padding, title, subtitle, gap, reset, gap, new, gap, load, remaining
      |> Grid.rows([20, 35, 30, 15, 50, 20, 50, 20, 50, 1])
      # Small padding, large content area, small padding
      |> Grid.columns([0.1, 0.8, 0.1])
      |> Grid.define_areas(%{
        title: {1, 1, 1, 1},
        subtitle: {2, 1, 1, 1},
        reset_button: {4, 1, 1, 1},
        new_button: {6, 1, 1, 1},
        load_button: {8, 1, 1, 1}
      })

    cell_frames = Grid.calculate(pane_grid)
    title_frame = Grid.area_frame(pane_grid, cell_frames, :title)
    subtitle_frame = Grid.area_frame(pane_grid, cell_frames, :subtitle)
    reset_button_frame = Grid.area_frame(pane_grid, cell_frames, :reset_button)
    new_button_frame = Grid.area_frame(pane_grid, cell_frames, :new_button)
    load_button_frame = Grid.area_frame(pane_grid, cell_frames, :load_button)

    graph
    # Grey background for constructor pane
    |> Primitives.rect(
      {frame.size.width, frame.size.height},
      fill: {:color, {230, 230, 235}},
      stroke: {1, {:color, {200, 200, 205}}},
      translate: frame.pin.point
    )
    # Add a title for the constructor pane
    |> Primitives.text(
      "Widget Workbench",
      font_size: 20,
      fill: {:color, {40, 40, 50}},
      translate:
        {elem(title_frame.pin.point, 0) + title_frame.size.width / 2,
         elem(title_frame.pin.point, 1) + 25},
      text_align: :center
    )
    # Add subtitle/help text
    |> Primitives.text(
      "Design & test Scenic components",
      font_size: 14,
      fill: {:color, {100, 100, 110}},
      translate:
        {elem(subtitle_frame.pin.point, 0) + subtitle_frame.size.width / 2,
         elem(subtitle_frame.pin.point, 1) + 20},
      text_align: :center
    )
    # Reset Scene button (red)
    |> Components.button(
      "Reset Scene",
      id: :reset_scene_button,
      width: reset_button_frame.size.width,
      height: reset_button_frame.size.height,
      translate: reset_button_frame.pin.point,
      theme: %{
        text: :white,
        background: {:color, {220, 53, 69}},
        border: {:color, {200, 33, 49}},
        active: {:color, {180, 13, 29}},
        thumb: {:color, {240, 73, 89}},
        focus: {:color, {160, 0, 19}}
      }
    )
    # New Widget button
    |> Components.button(
      "New Widget",
      id: :new_widget_button,
      width: new_button_frame.size.width,
      height: new_button_frame.size.height,
      translate: new_button_frame.pin.point,
      theme: %{
        text: :white,
        background: {:color, {70, 130, 180}},
        border: {:color, {60, 120, 170}},
        active: {:color, {50, 110, 160}},
        thumb: {:color, {80, 140, 190}},
        focus: {:color, {40, 100, 150}}
      }
    )
    # Load Component button
    |> Components.button(
      "Load Component",
      id: :load_component_button,
      width: load_button_frame.size.width,
      height: load_button_frame.size.height,
      translate: load_button_frame.pin.point,
      theme: %{
        text: :white,
        background: {:color, {34, 139, 34}},
        border: {:color, {24, 129, 24}},
        active: {:color, {14, 119, 14}},
        thumb: {:color, {44, 149, 44}},
        focus: {:color, {4, 109, 4}}
      }
    )
  end

  # Render the component selection modal
  defp render_component_selection_modal(graph, %Frame{} = frame, scroll_offset) do
    # Create a centered modal frame
    modal_width = 400
    modal_height = 500
    modal_x = (frame.size.width - modal_width) / 2
    modal_y = (frame.size.height - modal_height) / 2

    # Dynamically discover components from /lib/components
    components = discover_components()

    # Calculate scrollable area dimensions
    list_top = modal_y + 60
    # Space for title and cancel button
    list_height = modal_height - 60 - 55
    button_height = 40
    button_margin = 5
    total_content_height = length(components) * (button_height + button_margin)
    scrollbar_width = 15

    # Calculate max scroll (prevent scrolling past content)
    max_scroll = max(0, total_content_height - list_height)
    clamped_scroll = max(0, min(scroll_offset, max_scroll))

    # Calculate scrollbar dimensions if needed
    show_scrollbar = total_content_height > list_height

    scrollbar_height =
      if show_scrollbar do
        # Scrollbar thumb height proportional to visible content
        max(30, list_height * list_height / total_content_height)
      else
        0
      end

    # Calculate scrollbar position
    scrollbar_y_offset =
      if show_scrollbar and max_scroll > 0 do
        (list_height - scrollbar_height) * (clamped_scroll / max_scroll)
      else
        0
      end

    graph
    # Semi-transparent overlay
    |> Primitives.rect(
      {frame.size.width, frame.size.height},
      fill: {:color, {0, 0, 0, 128}},
      translate: {0, 0},
      id: :modal_overlay
    )
    # Modal background
    |> Primitives.rect(
      {modal_width, modal_height},
      fill: :white,
      stroke: {2, {:color, {100, 100, 100}}},
      translate: {modal_x, modal_y},
      id: :modal_background
    )
    # Modal title
    |> Primitives.text(
      "Select Component",
      font_size: 18,
      fill: {:color, {40, 40, 50}},
      translate: {modal_x + modal_width / 2, modal_y + 30},
      text_align: :center
    )
    # Scrollable component list (with scissor for clipping)
    # Outer group: Fixed position with scissor box
    # Inner group: Translates for scrolling
    |> Primitives.group(
      fn g ->
        g
        |> Primitives.group(
          fn inner_g ->
            inner_g
            |> render_component_list(components, 0, 0, modal_width - scrollbar_width - 5)
          end,
          id: :component_list_scroll_group,
          translate: {0, -clamped_scroll}
        )
      end,
      id: :component_list_container,
      scissor: {modal_width - scrollbar_width - 5, list_height},
      translate: {modal_x, list_top}
    )
    # Scrollbar background (if needed)
    |> then(fn g ->
      if show_scrollbar do
        g
        |> Primitives.rect(
          {scrollbar_width, list_height},
          fill: {:color, {230, 230, 230}},
          translate: {modal_x + modal_width - scrollbar_width - 10, list_top},
          id: :scrollbar_track
        )
        # Scrollbar thumb
        |> Primitives.rect(
          {scrollbar_width, scrollbar_height},
          fill: {:color, {150, 150, 150}},
          stroke: {1, {:color, {120, 120, 120}}},
          translate:
            {modal_x + modal_width - scrollbar_width - 10, list_top + scrollbar_y_offset},
          id: :scrollbar_thumb
        )
      else
        g
      end
    end)
    # Cancel button
    |> Components.button(
      "Cancel",
      id: :cancel_component_selection,
      width: 80,
      height: 35,
      translate: {modal_x + modal_width - 90, modal_y + modal_height - 45},
      theme: %{
        text: :white,
        background: {:color, {150, 150, 150}},
        border: {:color, {130, 130, 130}},
        active: {:color, {120, 120, 120}},
        thumb: {:color, {160, 160, 160}},
        focus: {:color, {140, 140, 140}}
      }
    )
  end

  # Render the list of components as buttons
  # x and start_y are in local coordinates (relative to group translate)
  # opts: modal_x, list_top, scroll_offset - for calculating absolute positions for MCP
  defp render_component_list(graph, components, x, start_y, width, opts \\ []) do
    button_height = 40
    button_margin = 5

    # Extract container positioning for absolute coordinate calculation
    modal_x = Keyword.get(opts, :modal_x, 0)
    list_top = Keyword.get(opts, :list_top, 0)
    scroll_offset = Keyword.get(opts, :scroll_offset, 0)

    components
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {{name, id}, index}, acc_graph ->
      local_y = start_y + (button_height + button_margin) * index

      # Calculate absolute position for MCP registration
      # absolute_y = container_top + local_y - scroll_offset
      absolute_y = list_top + local_y - scroll_offset
      absolute_x = modal_x + x + 20

      acc_graph
      |> Components.button(
        name,
        id: {:select_component, id},
        width: width - 40,
        height: button_height,
        translate: {x + 20, local_y},
        # Pass absolute position as metadata for MCP
        t: {absolute_x, absolute_y},  # MCP will use this for click positioning
        theme: %{
          text: {:color, {50, 50, 60}},
          background: {:color, {245, 245, 250}},
          border: {:color, {200, 200, 210}},
          active: {:color, {70, 130, 180}},
          thumb: {:color, {220, 220, 230}},
          focus: {:color, {60, 120, 170}}
        }
      )
    end)
  end

  # Render UI elements using the grid (unused, kept for potential future use)
  defp _render_grid_layout(graph, grid, cell_frames) do
    # Define named areas for better organization
    # Using {row, col, row_span, col_span} format
    grid_with_areas =
      grid
      |> Grid.define_areas(%{
        # Row 0, all 12 columns
        header: {0, 0, 1, 12},
        # Rows 1-7, columns 0-1 (2 columns wide)
        sidebar: {1, 0, 7, 2},
        # Rows 1-7, columns 2-11 (10 columns wide)
        content: {1, 2, 7, 10}
      })

    # Get frames for each area using the passed cell_frames
    header_frame = Grid.area_frame(grid_with_areas, cell_frames, :header)
    sidebar_frame = Grid.area_frame(grid_with_areas, cell_frames, :sidebar)
    content_frame = Grid.area_frame(grid_with_areas, cell_frames, :content)

    graph
    # Render the header area with menu bar
    |> _render_test_menu_bar(header_frame)
    # Render the sidebar with tools pane
    |> _render_tools_pane(sidebar_frame)
    # Content area - keep simple for now
    |> Primitives.rect(
      {content_frame.size.width, content_frame.size.height},
      fill: {:color, {252, 252, 253}},
      stroke: {1, {:color, {220, 220, 230}}},
      translate: content_frame.pin.point
    )
    |> Primitives.text(
      "Widget Canvas",
      font_size: 14,
      fill: {:color, {100, 100, 110}},
      translate: {elem(content_frame.pin.point, 0) + 10, elem(content_frame.pin.point, 1) + 30}
    )
  end

  # Discover components dynamically from /lib/components directory
  defp discover_components do
    components_dir = Path.join([File.cwd!(), "lib", "components"])

    if File.dir?(components_dir) do
      components_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(components_dir, &1)))
      |> Enum.map(&discover_component_from_dir(&1, Path.join(components_dir, &1)))
      # Remove nils
      |> Enum.filter(& &1)
      # Sort alphabetically
      |> Enum.sort_by(fn {name, _} -> name end)
    else
      # Fallback to hardcoded list if directory doesn't exist
      [
        {"Test Pattern", ScenicWidgets.TestPattern},
        {"Frame Box", ScenicWidgets.FrameBox},
        {"Text Button", ScenicWidgets.TextButton}
      ]
    end
  end

  # Try to discover a component from a directory
  defp discover_component_from_dir(dir_name, dir_path) do
    # Look for the main component file (same name as directory)
    main_file = "#{dir_name}.ex"
    main_file_path = Path.join(dir_path, main_file)

    cond do
      File.exists?(main_file_path) ->
        # Convert directory name to module name
        module_name = dir_name |> Macro.camelize()

        display_name =
          dir_name
          |> String.replace("_", " ")
          |> String.split(" ")
          |> Enum.map(&String.capitalize/1)
          |> Enum.join(" ")

        # Try to build the module atom - this might fail for non-standard modules
        try do
          module_atom = Module.concat([ScenicWidgets, module_name])
          Code.ensure_loaded(module_atom)
          {display_name, module_atom}
        rescue
          _ ->
            # If module creation fails, still include it but mark it specially
            {display_name <> " (experimental)",
             String.to_atom("Elixir.ScenicWidgets.#{module_name}")}
        end

      true ->
        # Look for any .ex file in the directory
        case File.ls(dir_path) do
          {:ok, files} ->
            ex_files = Enum.filter(files, &String.ends_with?(&1, ".ex"))

            if length(ex_files) > 0 do
              # Use the first .ex file found
              file_name = List.first(ex_files) |> String.replace(".ex", "")
              module_name = file_name |> Macro.camelize()

              display_name =
                dir_name
                |> String.replace("_", " ")
                |> String.split(" ")
                |> Enum.map(&String.capitalize/1)
                |> Enum.join(" ")

              try do
                module_atom = Module.concat([ScenicWidgets, module_name])
                {display_name, module_atom}
              rescue
                _ ->
                  {display_name <> " (experimental)",
                   String.to_atom("Elixir.ScenicWidgets.#{module_name}")}
              end
            else
              # No .ex files found
              nil
            end

          # Can't read directory
          _ ->
            nil
        end
    end
  end

  @spec select_component(Scene.t(), component_spec()) :: Scene.t()
  defp select_component(scene, component_spec) do
    new_graph =
      render(scene.assigns.frame, component_spec, false, nil, 0)
      |> apply_click_visualizations(scene)

    scene
    |> assign(selected_component: component_spec)
    # |> assign(selected_component_name: component_name)
    # |> assign(component_frame: component_frame)
    |> assign(graph: new_graph)
    |> push_graph(new_graph)
  end

  # Function to draw a pseudo-grid background of "+"
  defp draw_grid_background(graph, %Frame{} = frame) do
    # Ensure we have integers by flooring the division results
    width_count = :math.floor(frame.size.width / @grid_spacing) |> trunc()
    height_count = :math.floor(frame.size.height / @grid_spacing) |> trunc()

    # Get frame origin position
    {frame_x, frame_y} = frame.pin.point

    Enum.reduce(0..width_count, graph, fn x, acc ->
      Enum.reduce(0..height_count, acc, fn y, acc_inner ->
        acc_inner
        |> Primitives.text(
          "+",
          font_size: 16,
          fill: @grid_color,
          translate: {frame_x + x * @grid_spacing, frame_y + y * @grid_spacing}
        )
      end)
    end)
  end

  # Function to render the tools pane (unused, kept for potential future use)
  defp _render_tools_pane(graph, %Frame{} = frame) do
    # Create a grid for the tools pane layout
    # Padding of 20px on all sides, but ensure positive dimensions
    padding = 20
    padded_width = max(frame.size.width - padding * 2, 10)
    padded_height = max(frame.size.height - padding * 2, 10)

    padded_frame =
      Frame.new(%{
        pin: {padding, padding},
        size: {padded_width, padded_height}
      })

    tools_grid =
      Grid.new(padded_frame)
      # Title, gap, button1, button2, remaining space
      |> Grid.rows([60, 20, 50, 50, 1])
      |> Grid.columns([1])
      |> Grid.row_gap(10)
      |> Grid.define_areas(%{
        title: {0, 0, 1, 1},
        divider: {1, 0, 1, 1},
        open_button: {2, 0, 1, 1},
        create_button: {3, 0, 1, 1}
      })

    cell_frames = Grid.calculate(tools_grid)
    title_frame = Grid.area_frame(tools_grid, cell_frames, :title)
    divider_frame = Grid.area_frame(tools_grid, cell_frames, :divider)
    open_button_frame = Grid.area_frame(tools_grid, cell_frames, :open_button)
    create_button_frame = Grid.area_frame(tools_grid, cell_frames, :create_button)

    graph
    # Title
    |> Primitives.text(
      "WidgetWorkbench",
      font_size: 24,
      fill: {:color, {50, 50, 60, 255}},
      text_align: :center,
      translate: {title_frame.pin.x + title_frame.size.width / 2, title_frame.pin.y + 30}
    )
    # Divider line
    |> Primitives.line(
      {{frame.pin.x + 20, divider_frame.pin.y + 10},
       {frame.pin.x + frame.size.width - 20, divider_frame.pin.y + 10}},
      stroke: {1, {:color, {220, 220, 220, 255}}}
    )
    # Open Widget button
    |> Components.button(
      "Open Widget",
      id: :open_widget_button,
      width: open_button_frame.size.width,
      height: open_button_frame.size.height,
      translate: {open_button_frame.pin.x, open_button_frame.pin.y},
      theme: %{
        text: :black,
        background: {:color, {255, 255, 255, 255}},
        border: {:color, {200, 200, 200, 255}},
        active: {:color, {240, 240, 240, 255}},
        thumb: {:color, {180, 180, 180, 255}},
        focus: {:color, {0, 120, 212, 255}}
      }
    )
    # Create New Widget button
    |> Components.button(
      "Create New Widget",
      id: :create_widget_button,
      width: create_button_frame.size.width,
      height: create_button_frame.size.height,
      translate: {create_button_frame.pin.x, create_button_frame.pin.y},
      theme: %{
        text: :black,
        background: {:color, {255, 255, 255, 255}},
        border: {:color, {200, 200, 200, 255}},
        active: {:color, {240, 240, 240, 255}},
        thumb: {:color, {180, 180, 180, 255}},
        focus: {:color, {0, 120, 212, 255}}
      }
    )
  end

  # Function to render test menu bar (unused, kept for potential future use)
  defp _render_test_menu_bar(graph, %Frame{} = frame) do
    # Sample menu structure for testing
    test_menu_map = %{
      file:
        {"File",
         [
           {:new_file, "New File"},
           {:open_file, "Open File"},
           {:save_file, "Save"},
           {:save_as, "Save As..."},
           {:quit, "Quit"}
         ]},
      edit:
        {"Edit",
         [
           {:undo, "Undo"},
           {:redo, "Redo"},
           {:cut, "Cut"},
           {:copy, "Copy"},
           {:paste, "Paste"}
         ]},
      view:
        {"View",
         [
           {:zoom_in, "Zoom In"},
           {:zoom_out, "Zoom Out"},
           {:reset_zoom, "Reset Zoom"},
           {:toggle_sidebar, "Toggle Sidebar"}
         ]},
      help:
        {"Help",
         [
           {:documentation, "Documentation"},
           {:about, "About"}
         ]}
    }

    # Position menubar at top of canvas with some margin
    # Ensure positive dimensions
    menubar_width = max(frame.size.width - 40, 100)

    menu_bar_data = %{
      frame:
        Frame.new(%{
          pin: {20, 20},
          size: {menubar_width, 30}
        }),
      menu_map: test_menu_map
    }

    graph
    |> ScenicWidgets.MenuBar.add_to_graph(menu_bar_data, id: :test_menu_bar)
  end

  # Function to render the tool palette (unused, kept for potential future use)
  defp _render_tool_palette(graph, %Frame{} = frame) do
    palette_width = 200
    palette_height = 90
    palette_x = frame.size.width - palette_width - 20
    palette_y = 70

    # Draw the tool palette
    graph
    |> Primitives.group(
      fn graph ->
        graph
        # Draw the rounded rectangle background
        |> Primitives.rounded_rectangle(
          {palette_width, palette_height, 10},
          fill: :light_gray,
          stroke: {1, :dark_gray},
          translate: {0, 0}
        )
        # Add the "New Widget" button
        |> Components.button(
          "New Widget",
          id: :new_widget_button,
          width: palette_width - 20,
          height: 30,
          translate: {10, 10}
        )
        # Add the "Close Workbench" button
        |> Components.button(
          "Close Workbench",
          id: :close_workbench_button,
          width: palette_width - 20,
          height: 30,
          translate: {10, 50}
        )
      end,
      id: :tool_palette,
      translate: {palette_x, palette_y}
    )
  end

  # Function to render file tabs (unused, kept for potential future use)
  defp _render_file_tabs(graph, %Frame{} = frame) do
    tab_width = frame.size.width / 6
    tab_height = 40
    tab_y = frame.size.height - tab_height - 20

    # Draw tabs for each file
    graph
    |> Primitives.group(
      fn graph ->
        for i <- 0..5 do
          graph
          |> Components.button(
            "File #{i + 1}",
            id: {:file_tab, i},
            width: tab_width - 10,
            height: tab_height,
            translate: {i * tab_width + 5, tab_y}
          )
        end
      end,
      id: :file_tabs
    )
  end

  # Function to render the file editor (unused, kept for potential future use)
  defp _render_file_editor(graph, %Frame{} = frame) do
    editor_width = frame.size.width - 40
    editor_height = frame.size.height - 200
    editor_x = 20
    editor_y = 100

    graph
    |> Primitives.group(
      fn graph ->
        graph
        # Draw the editor background
        |> Primitives.rect(
          {editor_width, editor_height},
          fill: :light_yellow,
          stroke: {1, :dark_gray},
          translate: {editor_x, editor_y}
        )
        # Add placeholder text for the editor
        |> Primitives.text(
          "Edit your component file here...",
          font_size: 18,
          fill: :black,
          translate: {editor_x + 10, editor_y + 30}
        )
      end,
      id: :file_editor
    )
  end

  @impl Scenic.Scene
  def handle_input({:viewport, {:reshape, {width, height}}}, _context, scene) do
    # Logger.info("Viewport resized to #{width}x#{height}")

    # Store the new size in ETS for hot reload
    :ets.insert(:widget_workbench_state, {:current_size, {width, height}})

    # Update frame with new dimensions
    new_frame = Frame.new(%{pin: {0, 0}, size: {width, height}})

    # Re-render with new frame and selected component
    graph =
      render(
        new_frame,
        scene.assigns[:selected_component],
        scene.assigns[:component_modal_visible] || false,
        nil,
        scene.assigns[:modal_scroll_offset] || 0
      )

    scene =
      scene
      |> assign(frame: new_frame)
      |> assign(graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  # Keep the old handler in case the event name varies
  @impl Scenic.Scene
  def handle_input({:viewport, {:reshaped, {width, height}}}, context, scene) do
    # Forward to the main handler
    handle_input({:viewport, {:reshape, {width, height}}}, context, scene)
    {:noreply, scene}
  end

  # Handle cursor_button - requested but we don't consume it
  # It will still be routed to child buttons via do_listed_input
  @impl Scenic.Scene
  def handle_input({:cursor_button, {_button, _state, _mods, _coords}} = _input, _context, scene) do
    # Logger.info("🎯 Parent handle_input received cursor_button: #{inspect(input)}")
    # Don't consume - but Scenic requires us to return {:noreply, scene}
    # The input routing has ALREADY happened before this is called
    {:noreply, scene}
  end

  # Handle cursor_pos - requested but we don't consume it
  @impl Scenic.Scene
  def handle_input({:cursor_pos, _}, _context, scene) do
    {:noreply, scene}
  end

  # Handle cursor_scroll for mouse wheel scrolling in modal
  @impl Scenic.Scene
  def handle_input({:cursor_scroll, {{_dx, dy}, _coords}}, _context, scene) do
    # Only handle scroll if modal is visible
    if scene.assigns[:component_modal_visible] do
      # Scroll speed multiplier
      scroll_speed = 30
      current_offset = scene.assigns[:modal_scroll_offset] || 0
      new_offset = current_offset - dy * scroll_speed

      # Calculate modal dimensions (same as render function)
      frame = scene.assigns.frame
      modal_width = 400
      modal_height = 500
      modal_x = (frame.size.width - modal_width) / 2
      modal_y = (frame.size.height - modal_height) / 2
      list_top = modal_y + 60
      list_height = modal_height - 60 - 55
      button_height = 40
      button_margin = 5

      # Get component count to calculate max scroll
      components = discover_components()
      total_content_height = length(components) * (button_height + button_margin)
      max_scroll = max(0, total_content_height - list_height)
      clamped_scroll = max(0, min(new_offset, max_scroll))

      # Update graph transform without re-rendering everything
      new_graph =
        scene.assigns.graph
        |> Graph.modify(:component_list_scroll_group, fn p ->
          Primitives.update_opts(p, translate: {0, -clamped_scroll})
        end)
        |> Graph.modify(:scrollbar_thumb, fn p ->
          scrollbar_height =
            if total_content_height > list_height do
              max(30, list_height * list_height / total_content_height)
            else
              0
            end

          scrollbar_y_offset =
            if total_content_height > list_height and max_scroll > 0 do
              (list_height - scrollbar_height) * (clamped_scroll / max_scroll)
            else
              0
            end

          scrollbar_width = 15

          Primitives.update_opts(p,
            translate:
              {modal_x + modal_width - scrollbar_width - 10, list_top + scrollbar_y_offset}
          )
        end)

      scene =
        scene
        |> assign(modal_scroll_offset: clamped_scroll)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

      {:noreply, scene}
    else
      {:noreply, scene}
    end
  end

  # Handle arrow key scrolling in modal
  @impl Scenic.Scene
  def handle_input(@up_arrow, _context, scene) do
    if scene.assigns[:component_modal_visible] do
      scroll_by_lines(scene, -1)
    else
      {:noreply, scene}
    end
  end

  @impl Scenic.Scene
  def handle_input(@down_arrow, _context, scene) do
    if scene.assigns[:component_modal_visible] do
      scroll_by_lines(scene, 1)
    else
      {:noreply, scene}
    end
  end

  # Handle key input (we request it, so we must handle it)
  @impl Scenic.Scene
  def handle_input({:key, _}, _context, scene) do
    {:noreply, scene}
  end

  # Handle codepoint input (pass through to child components)
  @impl Scenic.Scene
  def handle_input({:codepoint, _}, _context, scene) do
    {:noreply, scene}
  end

  # Helper function to scroll by a number of lines (buttons)
  defp scroll_by_lines(scene, lines) do
    button_height = 40
    button_margin = 5
    line_height = button_height + button_margin

    current_offset = scene.assigns[:modal_scroll_offset] || 0
    new_offset = current_offset + lines * line_height

    # Calculate modal dimensions (same as render function)
    frame = scene.assigns.frame
    modal_width = 400
    modal_height = 500
    modal_x = (frame.size.width - modal_width) / 2
    modal_y = (frame.size.height - modal_height) / 2
    list_top = modal_y + 60
    list_height = modal_height - 60 - 55

    # Get component count to calculate max scroll
    components = discover_components()
    total_content_height = length(components) * (button_height + button_margin)
    max_scroll = max(0, total_content_height - list_height)
    clamped_scroll = max(0, min(new_offset, max_scroll))

    # Update graph transform without re-rendering everything
    new_graph =
      scene.assigns.graph
      |> Graph.modify(:component_list_scroll_group, fn p ->
        Primitives.update_opts(p, translate: {0, -clamped_scroll})
      end)
      |> Graph.modify(:scrollbar_thumb, fn p ->
        scrollbar_height =
          if total_content_height > list_height do
            max(30, list_height * list_height / total_content_height)
          else
            0
          end

        scrollbar_y_offset =
          if total_content_height > list_height and max_scroll > 0 do
            (list_height - scrollbar_height) * (clamped_scroll / max_scroll)
          else
            0
          end

        scrollbar_width = 15

        Primitives.update_opts(p,
          translate: {modal_x + modal_width - scrollbar_width - 10, list_top + scrollbar_y_offset}
        )
      end)

    scene =
      scene
      |> assign(modal_scroll_offset: clamped_scroll)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, scene}
  end

  # Catch-all for other inputs
  @impl Scenic.Scene
  def handle_input(_input, _context, scene) do
    {:noreply, scene}
  end

  # observe_input - called BEFORE handle_input, allows observation without consuming
  @impl Scenic.Scene
  def observe_input({:cursor_button, {:btn_left, 1, [], coords}}, _id, scene) do
    # Visualize on button press (state 1)

    # Send visualization message to self
    send(self(), {:visualize_click, coords})

    {:noreply, scene}
  end

  def observe_input({:cursor_pos, coords}, _id, scene) do
    # Visualize cursor movement with blue dots
    send(self(), {:visualize_hover, coords})
    {:noreply, scene}
  end

  def observe_input(_input, _id, scene), do: {:noreply, scene}

  # NOTE: We deliberately DON'T implement a catch-all handle_input
  # This allows Scenic's default behavior to route inputs to child components (buttons)
  # The specific viewport handlers above are kept for window resize events

  # Handle async visualization message for clicks
  def handle_info({:visualize_click, coords}, scene) do
    # Logger.info("🎨 Rendering click visualization at #{inspect(coords)}")
    {x, y} = coords

    # Get current click sequence number and increment
    click_history = scene.assigns[:click_history] || []
    # A-Z, then wrap
    click_number = rem(length(click_history), 26)
    # Convert to letter A-Z
    click_label = <<click_number + ?A>>

    # Store this click with timestamp
    timestamp = :os.system_time(:millisecond)
    new_click = %{coords: coords, label: click_label, timestamp: timestamp}
    updated_history = [new_click | click_history]

    # Add visualization directly to existing graph without re-rendering
    # This preserves button component state
    click_id = String.to_atom("click_viz_#{timestamp}")

    new_graph =
      scene.assigns.graph
      |> Primitives.circle(
        30,
        fill: {:color, {255, 0, 0, 80}},
        stroke: {3, {:color, {255, 0, 0, 200}}},
        translate: {x, y},
        id: String.to_atom("#{click_id}_outer")
      )
      |> Primitives.circle(
        8,
        fill: {:color, {255, 0, 0, 255}},
        translate: {x, y},
        id: String.to_atom("#{click_id}_inner")
      )
      |> Primitives.text(
        "#{click_label}: (#{trunc(x)}, #{trunc(y)})",
        font_size: 16,
        font: :ibm_plex_mono,
        fill: {:color, {255, 0, 0, 255}},
        translate: {x + 35, y + 5},
        id: String.to_atom("#{click_id}_text")
      )

    scene =
      scene
      |> assign(click_history: updated_history)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    # Logger.info("🎨 Click #{click_label} visualization pushed to graph")

    # Schedule first fade step after 200ms (smooth fade with 50 steps over 10 seconds)
    Process.send_after(self(), {:fade_click_step, click_id, timestamp, 1}, 200)

    {:noreply, scene}
  end

  # Handle async visualization message for hovers
  def handle_info({:visualize_hover, {x, y}}, scene) do
    # Use a single persistent hover indicator that follows the cursor

    new_graph =
      scene.assigns.graph
      |> Graph.delete(:hover_viz_outer)
      |> Graph.delete(:hover_viz_inner)
      |> Primitives.circle(
        15,
        # Dodger blue, semi-transparent
        fill: {:color, {30, 144, 255, 60}},
        stroke: {2, {:color, {30, 144, 255, 180}}},
        translate: {x, y},
        id: :hover_viz_outer
      )
      |> Primitives.circle(
        4,
        # Solid blue center
        fill: {:color, {30, 144, 255, 255}},
        translate: {x, y},
        id: :hover_viz_inner
      )

    scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, scene}
  end

  # Handle smooth fade - fade from 100% to 35% over 10 seconds (50 steps of 200ms each)
  # Smooth linear fade: 100% -> 35% over 50 steps
  def handle_info({:fade_click_step, click_id, timestamp, step}, scene) when step < 50 do
    # Calculate opacity: fade from 100% (1.0) to 35% (0.35) over 50 steps
    # opacity = 1.0 - ((1.0 - 0.35) * step / 50)
    opacity_percent = 1.0 - 0.65 * step / 50

    # Update the opacity for this specific click in history
    click_history = scene.assigns[:click_history] || []

    updated_history =
      Enum.map(click_history, fn click ->
        if click.timestamp == timestamp do
          Map.put(click, :opacity, opacity_percent)
        else
          click
        end
      end)

    # Find the click coordinates
    click = Enum.find(click_history, fn c -> c.timestamp == timestamp end)

    if click do
      # Calculate alpha values based on opacity
      outer_fill_alpha = trunc(80 * opacity_percent)
      outer_stroke_alpha = trunc(200 * opacity_percent)
      inner_alpha = trunc(255 * opacity_percent)
      text_alpha = trunc(255 * opacity_percent)

      # Update ONLY the click visualization primitives using Graph.modify
      outer_id = String.to_atom("#{click_id}_outer")
      inner_id = String.to_atom("#{click_id}_inner")
      text_id = String.to_atom("#{click_id}_text")

      new_graph =
        scene.assigns.graph
        |> Graph.modify(
          outer_id,
          &Primitives.update_opts(&1,
            fill: {:color, {255, 0, 0, outer_fill_alpha}},
            stroke: {3, {:color, {255, 0, 0, outer_stroke_alpha}}}
          )
        )
        |> Graph.modify(
          inner_id,
          &Primitives.update_opts(&1,
            fill: {:color, {255, 0, 0, inner_alpha}}
          )
        )
        |> Graph.modify(
          text_id,
          &Primitives.update_opts(&1,
            fill: {:color, {255, 0, 0, text_alpha}}
          )
        )

      scene =
        scene
        |> assign(click_history: updated_history)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

      # Schedule next fade step in 200ms for smooth animation
      Process.send_after(self(), {:fade_click_step, click_id, timestamp, step + 1}, 200)

      {:noreply, scene}
    else
      # Click was removed, stop fading
      {:noreply, scene}
    end
  end

  # Final step - remove the click after fade completes
  def handle_info({:fade_click_step, click_id, timestamp, _step}, scene) do
    # Remove this click from history
    click_history = scene.assigns[:click_history] || []
    updated_history = Enum.reject(click_history, fn c -> c.timestamp == timestamp end)

    # Delete the click visualization primitives from graph
    outer_id = String.to_atom("#{click_id}_outer")
    inner_id = String.to_atom("#{click_id}_inner")
    text_id = String.to_atom("#{click_id}_text")

    new_graph =
      scene.assigns.graph
      |> Graph.delete(outer_id)
      |> Graph.delete(inner_id)
      |> Graph.delete(text_id)

    scene =
      scene
      |> assign(click_history: updated_history)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, scene}
  end

  # Helper: Re-apply all active click visualizations to a graph
  # This is called after rendering to preserve clicks across graph updates
  defp apply_click_visualizations(graph, scene) do
    click_history = scene.assigns[:click_history] || []
    apply_click_visualizations_with_opacity(graph, click_history)
  end

  # Helper: Apply click visualizations with specific opacity levels
  defp apply_click_visualizations_with_opacity(graph, click_history) do
    Enum.reduce(click_history, graph, fn click, g ->
      {x, y} = click.coords
      timestamp = click.timestamp
      label = click.label
      # Default to 100% if not specified
      opacity = Map.get(click, :opacity, 1.0)
      click_id = String.to_atom("click_viz_#{timestamp}")

      # Calculate alpha values based on opacity
      outer_fill_alpha = trunc(80 * opacity)
      outer_stroke_alpha = trunc(200 * opacity)
      inner_alpha = trunc(255 * opacity)
      text_alpha = trunc(255 * opacity)

      g
      |> Primitives.circle(
        30,
        fill: {:color, {255, 0, 0, outer_fill_alpha}},
        stroke: {3, {:color, {255, 0, 0, outer_stroke_alpha}}},
        translate: {x, y},
        id: String.to_atom("#{click_id}_outer")
      )
      |> Primitives.circle(
        8,
        fill: {:color, {255, 0, 0, inner_alpha}},
        translate: {x, y},
        id: String.to_atom("#{click_id}_inner")
      )
      |> Primitives.text(
        "#{label}: (#{trunc(x)}, #{trunc(y)})",
        font_size: 16,
        font: :ibm_plex_mono,
        fill: {:color, {255, 0, 0, text_alpha}},
        translate: {x + 35, y + 5},
        id: String.to_atom("#{click_id}_text")
      )
    end)
  end

  @impl Scenic.Scene
  def handle_event({:click, :open_widget_button}, _from, scene) do
    # Logger.info("Open Widget button clicked!")
    # TODO: Show a list of available widgets to open
    # For now, let's just log it
    {:noreply, scene}
  end

  def handle_event({:click, :create_widget_button}, _from, scene) do
    # Logger.info("Create New Widget button clicked!")
    # TODO: Show modal to create new widget with name input
    # For now, let's just log it
    {:noreply, scene}
  end

  def handle_event({:click, :new_widget_button}, _from, scene) do
    # Logger.info("New Widget button clicked!")

    # Show the modal
    graph = show_modal(scene.assigns.graph, scene.assigns.frame)

    scene =
      scene
      |> assign(graph: graph)
      |> assign(modal_visible: true)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_event({:click, :close_workbench_button}, _from, scene) do
    # Return to the host app's root scene, if one was configured, e.g.
    #   config :scenic_widget_contrib, :workbench_return_scene, MyApp.RootScene
    case Application.get_env(:scenic_widget_contrib, :workbench_return_scene) do
      nil ->
        Logger.info("close_workbench: no :workbench_return_scene configured, staying put")

      return_scene ->
        {:ok, _} = ViewPort.set_root(scene.viewport, return_scene, nil)
    end

    {:noreply, scene}
  end

  def handle_event({:click, {:file_tab, index}}, _from, scene) do
    # Logger.info("File tab #{index + 1} clicked!")

    # Update the current file index
    scene =
      scene
      |> assign(current_file_index: index)
      |> push_graph(scene.assigns.graph)

    {:noreply, scene}
  end

  def handle_cast({:open_widget, _component}, scene) do
    {:noreply, scene}
  end

  def handle_cast({:load_and_select_component, component_spec}, scene) do
    scene = select_component(scene, component_spec)
    {:noreply, scene}
  end

  def handle_event({:modal_submitted, component_name}, _from, scene) do
    # Logger.info("Modal submitted with component name: #{component_name}")

    # Hide the modal
    graph = hide_modal(scene.assigns.graph)

    # Create new component files using the new ComponentGenerator
    case WidgetWorkbench.ComponentGenerator.generate(component_name) do
      {:ok, _created_files} ->
        # Logger.info("Successfully created component files: #{inspect(created_files)}")

        # Re-discover components to pick up the newly created one
        new_components = discover_components()

        # Find the newly created component module
        module_name = Macro.camelize(component_name)

        new_component =
          Enum.find(new_components, fn {name, _mod} ->
            String.replace(name, " ", "") == module_name
          end)

        # Load the new component automatically
        component_spec =
          case new_component do
            {name, module} ->
              Logger.info("Auto-loading newly created component: #{inspect(module)}")
              component_frame = Frame.new(%{pin: {50, 50}, size: {400, 300}})
              component_opts = prepare_component_data(module, component_frame)
              # Return the proper component_spec tuple: {name, module, opts}
              {name, module, component_opts}

            nil ->
              Logger.warning("Could not find newly created component in discovered list")
              nil
          end

        # Use select_component to properly load and render the component
        scene =
          scene
          |> assign(modal_visible: false)

        scene =
          if component_spec do
            select_component(scene, component_spec)
          else
            scene
            |> assign(graph: graph)
            |> push_graph(graph)
          end

        # Trigger immediate hot reload to re-render the entire scene properly
        send(self(), :hot_reload)

        {:noreply, scene}

      {:error, reason} ->
        Logger.error("Failed to create component: #{reason}")

        # Still hide modal and show error (TODO: show error in UI)
        scene =
          scene
          |> assign(graph: graph)
          |> assign(modal_visible: false)
          |> push_graph(graph)

        {:noreply, scene}
    end
  end

  def handle_event(:modal_cancelled, _from, scene) do
    # Logger.info("Modal cancelled")

    # Hide the modal
    graph =
      hide_modal(scene.assigns.graph)
      |> apply_click_visualizations(scene)

    scene =
      scene
      |> assign(graph: graph)
      |> assign(modal_visible: false)
      |> push_graph(graph)

    {:noreply, scene}
  end

  def handle_event({:menu_item_clicked, item_id}, _from, scene) do
    # Logger.info("Menu item clicked: #{inspect(item_id)}")

    # Handle different menu actions
    case item_id do
      :new_file ->
        Logger.info("Creating new file...")

      :quit ->
        Logger.info("Quit selected")

      _ ->
        nil # Logger.info("Menu action: #{item_id}")
    end

    {:noreply, scene}
  end

  # Load component button
  def handle_event({:click, :load_component_button}, _from, scene) do
    # Logger.info("Load Component button clicked - showing component selection modal")

    # Show the component selection modal (reset scroll to top)
    new_graph =
      render(scene.assigns.frame, scene.assigns.selected_component, true, nil, 0)
      |> apply_click_visualizations(scene)

    # Register component list buttons for MCP
    register_modal_components_for_mcp(scene)

    scene =
      scene
      |> assign(component_modal_visible: true)
      |> assign(modal_scroll_offset: 0)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, scene}
  end

  def handle_event({:click, :reset_scene_button}, _from, scene) do
    # Logger.info("Reset Scene button clicked - clearing component and reloading")

    # Clear selected component and re-render
    new_graph =
      render(scene.assigns.frame, nil, false, nil, 0)
      |> apply_click_visualizations(scene)

    scene =
      scene
      |> assign(selected_component: nil)
      |> assign(component_modal_visible: false)
      |> assign(modal_scroll_offset: 0)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, scene}
  end

  def handle_event({:click, :cancel_component_selection}, _from, scene) do
    # Logger.info("Component selection cancelled")

    # Hide the modal
    new_graph =
      render(
        scene.assigns.frame,
        scene.assigns.selected_component,
        false,
        nil,
        scene.assigns[:modal_scroll_offset] || 0
      )
      |> apply_click_visualizations(scene)

    scene =
      scene
      |> assign(component_modal_visible: false)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, scene}
  end

  def handle_event({:click, {:select_component, component_module}}, _from, scene) do
    # Find the component info from our discovered list
    components = discover_components()

    {component_name, component_module} =
      Enum.find(components, fn {_name, module} -> module == component_module end)

    Logger.info("Component selected: #{component_name}")

    # Calculate component frame for click-outside detection
    frame = scene.assigns.frame

    main_area =
      Frame.new(%{
        pin: {0, 0},
        size: {frame.size.width * 2 / 3, frame.size.height}
      })

    _center_point = Frame.center(main_area)

    # Component selected - render it at a consistent ANCHOR POINT
    # ANCHOR POINT: Always position components at (50, 50) for predictable testing
    anchor_x = 50
    anchor_y = 50

    # Create a reasonable default frame for the component
    # MenuBar needs more width for all menus, other components get 400x200
    default_size =
      case component_module do
        # 4 menus * 150px each
        ScenicWidgets.MenuBar -> {600, 200}
        _ -> {400, 200}
      end

    component_frame =
      Frame.new(%{
        pin: {anchor_x, anchor_y},
        size: default_size
      })

    Logger.info("🎯 Component positioning (ANCHORED at #{anchor_x}, #{anchor_y}):")

    component_opts = prepare_component_data(component_module, component_frame)
    selected = {component_name, component_module, component_opts}

    # Re-render with the selected component and hide modal
    new_graph =
      render(scene.assigns.frame, selected, false, nil, 0)
      |> apply_click_visualizations(scene)

    scene =
      scene
      |> assign(selected_component: selected)
      |> assign(selected_component_name: component_name)
      # |> assign(component_frame: component_frame)
      |> assign(component_modal_visible: false)
      |> assign(modal_scroll_offset: 0)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, scene}
  end

  def handle_event(_event, _from, scene), do: {:noreply, scene}

  # Handle get_graph for scenic_mcp
  def handle_call(:get_graph, _from, scene) do
    {:reply, {:ok, scene.assigns.graph}, scene}
  end

  # Function to show the modal
  defp show_modal(graph, frame) do
    modal_id = :new_widget_modal

    graph
    |> Graph.add_to(:modal_container, fn g ->
      g
      |> Modal.add_to_graph(
        %{
          id: modal_id,
          frame: frame,
          title: "Enter Component Name",
          placeholder: "ComponentName"
        },
        id: modal_id
      )
    end)
  end

  # Function to hide the modal
  defp hide_modal(graph) do
    graph
    |> Graph.modify(:modal_container, fn primitive ->
      %{primitive | data: []}
    end)
  end

  # Helper to find the loaded component's PID (unused, kept for potential future use)
  defp _find_loaded_component_pid(scene) do
    # Look for children with the :loaded_component id
    scene.children
    |> Enum.find_value(fn
      {{_parent_id, :loaded_component}, {pid, _child_pid, _id, _data}} when is_pid(pid) -> pid
      _ -> nil
    end)
  end

  # Render click visualization - a pulsing circle at click location
  defp render_click_visualization(graph, %{coords: {x, y}}) do
    graph
    # Outer pulse circle
    |> Primitives.circle(
      30,
      fill: {:color, {255, 0, 0, 50}},
      stroke: {3, {:color, {255, 0, 0, 150}}},
      translate: {x, y},
      id: :click_viz_outer
    )
    # Inner dot
    |> Primitives.circle(
      8,
      fill: {:color, {255, 0, 0, 255}},
      translate: {x, y},
      id: :click_viz_inner
    )
    # Coordinates text
    |> Primitives.text(
      "(#{trunc(x)}, #{trunc(y)})",
      font_size: 14,
      fill: {:color, {255, 0, 0, 255}},
      translate: {x + 35, y + 5},
      id: :click_viz_text
    )
  end

  def handle_info(:hot_reload, scene) do
    # Get size from multiple sources to debug
    stored_frame = scene.assigns.frame
    # Debug info available if needed:
    # scene_viewport_size = scene.viewport.size
    # {:ok, viewport_info} = Scenic.ViewPort.info(:main_viewport)
    # vp_info_size = viewport_info.size

    # Use the stored frame size since that's what was last set by resize event
    current_frame = stored_frame

    # Re-render with current dimensions and selected component
    new_graph =
      render(
        current_frame,
        scene.assigns[:selected_component],
        scene.assigns[:component_modal_visible] || false,
        scene.assigns[:click_visualization],
        scene.assigns[:modal_scroll_offset] || 0
      )

    scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, scene}
  end

  # Delegate :_input messages to Scenic.Scene's handle_info (for observe_input/handle_input)
  def handle_info({:_input, input, raw_input, id}, scene) do
    # Call Scenic.Scene's implementation directly
    Scenic.Scene.handle_info({:_input, input, raw_input, id}, scene)
  end

  # Handle navigation events from SideNav component
  # Note: Scenic wraps events with {:_event, msg, pid} when using send_parent_event/2
  def handle_info({:_event, {:sidebar, :navigate, item_id}, _sender_pid}, scene) do
    Logger.info("📬 PARENT RECEIVED: {:sidebar, :navigate, #{inspect(item_id)}}")
    Logger.info("   Widget Workbench can now respond to this navigation event!")
    {:noreply, scene}
  end

  def handle_info({:_event, {:sidebar, :expand, item_id}, _sender_pid}, scene) do
    Logger.info("📬 PARENT RECEIVED: {:sidebar, :expand, #{inspect(item_id)}}")
    {:noreply, scene}
  end

  def handle_info({:_event, {:sidebar, :collapse, item_id}, _sender_pid}, scene) do
    Logger.info("📬 PARENT RECEIVED: {:sidebar, :collapse, #{inspect(item_id)}}")
    {:noreply, scene}
  end

  def handle_info(msg, scene) do
    {:noreply, scene}
  end

  # ============================================================================
  # Semantic MCP Registration - Makes buttons clickable via semantic IDs
  # ============================================================================

  defp _register_buttons_for_mcp(_scene, frame) do
    # viewport = scene.viewport # For future semantic registration

    # Calculate button frames (same logic as render_constructor_pane)
    pane_width = frame.size.width / 3
    pane_height = frame.size.height

    pane_frame =
      Frame.new(%{pin: {frame.size.width - pane_width, 0}, size: {pane_width, pane_height}})

    pane_grid =
      Grid.new(pane_frame)
      |> Grid.rows([20, 35, 30, 15, 50, 20, 50, 20, 50, 1])
      |> Grid.columns([0.1, 0.8, 0.1])
      |> Grid.define_areas(%{
        title: {1, 1, 1, 1},
        subtitle: {2, 1, 1, 1},
        reset_button: {4, 1, 1, 1},
        new_button: {6, 1, 1, 1},
        load_button: {8, 1, 1, 1}
      })

    cell_frames = Grid.calculate(pane_grid)
    load_button_frame = Grid.area_frame(pane_grid, cell_frames, :load_button)

    # Register Load Component button
    {left, top} = load_button_frame.pin.point
    width = load_button_frame.size.width
    height = load_button_frame.size.height

    # TODO: Re-enable when Scenic.ViewPort.register_semantic/4 is available
    # Scenic.ViewPort.register_semantic(
    #   viewport,
    #   :_root_,
    #   :load_component_button,
    #   %{
    #     type: :button,
    #     label: "Load Component",
    #     clickable: true,
    #     bounds: %{
    #       left: left,
    #       top: top,
    #       width: width,
    #       height: height
    #     },
    #     semantic: %{
    #       type: :button,
    #       label: "Load Component"
    #     }
    #   }
    # )

    Logger.info(
      "🎯 Registered Load Component button for MCP at {#{left}, #{top}, #{width}x#{height}}"
    )
  end

  # Register all component buttons in the modal for MCP clicking
  defp register_modal_components_for_mcp(scene) do
    # viewport = scene.viewport # For future semantic registration
    frame = scene.assigns.frame

    # Calculate modal dimensions (same as in render_component_selection_modal)
    modal_width = 400
    modal_height = 500
    modal_x = (frame.size.width - modal_width) / 2
    modal_y = (frame.size.height - modal_height) / 2
    list_top = modal_y + 60
    scrollbar_width = 15

    button_height = 40
    button_margin = 5
    # Account for padding
    button_width = modal_width - scrollbar_width - 5 - 40

    components = discover_components()

    # Register each component button (global coordinates)
    components
    |> Enum.with_index()
    |> Enum.each(fn {{name, module}, index} ->
      # Calculate global position (group is translated to modal_x, list_top)
      y = list_top + (button_height + button_margin) * index
      # modal_x from group translate + 20 from local offset
      x = modal_x + 20

      # Create a semantic ID from the module name
      semantic_id =
        module
        |> to_string()
        |> String.split(".")
        |> List.last()
        |> Macro.underscore()
        |> then(&"component_#{&1}")
        |> String.to_atom()

      # Register using Phase 1 semantic format (direct ETS insertion)
      viewport = scene.viewport
      if viewport.semantic_table && viewport.semantic_enabled do
        entry = %Scenic.Semantic.Compiler.Entry{
          id: semantic_id,
          type: :component,
          module: module,
          parent_id: nil,
          children: [],
          local_bounds: %{left: x, top: y, width: button_width, height: button_height},
          screen_bounds: %{left: x, top: y, width: button_width, height: button_height},
          clickable: true,
          focusable: false,
          label: name,
          role: :button,
          value: nil,
          hidden: false,
          z_index: 10 + index  # Modal buttons have high z-index
        }
        :ets.insert(viewport.semantic_table, {{:_root_, semantic_id}, entry})
        :ets.insert(viewport.semantic_index, {semantic_id, {:_root_, semantic_id}})
      end

      Logger.info(
        "🎯 Registered component button '#{name}' (#{semantic_id}) for MCP at {#{x}, #{y}, #{button_width}x#{button_height}}"
      )
    end)

    # Also register the cancel button
    cancel_x = modal_x + modal_width - 90
    cancel_y = modal_y + modal_height - 45

    # Register cancel button using Phase 1 semantic format
    viewport = scene.viewport
    if viewport.semantic_table && viewport.semantic_enabled do
      cancel_entry = %Scenic.Semantic.Compiler.Entry{
        id: :cancel_component_selection,
        type: :component,
        module: nil,
        parent_id: nil,
        children: [],
        local_bounds: %{left: cancel_x, top: cancel_y, width: 80, height: 35},
        screen_bounds: %{left: cancel_x, top: cancel_y, width: 80, height: 35},
        clickable: true,
        focusable: false,
        label: "Cancel",
        role: :button,
        value: nil,
        hidden: false,
        z_index: 22  # Cancel button on top
      }
      :ets.insert(viewport.semantic_table, {{:_root_, :cancel_component_selection}, cancel_entry})
      :ets.insert(viewport.semantic_index, {:cancel_component_selection, {:_root_, :cancel_component_selection}})
    end

    Logger.info("🎯 Registered Cancel button for MCP at {#{cancel_x}, #{cancel_y}, 80x35}")
  end

  # Helper to build menu_map with optional action callbacks for testing
  defp build_menu_map do
    # Check if we're in test mode and get test PID
    test_pid = Application.get_env(:scenic_widget_contrib, :test_pid)

    # Base menu structure
    base_menu = [
      {:sub_menu, "File",
       [
         {"new_file", "New File"},
         {"open_file", "Open File"},
         {:sub_menu, "Recent Files",
          [
            {"recent_1", "Document 1.txt"},
            {"recent_2", "Project Notes.md"},
            {:sub_menu, "By Project",
             [
               {:sub_menu, "Project A",
                [
                  {:sub_menu, "Source Code",
                   [
                     {:sub_menu, "Core Modules",
                      [
                        {:sub_menu, "Authentication",
                         [
                           {"auth_user", "user.ex"},
                           {"auth_session", "session.ex"},
                           {"auth_token", "token.ex"},
                           {"auth_middleware", "middleware.ex"}
                         ]},
                        {:sub_menu, "Database",
                         [
                           {"db_schema", "schema.ex"},
                           {"db_repo", "repo.ex"},
                           {"db_migration", "migration.ex"}
                         ]},
                        {"core_app", "application.ex"},
                        {"core_supervisor", "supervisor.ex"}
                      ]},
                     {"src_main", "main.ex"},
                     {"src_utils", "utils.ex"}
                   ]},
                  {"proj_a_readme", "README.md"},
                  {"proj_a_config", "config.exs"}
                ]},
               {:sub_menu, "Project B",
                [
                  {"proj_b_app", "application.ex"},
                  {"proj_b_server", "server.ex"}
                ]},
               {"all_projects", "All Projects..."}
             ]}
          ]},
         {"save_file", "Save"},
         {"save_as", "Save As..."},
         {:sub_menu, "Export",
          [
            {"export_pdf", "Export as PDF"},
            {"export_html", "Export as HTML"},
            {:sub_menu, "Export Image",
             [
               {"export_png", "PNG"},
               {"export_jpg", "JPEG"},
               {"export_svg", "SVG"}
             ]}
          ]},
         {"quit", "Quit"}
       ]},
      {:sub_menu, "Edit",
       [
         {"undo", "Undo"},
         {"redo", "Redo"},
         {"cut", "Cut"},
         {"copy", "Copy"},
         {"paste", "Paste"},
         {:sub_menu, "Find",
          [
            {"find", "Find..."},
            {"find_replace", "Find and Replace..."},
            {:sub_menu, "Find in",
             [
               {"find_project", "Current Project"},
               {"find_folder", "Current Folder"},
               {"find_all", "All Open Files"}
             ]}
          ]}
       ]},
      {:sub_menu, "View",
       [
         {:sub_menu, "Appearance",
          [
            {"theme_light", "Light Theme"},
            {"theme_dark", "Dark Theme"},
            {"theme_auto", "Auto"}
          ]},
         {:sub_menu, "Layout",
          [
            {"layout_single", "Single Pane"},
            {"layout_split", "Split Horizontal"},
            {"layout_split_v", "Split Vertical"}
          ]},
         {"fullscreen", "Toggle Fullscreen"}
       ]},
      {:sub_menu, "Help",
       [
         {"docs", "Documentation"},
         {"shortcuts", "Keyboard Shortcuts"},
         {:sub_menu, "Tutorials",
          [
            {"tut_basics", "Getting Started"},
            {"tut_advanced", "Advanced Features"},
            {"tut_tips", "Tips & Tricks"}
          ]},
         {"about", "About"}
       ]}
    ]

    # If we're in test mode with a test PID, add action callbacks
    if test_pid do
      add_action_callbacks(base_menu, test_pid)
    else
      base_menu
    end
  end

  # Recursively add action callbacks to menu items
  defp add_action_callbacks(menu_list, test_pid) do
    Enum.map(menu_list, fn
      {:sub_menu, label, items} ->
        {:sub_menu, label, add_action_callbacks(items, test_pid)}

      {item_id, label} when is_binary(item_id) ->
        # Add action callback that sends message to test process
        {item_id, label, fn -> send(test_pid, {:action_executed, item_id}) end}

      other ->
        other
    end)
  end
end
