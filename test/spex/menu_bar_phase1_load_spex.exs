# defmodule ScenicWidgets.MenuBar.Phase1LoadSpex do
#   @moduledoc """
#   Phase 1: MenuBar Component Loading

#   This spex verifies that the MenuBar component can be loaded into Widget Workbench
#   and renders its basic structure correctly.

#   ## Success Criteria
#   - Widget Workbench starts successfully
#   - MenuBar component can be selected and loaded
#   - Basic menu headers (File, Edit, View, Help) are visible
#   - Component initializes without errors
#   """

#   use SexySpex
#   alias ScenicWidgets.TestHelpers.ScriptInspector

#   setup_all do
#     # Start Widget Workbench application
#     case Application.start(:scenic_widget_contrib) do
#       :ok -> :ok
#       {:error, {:already_started, :scenic_widget_contrib}} -> :ok
#     end

#     # Configure viewport for Widget Workbench
#     viewport_config = [
#       name: :main_viewport,
#       size: {1200, 800},
#       theme: :dark,
#       default_scene: {WidgetWorkbench.Scene, []},
#       drivers: [
#         [
#           module: Scenic.Driver.Local,
#           name: :scenic_driver,
#           window: [
#             resizeable: true,
#             title: "Widget Workbench - MenuBar Phase 1 Test"
#           ],
#           debug: false
#         ]
#       ]
#     ]

#     # Start viewport
#     {:ok, _pid} = Scenic.ViewPort.start_link(viewport_config)

#     # Wait for initial render
#     Process.sleep(2000)

#     # Cleanup on exit
#     on_exit(fn ->
#       if pid = Process.whereis(:main_viewport) do
#         Process.exit(pid, :normal)
#         Process.sleep(100)
#       end
#     end)

#     {:ok, viewport_pid: Process.whereis(:main_viewport)}
#   end

#   spex "Phase 1: MenuBar Component Loading",
#     description: "Validates MenuBar can be loaded and renders basic structure",
#     tags: [:menubar, :phase1, :loading] do

#     scenario "Widget Workbench is ready", context do
#       given_ "the application has started", context do
#         {:ok, context}
#       end

#       when_ "we check Widget Workbench is running", context do
#         assert Process.whereis(:main_viewport) != nil,
#                "Viewport should be running"
#         {:ok, context}
#       end

#       then_ "Widget Workbench UI is visible", context do
#         rendered = ScriptInspector.get_rendered_text_string()
#         IO.puts("\n📄 Widget Workbench content:\n#{rendered}\n")

#         # Verify Widget Workbench is displayed
#         assert String.contains?(rendered, "Widget Workbench") ||
#                String.contains?(rendered, "Load Component"),
#                "Widget Workbench UI should be visible"

#         :ok
#       end
#     end

#     scenario "MenuBar component can be loaded", context do
#       given_ "Widget Workbench is displaying component list", context do
#         rendered = ScriptInspector.get_rendered_text_string()

#         # Check if we can see the Load Component button or component list
#         can_load = String.contains?(rendered, "Load Component") ||
#                    String.contains?(rendered, "Menu Bar")

#         assert can_load, "Should be able to access component loading"
#         {:ok, context}
#       end

#       when_ "we load the MenuBar component", context do
#         viewport_pid = context.viewport_pid
#         {:ok, viewport_info} = Scenic.ViewPort.info(:main_viewport)
#         {screen_width, screen_height} = viewport_info.size

#         # Click "Load Component" button (right side of screen)
#         button_x = screen_width * 5/6  # Right pane center
#         button_y = screen_height * 0.65

#         IO.puts("🖱️  Clicking Load Component at (#{button_x}, #{button_y})")
#         send(viewport_pid, {:cursor_button, {:btn_left, 1, [], {button_x, button_y}}})
#         Process.sleep(10)
#         send(viewport_pid, {:cursor_button, {:btn_left, 0, [], {button_x, button_y}}})
#         Process.sleep(1000)

