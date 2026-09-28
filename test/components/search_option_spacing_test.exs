defmodule ScenicWidgets.SearchOptionSpacingTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.SearchBar
  alias ScenicWidgets.SearchPane
  alias Widgex.Frame

  test "local find gives its option buttons equal, visible margins" do
    state = SearchBar.State.new(id: :find, frame: frame(500, 80))
    widgets = SearchBar.State.widgets(state)

    field = widget(widgets, :search_field)
    case_button = widget(widgets, {:toggle, :case_sensitive})
    regex_button = widget(widgets, {:toggle, :regex})

    assert_equal_margins(field, case_button, regex_button)
    assert regex_button.x - (case_button.x + case_button.w) >= 4
  end

  test "project find uses the same balanced option-button spacing" do
    state = SearchPane.State.new(%{frame: frame(360, 600)})
    widgets = SearchPane.State.header_widgets(state)

    field = widget(widgets, {:field, :query})
    case_button = widget(widgets, {:toggle, :case_sensitive})
    regex_button = widget(widgets, {:toggle, :regex})

    assert_equal_margins(field, case_button, regex_button)
    assert regex_button.x - (case_button.x + case_button.w) >= 4
  end

  defp assert_equal_margins(field, case_button, regex_button) do
    top = case_button.y - field.y
    bottom = field.y + field.h - (case_button.y + case_button.h)
    between = regex_button.x - (case_button.x + case_button.w)
    right = field.x + field.w - (regex_button.x + regex_button.w)

    assert top == bottom
    assert between == right
    assert right == top
  end

  defp widget(widgets, id), do: Enum.find(widgets, &(&1.id == id))
  defp frame(width, height), do: Frame.new(pin: {0, 0}, size: {width, height})
end
