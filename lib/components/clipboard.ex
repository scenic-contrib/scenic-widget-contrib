defmodule ScenicWidgets.Clipboard do
  @moduledoc "Configurable clipboard boundary used by direct-mode widgets."

  @callback copy(String.t()) :: :ok | {:error, term()}
  @callback paste() :: {:ok, String.t()} | {:error, term()}

  def adapter do
    Application.get_env(:scenic_widget_contrib, :clipboard_adapter, __MODULE__.System)
  end
end

defmodule ScenicWidgets.Clipboard.System do
  @moduledoc false
  @behaviour ScenicWidgets.Clipboard

  @impl true
  def copy(text) do
    with {:ok, executable, args} <- command(:copy, :os.type()) do
      port = Port.open({:spawn_executable, executable}, [:binary, args: args])
      send(port, {self(), {:command, text}})
      send(port, {self(), :close})

      receive do
        {^port, :closed} -> :ok
      after
        5_000 -> {:error, :timeout}
      end
    end
  end

  @impl true
  def paste do
    with {:ok, executable, args} <- command(:paste, :os.type()),
         {text, 0} <- System.cmd(executable, args) do
      {:ok, text}
    else
      {message, status} -> {:error, {status, message}}
      error -> error
    end
  rescue
    error -> {:error, error}
  end

  defp command(:copy, {:unix, :darwin}), do: executable("pbcopy", [])
  defp command(:copy, {:unix, _}), do: executable("xclip", ["-selection", "clipboard"])
  defp command(:copy, {:win32, _}), do: executable("clip", [])
  defp command(:paste, {:unix, :darwin}), do: executable("pbpaste", [])
  defp command(:paste, {:unix, _}), do: executable("xclip", ["-selection", "clipboard", "-o"])
  defp command(:paste, {:win32, _}), do: executable("powershell", ["-command", "Get-Clipboard"])
  defp command(_, _), do: {:error, :unsupported_os}

  defp executable(name, args) do
    case System.find_executable(name) do
      nil -> {:error, {:executable_not_found, name}}
      path -> {:ok, path, args}
    end
  end
end
