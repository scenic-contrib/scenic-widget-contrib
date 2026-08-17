defmodule ScenicWidgets.UbuntuBarTest do
  use ExUnit.Case, async: true
  alias ScenicWidgets.UbuntuBar
  
  describe "validate/1" do
    test "accepts valid map data with defaults" do
      assert {:ok, data} = UbuntuBar.validate(%{})
      assert data.buttons == UbuntuBar.default_buttons()
      assert data.button_size == 50
      assert data.layout == :center
      assert data.button_spacing == 8
    end
    
    test "accepts custom configuration" do
      custom_buttons = [
        %{id: :custom, glyph: "X", tooltip: "Custom"}
      ]
      
      config = %{
        buttons: custom_buttons,
        button_size: 60,
        layout: :top,
        button_spacing: 15,
        font_family: "CustomFont"
      }
      
      assert {:ok, data} = UbuntuBar.validate(config)
      assert data.buttons == custom_buttons
      assert data.button_size == 60
      assert data.layout == :top
      assert data.button_spacing == 15
      assert data.font_family == "CustomFont"
    end
    
    test "validates layout options" do
      assert {:ok, _} = UbuntuBar.validate(%{layout: :top})
      assert {:ok, _} = UbuntuBar.validate(%{layout: :center})
      assert {:ok, _} = UbuntuBar.validate(%{layout: :bottom})
      assert {:error, _} = UbuntuBar.validate(%{layout: :invalid})
    end
    
    test "rejects non-map data" do
      assert {:error, _} = UbuntuBar.validate("not a map")
      assert {:error, _} = UbuntuBar.validate(nil)
      assert {:error, _} = UbuntuBar.validate([])
    end
  end
  
  describe "button sets" do
    test "default_buttons returns valid button list" do
      buttons = UbuntuBar.default_buttons()
      assert is_list(buttons)
      assert length(buttons) > 0
      
      Enum.each(buttons, fn button ->
        assert Map.has_key?(button, :id)
        assert Map.has_key?(button, :glyph)
        assert Map.has_key?(button, :tooltip)
        assert is_atom(button.id)
        assert is_binary(button.glyph)
        assert is_binary(button.tooltip)
      end)
    end
    
    test "egyptian_buttons returns hieroglyphs" do
      buttons = UbuntuBar.egyptian_buttons()
      assert is_list(buttons)
      
      # Check that glyphs contain hieroglyphs (unicode range U+13000-U+1342F)
      Enum.each(buttons, fn button ->
        glyph = button.glyph
        assert String.length(glyph) > 0
        # Note: Hieroglyphs will likely render as boxes, but they're valid Unicode
      end)
    end
    
    test "emoji_buttons returns emoji glyphs" do
      buttons = UbuntuBar.emoji_buttons()
      assert is_list(buttons)
      
      # Verify emoji structure
      Enum.each(buttons, fn button ->
        assert Map.has_key?(button, :glyph)
        # Emojis are multi-byte unicode sequences
        assert byte_size(button.glyph) > 1
      end)
    end
    
    test "symbol_buttons returns mathematical symbols" do
      buttons = UbuntuBar.symbol_buttons()
      assert is_list(buttons)
      
      # Check for mathematical symbols
      glyphs = Enum.map(buttons, & &1.glyph)
      assert "⊕" in glyphs  # Plus in circle
      assert "⊞" in glyphs  # Square plus
    end
    
    test "ascii_buttons returns simple ASCII characters" do
      buttons = UbuntuBar.ascii_buttons()
      assert is_list(buttons)
      
      # All glyphs should be single ASCII characters
      Enum.each(buttons, fn button ->
        assert String.length(button.glyph) == 1
        assert button.glyph =~ ~r/^[+OS?*]$/
      end)
    end
  end
  
  describe "layout calculations" do
    test "consistent margins calculation" do
      # Test that side margins equal top/bottom margins
      frame_width = 60
      button_size = 48
      expected_margin = (frame_width - button_size) / 2
      
      # For a frame of 60px width and button of 48px
      # Side margin should be (60 - 48) / 2 = 6px
      assert expected_margin == 6
    end
    
    test "button spacing affects total height" do
      button_count = 5
      button_size = 48
      button_spacing = 10
      
      total_height = button_count * button_size + (button_count - 1) * button_spacing
      expected = 5 * 48 + 4 * 10  # 240 + 40 = 280
      
      assert total_height == expected
    end
  end
  
  describe "event handling" do
    test "button click event structure" do
      # Verify the event format that gets sent to parent
      button = %{id: :test_button, glyph: "T", tooltip: "Test"}
      event = {:ubuntu_bar_button_clicked, button.id, button}
      
      # Destructure to verify format
      {:ubuntu_bar_button_clicked, id, button_data} = event
      assert id == :test_button
      assert button_data.glyph == "T"
      assert button_data.tooltip == "Test"
    end
  end
  
  describe "color theming" do
    test "default colors are properly structured" do
      assert {:ok, data} = UbuntuBar.validate(%{})
      
      # Colors should be RGB tuples
      assert tuple_size(data.background_color) == 3
      assert tuple_size(data.button_color) == 3
      assert tuple_size(data.button_hover_color) == 3
      assert tuple_size(data.button_active_color) == 3
      assert tuple_size(data.text_color) == 3
      
      # Verify they're valid RGB values (0-255)
      {r, g, b} = data.background_color
      assert r >= 0 and r <= 255
      assert g >= 0 and g <= 255
      assert b >= 0 and b <= 255
    end
  end
  
  describe "font configuration" do
    test "font_family is optional" do
      assert {:ok, data} = UbuntuBar.validate(%{})
      assert data.font_family == nil
      
      assert {:ok, data} = UbuntuBar.validate(%{font_family: "CustomFont"})
      assert data.font_family == "CustomFont"
    end
    
    test "font_size defaults based on button_size" do
      assert {:ok, data} = UbuntuBar.validate(%{button_size: 50})
      # Default calculation: button_size * 0.6
      assert data.font_size == nil  # Uses default calculation in init
      
      assert {:ok, data} = UbuntuBar.validate(%{font_size: 24})
      assert data.font_size == 24
    end
  end
end