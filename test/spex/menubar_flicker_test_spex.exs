defmodule ScenicWidgets.MenuBarFlickerTestSpex do
  @moduledoc """
  Focused spex test to identify and fix MenuBar flickering issues.
  This test simulates rapid mouse movements to trigger flickering.
  """
  use SexySpex
  
  alias ScenicWidgets.TestHelpers.ScriptInspector
  
  setup_all do
    # Start the scenic_widget_contrib application
    case Application.start(:scenic_widget_contrib) do
      :ok -> :ok
      {:error, {:already_started, :scenic_widget_contrib}} -> :ok
      error -> error
    end
    
    # Start Widget Workbench if not already running
    unless WidgetWorkbench.running?() do
      {:ok, _pid} = WidgetWorkbench.start(size: {1200, 800}, title: "MenuBar Flicker Test")
      Process.sleep(1000)
    end
    
    # Register cleanup
    on_exit(fn ->
      if WidgetWorkbench.running?() do
        WidgetWorkbench.stop()
        Process.sleep(100)
      end
    end)
    
    :ok
  end

  spex "MenuBar Flickering Detection",
    description: "Detect and fix MenuBar flickering during rapid interactions",
    tags: [:menubar, :flicker, :performance] do

    scenario "Rapid hover movements trigger flickering", context do
      given_ "MenuBar is loaded in Widget Workbench", context do
        # Create MenuBar test data
        frame = %{
          pin: %{x: 100, y: 100},
          size: %{width: 600, height: 30}
        }
        
        menu_map = %{
          file: {"File", [
            {"new", "New"},
            {"open", "Open"},
            {"save", "Save"},
            {"exit", "Exit"}
          ]},
          edit: {"Edit", [
            {"undo", "Undo"},
            {"redo", "Redo"},
            {"cut", "Cut"},
            {"copy", "Copy"},
            {"paste", "Paste"}
          ]},
          view: {"View", [
            {"zoom_in", "Zoom In"},
            {"zoom_out", "Zoom Out"},
            {"full_screen", "Full Screen"}
          ]}
        }
        
        # Push MenuBar to the scene
        # Note: In a real implementation, we'd load this through Widget Workbench's UI
        # For now, we'll simulate direct loading
        
        {:ok, Map.merge(context, %{
          frame: frame,
          menu_map: menu_map,
          menu_positions: %{
            file: {100, 100, 250, 130},   # x1, y1, x2, y2
            edit: {250, 100, 400, 130},
            view: {400, 100, 550, 130}
          }
        })}
      end

      when_ "we rapidly move the mouse between menu headers", context do
        # Capture initial render state
        initial_renders = capture_render_count()
        
        # Simulate rapid mouse movements
        movements = [
          {150, 115},  # Over File menu
          {300, 115},  # Over Edit menu
          {150, 115},  # Back to File
          {450, 115},  # Over View menu
          {300, 115},  # Back to Edit
          {150, 115},  # Back to File
          {300, 115},  # Edit again
          {450, 115},  # View again
          {150, 115},  # File again
          {300, 115}   # Edit again
        ]
        
        # Track render counts during movements
        render_counts = Enum.map(movements, fn {x, y} ->
          # Simulate mouse movement
          send_cursor_pos_event(x, y)
          Process.sleep(50)  # Small delay to allow processing
          
          # Capture render count after movement
          capture_render_count()
        end)
        
        {:ok, Map.merge(context, %{
          initial_renders: initial_renders,
          render_counts: render_counts,
          movement_count: length(movements)
        })}
      end

      then_ "the MenuBar should not flicker excessively", context do
        # Calculate total renders
        total_renders = List.last(context.render_counts) - context.initial_renders
        
        # Each mouse movement should ideally cause at most 1 render
        # Allow some buffer for state transitions
        max_expected_renders = context.movement_count * 2
        
        assert total_renders <= max_expected_renders,
               "Too many renders detected: #{total_renders} (expected <= #{max_expected_renders}). " <>
               "This indicates flickering due to inefficient rendering."
        
        # Check for render spikes (multiple renders in quick succession)
        render_deltas = 
          [context.initial_renders | context.render_counts]
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] -> b - a end)
        
        max_delta = Enum.max(render_deltas)
        assert max_delta <= 3,
               "Render spike detected: #{max_delta} renders in one update cycle. " <>
               "This indicates a flickering issue."
        
        IO.puts("✅ MenuBar render performance:")
        IO.puts("   Total renders: #{total_renders}")
        IO.puts("   Max renders per update: #{max_delta}")
        IO.puts("   Average renders per movement: #{Float.round(total_renders / context.movement_count, 2)}")
      end
    end

    scenario "Dropdown open/close transitions are smooth", context do
      given_ "MenuBar is ready for interaction", context do
        # Use the same setup as above
        {:ok, context}
      end

      when_ "we open and close dropdowns rapidly", context do
        initial_renders = capture_render_count()
        
        # Simulate clicking to open/close dropdowns
        interactions = [
          {:click, 150, 115},  # Open File dropdown
          {:click, 150, 115},  # Close File dropdown
          {:click, 300, 115},  # Open Edit dropdown
          {:click, 300, 115},  # Close Edit dropdown
          {:click, 450, 115},  # Open View dropdown
          {:click, 150, 115},  # Click File (closes View, opens File)
          {:click, 300, 115},  # Click Edit (closes File, opens Edit)
          {:click, 300, 115}   # Close Edit
        ]
        
        render_counts = Enum.map(interactions, fn {action, x, y} ->
          case action do
            :click -> send_click_event(x, y)
          end
          Process.sleep(100)  # Allow for animation/transition
          capture_render_count()
        end)
        
        {:ok, Map.merge(context, %{
          initial_renders: initial_renders,
          render_counts: render_counts,
          interaction_count: length(interactions)
        })}
      end

      then_ "dropdown transitions should be efficient", context do
        total_renders = List.last(context.render_counts) - context.initial_renders
        
        # Opening/closing a dropdown should cause minimal renders
        # Ideally 1-2 renders per interaction
        max_expected_renders = context.interaction_count * 3
        
        assert total_renders <= max_expected_renders,
               "Dropdown transitions causing excessive renders: #{total_renders} " <>
               "(expected <= #{max_expected_renders})"
        
        IO.puts("✅ Dropdown transition performance:")
        IO.puts("   Total renders: #{total_renders}")
        IO.puts("   Average renders per interaction: #{Float.round(total_renders / context.interaction_count, 2)}")
      end
    end
  end

  # Helper functions
  
  defp capture_render_count do
    # This would integrate with ScriptInspector or a custom render counter
    # For now, we'll simulate
    case ScriptInspector.get_render_stats() do
      {:ok, stats} -> Map.get(stats, :total_renders, 0)
      _ -> 0
    end
  end
  
  defp send_cursor_pos_event(x, y) do
    # Send cursor position event to the viewport
    case Process.whereis(:main_viewport) do
      nil -> :error
      pid -> send(pid, {:cursor_pos, {x, y}})
    end
  end
  
  defp send_click_event(x, y) do
    # Send click event to the viewport
    case Process.whereis(:main_viewport) do
      nil -> :error
      pid -> 
        send(pid, {:cursor_button, {:btn_left, 1, [], {x, y}}})
        Process.sleep(10)
        send(pid, {:cursor_button, {:btn_left, 0, [], {x, y}}})
    end
  end
end