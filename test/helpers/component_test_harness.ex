defmodule ScenicWidgets.TestHelpers.ComponentTestHarness do
  @moduledoc """
  Reusable helper functions for automated component testing via scenic_mcp.

  This module provides high-level functions for:
  - Loading components programmatically
  - Verifying component state
  - Visual regression testing
  - Automated UI interaction

  ## Usage

      alias ScenicWidgets.TestHelpers.ComponentTestHarness

      # Load a component
      {:ok, screenshot} = ComponentTestHarness.load_component("MenuBar")

      # Verify it loaded
      assert ComponentTestHarness.component_loaded?(ScenicWidgets.MenuBar)

      # Get all available components
      components = ComponentTestHarness.list_available_components()
  """

  alias ScenicWidgets.TestHelpers.ScriptInspector

  # Configuration
  @default_wait_ms 500
  @modal_wait_ms 300
  @component_load_wait_ms 1000

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Get a list of all available components in the Widget Workbench.

  Returns a list of `{name, module}` tuples.

  ## Example

      iex> ComponentTestHarness.list_available_components()
      [
        {"Buttons", ScenicWidgets.Buttons},
        {"MenuBar", ScenicWidgets.MenuBar},
        ...
      ]
  """
  @spec list_available_components() :: [{String.t() | atom(), module()}]
  def list_available_components do
    WidgetWorkbench.Scene.discover_components()
  end

  @doc """
  Load a specific component by name via MCP automation.

  This function:
  1. Clicks the "Load Component" button
  2. Waits for the modal to open
  3. Finds and clicks the component button
  4. Waits for component to load
  5. Takes a screenshot for verification

  Returns `{:ok, screenshot_path}` on success, or `{:error, reason}` on failure.

  ## Options

  - `:wait_ms` - Time to wait for component to load (default: 1000ms)
  - `:screenshot` - Whether to take a screenshot (default: true)
  - `:screenshot_name` - Custom screenshot name (default: "component_{name}")

  ## Examples

      iex> ComponentTestHarness.load_component("MenuBar")
      {:ok, "/tmp/scenic_screenshot_2025-10-11_component_MenuBar.png"}

      iex> ComponentTestHarness.load_component("InvalidComponent")
      {:error, "Component button not found"}
  """
  @spec load_component(String.t() | atom(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def load_component(component_name, opts \\ []) do
    wait_ms = Keyword.get(opts, :wait_ms, @component_load_wait_ms)
    take_screenshot? = Keyword.get(opts, :screenshot, true)
    screenshot_name = Keyword.get(opts, :screenshot_name, "component_#{component_name}")

    with :ok <- open_component_modal(),
         :ok <- click_component_button(component_name),
         :ok <- wait_for_load(wait_ms),
         {:ok, screenshot} <- maybe_take_screenshot(take_screenshot?, screenshot_name) do
      {:ok, screenshot}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Load a component and verify it rendered successfully.

  Returns `{:ok, screenshot_path}` if the component loaded and is visible,
  or `{:error, reason}` if loading failed or component is not visible.

  ## Example

      iex> ComponentTestHarness.load_and_verify_component("MenuBar", ScenicWidgets.MenuBar)
      {:ok, "/tmp/scenic_screenshot_...png"}
  """
  @spec load_and_verify_component(String.t() | atom(), module(), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def load_and_verify_component(component_name, component_module, opts \\ []) do
    case load_component(component_name, opts) do
      {:ok, screenshot} ->
        if component_loaded?(component_module) do
          {:ok, screenshot}
        else
          {:error, "Component loaded but not found in viewport"}
        end

      error -> error
    end
  end

  @doc """
  Check if a specific component module is currently loaded in the viewport.

  Returns `true` if the component is found in the script table, `false` otherwise.

  ## Example

      iex> ComponentTestHarness.component_loaded?(ScenicWidgets.MenuBar)
      true
  """
  @spec component_loaded?(module()) :: boolean()
  def component_loaded?(component_module) when is_atom(component_module) do
    script_dump = ScriptInspector.debug_script_table()
    String.contains?(script_dump, inspect(component_module))
  end

  @doc """
  Find a component button by name and return its semantic ID.

  Returns `{:ok, element_id}` if found, or `{:error, reason}` if not found.

  ## Example

      iex> ComponentTestHarness.find_component_button("MenuBar")
      {:ok, :component_menu_bar}
  """
  @spec find_component_button(String.t() | atom()) :: {:ok, atom()} | {:error, String.t()}
  def find_component_button(component_name) do
    # Convert name to semantic ID format
    component_id = build_component_id(component_name)

    # Try to find the element via MCP
    case ScenicMcp.Probes.find_clickable_elements() do
      {:ok, %{elements: elements}} ->
        matching = Enum.find(elements, fn elem ->
          elem_id_str = elem.id |> to_string()
          target_id_str = component_id |> to_string()
          elem_id_str == target_id_str or elem_id_str =~ target_id_str
        end)

        if matching do
          {:ok, component_id}
        else
          {:error, "Component button '#{component_name}' not found in clickable elements"}
        end

      {:error, reason} ->
        {:error, "Failed to query clickable elements: #{inspect(reason)}"}
    end
  end

  @doc """
  Get a list of all currently clickable elements in the viewport.

  Returns `{:ok, elements}` where elements is a list of element maps with
  `:id`, `:center`, `:bounds`, etc.

  ## Example

      iex> ComponentTestHarness.list_clickable_elements()
      {:ok, [
        %{id: ":load_component_button", center: %{x: 100, y: 50}, ...},
        %{id: ":component_menu_bar", center: %{x: 200, y: 150}, ...}
      ]}
  """
  @spec list_clickable_elements() :: {:ok, list(map())} | {:error, String.t()}
  def list_clickable_elements do
    case ScenicMcp.Probes.find_clickable_elements() do
      {:ok, %{elements: elements}} -> {:ok, elements}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reset the Widget Workbench to clean state.

  Clicks the "Reset Scene" button to unload any loaded components.

  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  @spec reset_workbench() :: :ok | {:error, String.t()}
  def reset_workbench do
    case ScenicMcp.Probes.click_element(:reset_scene_button) do
      {:ok, _} ->
        Process.sleep(@default_wait_ms)
        :ok

      {:error, reason} ->
        {:error, "Failed to reset workbench: #{inspect(reason)}"}
    end
  end

  @doc """
  Wait for a specific amount of time for a component to render.

  Default wait time is 500ms.
  """
  @spec wait_for_render(non_neg_integer()) :: :ok
  def wait_for_render(ms \\ @default_wait_ms) do
    Process.sleep(ms)
    :ok
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  # Open the component selection modal by clicking the button
  defp open_component_modal do
    case ScenicMcp.Probes.click_element(:load_component_button) do
      {:ok, _} ->
        Process.sleep(@modal_wait_ms)
        :ok

      {:error, reason} ->
        {:error, "Failed to open component modal: #{inspect(reason)}"}
    end
  end

  # Click a specific component button in the modal
  defp click_component_button(component_name) do
    component_id = build_component_id(component_name)

    case ScenicMcp.Probes.click_element(component_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Failed to click component button: #{inspect(reason)}"}
    end
  end

  # Wait for component to load
  defp wait_for_load(ms) do
    Process.sleep(ms)
    :ok
  end

  # Optionally take a screenshot
  defp maybe_take_screenshot(false, _name), do: {:ok, nil}

  defp maybe_take_screenshot(true, name) do
    case ScenicMcp.Probes.take_screenshot(name) do
      {:ok, path} -> {:ok, path}
      {:error, reason} -> {:error, "Screenshot failed: #{inspect(reason)}"}
    end
  end

  # Build semantic ID for component button
  # Format: component_#{Macro.underscore(name)}
  defp build_component_id(component_name) do
    name_str = to_string(component_name)
    underscored = Macro.underscore(name_str)
    "component_#{underscored}" |> String.to_atom()
  end
end
