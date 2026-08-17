defmodule ScenicWidgets.Workbench.BasicLaunchSpex do
  @moduledoc """
  Phase 1: Widget Workbench Launch & Basic UI

  Validates that the Widget Workbench boots correctly and displays its
  core UI: the constructor pane (title, Reset Scene / New Widget / Load
  Component buttons) and the main canvas.

  This is the foundational spex for the workbench - it replaces a set of
  ad-hoc scripts (basic_workbench_spex.exs, simple_workbench_spex.exs,
  simple_workbench_test_spex.exs, component_loading_test_harness_spex.exs,
  debug_module_loading_spex.exs, widget_workbench_manual_demo_spex.exs)
  that predated the shared workbench setup helper and relied on
  `IO.puts` narration, manual `Scenic.ViewPort.start_link/1` calls, and
  scenic_mcp APIs (`find_clickable_elements/0`, atom `click_element/1`,
  `WidgetWorkbench.Scene.discover_components/0`) that either never
  existed or are private.
  """
  use SexySpex

  alias ScenicMcp.Query

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  spex "Widget Workbench Launch",
    description: "Validates the workbench boots and renders its core UI",
    tags: [:workbench, :launch] do
    scenario "Workbench boots and renders UI", context do
      given_ "the application has started", context do
        {:ok, context}
      end

      then_ "the workbench UI should be visible", context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != ""
        :ok
      end
    end

    scenario "Workbench viewport is registered and sized correctly", context do
      given_ "the workbench has launched", context do
        {:ok, context}
      end

      when_ "we inspect the viewport", context do
        {:ok, vp_info} = Scenic.ViewPort.info(:main_viewport)
        {:ok, Map.put(context, :vp_info, vp_info)}
      end

      then_ "the viewport is named and sized as expected", context do
        assert context.vp_info.name == :main_viewport

        {width, height} = context.vp_info.size
        assert width >= 1200 and width <= 1202,
               "Viewport width should be around 1200 (got #{width})"
        assert height >= 780 and height <= 800,
               "Viewport height should be around 800 (got #{height})"

        :ok
      end
    end

    scenario "Constructor pane displays its core controls", context do
      given_ "the workbench has launched", context do
        {:ok, context}
      end

      then_ "the constructor pane title and buttons are visible", context do
        assert Query.text_visible?("Widget Workbench"),
               "Constructor pane title should be visible"
        assert Query.text_visible?("Reset Scene"),
               "Reset Scene button should be visible"
        assert Query.text_visible?("New Widget"),
               "New Widget button should be visible"

        :ok
      end
    end

    scenario "Component loading capability is available", context do
      given_ "the workbench has launched", context do
        {:ok, context}
      end

      then_ "the Load Component button is visible", context do
        assert Query.text_visible?("Load Component"),
               "Load Component button should be visible, exposing component-loading capability"

        :ok
      end
    end
  end
end
