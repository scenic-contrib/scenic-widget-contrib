defmodule Mix.Tasks.Workbench do
    @moduledoc "The hello mix task: `mix help hello`"
    use Mix.Task
  
    @shortdoc "Simply calls the Hello.say/0 function."
    def run(_) do
      # calling our Hello.say() function from earlier
    #   Hello.say()
        IO.puts "Opening workbench..."
        {:ok, _} = Application.ensure_all_started(:widget_workbench)
        IO.puts "DONE"
    end
  end