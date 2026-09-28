defmodule ScenicWidgets.DebugModuleLoadingSpex do
  @moduledoc """
  Debug test to understand module loading issues with mix spex.
  """
  use SexySpex

  spex "Debug module loading in test environment" do
    scenario "Check which modules are available", _context do
      given_ "we are in test environment", _context do
        IO.puts("\n🔍 Mix environment: #{Mix.env()}")
        IO.puts("🔍 Current working directory: #{File.cwd!()}")
        
        # Check if scenic_widget_contrib app is started
        apps = Application.started_applications()
        IO.puts("\n📦 Started applications:")
        Enum.each(apps, fn {app, _, _} -> IO.puts("  - #{app}") end)
        
        # Check if specific modules are loaded
        modules_to_check = [
          WidgetWorkbench,
          WidgetWorkbench.Scene,
          ScenicWidgets.MenuBar,
          Widgex.Frame,
          ScenicMcp.Probes,
          ScenicWidgets.TestHelpers.ScriptInspector
        ]
        
        IO.puts("\n🔍 Checking module availability:")
        Enum.each(modules_to_check, fn module ->
          case Code.ensure_loaded(module) do
            {:module, _} -> 
              IO.puts("  ✅ #{module}")
            {:error, reason} -> 
              IO.puts("  ❌ #{module} - #{reason}")
          end
        end)
        
        # Check compilation paths
        IO.puts("\n📁 Elixir compilation paths:")
        paths = :code.get_path()
        |> Enum.map(&to_string/1)
        |> Enum.filter(&String.contains?(&1, "scenic_widget_contrib"))
        |> Enum.each(&IO.puts("  - #{&1}"))
        
        :ok
      end

      then_ "we understand the loading issue", _context do
        # Let's try to manually ensure WidgetWorkbench is available
        case Code.ensure_loaded(WidgetWorkbench) do
          {:module, _} ->
            IO.puts("\n✅ WidgetWorkbench module is now available!")
            assert true
          {:error, reason} ->
            IO.puts("\n❌ WidgetWorkbench still not available: #{reason}")
            
            # Try to find the beam file
            beam_paths = :code.get_path()
            |> Enum.map(&to_string/1)
            |> Enum.flat_map(fn path ->
              Path.wildcard(Path.join(path, "Elixir.WidgetWorkbench.beam"))
            end)
            
            IO.puts("\n🔍 Beam file search results:")
            if Enum.empty?(beam_paths) do
              IO.puts("  No WidgetWorkbench.beam file found in code paths")
            else
              Enum.each(beam_paths, &IO.puts("  Found: #{&1}"))
            end
            
            flunk("WidgetWorkbench module not available")
        end
      end
    end
  end
end