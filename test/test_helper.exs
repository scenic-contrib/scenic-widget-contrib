# Test helper configuration for scenic-widget-contrib
ExUnit.start()

# Ensure the spex framework is available
Code.ensure_loaded(SexySpex)
Code.ensure_loaded(ScenicMcp.Probes)

# Ensure WidgetWorkbench modules are compiled
Code.ensure_compiled(WidgetWorkbench)
Code.ensure_compiled(WidgetWorkbench.Scene)

# Load test helpers
Code.require_file("helpers/script_inspector.ex", __DIR__)
Code.require_file("helpers/semantic_ui.ex", __DIR__)

# Configure test environment
Application.put_env(:scenic_widget_contrib, :test_mode, true)

# Helper functions for spex tests
defmodule ScenicWidgets.TestHelpers do
  @moduledoc """
  Common test helpers for Widget Workbench spex tests.
  """

  @doc """
  Starts the Widget Workbench application for testing.
  """
  def start_widget_workbench() do
    # Start the workbench with test configuration
    {:ok, _pid} = WidgetWorkbench.start(size: {1200, 800}, title: "Widget Workbench - Testing")
    
    # Wait for startup
    Process.sleep(1000)
    
    # Verify it's running
    WidgetWorkbench.running?()
  end

  @doc """
  Stops the Widget Workbench application.
  """
  def stop_widget_workbench() do
    WidgetWorkbench.stop()
    Process.sleep(500)
  end

  @doc """
  Resets the Widget Workbench to clean state.
  """
  def reset_widget_workbench() do
    WidgetWorkbench.reset()
    Process.sleep(500)
  end

  @doc """
  Clicks the Load Component button in the workbench.
  """
  def click_load_component_button() do
    {screen_width, screen_height} = ScenicMcp.Probes.viewport_state().size
    button_x = screen_width * 0.75  # Right pane center
    button_y = screen_height * 0.6   # Approximate button position
    
    ScenicMcp.Probes.send_mouse_click(button_x, button_y)
  end

  @doc """
  Selects a component from the modal by name.
  """
  def select_component_from_modal(component_name) do
    {screen_width, screen_height} = ScenicMcp.Probes.viewport_state().size
    modal_center_x = screen_width / 2
    
    # Calculate approximate button position based on component name
    button_y = case component_name do
      "Menu Bar" -> screen_height / 2 + 50
      "Icon Button" -> screen_height / 2 + 100
      _ -> screen_height / 2 + 50
    end
    
    ScenicMcp.Probes.send_mouse_click(modal_center_x, button_y)
  end

  @doc """
  Clicks the Reset Scene button.
  """
  def click_reset_scene_button() do
    {screen_width, _screen_height} = ScenicMcp.Probes.viewport_state().size
    reset_button_x = screen_width * 0.75  # Right pane center
    reset_button_y = 200  # Approximate position of Reset button
    
    ScenicMcp.Probes.send_mouse_click(reset_button_x, reset_button_y)
  end
end