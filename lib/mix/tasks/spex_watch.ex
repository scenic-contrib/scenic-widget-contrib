defmodule Mix.Tasks.SpexWatch do
  @moduledoc """
  Run spex tests in watch mode for iterative development.
  
  ## Usage
  
      mix spex_watch                           # Watch all spex files
      mix spex_watch test/spex/menubar*.exs    # Watch specific pattern
      mix spex_watch --focus menubar_flicker   # Focus on specific test
  
  ## Options
  
      --focus     Run only tests matching pattern
      --verbose   Show detailed output
      --interval  Check interval in ms (default: 1000)
  """
  use Mix.Task
  
  @default_interval 1000
  @spex_pattern "test/spex/**/*_spex.exs"
  
  def run(args) do
    {opts, files, _} = OptionParser.parse(args,
      switches: [focus: :string, verbose: :boolean, interval: :integer],
      aliases: [f: :focus, v: :verbose, i: :interval]
    )
    
    # Ensure test environment
    Mix.env(:test)
    Mix.Task.run("compile")
    
    IO.puts("🔍 Starting Spex Watch Mode...")
    IO.puts("   Press Ctrl+C to exit")
    IO.puts("")
    
    # Determine which files to watch
    pattern = if Enum.empty?(files), do: @spex_pattern, else: hd(files)
    focus = opts[:focus]
    interval = opts[:interval] || @default_interval
    
    # Start watching
    watch_loop(pattern, focus, opts, interval)
  end
  
  defp watch_loop(pattern, focus, opts, interval) do
    # Get current file timestamps
    files = get_spex_files(pattern, focus)
    timestamps = get_timestamps(files)
    
    # Run tests
    run_spex_tests(files, opts)
    
    # Enter watch loop
    do_watch(pattern, focus, opts, interval, timestamps)
  end
  
  defp do_watch(pattern, focus, opts, interval, last_timestamps) do
    Process.sleep(interval)
    
    files = get_spex_files(pattern, focus)
    current_timestamps = get_timestamps(files)
    
    if current_timestamps != last_timestamps do
      IO.puts("\n📝 Changes detected, running spex tests...")
      run_spex_tests(files, opts)
      do_watch(pattern, focus, opts, interval, current_timestamps)
    else
      do_watch(pattern, focus, opts, interval, last_timestamps)
    end
  end
  
  defp get_spex_files(pattern, nil) do
    Path.wildcard(pattern)
  end
  
  defp get_spex_files(pattern, focus) do
    Path.wildcard(pattern)
    |> Enum.filter(&String.contains?(&1, focus))
  end
  
  defp get_timestamps(files) do
    Enum.map(files, fn file ->
      case File.stat(file) do
        {:ok, stat} -> {file, stat.mtime}
        _ -> {file, nil}
      end
    end)
    |> Map.new()
  end
  
  defp run_spex_tests(files, opts) do
    args = files ++ build_args(opts)
    
    # Clear screen for better visibility
    IO.puts("\e[2J\e[H")
    IO.puts("🎯 Running Spex Tests")
    IO.puts("=" |> String.duplicate(60))
    
    # Run the tests
    case System.cmd("mix", ["spex" | args], into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        IO.puts("\n✅ All spex tests passed!")
      {_, _} ->
        IO.puts("\n❌ Some spex tests failed")
    end
    
    IO.puts("\n👀 Watching for changes...")
  end
  
  defp build_args(opts) do
    args = []
    args = if opts[:verbose], do: ["--verbose" | args], else: args
    args
  end
end