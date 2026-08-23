# Test component discovery logic
components_dir = Path.join([File.cwd!(), "lib", "components"])
IO.puts("Components directory: #{components_dir}")
IO.puts("Exists: #{File.dir?(components_dir)}")

if File.dir?(components_dir) do
  dirs = File.ls!(components_dir)
  IO.puts("\nDirectories found:")
  
  components = dirs
  |> Enum.filter(&File.dir?(Path.join(components_dir, &1)))
  |> Enum.map(fn dir_name ->
    dir_path = Path.join(components_dir, dir_name)
    main_file = "#{dir_name}.ex"
    main_file_path = Path.join(dir_path, main_file)
    
    IO.puts("\n  Directory: #{dir_name}")
    IO.puts("    Main file path: #{main_file_path}")
    IO.puts("    Main file exists: #{File.exists?(main_file_path)}")
    
    if File.exists?(main_file_path) do
      module_name = dir_name |> Macro.camelize()
      display_name = dir_name |> String.replace("_", " ") |> String.split(" ") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
      
      try do
        module_atom = Module.concat([ScenicWidgets, module_name])
        IO.puts("    Display name: #{display_name}")
        IO.puts("    Module: #{inspect(module_atom)}")
        {display_name, module_atom}
      rescue
        e ->
          IO.puts("    Error creating module: #{inspect(e)}")
          nil
      end
    else
      # Look for any .ex file
      case File.ls(dir_path) do
        {:ok, files} ->
          ex_files = Enum.filter(files, &String.ends_with?(&1, ".ex"))
          IO.puts("    .ex files found: #{inspect(ex_files)}")
        {:error, reason} ->
          IO.puts("    Error listing files: #{reason}")
      end
      nil
    end
  end)
  |> Enum.filter(& &1)
  
  IO.puts("\n\nDiscovered components:")
  Enum.each(components, fn {name, module} ->
    IO.puts("  - #{name} => #{inspect(module)}")
  end)
end