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
  defp command(:copy, {:unix, _}), do: first_executable(unix_candidates(:copy))
  defp command(:copy, {:win32, _}), do: executable("clip", [])
  defp command(:paste, {:unix, :darwin}), do: executable("pbpaste", [])
  defp command(:paste, {:unix, _}), do: first_executable(unix_candidates(:paste))
  defp command(:paste, {:win32, _}), do: executable("powershell", ["-command", "Get-Clipboard"])
  defp command(_, _), do: {:error, :unsupported_os}

  # Linux has no single clipboard tool. A Wayland session needs wl-clipboard —
  # xclip may well be installed there too, but it only ever sees the X11
  # clipboard, which under XWayland is not the one the user copied to — so the
  # session decides the preference and the rest are fallbacks.
  @x11_copy [{"xclip", ["-selection", "clipboard"]}, {"xsel", ["--clipboard", "--input"]}]
  @x11_paste [{"xclip", ["-selection", "clipboard", "-o"]}, {"xsel", ["--clipboard", "--output"]}]
  @wayland_copy [{"wl-copy", []}]
  @wayland_paste [{"wl-paste", ["--no-newline"]}]

  defp unix_candidates(:copy),
    do: if(wayland?(), do: @wayland_copy ++ @x11_copy, else: @x11_copy ++ @wayland_copy)

  defp unix_candidates(:paste),
    do: if(wayland?(), do: @wayland_paste ++ @x11_paste, else: @x11_paste ++ @wayland_paste)

  defp wayland?, do: System.get_env("WAYLAND_DISPLAY") not in [nil, ""]

  defp first_executable(candidates) do
    Enum.find_value(candidates, {:error, {:executable_not_found, Enum.map(candidates, &elem(&1, 0))}}, fn
      {name, args} ->
        case System.find_executable(name) do
          nil -> nil
          path -> {:ok, path, args}
        end
    end)
  end

  defp executable(name, args) do
    case System.find_executable(name) do
      nil -> {:error, {:executable_not_found, name}}
      path -> {:ok, path, args}
    end
  end
end
