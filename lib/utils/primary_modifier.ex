defmodule ScenicWidgets.PrimaryModifier do
  @moduledoc """
  Which physical key means "the command key" on this machine.

  On Linux and Windows it is Control. On macOS it is Command — which Scenic
  reports as `:meta` — and a Mac user pressing Control expects nothing to
  happen. Twenty years of muscle memory sit behind that difference, and a text
  editor that gets it wrong is one a Mac user closes in the first minute.

  ## Why it is set rather than detected

  Detecting the platform gets it right for most people and wrong for the ones
  who have opinions: a Mac user who remaps Caps Lock to Control and wants
  Control shortcuts, someone on Linux with a Mac keyboard. So the host
  application decides — detecting the platform is a fine way to decide, and a
  setting is a fine way to override the detection — and tells these widgets
  once, here.

  ## Why it is application state and not a component parameter

  Every widget that reads a keystroke needs to know this, and the answer is
  the same for all of them: it is a fact about the keyboard, not about any one
  text field. Threading it through every component's params — and remembering
  to re-push all of them when it changes — would be a great deal of plumbing
  in exchange for the ability to have two text fields disagree about what
  Command means, which nobody wants.

  ## What the widgets actually do with it

  They call `normalize/1` on the modifier list as input arrives, which turns
  the configured key into `:ctrl`. Everything downstream matches on `[:ctrl]`
  and never learns there was a question. That keeps the platform difference at
  the doorway instead of spread through every key clause.
  """

  @doc "The configured key: `:ctrl` (Control) or `:meta` (Command)."
  def get, do: Application.get_env(:scenic_widget_contrib, :primary_modifier, :ctrl)

  @doc "Set it. The host calls this at boot and whenever the setting changes."
  def put(modifier) when modifier in [:ctrl, :meta] do
    Application.put_env(:scenic_widget_contrib, :primary_modifier, modifier)
  end

  @doc """
  Rewrite a modifier list so the configured key reads as `:ctrl`.

  When the configured key IS Control this is the identity, which is the
  common case and costs nothing. When it is Command, `[:meta, :shift]` becomes
  `[:ctrl, :shift]` — and a real Control press becomes nothing at all, because
  on a Mac Control is not the command key and Ctrl+S should not save.
  """
  def normalize(mods) when is_list(mods), do: normalize(mods, get())

  @doc "As `normalize/1`, but against a given modifier — for tests, and for callers that already know."
  def normalize(mods, :ctrl) when is_list(mods), do: mods

  def normalize(mods, :meta) when is_list(mods) do
    mods
    |> Enum.reject(&(&1 == :ctrl))
    |> Enum.map(fn
      :meta -> :ctrl
      other -> other
    end)
  end
end
