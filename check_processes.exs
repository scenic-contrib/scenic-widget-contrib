# Check all registered processes
IO.puts("Registered processes:")
Process.registered() |> Enum.sort() |> Enum.each(&IO.puts("  #{inspect(&1)}"))

# Check for viewport-like processes
viewport_procs = Process.registered() |> Enum.filter(fn name ->
  name_str = to_string(name)
  String.contains?(name_str, "viewport") or String.contains?(name_str, "main")
end)

IO.puts("\nViewport-like processes: #{inspect(viewport_procs)}")

# Check for driver-like processes  
driver_procs = Process.registered() |> Enum.filter(fn name ->
  name_str = to_string(name)
  String.contains?(name_str, "driver") or String.contains?(name_str, "scenic")
end)

IO.puts("Driver-like processes: #{inspect(driver_procs)}")
