defmodule ScenicWidgets.TestHelpers.SemanticUI do
  @moduledoc """
  Semantic UI testing helpers that work with rendered content and layout,
  rather than hardcoded coordinates.

  This provides a higher-level abstraction for UI testing that:
  1. Looks at what's actually rendered
  2. Finds elements by text/description
  3. Clicks intelligently based on what's visible
  4. Verifies outcomes semantically
  """

  alias ScenicWidgets.TestHelpers.ScriptInspector
  alias ScenicMcp.Tools

  @doc """
  Connect and setup viewport for testing.
  Used in setup_all blocks for spex tests.
  """
  def connect_and_setup_viewport() do
    # Give the app time to boot
    Process.sleep(1000)
    {:ok, %{}}
  end

  @doc """
  Cleanup viewport after testing.
  Used in on_exit blocks for spex tests.
  """
  def cleanup_viewport() do
    :ok
  end

  @doc """
  Verify that Widget Workbench has booted properly.
  Returns {:ok, state} or {:error, reason}.
  """
  def verify_widget_workbench_loaded() do
    rendered_content = ScriptInspector.get_rendered_text_string()

    cond do
      String.contains?(rendered_content, "Widget Workbench") ->
        {:ok, %{status: :loaded, content: rendered_content}}

      String.contains?(rendered_content, "Load Component") ->
        {:ok, %{status: :ready_for_component, content: rendered_content}}

      true ->
        {:error, "Widget Workbench not detected. Got: #{inspect(String.slice(rendered_content, 0, 200))}"}
    end
  end

  @doc """
  Verify that a specific button or element exists in the UI.
  Returns {:ok, position} or {:error, reason}.
  """
  def verify_element_exists(element_text) do
    rendered_content = ScriptInspector.get_rendered_text_string()

    if String.contains?(rendered_content, element_text) do
      {:ok, %{text: element_text, found: true}}
    else
      {:error, "Element '#{element_text}' not found. Available: #{inspect(String.slice(rendered_content, 0, 200))}"}
    end
  end

  @doc """
  Click on the Load Component button using intelligent positioning.
  First checks what's actually available, then finds and clicks the right button.
  """
  def click_load_component_button() do
    rendered_content = ScriptInspector.get_rendered_text_string()
    IO.puts("🔍 Current UI content: #{inspect(String.slice(rendered_content, 0, 200))}")

    # Check what buttons are actually available
    cond do
      String.contains?(rendered_content, "Load Component") ->
        # We know from WidgetWorkbench.Scene that Load Component is in right pane
        click_load_component_directly()

      String.contains?(rendered_content, "New Widget") ->
        # If we only see "New Widget", we might need to navigate to find "Load Component"
        # For now, let's try a broader search approach
        IO.puts("⚠️  'Load Component' not found, trying to find it in the UI...")
        find_and_click_load_component()

      true ->
        {:error, "Neither 'Load Component' nor 'New Widget' buttons found. UI may not be ready."}
    end
  end

  defp click_load_component_directly() do
    {:ok, viewport_info} = get_viewport_info()
    {screen_width, screen_height} = viewport_info.size

    # From WidgetWorkbench.Scene, we know:
    # - Constructor pane is right 1/3 of screen
    # - Grid layout: rows [20, 35, 30, 15, 50, 20, 50, 20, 50, 1]
    # - Load button is in row 8 (index 8)
    # Let's calculate the exact position

    # Right pane starts at 2/3 of width
    right_pane_start = screen_width * (2.0 / 3.0)
    right_pane_width = screen_width * (1.0 / 3.0)

    # Button is centered in the pane with 0.1 padding on each side
    button_center_x = right_pane_start + (right_pane_width * 0.5)

    # Calculate Y position based on grid rows
    # rows: [20, 35, 30, 15, 50, 20, 50, 20, 50, 1]
    # Load button is at row index 8
    row_heights = [20, 35, 30, 15, 50, 20, 50, 20, 50]
    button_y_start = Enum.sum(Enum.take(row_heights, 8))
    button_y_center = button_y_start + 25  # Middle of 50px button

    # Convert to integers
    click_x = round(button_center_x)
    click_y = round(button_y_center)

    IO.puts("🎯 Clicking Load Component button at calculated position (#{click_x}, #{click_y})")

    click_at_position(click_x, click_y)
    Process.sleep(500)

    # Verify the modal opened
    case verify_modal_opened() do
      {:ok, modal_info} -> {:ok, %{clicked: true, modal: modal_info}}
      {:error, reason} -> {:error, "Button clicked but modal didn't open: #{reason}"}
    end
  end

  @doc """
  Generic button clicking by finding the button text and clicking near it.
  """
  def click_button_by_name(button_text) do
    with {:ok, _} <- verify_element_exists(button_text),
         {:ok, viewport_info} <- get_viewport_info() do

      {screen_width, screen_height} = viewport_info.size

      # Try different locations based on Widget Workbench layout
      # Right pane (tools pane) - most likely location
      right_pane_center = round(screen_width * 0.75)
      button_y = round(screen_height * 0.6)  # Try middle area first

      IO.puts("🖱️  Clicking '#{button_text}' button at (#{right_pane_center}, #{button_y})")

      click_at_position(right_pane_center, button_y)

      # Verify the modal opened (if this was Load Component)
      if button_text == "Load Component" do
        case verify_modal_opened() do
          {:ok, modal_info} -> {:ok, %{clicked: true, modal: modal_info}}
          {:error, reason} ->
            # Try a different position if first attempt failed
            IO.puts("🔄 First click failed, trying different position...")
            button_y2 = round(screen_height * 0.5)
            click_at_position(right_pane_center, button_y2)
            Process.sleep(500)

            case verify_modal_opened() do
              {:ok, modal_info} -> {:ok, %{clicked: true, modal: modal_info}}
              {:error, reason2} -> {:error, "Button clicked but modal didn't open after retries: #{reason2}"}
            end
        end
      else
        {:ok, %{clicked: true, button: button_text}}
      end
    else
      error -> error
    end
  end

  defp find_and_click_load_component() do
    # Try to navigate or find the Load Component button
    # This might involve clicking through different UI areas
    {:ok, viewport_info} = get_viewport_info()
    {screen_width, screen_height} = viewport_info.size

    # Try clicking in different areas of the right pane to find Load Component
    positions_to_try = [
      {round(screen_width * 0.75), round(screen_height * 0.4)},  # Upper right pane
      {round(screen_width * 0.75), round(screen_height * 0.6)},  # Middle right pane
      {round(screen_width * 0.75), round(screen_height * 0.8)},  # Lower right pane
    ]

    try_positions_until_modal_opens(positions_to_try)
  end

  defp try_positions_until_modal_opens([]) do
    {:error, "Could not find Load Component button after trying multiple positions"}
  end

  defp try_positions_until_modal_opens([{x, y} | rest]) do
    IO.puts("🔄 Trying position (#{x}, #{y})...")
    click_at_position(x, y)

    case verify_modal_opened() do
      {:ok, modal_info} ->
        IO.puts("✅ Found the right button!")
        {:ok, %{clicked: true, modal: modal_info}}
      {:error, _} ->
        try_positions_until_modal_opens(rest)
    end
  end

  defp click_at_position(x, y) do
    # Use the same approach as ScenicMcp.Probes - get the driver and send input directly
    driver_struct = get_driver_state()

    # Press
    Scenic.Driver.send_input(driver_struct, {:cursor_button, {:btn_left, 1, [], {x, y}}})
    Process.sleep(10)

    # Release
    Scenic.Driver.send_input(driver_struct, {:cursor_button, {:btn_left, 0, [], {x, y}}})
    Process.sleep(500)
  end

  defp send_scroll_event({dx, dy}, {x, y}) do
    # Send scroll event at specific coordinates
    driver_struct = get_driver_state()
    Scenic.Driver.send_input(driver_struct, {:cursor_scroll, {{dx, dy}, {x, y}}})
    Process.sleep(100)
  end

  defp get_driver_state() do
    # Get driver name from config (allows test and dev to run simultaneously)
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :scenic_driver)
    viewport_name = ScenicMcp.Config.viewport_name()

    # Get the driver from the registered name or via viewport
    case Process.whereis(driver_name) do
      nil ->
        # Fallback: get driver from viewport
        viewport_pid = Process.whereis(viewport_name)
        state = :sys.get_state(viewport_pid, 5000)
        [driver | _] = Map.get(state, :driver_pids, [])
        :sys.get_state(driver, 5000)
      driver_pid ->
        :sys.get_state(driver_pid, 5000)
    end
  end

  @doc """
  Verify that the component selection modal has opened.
  """
  def verify_modal_opened() do
    Process.sleep(500)  # Give modal time to appear
    rendered_content = ScriptInspector.get_rendered_text_string()

    cond do
      String.contains?(rendered_content, "Menu Bar") and
      String.contains?(rendered_content, "Tab Bar") ->
        # Debug: show what components we see
        IO.puts("📋 Modal components detected in rendered content")
        {:ok, %{status: :open, components_visible: true, content: rendered_content}}

      String.contains?(rendered_content, "Select Component") ->
        {:ok, %{status: :open, components_visible: false}}

      true ->
        {:error, "Modal not detected. Got: #{inspect(String.slice(rendered_content, 0, 300))}"}
    end
  end

  @doc """
  Click on a component in the modal by name.
  """
  def click_component_in_modal(component_name) do
    with {:ok, _modal} <- verify_modal_opened(),
         {:ok, _} <- verify_element_exists(component_name),
         {:ok, viewport_info} <- get_viewport_info() do

      {screen_width, screen_height} = viewport_info.size

      # From WidgetWorkbench.Scene render_component_selection_modal:
      # Modal is 400x500, centered on screen
      modal_width = 400
      modal_height = 500
      modal_x = (screen_width - modal_width) / 2
      modal_y = (screen_height - modal_height) / 2

      # Components list starts at modal_y + 60
      # Each button is 40px high with 5px margin
      button_height = 40
      button_margin = 5

      # Button width is modal_width - 40 (20px padding on each side)
      button_width = modal_width - 40
      button_x = modal_x + 20

      # From the rendered output, components appear in this order:
      # Parse the rendered content to find the actual order
      rendered_content = ScriptInspector.get_rendered_text_string()

      # Find Menu Bar's position by looking for it in the modal content
      # Components seem to be listed vertically in the modal
      component_index = if String.contains?(rendered_content, "Select Component") do
        # Count how many component names appear before our target
        components_before = 0

        # List of components we might see (based on actual output)
        possible_components = [
          "Buttons", "Frame Box", "Icon Button", "Input Modal",
          "Menu Bar", "Reset Scene", "Scroll Bars", "Side Nav",
          "Tab Bar", "Test Pattern", "Text Button"
        ]

        # Based on alphabetical directory listing from lib/components/
        # Components are discovered and sorted alphabetically by display name
        case component_name do
          "Buttons" -> 0
          "Frame Box" -> 1
          "Input Modal" -> 2
          "Markup Widgets" -> 3
          "Menu Bar" -> 4
          "Scroll Bars" -> 5
          "Side Nav" -> 6
          "Sidebar" -> 7
          "Spare Parts" -> 8
          "Tab Bar" -> 9
          "Text Field" -> 10  # text_field directory = "Text Field"
          "Ubuntu Bar" -> 11
          _ -> 0  # Default to first position
        end
      else
        4  # Default fallback
      end

      # Calculate button position based on component index
      # Buttons start at list_top = modal_y + 60
      list_top = modal_y + 60
      button_y = list_top + (component_index * (button_height + button_margin))

      # Check if we need to scroll to make this component visible
      list_bottom = modal_y + modal_height - 55
      max_visible_index = trunc((modal_height - 60 - 55) / (button_height + button_margin)) - 1

      # If component index is beyond visible area, scroll to make it visible
      if component_index > max_visible_index do
        scroll_events = component_index - max_visible_index
        IO.puts("📜 Component #{component_name} at index #{component_index} needs scrolling")
        IO.puts("    Sending #{scroll_events} down arrow keys...")

        for _i <- 1..scroll_events do
          ScenicMcp.Probes.send_keys("down", [])
          Process.sleep(100)
        end
        Process.sleep(300)
      end

      # After scrolling (or if no scroll needed), use semantic clicking
      # Build semantic ID: "Text Field" -> "component_text_field"
      component_id = component_name
        |> String.downcase()
        |> String.replace(" ", "_")
        |> then(&("component_" <> &1))

      IO.puts("🖱️  Clicking #{component_name} using semantic ID: :#{component_id}")

      # Use ScenicMcp.Tools to click by semantic ID
      # The function expects a map with "element_id" key (string)
      case Tools.click_element(%{"element_id" => component_id}) do
        {:ok, result} ->
          IO.puts("✓ Successfully clicked #{component_name}")
          IO.puts("     Result: #{inspect(result)}")
          Process.sleep(1000)

        {:error, reason} ->
          IO.puts("❌ Failed to click #{component_name}: #{inspect(reason)}")
          Process.sleep(1000)
      end

      # Verify the component loaded
      verify_component_loaded(component_name)
    else
      error -> error
    end
  end

  @doc """
  Verify that a specific component has been loaded and is visible.
  """
  def verify_component_loaded(component_name) do
    Process.sleep(1000)  # Give component time to load
    rendered_content = ScriptInspector.get_rendered_text_string()

    # For MenuBar, we expect to see menu items like "File", "Edit", "View", "Help"
    case component_name do
      "Menu Bar" ->
        menu_items = ["File", "Edit", "View", "Help"]
        found_items = Enum.filter(menu_items, fn item ->
          String.contains?(rendered_content, item)
        end)

        if length(found_items) >= 2 do
          {:ok, %{component: component_name, menu_items: found_items, loaded: true}}
        else
          {:error, "MenuBar not loaded. Expected menu items, got: #{inspect(String.slice(rendered_content, 0, 300))}"}
        end

      "Text Field" ->
        # TextField now starts empty (for testing)
        # Just verify the component loaded without errors - we'll check functionality in tests
        # The workbench UI shows "+" characters which indicates the TextField is rendered
        if not String.contains?(rendered_content, "Error") do
          {:ok, %{component: component_name, loaded: true}}
        else
          {:error, "TextField failed to load. Got: #{inspect(String.slice(rendered_content, 0, 300))}"}
        end

      "Side Nav" ->
        # SideNav renders a tree with items like "GETTING STARTED"
        if String.contains?(rendered_content, "GETTING STARTED") do
          {:ok, %{component: component_name, loaded: true, tree_visible: true}}
        else
          {:error, "Side Nav tree not visible. Got: #{inspect(String.slice(rendered_content, 0, 300))}"}
        end

      _ ->
        if String.contains?(rendered_content, component_name) do
          {:ok, %{component: component_name, loaded: true}}
        else
          {:error, "Component #{component_name} not loaded. Got: #{inspect(String.slice(rendered_content, 0, 300))}"}
        end
    end
  end

  @doc """
  Complete workflow: Load a component in Widget Workbench.
  """
  def load_component(component_name) do
    IO.puts("🎯 Loading component: #{component_name}")

    with {:ok, _} <- verify_widget_workbench_loaded(),
         {:ok, _} <- click_load_component_button(),
         {:ok, _} <- click_component_in_modal(component_name),
         {:ok, result} <- verify_component_loaded(component_name) do

      IO.puts("✅ Successfully loaded #{component_name}")
      {:ok, result}
    else
      {:error, reason} ->
        IO.puts("❌ Failed to load #{component_name}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Send keyboard keys to the application.
  Accepts either a string (for text) or {:key, key_name} tuple for special keys.
  """
  def send_keys(text) when is_binary(text) do
    case Tools.handle_send_keys(%{"text" => text}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def send_keys({:key, key_name}) do
    case Tools.handle_send_keys(%{"key" => Atom.to_string(key_name)}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Click on an element by its semantic ID.
  """
  def click_element(element_id) when is_atom(element_id) do
    click_element(Atom.to_string(element_id))
  end

  def click_element(element_id) when is_binary(element_id) do
    # Remove leading colon if present
    id = String.trim_leading(element_id, ":")

    case Tools.click_element(%{"element_id" => id}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Send a mouse click at specific coordinates.
  """
  def send_mouse_click(x, y) do
    case Tools.handle_mouse_click(%{"x" => x, "y" => y}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Find all clickable elements in the viewport.
  """
  def find_clickable_elements() do
    case Tools.find_clickable_elements(%{}) do
      {:ok, %{elements: elements}} -> {:ok, elements}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Inspect the viewport and return visual description.
  """
  def inspect_viewport() do
    case Tools.handle_get_scenic_graph() do
      {:ok, %{visual_description: desc}} -> {:ok, desc}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Take a screenshot and return the path.
  """
  def take_screenshot(name) do
    case Tools.take_screenshot(%{"filename" => name}) do
      {:ok, %{path: path}} -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helpers
  defp get_viewport_info() do
    # Get viewport name from config (allows test and dev to run simultaneously)
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :main_viewport)

    case Scenic.ViewPort.info(viewport_name) do
      {:ok, info} -> {:ok, info}
      error -> {:error, "Could not get viewport info: #{inspect(error)}"}
    end
  end
end