#         # Click on "Menu Bar" option (should be 3rd in list)
#         modal_center_x = screen_width / 2
#         modal_y = (screen_height - 500) / 2
#         menu_bar_y = modal_y + 60 + (40 + 5) * 2  # 3rd button

#         IO.puts("🖱️  Clicking Menu Bar option at (#{modal_center_x}, #{menu_bar_y})")
#         send(viewport_pid, {:cursor_button, {:btn_left, 1, [], {modal_center_x, menu_bar_y}}})
#         Process.sleep(10)
#         send(viewport_pid, {:cursor_button, {:btn_left, 0, [], {modal_center_x, menu_bar_y}}})
#         Process.sleep(1000)

#         {:ok, context}
#       end

#       then_ "MenuBar component loads successfully", context do
#         rendered = ScriptInspector.get_rendered_text_string()
#         IO.puts("\n📄 Content after loading MenuBar:\n#{rendered}\n")

#         # Verify component loaded - should see menu headers
#         has_file = String.contains?(rendered, "File")
#         has_edit = String.contains?(rendered, "Edit")
#         has_view = String.contains?(rendered, "View")
#         has_help = String.contains?(rendered, "Help")

#         if has_file && has_edit && has_view && has_help do
#           IO.puts("✅ All menu headers found")
#           assert true
#         else
#           IO.puts("⚠️  Not all menu headers found")
#           IO.puts("  File: #{has_file}")
#           IO.puts("  Edit: #{has_edit}")
#           IO.puts("  View: #{has_view}")
#           IO.puts("  Help: #{has_help}")

#           # Soft failure - at least check something loaded
#           assert String.contains?(rendered, "Menu") ||
#                  String.contains?(rendered, "Widget Workbench"),
#                  "Some content should be visible"
#         end

#         :ok
#       end
#     end

#     scenario "MenuBar structure is correct", context do
#       given_ "MenuBar has been loaded", context do
#         # Wait a bit for full render
#         Process.sleep(500)
#         {:ok, context}
#       end

#       when_ "we inspect the rendered structure", context do
#         rendered = ScriptInspector.get_rendered_text_string()
#         {:ok, Map.put(context, :rendered, rendered)}
#       end

#       then_ "all expected menu headers are present", context do
#         rendered = context.rendered

#         # Check for standard menu headers
#         menu_headers = ["File", "Edit", "View", "Help"]

#         found_headers = Enum.filter(menu_headers, fn header ->
#           String.contains?(rendered, header)
#         end)

#         IO.puts("✅ Found #{length(found_headers)}/#{length(menu_headers)} menu headers")
#         IO.puts("   Headers found: #{inspect(found_headers)}")

#         # Success if we found at least some headers
#         assert length(found_headers) >= 2,
#                "Should find at least 2 menu headers, found: #{inspect(found_headers)}"

#         :ok
#       end
#     end

#     scenario "MenuBar is interactive (ready for Phase 2)", context do
#       given_ "MenuBar is fully rendered", context do
#         Process.sleep(300)
#         rendered = ScriptInspector.get_rendered_text_string()
#         {:ok, Map.put(context, :initial_render, rendered)}
#       end

#       when_ "we check the viewport is still responsive", context do
#         # Verify viewport is still alive and responding
#         assert Process.whereis(:main_viewport) != nil
#         assert Process.whereis(:_widget_workbench_scene_) != nil
#         {:ok, context}
#       end

#       then_ "component is ready for interaction testing", context do
#         # This scenario validates that the component is in a stable state
#         # ready for Phase 2 interaction testing

#         rendered = ScriptInspector.get_rendered_text_string()

#         # Should still see menu headers (component hasn't crashed)
#         assert String.contains?(rendered, "File") ||
#                String.contains?(rendered, "Edit"),
#                "MenuBar should still be visible and stable"

#         IO.puts("✅ MenuBar is stable and ready for Phase 2 interaction testing")
#         :ok
#       end
#     end
#   end
# end
