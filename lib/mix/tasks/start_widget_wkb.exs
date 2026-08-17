# Start WidgetWorkbench and keep running
# Run with: mix run --no-halt start_widget_wkb.exs
# Or better: iex -S mix (then it starts automatically)

IO.puts """
🚀 Starting WidgetWorkbench...
   MCP Server on port 9996
   Look for: 🎯 Registered Load Component button for MCP...

   Press Ctrl+C twice to exit
"""

# Start the application if not already started
Application.ensure_all_started(:tidewave)
Application.ensure_all_started(:scenic_widget_contrib)

# Keep running
WidgetWorkbench.start()
