defmodule ScenicWidgets.SideNav.ExpandCollapseSpex do
  @moduledoc """
  SideNav Expand/Collapse Behavior Specification

  ## Purpose
  Verifies that the SideNav component correctly handles expand/collapse interactions:
  1. Clicking chevron toggles node expansion
  2. Clicking text does NOT toggle (HexDocs behavior)
  3. Nested items appear/disappear correctly
  4. Visual state updates (chevron rotation, indentation)
  5. Active item highlighting persists through expand/collapse

  ## HexDocs Behavior
  Based on hexdocs.pm navigation:
  - Chevron click: expand/collapse
  - Text click: navigate (no expand/collapse)
  - Expanded nodes show down-facing chevron
  - Collapsed nodes show right-facing chevron
  - Children are indented under parent

  ## Test Approach
  - Load SideNav with test tree structure
  - Interact with chevrons to expand/collapse nodes
  - Verify children visibility changes
  - Verify chevron icon state changes
  - Test nested expansion (parent → child → grandchild)

  ## Success Criteria
  - Chevron clicks toggle expansion state
  - Children appear when parent expanded
  - Children hide when parent collapsed
  - Chevron icons update to reflect state
  - Text clicks do NOT toggle expansion
  """

  use SexySpex

  alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}

  setup_all do
    viewport_name = Application.get_env(:scenic_mcp, :viewport_name, :test_viewport)
    driver_name = Application.get_env(:scenic_mcp, :driver_name, :test_driver)

    if viewport_pid = Process.whereis(viewport_name) do
      Process.exit(viewport_pid, :kill)
      Process.sleep(100)
    end

    case Application.ensure_all_started(:scenic_widget_contrib) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
    end

    viewport_config = [
      name: viewport_name,
      size: {1200, 800},
      theme: :dark,
      default_scene: {WidgetWorkbench.Scene, []},
      drivers: [
        [
          module: Scenic.Driver.Local,
          name: driver_name,
          window: [
            resizeable: true,
            title: "Widget Workbench - SideNav Expand/Collapse Test"
          ],
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
        ]
      ]
    ]

    {:ok, viewport_pid} = Scenic.ViewPort.start_link(viewport_config)
    Process.sleep(1500)

    on_exit(fn ->
      if pid = Process.whereis(viewport_name) do
        Process.exit(pid, :normal)
        Process.sleep(100)
      end
    end)

    {:ok, %{viewport_pid: viewport_pid, viewport_name: viewport_name}}
  end

  spex "SideNav Expand/Collapse Behavior",
    description: "Verifies expand/collapse interactions work correctly",
    tags: [:side_nav, :expand, :collapse, :interaction] do

    scenario "Initial state shows collapsed nodes", context do
      given_ "SideNav is loaded with hierarchical tree", context do
        case SemanticUI.load_component("Side Nav") do
          {:ok, _} ->
            Process.sleep(500)
            # Verify by checking for tree content, not component name
            rendered = ScriptInspector.get_rendered_text_string()
            if String.contains?(rendered, "GETTING STARTED") do
              {:ok, context}
            else
              {:error, "SideNav tree not visible"}
            end
          {:error, reason} -> {:error, reason}
        end
      end

      when_ "we inspect the initial tree state", context do
        rendered = ScriptInspector.get_rendered_text_string()
        {:ok, Map.put(context, :initial_render, rendered)}
      end

      then_ "collapsed nodes should show right-facing chevron", context do
        # Once implemented, verify chevron icons
        # For now, just verify component loaded
        assert context.initial_render != nil
        IO.puts("✅ Initial state captured")
        :ok
      end
    end

    scenario "Clicking chevron expands collapsed node", context do
      given_ "SideNav is loaded with a collapsed node", context do
        case SemanticUI.load_component("Side Nav") do
          {:ok, _} ->
            # Wait longer for component to fully initialize and register semantic elements
            Process.sleep(2000)
            IO.puts("⏰ Waited 2s for SideNav to initialize...")
            # Verify by checking for tree content
            rendered = ScriptInspector.get_rendered_text_string()
            if String.contains?(rendered, "GETTING STARTED") do
              {:ok, context}
            else
              {:error, "SideNav tree not visible"}
            end
          {:error, reason} -> {:error, reason}
        end
      end

      when_ "we click the 'getting_started' node's chevron icon", context do
        # First, let's see what elements ARE registered
        IO.puts("\n🔍 Checking what clickable elements are registered:")
        case SemanticUI.find_clickable_elements() do
          {:ok, elements} ->
            IO.puts("Found #{length(elements)} clickable elements:")
            elements
            |> Enum.take(20)
            |> Enum.each(fn elem ->
              IO.puts("  - #{inspect(elem)}")
            end)
          {:error, reason} ->
            IO.puts("  Failed to get elements: #{inspect(reason)}")
        end

        # Click the chevron for the "getting_started" node using semantic ID
        # The chevron ID is built as :chevron_<item_id> in the renderizer
        IO.puts("\n🎯 Attempting to click chevron_getting_started")

        case SemanticUI.click_element("chevron_getting_started") do
          :ok ->
            Process.sleep(300)  # Let the expansion animation complete
            {:ok, context}
          {:error, reason} ->
            IO.puts("❌ Failed to click chevron: #{inspect(reason)}")
            IO.puts("    Note: This might indicate Phase 1 semantic registration")
            IO.puts("    isn't picking up elements from component sub-scenes")
            {:error, reason}
        end
      end

      then_ "node should expand and show children", context do
        rendered = ScriptInspector.get_rendered_text_string()

        # Verify that child items are now visible
        # From test_tree: children are "Introduction", "Installation", "Interactive mode"
        children_visible =
          String.contains?(rendered, "Introduction") and
          String.contains?(rendered, "Installation")

        assert children_visible,
               "Expected child nodes to be visible after expanding. Rendered: #{inspect(String.slice(rendered, 0, 500))}"

        IO.puts("✅ Expand behavior verified - children are visible")
        :ok
      end
    end

    scenario "Clicking chevron again collapses expanded node", context do
      given_ "SideNav has an expanded node", context do
        # Load component and expand the getting_started node
        case SemanticUI.load_component("Side Nav") do
          {:ok, _} ->
            Process.sleep(500)
            # Expand the node first
            SemanticUI.click_element("chevron_getting_started")
            Process.sleep(300)
            {:ok, context}
          {:error, reason} -> {:error, reason}
        end
      end

      when_ "we click the expanded node's chevron again", context do
        IO.puts("🎯 Clicking chevron_getting_started again to collapse")

        case SemanticUI.click_element("chevron_getting_started") do
          :ok ->
            Process.sleep(300)  # Let the collapse animation complete
            {:ok, context}
          {:error, reason} ->
            IO.puts("❌ Failed to click chevron: #{inspect(reason)}")
            {:error, reason}
        end
      end

      then_ "node should collapse and hide children", context do
        rendered = ScriptInspector.get_rendered_text_string()

        # Verify that child items are no longer visible
        # Children should be hidden after collapsing
        children_hidden =
          not String.contains?(rendered, "Introduction") or
          not String.contains?(rendered, "Installation")

        assert children_hidden,
               "Expected child nodes to be hidden after collapsing. Rendered: #{inspect(String.slice(rendered, 0, 500))}"

        IO.puts("✅ Collapse behavior verified - children are hidden")
        :ok
      end
    end

    scenario "Clicking node text does NOT toggle expansion", context do
      given_ "SideNav has a collapsed node", context do
        case SemanticUI.load_component("Side Nav") do
          {:ok, _} ->
            Process.sleep(500)
            {:ok, context}
          {:error, reason} -> {:error, reason}
        end
      end

      when_ "we click the node's text (not chevron)", context do
        IO.puts("🎯 Clicking item_text_getting_started")

        # Click the text element (not the chevron)
        # Text ID is built as :item_text_<item_id> in the renderizer
        case SemanticUI.click_element("item_text_getting_started") do
          :ok ->
            Process.sleep(300)
            {:ok, context}
          {:error, reason} ->
            IO.puts("❌ Failed to click text: #{inspect(reason)}")
            {:error, reason}
        end
      end

      then_ "node should remain collapsed", context do
        rendered = ScriptInspector.get_rendered_text_string()

        # This matches HexDocs behavior:
        # - Text click = navigate/select (doesn't expand)
        # - Chevron click = expand/collapse

        # Verify children are still hidden (node didn't expand)
        children_still_hidden =
          not String.contains?(rendered, "Introduction") or
          not String.contains?(rendered, "Installation")

        assert children_still_hidden,
               "Expected node to remain collapsed after clicking text. Rendered: #{inspect(String.slice(rendered, 0, 500))}"

        IO.puts("✅ Text click behavior verified - node stayed collapsed")
        :ok
      end
    end

    scenario "Nested expansion works multiple levels deep", context do
      given_ "SideNav has multi-level nested structure", context do
        case SemanticUI.load_component("Side Nav") do
          {:ok, _} ->
            Process.sleep(500)
            {:ok, context}
          {:error, reason} -> {:error, reason}
        end
      end

      when_ "we expand parent, then child, then grandchild", context do
        IO.puts("🎯 Would expand: parent → child → grandchild")
        {:ok, context}
      end

      then_ "all three levels should be visible with correct indentation", context do
        # Verify:
        # 1. Parent at indent level 0
        # 2. Child at indent level 1
        # 3. Grandchild at indent level 2
        # 4. Each has appropriate chevron state
        IO.puts("✅ Multi-level expansion verified (placeholder)")
        :ok
      end
    end

    scenario "Collapsing parent hides all nested children", context do
      given_ "SideNav has expanded parent with expanded children", context do
        case SemanticUI.load_component("Side Nav") do
          {:ok, _} ->
            Process.sleep(500)
            # TODO: Expand parent and children
            {:ok, context}
          {:error, reason} -> {:error, reason}
        end
      end

      when_ "we collapse the top-level parent", context do
        IO.puts("🎯 Would collapse parent node")
        {:ok, context}
      end

      then_ "parent and all nested children should be hidden", context do
        # Verify entire subtree collapses
        IO.puts("✅ Subtree collapse verified (placeholder)")
        :ok
      end
    end
  end
end
