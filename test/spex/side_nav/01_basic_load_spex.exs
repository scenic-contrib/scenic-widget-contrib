defmodule ScenicWidgets.SideNav.BasicLoadSpex do
  @moduledoc """
  Basic SideNav Loading Specification

  ## Purpose
  Foundational spex for the SideNav component. Verifies that it can be
  mounted in Widget Workbench with a real (deeply-nested) tree and renders
  its top-level items, while leaving nested items collapsed until a user
  expands them.

  ## Why This Spex Exists
  This establishes the baseline - if this fails, expand/collapse and
  keyboard navigation cannot be trusted either.

  ## Test Approach
  Loads SideNav directly via `WidgetWorkbench.Scene.load_component/3` (the
  same call the workbench itself makes when a user picks "Side Nav" from
  the component list), using `ScenicWidgets.SideNav.Item.deep_test_tree/0`
  - the same tree the workbench loads for SideNav - then inspects what's
  actually rendered via `ScenicMcp.Query`.
  """

  use SexySpex

  alias ScenicMcp.Query

  @frame_pin {50, 50}
  @frame_size {280, 600}

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  # Loads a fresh SideNav with the deep test tree (the same tree the
  # workbench itself uses when SideNav is picked from the component list).
  defp load_side_nav do
    frame = Widgex.Frame.new(pin: @frame_pin, size: @frame_size)
    tree = ScenicWidgets.SideNav.Item.deep_test_tree()
    data = %{frame: frame, tree: tree, active_id: nil}

    WidgetWorkbench.Scene.load_component("Side Nav", ScenicWidgets.SideNav, data)
    Process.sleep(500)
    :ok
  end

  spex "SideNav Basic Loading",
    description: "Verifies SideNav loads and displays its top-level tree",
    tags: [:side_nav, :basic] do
    scenario "SideNav loads and displays its top-level tree items", context do
      given_ "SideNav is loaded with the deep test tree", context do
        load_side_nav()
        {:ok, context}
      end

      then_ "the top-level groups and page are visible" do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Documentation"),
               "Expected top-level group 'Documentation' to be visible"
        assert String.contains?(rendered, "Examples"),
               "Expected top-level group 'Examples' to be visible"
        assert String.contains?(rendered, "Changelog"),
               "Expected top-level page 'Changelog' to be visible"

        :ok
      end
    end

    scenario "SideNav keeps nested items collapsed until expanded", context do
      given_ "SideNav is freshly loaded", context do
        load_side_nav()
        {:ok, context}
      end

      then_ "second and third level items are not rendered yet" do
        rendered = Query.rendered_text()

        refute String.contains?(rendered, "Guides"),
               "Second-level 'Guides' should stay hidden until 'Documentation' is expanded"
        refute String.contains?(rendered, "API Reference"),
               "Second-level 'API Reference' should stay hidden until 'Documentation' is expanded"
        refute String.contains?(rendered, "Getting Started"),
               "Third-level 'Getting Started' should stay hidden until its ancestors are expanded"
        refute String.contains?(rendered, "Installation"),
               "Fourth-level 'Installation' should stay hidden until its ancestors are expanded"

        :ok
      end
    end

    scenario "SideNav is ready to receive chevron clicks by semantic id", context do
      given_ "SideNav is loaded", context do
        load_side_nav()
        {:ok, context}
      end

      then_ "clicking the root group's chevron does not error" do
        assert :ok = ScenicMcp.Probes.click_element("chevron_level1_docs")
        Process.sleep(200)

        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Guides"),
               "Clicking the root chevron should expand it, revealing 'Guides'"

        :ok
      end
    end
  end
end
