defmodule ScenicWidgets.SideNav.KeyboardNavSpex do
  @moduledoc """
  SideNav Keyboard Navigation Specification

  ## Purpose
  Verifies keyboard navigation as implemented in
  `ScenicWidgets.SideNav.Reducer`:
  - Down/Up move focus between currently *visible* items only.
  - Right expands a focused, collapsed group; on a focused group that's
    already expanded, it moves focus into the first child instead.
  - Left collapses a focused, expanded group; otherwise it moves focus up
    to the parent.
  - Home/End jump focus to the first/last visible item.
  - Escape clears keyboard focus entirely.

  ## Observability note
  SideNav has no on-screen "you are here" text - focus is shown only via a
  focus ring (a stroke, not a text primitive) which `ScenicMcp.Query` can't
  see. Every scenario below instead proves focus moved to the right item by
  immediately following up with Right/Left, whose *expand/collapse* effect
  *is* visible as text appearing or disappearing. If focus had landed
  somewhere else, the expected text would not (dis)appear.

  ## Focus gating
  SideNav ignores all `{:key, ...}` input until its component-level
  `focused` flag is true (see `handle_input({:key, _}, ...)` guard in
  `side_nav.ex`). That flag is set by any chevron/row click, independently
  of which item ends up expanded - so `load_and_focus/0` below clicks the
  root chevron twice (expand, then collapse back) purely to grant keyboard
  focus while leaving the tree in its default fully-collapsed state.
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

  defp key(name) do
    assert :ok = Probes.send_keys(name, [])
    Process.sleep(150)
    :ok
  end

  # Loads a fresh, fully-collapsed SideNav that already has keyboard focus.
  defp load_and_focus do
    load_side_nav()
    click("chevron_level1_docs")
    click("chevron_level1_docs")
    refute Query.text_visible?("Guides"), "tree should be back to fully collapsed"
    :ok
  end

  spex "SideNav Keyboard Navigation",
    description: "Verifies arrow/Home/End/Escape keyboard navigation",
    tags: [:side_nav, :keyboard] do
    scenario "Down arrow moves focus through top-level siblings", context do
      given_ "a focused, fully-collapsed SideNav", context do
        load_and_focus()
        {:ok, context}
      end

      when_ "we press Down twice, then Right", context do
        key("down")
        key("down")
        key("right")
        {:ok, context}
      end

      then_ "the second top-level item ('Examples') expands, not the first" do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Basic Examples"),
               "Two Down presses should focus 'Examples' (the second item), which Right then expands"
        assert String.contains?(rendered, "Advanced Examples")

        refute String.contains?(rendered, "Guides"),
               "'Documentation' (the first item) should not have been expanded"
        refute String.contains?(rendered, "API Reference")

        :ok
      end
    end

    scenario "Right arrow expands a focused group, then moves into it on the next press", context do
      given_ "a focused, fully-collapsed SideNav", context do
        load_and_focus()
        {:ok, context}
      end

      when_ "we press Down, then Right three times", context do
        key("down")
        key("right")
        key("right")
        key("right")
        {:ok, context}
      end

      then_ "focus travelled Documentation -> Guides, expanding Guides" do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Getting Started"),
               "Down focuses 'Documentation'; first Right expands it; second Right moves focus " <>
                 "to its first child 'Guides'; third Right expands 'Guides'"
        assert String.contains?(rendered, "Advanced Topics")

        :ok
      end
    end

    scenario "Left arrow collapses a focused group, then walks focus up to collapse its parent", context do
      given_ "focus has travelled down into the expanded 'Guides' group", context do
        load_and_focus()
        key("down")
        key("right")
        key("right")
        key("right")
        assert Query.text_visible?("Getting Started")
        {:ok, context}
      end

      when_ "we press Left once", context do
        key("left")
        {:ok, context}
      end

      then_ "'Guides' collapses but 'Documentation' stays expanded", context do
        rendered = Query.rendered_text()

        refute String.contains?(rendered, "Getting Started"),
               "Left should collapse the focused, expanded 'Guides' group"
        assert String.contains?(rendered, "API Reference"),
               "'Documentation' should remain expanded - only 'Guides' collapsed"

        {:ok, context}
      end

      and_ "pressing Left again moves focus up to 'Documentation' and collapses it too", context do
        key("left")
        key("left")

        rendered = Query.rendered_text()

        refute String.contains?(rendered, "API Reference"),
               "Second Left moves focus from collapsed 'Guides' to parent 'Documentation'; " <>
                 "third Left collapses focused, expanded 'Documentation'"
        assert String.contains?(rendered, "Documentation"),
               "'Documentation' itself should remain visible while collapsed"

        :ok
      end
    end

    scenario "Home key returns focus to the first item after navigating away", context do
      given_ "focus has moved to the second top-level item", context do
        load_and_focus()
        key("down")
        key("down")
        {:ok, context}
      end

      when_ "we press Home, then Right", context do
        key("home")
        key("right")
        {:ok, context}
      end

      then_ "the first item ('Documentation') expands" do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Guides"),
               "Home should have moved focus back to 'Documentation', which Right then expanded"
        assert String.contains?(rendered, "API Reference")

        :ok
      end
    end

    scenario "End key moves focus to the last visible item", context do
      given_ "a focused, fully-collapsed SideNav", context do
        load_and_focus()
        {:ok, context}
      end

      when_ "we press End, then Up, then Right", context do
        key("end")
        key("up")
        key("right")
        {:ok, context}
      end

      then_ "focus lands on 'Examples' (one above the last item), which Right then expands" do
        rendered = Query.rendered_text()

        assert String.contains?(rendered, "Basic Examples"),
               "End focuses the last item ('Changelog'); Up moves back to 'Examples'; Right expands it"
        assert String.contains?(rendered, "Advanced Examples")

        :ok
      end
    end

    scenario "Escape clears keyboard focus, so a subsequent Right arrow is a no-op", context do
      given_ "focus is on the first top-level item", context do
        load_and_focus()
        key("down")
        {:ok, context}
      end

      when_ "we press Escape, then Right", context do
        key("escape")
        key("right")
        {:ok, context}
      end

      then_ "nothing expands, proving Escape cleared the focused item" do
        rendered = Query.rendered_text()

        refute String.contains?(rendered, "Guides"),
               "Right should have no target after Escape cleared keyboard focus"
        refute String.contains?(rendered, "API Reference")

        :ok
      end
    end
  end
end
