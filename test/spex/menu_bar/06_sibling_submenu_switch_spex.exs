defmodule ScenicWidgets.MenuBar.SiblingSubmenuSwitchSpex do
  @moduledoc """
  Comprehensive spex to test and verify the sibling sub-menu switching bug fix.

  Bug: When hovering from "Appearance" to "Layout" in the View menu, the Appearance
  sub-menu stays visible instead of being replaced by the Layout sub-menu.

  Expected: Switching between sibling sub-menus should hide the old one and show the new one.
  """

  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}

  setup_all do
    # Get environment-specific names
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)

    # Kill any existing viewport
    if viewport_pid = Process.whereis(viewport_name) do
      Process.exit(viewport_pid, :kill)
      Process.sleep(100)
    end

    # Start application
    Application.ensure_all_started(:scenic_widget_contrib)

    # Configure viewport
    viewport_config = [
      name: viewport_name,
      size: {1200, 800},
      theme: :dark,
      default_scene: {WidgetWorkbench.Scene, []},
      drivers: [[
        module: Scenic.Driver.Local,
        name: driver_name,
        window: [resizeable: true, title: "Sibling Submenu Switch Test"],
        on_close: :stop_viewport,
        debug: false,
        cursor: true,
        antialias: true,
        layer: 0,
        opacity: 255,
        position: [
          scaled: false,
          centered: false,
          orientation: :normal
        ]
      ]]
    ]

    # Start viewport
    {:ok, viewport_pid} = Scenic.ViewPort.start_link(viewport_config)
    Process.sleep(1500)

    # Cleanup on exit
    on_exit(fn ->
      if pid = Process.whereis(viewport_name) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)

    {:ok, %{viewport_pid: viewport_pid}}
  end

  spex "Switching between sibling sub-menus closes the previous one",
    description: "Verifies that hovering from Appearance to Layout properly switches sub-menus",
    tags: [:menubar, :submenu, :bug_fix] do

    scenario "Load MenuBar and test sibling submenu switching", context do
      given_ "Widget Workbench with MenuBar is running", context do
        case SemanticUI.verify_widget_workbench_loaded() do
          {:ok, state} ->
            # Load Menu Bar component
            case SemanticUI.load_component("Menu Bar") do
              {:ok, result} ->
                Process.sleep(1000)
                {:ok, Map.merge(context, %{workbench: state, menubar: result})}
              {:error, reason} ->
                {:error, "Failed to load MenuBar: #{reason}"}
            end
          {:error, reason} ->
            {:error, reason}
        end
      end

      when_ "I open the View menu", context do
        # Click on View menu button
        case ScenicMcp.Tools.handle_mouse_click(%{"x" => 438, "y" => 117}) do
          {:ok, _} ->
            Process.sleep(500)
            rendered = ScriptInspector.get_rendered_text_string()

            if String.contains?(rendered, "Appearance") && String.contains?(rendered, "Layout") do
              {:ok, Map.put(context, :view_menu_open, true)}
            else
              {:error, "View menu did not open - items not visible: #{rendered}"}
            end
          {:error, reason} ->
            {:error, "Failed to click View menu: #{reason}"}
        end
      end

      and_ "I hover over Appearance to open its sub-menu", context do
        # Hover over Appearance item
        case ScenicMcp.Tools.handle_mouse_move(%{"x" => 486, "y" => 156}) do
          {:ok, _} ->
            Process.sleep(500)
            rendered = ScriptInspector.get_rendered_text_string()

            if String.contains?(rendered, "Light Theme") &&
               String.contains?(rendered, "Dark Theme") &&
               String.contains?(rendered, "Auto") do
              {:ok, Map.put(context, :appearance_submenu_open, true)}
            else
              {:error, "Appearance sub-menu did not open - theme options not visible"}
            end
          {:error, reason} ->
            {:error, "Failed to hover over Appearance: #{reason}"}
        end
      end

      when_ "I then hover over Layout (a sibling sub-menu)", context do
        # Hover over Layout item
        case ScenicMcp.Tools.handle_mouse_move(%{"x" => 457, "y" => 187}) do
          {:ok, _} ->
            Process.sleep(500)
            {:ok, Map.put(context, :hovered_layout, true)}
          {:error, reason} ->
            {:error, "Failed to hover over Layout: #{reason}"}
        end
      end

      then_ "the Appearance sub-menu should be hidden", context do
        rendered = ScriptInspector.get_rendered_text_string()

        # Check that Appearance items are NOT visible
        appearance_visible = String.contains?(rendered, "Light Theme") ||
                            String.contains?(rendered, "Dark Theme") ||
                            String.contains?(rendered, "Auto")

        if appearance_visible do
          IO.puts("\n❌ BUG REPRODUCED: Appearance sub-menu is still visible!")
          IO.puts("Rendered text: #{rendered}")
          {:error, "BUG: Appearance sub-menu did not close when switching to Layout"}
        else
          IO.puts("\n✅ SUCCESS: Appearance sub-menu properly closed")
          :ok
        end
      end

      and_ "the Layout sub-menu should be visible", context do
        rendered = ScriptInspector.get_rendered_text_string()

        # Check that Layout items ARE visible
        layout_visible = String.contains?(rendered, "Single Pane") &&
                        String.contains?(rendered, "Split Horizontal") &&
                        String.contains?(rendered, "Split Vertical")

        if layout_visible do
          IO.puts("✅ Layout sub-menu is properly displayed")
          :ok
        else
          {:error, "Layout sub-menu did not open"}
        end
      end
    end
  end
end
