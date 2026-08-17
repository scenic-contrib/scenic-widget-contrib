defmodule QuillEx.Fluxus.RadixReducer do
  @moduledoc """
  This reducer works slightly different to the others... the others
  are apart of the Fluxus system. This module just contains mutation
  functions for the RadixState.
  """
  require Logger

  alias QuillEx.Fluxus.Structs.RadixState

  # these are just here to keep the RadixStore module from becoming cluttered
  def handle_action(radix_state, {:action, a}) do
    {:ok, new_radix_state} = QuillEx.Fluxus.RadixReducer.process(radix_state, a)

    QuillEx.Lib.Utils.PubSub.broadcast(
      topic: :radix_state_change,
      msg: {:radix_state_change, new_radix_state}
    )

    {:ok, new_radix_state}
  end

  def process(radix_state, :open_read_only_text_pane) do
    new_rdx = radix_state |> RadixState.show_text_pane()
    {:ok, new_rdx}
  end

  def process(radix_state, {:minor_mode, m}) do
    new_rdx = radix_state |> RadixState.minor_mode(m)
    {:ok, new_rdx}
  end

  def process(radix_state, :open_text_pane) do
    new_rdx = radix_state |> RadixState.show_text_pane_two()
    {:ok, new_rdx}
  end

  def process(radix_state, :open_text_pane_scrollable) do
    new_rdx = radix_state |> RadixState.show_text_pane_scrollable()
    {:ok, new_rdx}
  end

  def process(radix_state, {:scroll, input}) do
    # new_components = [
    #   ScenicWidgets.UbuntuBar.draw(),
    #   PlainText.draw(~s|Hello world!|)
    # ]

    # radix_state.components

    new_rdx = radix_state |> RadixState.scroll_editor({:scroll, input})

    {:ok, new_rdx}
  end

  # def change_font(%{editor: %{font: current_font}} = radix_state, new_font)
  #     when is_atom(new_font) do
  #   {:ok, {_type, new_font_metrics}} = Scenic.Assets.Static.meta(new_font)

  #   full_new_font = current_font |> Map.merge(%{name: new_font, metrics: new_font_metrics})

  #   radix_state
  #   |> put_in([:editor, :font], full_new_font)
  # end

  # def change_font_size(%{editor: %{font: current_font}} = radix_state, direction)
  #     when direction in [:increase, :decrease] do
  #   delta = if direction == :increase, do: 4, else: -4
  #   full_new_font = current_font |> Map.merge(%{size: current_font.size + delta})

  #   radix_state
  #   |> put_in([:editor, :font], full_new_font)
  # end

  def change_editor_scroll_state(
        radix_state,
        %{inner: %{width: _w, height: _h}, frame: _f} = new_scroll_state
      ) do
    radix_state
    |> put_in([:editor, :scroll_state], new_scroll_state)
  end

  def process(radix_state, :test_input_action) do
    IO.puts("PROCESSING TEST ACTION")
    {:ok, radix_state}
  end

  def process(radix_state, unknown_action) do
    Logger.warn("Unknown action: #{inspect(unknown_action)}")
    {:ok, radix_state}
  end
end
