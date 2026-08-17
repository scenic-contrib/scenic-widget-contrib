defmodule ScenicWidgets.MenuBar.MenuInteractionSpex do
  @moduledoc """
  MenuBar Interaction Specification

  ## Purpose
  Verifies the core open/close/switch behavior of top-level menu dropdowns:
  1. Clicking a header opens its dropdown
  2. Clicking the same header again closes it (toggle)
  3. Clicking a different header switches the open dropdown
  4. Hovering a different header while one is open switches the dropdown too

  Action-triggering and keyboard shortcuts are covered separately in
  `04_menu_actions_spex.exs`. Deep/nested sub-menu navigation is covered in
  `03_submenu_navigation_spex.exs`.
  """

  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  # Header centers for a 4-header, 150px-wide (default theme), 40px-tall menu bar
  # pinned at {0, 0}: File, Edit, View, Help.
  @file_header {75, 20}
  @edit_header {225, 20}

  defp menu_map do
    [
      {:sub_menu, "File",
       [
         {"new_file", "New File"},
         {"open_file", "Open File"},
         {"save_file", "Save"},
         {"quit", "Quit"}
       ]},
      {:sub_menu, "Edit", [{"undo", "Undo"}, {"redo", "Redo"}, {"cut", "Cut"}]},
      {:sub_menu, "View", [{"fullscreen", "Toggle Fullscreen"}]},
      {:sub_menu, "Help", [{"about", "About"}]}
    ]
  end

  defp load_menu_bar do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {600, 40})
    data = %{frame: frame, menu_map: menu_map()}

    WidgetWorkbench.Scene.load_component("Menu Bar", ScenicWidgets.MenuBar, data)
    Process.sleep(400)
  end

  spex "MenuBar dropdown open/close/switch behavior",
    description: "Verifies clicking and hovering headers opens, closes and switches dropdowns",
    tags: [:menu_bar, :interaction] do
    scenario "Clicking a header opens its dropdown", context do
      given_ "MenuBar is loaded", context do
        load_menu_bar()
        {:ok, context}
      end

      when_ "we click the File header", context do
        Probes.click_element("menu_file")
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the File dropdown items are visible" do
        assert Query.text_visible?("New File")
        assert Query.text_visible?("Open File")
        assert Query.text_visible?("Quit")

        :ok
      end
    end

    scenario "Clicking the open header again closes its dropdown", context do
      given_ "the File dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        assert Query.text_visible?("New File")
        {:ok, context}
      end

      when_ "we click the File header again", context do
        Probes.click_element("menu_file")
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the File dropdown is closed" do
        refute Query.text_visible?("New File"),
               "File dropdown should close when its header is clicked again"

        :ok
      end
    end

    scenario "Clicking a different header switches the open dropdown", context do
      given_ "the File dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        assert Query.text_visible?("New File")
        {:ok, context}
      end

      when_ "we click the Edit header", context do
        Probes.click_element("menu_edit")
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the Edit dropdown replaces the File dropdown" do
        assert Query.text_visible?("Undo")
        assert Query.text_visible?("Redo")
        refute Query.text_visible?("New File"), "File dropdown should have closed"

        :ok
      end
    end

    scenario "Hovering a different header while one is open switches the dropdown", context do
      given_ "the File dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        assert Query.text_visible?("New File")
        {:ok, context}
      end

      when_ "we hover over the Edit header without clicking", context do
        {edit_x, edit_y} = @edit_header
        Probes.send_mouse_move(edit_x, edit_y)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the Edit dropdown is shown instead of File's" do
        assert Query.text_visible?("Cut")
        refute Query.text_visible?("New File"), "File dropdown should have closed on hover-switch"

        :ok
      end
    end

    scenario "Hovering back over the original header restores it", context do
      given_ "we switched from File to Edit via hover", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        {edit_x, edit_y} = @edit_header
        Probes.send_mouse_move(edit_x, edit_y)
        Process.sleep(300)
        assert Query.text_visible?("Cut")
        {:ok, context}
      end

      when_ "we hover back over the File header", context do
        {file_x, file_y} = @file_header
        Probes.send_mouse_move(file_x, file_y)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the File dropdown is shown again" do
        assert Query.text_visible?("New File")
        refute Query.text_visible?("Cut"), "Edit dropdown should have closed"

        :ok
      end
    end
  end
end
