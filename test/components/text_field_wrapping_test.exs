defmodule ScenicWidgets.TextFieldWrappingTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.Wrapping

  defp width(text), do: String.length(text)

  test "word wrapping prefers complete words" do
    assert Wrapping.word("alpha beta gamma", 10, &width/1) == ["alpha beta", "gamma"]
  end

  test "an oversized word falls back to grapheme wrapping" do
    assert Wrapping.word("abcdefghijkl tail", 5, &width/1) == ["abcde", "fghij", "kl", "tail"]
  end

  test "character wrapping does not depend on word boundaries" do
    assert Wrapping.character("abc def", 4, &width/1) == ["abc ", "def"]
  end

  test "every produced segment fits unless one grapheme itself is too wide" do
    for mode <- [&Wrapping.word/3, &Wrapping.character/3], width <- 1..12 do
      segments = mode.("one extraordinarilylongtoken three", width, &String.length/1)
      assert Enum.all?(segments, &(String.length(&1) <= width))
    end
  end
end
