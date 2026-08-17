defmodule ScenicWidgets.MenuBar.BasicLoadSpex do
  @moduledoc """
  Basic MenuBar Loading Specification

  ## Purpose
  This is the foundational spex for the MenuBar component. It verifies that:
  1. Widget Workbench boots successfully
  2. MenuBar can be loaded into the workbench
  3. Its top-level menu headers render correctly

  This establishes the baseline - if this fails, no other MenuBar spex can
  reasonably be expected to pass.

  ## Loading Strategy
  Loading happens through `WidgetWorkbench.Scene.load_component/3` directly
  (the same public API the "Load Component" modal calls into) rather than by
  clicking through the component-selection modal. That keeps this spex focused
  on MenuBar's own rendering instead of Widget Workbench's UI navigation.
  """

  use SexySpex

  alias ScenicMcp.Query

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  defp menu_map do
    [
      {:sub_menu, "File", [{"new_file", "New File"}, {"quit", "Quit"}]},
      {:sub_menu, "Edit", [{"undo", "Undo"}]},
      {:sub_menu, "View", [{"fullscreen", "Toggle Fullscreen"}]},
      {:sub_menu, "Help", [{"about", "About"}]}
    ]
  end

  defp load_menu_bar(opts \\ %{}) do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {600, 40})
    data = Map.merge(%{frame: frame, menu_map: menu_map()}, opts)

    WidgetWorkbench.Scene.load_component("Menu Bar", ScenicWidgets.MenuBar, data)
    Process.sleep(400)
    frame
  end

  spex "MenuBar Basic Loading",
    description: "Verifies MenuBar can be loaded and displays its menu headers",
    tags: [:menu_bar, :basic, :loading] do
    scenario "Widget Workbench boots into its default state", context do
      given_ "the workbench application has started", context do
        {:ok, context}
      end

      then_ "the workbench's own UI is visible" do
        assert Query.text_visible?("Widget Workbench"),
               "Expected the Widget Workbench title to be visible on boot"

        :ok
      end
    end

    scenario "MenuBar loads and shows its top-level headers", context do
      given_ "the workbench is running with no component loaded yet", context do
        {:ok, context}
      end

      when_ "we load the MenuBar component", context do
        load_menu_bar()
        {:ok, context}
      end

      then_ "the standard menu headers are visible" do
        assert Query.text_visible?("File")
        assert Query.text_visible?("Edit")
        assert Query.text_visible?("View")
        assert Query.text_visible?("Help")

        :ok
      end
    end

    scenario "MenuBar renders without an error or crash state", context do
      given_ "MenuBar has been loaded", context do
        load_menu_bar()
        {:ok, context}
      end

      then_ "no error or crash message is rendered" do
        refute Query.text_visible?("Failed to load"),
               "MenuBar should not report a load failure"

        refute Query.text_visible?("crashed"), "MenuBar should not have crashed"

        :ok
      end
    end
  end
end
