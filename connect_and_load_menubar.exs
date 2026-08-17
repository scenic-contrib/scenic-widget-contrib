# Add scenic_mcp to the code path
Code.append_path("../scenic_mcp/_build/dev/lib/scenic_mcp/ebin")
Code.append_path("_build/dev/lib/scenic_widget_contrib/ebin")

# Ensure scenic_mcp is loaded
case Code.ensure_loaded(ScenicMcp.Probes) do
  {:module, _} -> 
    IO.puts("✅ ScenicMcp.Probes loaded")
  {:error, reason} ->
    IO.puts("❌ Failed to load ScenicMcp.Probes: #{inspect(reason)}")
end

# Now try to get the rendered content
try do
  script_data = ScenicMcp.Probes.script_table()
  IO.puts("✅ Got script data\!")
  IO.inspect(script_data, limit: 20)
rescue
  error ->
    IO.puts("❌ Error getting script data: #{inspect(error)}")
end

# Try to click the Load Component button
try do
  # Click approximately where the Load Component button should be
  # Based on the layout, it's in the right third of the screen
  ScenicMcp.Probes.send_mouse_click(900, 290)
  Process.sleep(1000)
  
  # Check if modal opened
  script_data = ScenicMcp.Probes.script_table()
  rendered_text = inspect(script_data)
  
  if String.contains?(rendered_text, "Menu Bar") do
    IO.puts("✅ Modal opened, clicking Menu Bar...")
    # Click on Menu Bar in the modal (should be around 4th position)
    ScenicMcp.Probes.send_mouse_click(600, 300)
    Process.sleep(1000)
    IO.puts("✅ Menu Bar should be loaded now")
  else
    IO.puts("⚠️  Modal might not have opened, trying different position...")
    ScenicMcp.Probes.send_mouse_click(900, 400)
  end
rescue
  error ->
    IO.puts("❌ Error during interaction: #{inspect(error)}")
end
