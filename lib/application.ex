defmodule ScenicWidgets.Application do
  @moduledoc false

  use Application
  require Logger

  @dev_mode? Mix.env() == :dev
  @live_reload_available? Code.ensure_loaded?(ScenicLiveReload)

  def start(_type, _args) do
    if @dev_mode? and @live_reload_available? do
      check_dev_dependencies()
    end

    children = []

    # Add ScenicLiveReload to children in dev environment if not already started
    # children =
    #   if Mix.env() == :dev && !Process.whereis(ScenicLiveReload) do
    #     [{ScenicLiveReload, []}] ++ children
    #   else
    #     children
    #   end

    # Conditionally start Tidewave server for development
    children =
      children ++
        if Application.get_env(:scenic_widget_contrib, :environment) == :dev and Code.ensure_loaded?(Tidewave) and Code.ensure_loaded?(Bandit) do
          require Logger
          Logger.info("Starting Tidewave server on port 4067 for development")
          [{Bandit, plug: Tidewave, port: 4067}]
        else
          []
        end

    opts = [strategy: :one_for_one, name: ScenicWidgets.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp check_dev_dependencies do
    case :os.type() do
      {:unix, :linux} ->
        check_linux_file_watcher()

      {:unix, :darwin} ->
        check_macos_file_watcher()

      {:win32, :nt} ->
        check_windows_file_watcher()

      _ ->
        :ok
    end
  end

  defp check_linux_file_watcher do
    if is_nil(System.find_executable("inotifywait")) do
      Logger.error("""

      ================================================================================
      MISSING REQUIRED DEPENDENCY: inotify-tools
      ================================================================================

      The ExSync auto-reload feature requires `inotify-tools` to be installed
      on Linux systems to watch for file changes.

      To install:
        Ubuntu/Debian: sudo apt-get install inotify-tools
        Fedora/RHEL:   sudo dnf install inotify-tools
        Arch:          sudo pacman -S inotify-tools

      After installing, restart your application.

      If you want to disable auto-reload instead, add to config/dev.exs:
        config :exsync, src_monitor: false
      ================================================================================
      """)

      raise """
      Cannot start application: inotify-tools is not installed.
      Please install it or disable auto-reload (see error message above).
      """
    end
  end

  defp check_macos_file_watcher do
    # macOS uses FSEvents API with a compiled listener executable
    # Check if the mac_listener executable exists in the file_system app
    file_system_priv = Application.app_dir(:file_system, "priv")
    mac_listener = Path.join(file_system_priv, "mac_listener")

    if not File.exists?(mac_listener) do
      Logger.error("""

      ================================================================================
      MISSING REQUIRED EXECUTABLE: mac_listener
      ================================================================================

      The ExSync auto-reload feature requires the `mac_listener` executable
      to be compiled for macOS file watching.

      This should have been built automatically when you ran `mix deps.get`.

      To fix:
        1. cd deps/file_system
        2. mix compile
        3. cd ../..

      If issues persist, try:
        mix deps.clean file_system
        mix deps.get
        mix deps.compile

      If you want to disable auto-reload instead, add to config/dev.exs:
        config :exsync, src_monitor: false
      ================================================================================
      """)

      raise """
      Cannot start application: mac_listener executable not found.
      Please recompile file_system or disable auto-reload (see error message above).
      """
    end
  end

  defp check_windows_file_watcher do
    # Windows uses a bundled inotifywait.exe in the file_system app
    file_system_priv = Application.app_dir(:file_system, "priv")
    windows_watcher = Path.join(file_system_priv, "inotifywait.exe")

    if not File.exists?(windows_watcher) do
      Logger.error("""

      ================================================================================
      MISSING REQUIRED EXECUTABLE: inotifywait.exe
      ================================================================================

      The ExSync auto-reload feature requires the `inotifywait.exe` executable
      for Windows file watching.

      This should be included with the file_system dependency.

      To fix:
        mix deps.clean file_system
        mix deps.get
        mix deps.compile

      If you want to disable auto-reload instead, add to config/dev.exs:
        config :exsync, src_monitor: false
      ================================================================================
      """)

      raise """
      Cannot start application: inotifywait.exe not found.
      Please reinstall file_system or disable auto-reload (see error message above).
      """
    end
  end
end
