defmodule ScenicWidgets.SideNav.ExpandCollapseSpex do
  @moduledoc """
  SideNav Expand/Collapse Behavior Specification

  ## Purpose
  Verifies that SideNav's tree correctly expands and collapses:
  1. Clicking a group's chevron toggles its expansion.
  2. Clicking a group's row text toggles expansion too (per
     `ScenicWidgets.SideNav.handle_row_click/5`, a :group row toggles
     expansion instead of navigating - the whole row, not just the
     chevron, is the toggle target).
  3. Expansion nests correctly (parent -> child -> grandchild).
  4. Collapsing a parent hides its entire expanded subtree, even though
     the nested child's own expansion flag is left untouched.

  Every assertion here is driven by `ScenicWidgets.SideNav.Item.deep_test_tree/0`,
  the same tree Widget Workbench loads for SideNav, so item ids/titles
  match `lib/components/side_nav/item.ex` exactly.
  """

  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

  @frame_pin {50, 50}
  @frame_size {280, 600}

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  defp load_side_nav do
    frame = Widgex.Frame.new(pin: @frame_pin, size: @frame_size)
    tree = ScenicWidgets.SideNav.Item.deep_test_tree()
    data = %{frame: frame, tree: tree, active_id: nil}

    WidgetWorkbench.Scene.load_component("Side Nav", ScenicWidgets.SideNav, data)
    Process.sleep(500)
    :ok
  end

  defp click(element_id) do
    assert :ok = Probes.click_element(element_id)
    Process.sleep(200)
    :ok
  end

  spex "SideNav Expand/Collapse Behavior",
    description: "Verifies chevron/text clicks expand and collapse tree nodes correctly",
    tags: [:side_nav, :expand_collapse] do
    scenario "Clicking a chevron expands a collapsed group", context do
      given_ "SideNav is loaded with 'Documentation' collapsed", context do
        load_side_nav()
        refute Query.text_visible?("Guides"), "'Documentation' should start collapsed"
        {:ok, context}
      end

      when_ "we click the 'Documentation' chevron", context do
        click("chevron_level1_docs")
        {:ok, context}
      end

      then_ "its children become visible" do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Guides"),
               "Expected 'Guides' to appear after expanding 'Documentation'"
        assert String.contains?(rendered, "API Reference"),
               "Expected 'API Reference' to appear after expanding 'Documentation'"

        :ok
      end
    end

    scenario "Clicking the same chevron again collapses the group", context do
      given_ "'Documentation' is expanded", context do
        load_side_nav()
        click("chevron_level1_docs")
        assert Query.text_visible?("Guides"), "'Documentation' should be expanded by now"
        {:ok, context}
      end

      when_ "we click the 'Documentation' chevron again", context do
        click("chevron_level1_docs")
        {:ok, context}
      end

      then_ "its children are hidden again" do
        rendered = Query.rendered_text()

        refute String.contains?(rendered, "Guides"),
               "Expected 'Guides' to disappear after collapsing 'Documentation'"
        refute String.contains?(rendered, "API Reference"),
               "Expected 'API Reference' to disappear after collapsing 'Documentation'"

        assert String.contains?(rendered, "Documentation"),
               "'Documentation' itself should remain visible while collapsed"

        :ok
      end
    end

    scenario "Clicking a group row's text toggles expansion, same as its chevron", context do
      given_ "SideNav is loaded with 'Examples' collapsed", context do
        load_side_nav()
        refute Query.text_visible?("Basic Examples"), "'Examples' should start collapsed"
        {:ok, context}
      end

      when_ "we click the 'Examples' row text (not the chevron)", context do
        click("item_text_level1_examples")
        {:ok, context}
      end

      then_ "'Examples' expands to show its children" do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Basic Examples"),
               "Clicking a group's row text should toggle expansion just like its chevron"
        assert String.contains?(rendered, "Advanced Examples"),
               "Clicking a group's row text should toggle expansion just like its chevron"

        :ok
      end
    end

    scenario "Expansion nests correctly across three levels", context do
      given_ "'Documentation' is expanded", context do
        load_side_nav()
        click("chevron_level1_docs")
        assert Query.text_visible?("Guides")
        {:ok, context}
      end

      when_ "we expand the nested 'Guides' group", context do
        click("chevron_level2_guides")
        {:ok, context}
      end

      then_ "its grandchildren become visible" do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Getting Started"),
               "Expected third-level 'Getting Started' to appear under expanded 'Guides'"
        assert String.contains?(rendered, "Advanced Topics"),
               "Expected third-level 'Advanced Topics' to appear under expanded 'Guides'"

        :ok
      end
    end

    scenario "Collapsing a parent hides its entire expanded subtree", context do
      given_ "'Documentation' and its nested 'Guides' are both expanded", context do
        load_side_nav()
        click("chevron_level1_docs")
        click("chevron_level2_guides")
        assert Query.text_visible?("Getting Started"), "Nested tree should be fully expanded"
        {:ok, context}
      end

      when_ "we collapse the top-level 'Documentation' node", context do
        click("chevron_level1_docs")
        {:ok, context}
      end

      then_ "the whole subtree, including the nested grandchildren, disappears" do
        rendered = Query.rendered_text()

        refute String.contains?(rendered, "Guides"),
               "Direct child 'Guides' should be hidden when its parent collapses"
        refute String.contains?(rendered, "Getting Started"),
               "Grandchild 'Getting Started' should also be hidden, even though 'Guides' was never itself collapsed"

        assert String.contains?(rendered, "Documentation"),
               "'Documentation' itself should remain visible while collapsed"

        :ok
      end
    end
  end
end
