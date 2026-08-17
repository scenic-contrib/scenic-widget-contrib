defmodule ScenicWidgets.MenuBar.SubmenuNavigationSpex do
  @moduledoc """
  MenuBar Nested Sub-Menu Navigation Specification

  ## Purpose
  Verifies navigation through nested (`:sub_menu`) menu structures several
  levels deep, e.g. File > Recent Files > By Project, and the sibling-switch
  cleanup behavior at a nested level, e.g. View > Appearance vs. View > Layout.

  ## Why sub-menu items need coordinates instead of semantic IDs
  `ScenicWidgets.MenuBar` only registers MCP semantic IDs (`menu_<header>` /
  `menu_<header>_<item_id>`) for the direct children of each top-level header
  (see `register_semantic_elements/2` in `menu_bar.ex`). Items nested inside a
  `:sub_menu` are not (yet) recursively registered, so hovering into them has
  to be done with `ScenicMcp.Probes.send_mouse_move/2` at their known pixel
  position instead of `click_element/1`.

  The coordinates below are derived directly from the positioning formulas in
  `ScenicWidgets.MenuBar.OptimizedRenderizer` for the default theme
  (item_width: 150, menu_height: 40, sub_menu_width: 150, item_height: 30,
  padding: 5) and the exact `menu_map/0` defined in this file, so they are not
  guesses - they're computed to land on the items being tested.
  """

  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  # File dropdown item centers (header "File" is index 0, dropdown opens at {0, 40})
  @recent_files_item {75, 120}
  @by_project_item {220, 155}
  @save_item {75, 150}

  # View dropdown item centers (header "View" is index 1, dropdown opens at {150, 40})
  @appearance_item {225, 60}
  @layout_item {225, 90}

  defp menu_map do
    [
      {:sub_menu, "File",
       [
         {"new_file", "New File"},
         {"open_file", "Open File"},
         {:sub_menu, "Recent Files",
          [
            {"recent_1", "Document 1.txt"},
            {:sub_menu, "By Project", [{"proj_a", "Project A"}, {"proj_b", "Project B"}]}
          ]},
         {"save_file", "Save"},
         {"quit", "Quit"}
       ]},
      {:sub_menu, "View",
       [
         {:sub_menu, "Appearance",
          [{"theme_light", "Light Theme"}, {"theme_dark", "Dark Theme"}]},
         {:sub_menu, "Layout",
          [{"layout_single", "Single Pane"}, {"layout_split", "Split Horizontal"}]},
         {"fullscreen", "Toggle Fullscreen"}
       ]}
    ]
  end

  defp load_menu_bar do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {300, 40})
    data = %{frame: frame, menu_map: menu_map()}

    WidgetWorkbench.Scene.load_component("Menu Bar", ScenicWidgets.MenuBar, data)
    Process.sleep(400)
  end

  defp hover(x, y) do
    Probes.send_mouse_move(x, y)
    Process.sleep(300)
  end

  spex "MenuBar nested sub-menu navigation",
    description: "Verifies deep nesting and sibling sub-menu cleanup",
    tags: [:menu_bar, :submenu, :nesting] do
    scenario "Hovering a nested item opens its sub-menu", context do
      given_ "the File dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        assert Query.text_visible?("New File")
        {:ok, context}
      end

      when_ "we hover over Recent Files", context do
        {x, y} = @recent_files_item
        hover(x, y)
        {:ok, context}
      end

      then_ "the Recent Files sub-menu appears" do
        assert Query.text_visible?("Document 1.txt")
        assert Query.text_visible?("By Project")

        :ok
      end
    end

    scenario "Hovering deeper opens the next nested level", context do
      given_ "File > Recent Files is open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        {x, y} = @recent_files_item
        hover(x, y)
        assert Query.text_visible?("By Project")
        {:ok, context}
      end

      when_ "we hover over By Project", context do
        {x, y} = @by_project_item
        hover(x, y)
        {:ok, context}
      end

      then_ "the By Project sub-menu (3 levels deep) appears" do
        assert Query.text_visible?("Project A")
        assert Query.text_visible?("Project B")

        :ok
      end
    end

    scenario "Switching to a shallower sibling closes the deeper nested chain", context do
      given_ "File > Recent Files > By Project is fully open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        {rx, ry} = @recent_files_item
        hover(rx, ry)
        {bx, by} = @by_project_item
        hover(bx, by)
        assert Query.text_visible?("Project A")
        {:ok, context}
      end

      when_ "we hover over Save, a sibling item with no sub-menu", context do
        {x, y} = @save_item
        hover(x, y)
        {:ok, context}
      end

      then_ "both nested sub-menus close" do
        refute Query.text_visible?("Project A"), "By Project sub-menu should have closed"
        refute Query.text_visible?("Document 1.txt"), "Recent Files sub-menu should have closed"

        :ok
      end
    end

    scenario "Switching between sibling sub-menus closes the previous one", context do
      given_ "the View dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_view")
        Process.sleep(200)
        assert Query.text_visible?("Toggle Fullscreen")
        {:ok, context}
      end

      when_ "we hover over Appearance", context do
        {x, y} = @appearance_item
        hover(x, y)
        {:ok, context}
      end

      then_ "the Appearance sub-menu is visible" do
        assert Query.text_visible?("Light Theme")
        assert Query.text_visible?("Dark Theme")

        :ok
      end

      when_ "we then hover over Layout, a sibling sub-menu", context do
        {x, y} = @layout_item
        hover(x, y)
        {:ok, context}
      end

      then_ "the Appearance sub-menu closes and Layout's opens" do
        refute Query.text_visible?("Light Theme"),
               "Appearance sub-menu should close when switching to its sibling Layout"

        refute Query.text_visible?("Dark Theme")
        assert Query.text_visible?("Single Pane")
        assert Query.text_visible?("Split Horizontal")

        :ok
      end
    end
  end
end
