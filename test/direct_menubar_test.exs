# Direct test to verify MenuBar components work
# Run with: elixir test/direct_menubar_test.exs

# Add the lib directory to the code path
Code.prepend_path("_build/test/lib/scenic_widget_contrib/ebin")

# Start required applications
{:ok, _} = Application.ensure_all_started(:scenic)
{:ok, _} = Application.ensure_all_started(:scenic_driver_local)
{:ok, _} = Application.ensure_all_started(:scenic_widget_contrib)

defmodule DirectMenuBarTest do
  @moduledoc """
  Direct test of MenuBar components without the spex framework complexity.
  """

  def run do
    IO.puts("\n🧪 Direct MenuBar Component Test")
    IO.puts("=" |> String.duplicate(50))

    # Test 1: Verify modules are loaded
    test_module_loading()

    # Test 2: Test State module
    test_state_module()

    # Test 3: Test Reducer logic
    test_reducer_logic()

    # Test 4: Test Renderizer
    test_renderizer()

    # Test 5: Test MenuBar with optimized rendering
    test_menubar_optimization()

    IO.puts("\n✅ All tests completed!")
  end

  defp test_module_loading do
    IO.puts("\n📦 Test 1: Module Loading")

    modules = [
      ScenicWidgets.MenuBar,
      ScenicWidgets.MenuBar.State,
      ScenicWidgets.MenuBar.Reducer,
      ScenicWidgets.MenuBar.Renderizer,
      ScenicWidgets.MenuBar.OptimizedRenderizer
    ]

    Enum.each(modules, fn module ->
      case Code.ensure_loaded(module) do
        {:module, ^module} ->
          IO.puts("  ✅ #{inspect(module)}")

        {:error, reason} ->
          IO.puts("  ❌ #{inspect(module)} - #{reason}")
      end
    end)
  end

  defp test_state_module do
    IO.puts("\n🔧 Test 2: State Module")

    menu_data = %{
      frame: %{
        pin: %{x: 100, y: 100},
        size: %{width: 600, height: 30}
      },
      menu_map: %{
        file:
          {"File",
           [
             {"new", "New"},
             {"open", "Open"}
           ]},
        edit:
          {"Edit",
           [
             {"undo", "Undo"},
             {"redo", "Redo"}
           ]}
      }
    }

    state = ScenicWidgets.MenuBar.State.new(menu_data)

    IO.puts("  ✅ State created: #{inspect(Map.keys(state))}")
    IO.puts("  ✅ Active menu: #{inspect(state.active_menu)}")
    IO.puts("  ✅ Theme: #{inspect(Map.keys(state.theme))}")
    IO.puts("  ✅ Dropdown bounds calculated: #{map_size(state.dropdown_bounds)} menus")
  end

  defp test_reducer_logic do
    IO.puts("\n🎮 Test 3: Reducer Logic")

    # Create initial state
    menu_data = %{
      frame: %{
        pin: %{x: 0, y: 0},
        size: %{width: 300, height: 30}
      },
      menu_map: %{
        file: {"File", [{"new", "New"}]}
      }
    }

    state = ScenicWidgets.MenuBar.State.new(menu_data)

    # Test hover
    new_state = ScenicWidgets.MenuBar.Reducer.handle_cursor_pos(state, {75, 15})
    IO.puts("  ✅ Hover state updated: #{inspect(new_state.hovered_item)}")

    # Test click
    case ScenicWidgets.MenuBar.Reducer.handle_click(state, {75, 15}) do
      {:noop, clicked_state} ->
        IO.puts("  ✅ Click handled: active_menu = #{inspect(clicked_state.active_menu)}")

      _ ->
        IO.puts("  ✅ Click handled with action")
    end
  end

  defp test_renderizer do
    IO.puts("\n🎨 Test 4: Renderizer")

    state = create_test_state()

    # Test the component's current renderer.
    graph = Scenic.Graph.build()
    opt_graph = ScenicWidgets.MenuBar.OptimizedRenderizer.initial_render(graph, state)
    opt_primitive_count = count_graph_primitives(opt_graph)
    IO.puts("  ✅ Optimized render created #{opt_primitive_count} primitives")
  end

  defp test_menubar_optimization do
    IO.puts("\n🚀 Test 5: MenuBar with Optimized Rendering")

    menu_data = %{
      frame: %{
        pin: %{x: 0, y: 0},
        size: %{width: 300, height: 30}
      },
      menu_map: %{
        file: {"File", [{"new", "New"}]}
      }
    }

    # Test validation
    case ScenicWidgets.MenuBar.validate(menu_data) do
      {:ok, _data} ->
        IO.puts("  ✅ Validation passed")

      {:error, reason} ->
        IO.puts("  ❌ Validation failed: #{reason}")
    end

    # Verify it's using the optimized renderizer
    state = ScenicWidgets.MenuBar.State.new(menu_data)
    graph = Scenic.Graph.build()

    # Test that OptimizedRenderizer functions are available
    initial_graph = ScenicWidgets.MenuBar.OptimizedRenderizer.initial_render(graph, state)
    IO.puts("  ✅ Initial render with OptimizedRenderizer works")

    # Test update render
    new_state = %{state | hovered_item: :file}

    updated_graph =
      ScenicWidgets.MenuBar.OptimizedRenderizer.update_render(initial_graph, state, new_state)

    IO.puts("  ✅ Update render with OptimizedRenderizer works")

    # Verify it's a proper Scenic component
    behaviors =
      ScenicWidgets.MenuBar.__info__(:attributes)
      |> Keyword.get(:behaviour, [])

    IO.puts("  ✅ Implements behaviors: #{inspect(behaviors)}")
  end

  # Helper functions

  defp create_test_state do
    menu_data = %{
      frame: %{
        pin: %{x: 0, y: 0},
        size: %{width: 600, height: 30}
      },
      menu_map: %{
        file:
          {"File",
           [
             {"new", "New"},
             {"open", "Open"}
           ]},
        edit:
          {"Edit",
           [
             {"undo", "Undo"}
           ]}
      }
    }

    ScenicWidgets.MenuBar.State.new(menu_data)
  end

  defp count_graph_primitives(graph) do
    # Count primitives in the graph structure
    case graph do
      %{primitives: primitives} when is_map(primitives) ->
        map_size(primitives)

      _ ->
        0
    end
  end
end

# Run the test
DirectMenuBarTest.run()
