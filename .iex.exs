# Widget Workbench IEx configuration
# This file is loaded automatically when you run: iex -S mix

IO.puts("""
╔═══════════════════════════════════════════════════════════╗
║              Widget Workbench Development                 ║
╠═══════════════════════════════════════════════════════════╣
║  Commands:                                                ║
║    wkb()           - Start Widget Workbench               ║
║    sidenav()       - Load SideNav component directly      ║
║    reload()        - Recompile and reload                 ║
║                                                           ║
║  MCP: Port 9996 | Tidewave: Enabled                       ║
╚═══════════════════════════════════════════════════════════╝
""")

# Helper to start workbench
defmodule WkbHelpers do
  def wkb do
    IO.puts("🚀 Starting Widget Workbench...")
    Application.ensure_all_started(:tidewave)
    Application.ensure_all_started(:scenic_widget_contrib)
    WidgetWorkbench.start()
    :ok
  end

  def sidenav do
    # Quick load of SideNav for testing
    IO.puts("📍 Loading SideNav component...")
    wkb()
    Process.sleep(500)
    # TODO: Auto-click load component -> side_nav
    :ok
  end

  def reload do
    IO.puts("🔄 Recompiling...")
    IEx.Helpers.recompile()
  end
end

import WkbHelpers
