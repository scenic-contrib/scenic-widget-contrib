defmodule Mix.Tasks.Wkb do
  @moduledoc """
  Starts the Widget Workbench with IEx for interactive development.

  Usage:
      mix wkb

  This starts the Widget Workbench application with:
  - MCP Server on port 9996
  - Tidewave for logging
  - Interactive IEx shell
  """

  use Mix.Task

  @shortdoc "Start Widget Workbench interactively"

  @impl Mix.Task
  def run(_args) do
    IO.puts("""
    🚀 Starting Widget Workbench...
       MCP Server on port 9996
       Tidewave enabled for logging

       Press Ctrl+C twice to exit
    """)

    # Start required applications
    Application.ensure_all_started(:tidewave)
    Application.ensure_all_started(:scenic_widget_contrib)

    # Start the workbench
    WidgetWorkbench.start()

    # Keep running (for non-iex usage)
    unless IEx.started?() do
      Process.sleep(:infinity)
    end
  end
end
