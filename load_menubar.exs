# Connect to the running Widget Workbench and load Menu Bar

# Ensure test helpers are loaded
Code.require_file("test/test_helpers/script_inspector.ex")
Code.require_file("test/test_helpers/semantic_ui.ex")

alias ScenicWidgets.TestHelpers.{ScriptInspector, SemanticUI}
alias ScenicMcp.Probes

IO.puts("🔍 Checking current UI state...")
rendered_content = ScriptInspector.get_rendered_text_string()
IO.puts("Current content: #{String.slice(rendered_content, 0, 200)}")

# Try to load Menu Bar
case SemanticUI.load_component("Menu Bar") do
  {:ok, result} -> 
    IO.puts("✅ Successfully loaded Menu Bar\!")
    IO.inspect(result)
  {:error, reason} ->
    IO.puts("❌ Failed to load Menu Bar: #{reason}")
end

# Check what's rendered now
Process.sleep(1000)
rendered_content = ScriptInspector.get_rendered_text_string()
IO.puts("\nAfter loading:")
IO.puts("Content: #{String.slice(rendered_content, 0, 500)}")
