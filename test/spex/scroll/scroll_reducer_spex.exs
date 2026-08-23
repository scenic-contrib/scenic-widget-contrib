defmodule Widgex.Scroll.ScrollReducerSpex do
  @moduledoc """
  Comprehensive Spex tests for ScrollReducer functionality.

  Tests the pure scroll calculation functions including:
  - Basic vertical scrolling
  - Basic horizontal scrolling
  - 2D scrolling (both axes)
  - Shift+scroll axis swapping
  - Boundary clamping
  - Direction constraints
  - Scroll-to-show functionality
  """
  use SexySpex

  alias Widgex.Scroll.{ScrollState, ScrollReducer}
  alias Widgex.Frame

  # Helper to create a test frame
  defp create_frame(width, height) do
    Frame.new(%{
      pin: {0, 0},
      size: {width, height}
    })
  end

  # Helper to create scroll state with options
  defp create_scroll(opts \\ []) do
    frame_width = Keyword.get(opts, :viewport_width, 400)
    frame_height = Keyword.get(opts, :viewport_height, 300)
    frame = create_frame(frame_width, frame_height)

    scroll_opts = [
      content_width: Keyword.get(opts, :content_width, frame_width),
      content_height: Keyword.get(opts, :content_height, frame_height),
      direction: Keyword.get(opts, :direction, :vertical),
      scroll_speed: Keyword.get(opts, :scroll_speed, 40)
    ]

    ScrollState.new(frame, scroll_opts)
  end

  spex "ScrollReducer - Vertical Scrolling",
    description: "Tests vertical-only scroll behavior",
    tags: [:scroll, :vertical] do

    scenario "Basic vertical scroll down", context do
      given_ "a vertical scroll state with content taller than viewport", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll down (positive delta)", context do
        # Simulate mouse wheel scroll down (delta_y = 1)
        new_scroll = ScrollReducer.handle_wheel(context.scroll, 1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "the offset_y increases", context do
        assert context.new_scroll.offset_y > 0,
          "offset_y should increase when scrolling down"
        assert context.new_scroll.offset_y == 40,
          "offset_y should increase by scroll_speed (40)"
        assert context.new_scroll.scrollbar_visible == true,
          "scrollbar should become visible after scrolling"
        :ok
      end
    end

    scenario "Basic vertical scroll up", context do
      given_ "a scroll state already scrolled down", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        # Pre-scroll down
        scroll = %{scroll | offset_y: 200}
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll up (negative delta)", context do
        new_scroll = ScrollReducer.handle_wheel(context.scroll, -1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "the offset_y decreases", context do
        assert context.new_scroll.offset_y == 160,
          "offset_y should decrease by scroll_speed (40)"
        :ok
      end
    end

    scenario "Vertical scroll ignores horizontal input", context do
      given_ "a vertical-only scroll state", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 1000,
          content_height: 1000,
          direction: :vertical
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we attempt horizontal scrolling via scroll_by", context do
        new_scroll = ScrollReducer.scroll_by(context.scroll, 100, 0)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "offset_x remains unchanged", context do
        assert context.new_scroll.offset_x == 0,
          "offset_x should not change for vertical-only scroll"
        :ok
      end
    end

    scenario "Vertical scroll clamps at top boundary", context do
      given_ "a scroll state at the top", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we try to scroll up past the top", context do
        new_scroll = ScrollReducer.handle_wheel(context.scroll, -5)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "offset_y is clamped to 0", context do
        assert context.new_scroll.offset_y == 0,
          "offset_y should be clamped to 0 (cannot scroll past top)"
        :ok
      end
    end

    scenario "Vertical scroll clamps at bottom boundary", context do
      given_ "a scroll state near the bottom", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        # Scroll to near bottom (max is 1000-300=700)
        scroll = %{scroll | offset_y: 680}
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we try to scroll down past the bottom", context do
        # Try to scroll 5 ticks = 200px, but max is 700
        new_scroll = ScrollReducer.handle_wheel(context.scroll, 5)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "offset_y is clamped to max", context do
        assert context.new_scroll.offset_y == 700,
          "offset_y should be clamped to max_offset_y (700)"
        :ok
      end
    end
  end

  spex "ScrollReducer - Horizontal Scrolling",
    description: "Tests horizontal-only scroll behavior",
    tags: [:scroll, :horizontal] do

    scenario "Basic horizontal scroll right", context do
      given_ "a horizontal scroll state with content wider than viewport", context do
        scroll = create_scroll(
          viewport_width: 400,
          content_width: 1000,
          direction: :horizontal
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll right (positive delta)", context do
        new_scroll = ScrollReducer.handle_wheel_x(context.scroll, 1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "the offset_x increases", context do
        assert context.new_scroll.offset_x == 40,
          "offset_x should increase by scroll_speed (40)"
        :ok
      end
    end

    scenario "Horizontal scroll ignores vertical input", context do
      given_ "a horizontal-only scroll state", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 1000,
          content_height: 1000,
          direction: :horizontal
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we attempt vertical scrolling via scroll_by", context do
        new_scroll = ScrollReducer.scroll_by(context.scroll, 0, 100)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "offset_y remains unchanged", context do
        assert context.new_scroll.offset_y == 0,
          "offset_y should not change for horizontal-only scroll"
        :ok
      end
    end

    scenario "Horizontal scroll clamps at boundaries", context do
      given_ "a horizontal scroll state", context do
        scroll = create_scroll(
          viewport_width: 400,
          content_width: 1000,
          direction: :horizontal
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we try to scroll left past the start", context do
        new_scroll = ScrollReducer.handle_wheel_x(context.scroll, -5)
        {:ok, Map.merge(context, %{left_scroll: new_scroll})}
      end

      and_ "we try to scroll right past the end", context do
        scroll = %{context.scroll | offset_x: 580}
        new_scroll = ScrollReducer.handle_wheel_x(scroll, 5)
        {:ok, Map.merge(context, %{right_scroll: new_scroll})}
      end

      then_ "both are clamped appropriately", context do
        assert context.left_scroll.offset_x == 0,
          "left scroll should be clamped to 0"
        assert context.right_scroll.offset_x == 600,
          "right scroll should be clamped to max (1000-400=600)"
        :ok
      end
    end
  end

  spex "ScrollReducer - 2D Scrolling",
    description: "Tests bidirectional scroll behavior",
    tags: [:scroll, :both] do

    scenario "2D scroll updates both axes", context do
      given_ "a bidirectional scroll state", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 1000,
          content_height: 800,
          direction: :both
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll in both directions simultaneously", context do
        new_scroll = ScrollReducer.handle_wheel_2d(context.scroll, 1, 1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "both offsets change", context do
        assert context.new_scroll.offset_x == 40,
          "offset_x should increase"
        assert context.new_scroll.offset_y == 40,
          "offset_y should increase"
        :ok
      end
    end

    scenario "2D scroll clamps both axes independently", context do
      given_ "a scroll state near boundaries", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 500,  # max_x = 100
          content_height: 400, # max_y = 100
          direction: :both
        )
        scroll = %{scroll | offset_x: 90, offset_y: 90}
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll past both boundaries", context do
        # Try to scroll +80 on each axis, but max is 100
        new_scroll = ScrollReducer.scroll_by(context.scroll, 80, 80)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "each axis is clamped to its own max", context do
        assert context.new_scroll.offset_x == 100,
          "offset_x clamped to max (100)"
        assert context.new_scroll.offset_y == 100,
          "offset_y clamped to max (100)"
        :ok
      end
    end
  end

  spex "ScrollReducer - Shift+Scroll Axis Swapping",
    description: "Tests Shift key modifier for horizontal scrolling",
    tags: [:scroll, :shift, :smart] do

    scenario "Normal scroll without shift (vertical)", context do
      given_ "a bidirectional scroll state without shift held", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 1000,
          content_height: 800,
          direction: :both
        )
        assert scroll.shift_held == false, "shift should not be held by default"
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we use smart scroll with vertical input", context do
        # Normal vertical scroll (dx=0, dy=1)
        new_scroll = ScrollReducer.handle_wheel_smart(context.scroll, 0, 1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "vertical axis is affected normally", context do
        assert context.new_scroll.offset_x == 0,
          "offset_x should remain 0"
        assert context.new_scroll.offset_y == 40,
          "offset_y should increase by scroll_speed"
        :ok
      end
    end

    scenario "Shift+scroll converts vertical to horizontal", context do
      given_ "a bidirectional scroll state with shift held", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 1000,
          content_height: 800,
          direction: :both
        )
        scroll = ScrollReducer.set_shift_held(scroll, true)
        assert scroll.shift_held == true, "shift should be held"
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we use smart scroll with vertical input", context do
        # Vertical scroll input (dx=0, dy=1) should become horizontal
        new_scroll = ScrollReducer.handle_wheel_smart(context.scroll, 0, 1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "horizontal axis is affected instead", context do
        assert context.new_scroll.offset_x == 40,
          "offset_x should increase (vertical converted to horizontal)"
        assert context.new_scroll.offset_y == 0,
          "offset_y should remain 0"
        :ok
      end
    end

    scenario "Shift+scroll with vertical-only direction does NOT swap", context do
      given_ "a vertical-only scroll state with shift held", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 1000,
          content_height: 800,
          direction: :vertical  # Vertical only!
        )
        scroll = ScrollReducer.set_shift_held(scroll, true)
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we use smart scroll with vertical input", context do
        new_scroll = ScrollReducer.handle_wheel_smart(context.scroll, 0, 1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "vertical axis is affected (no swap for vertical-only)", context do
        assert context.new_scroll.offset_x == 0,
          "offset_x should remain 0 (vertical-only ignores shift swap)"
        assert context.new_scroll.offset_y == 40,
          "offset_y should increase normally"
        :ok
      end
    end

    scenario "Shift+scroll with horizontal-only direction DOES swap", context do
      given_ "a horizontal-only scroll state with shift held", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 1000,
          content_height: 800,
          direction: :horizontal
        )
        scroll = ScrollReducer.set_shift_held(scroll, true)
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we use smart scroll with vertical input", context do
        new_scroll = ScrollReducer.handle_wheel_smart(context.scroll, 0, 1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "horizontal axis is affected (swap works)", context do
        assert context.new_scroll.offset_x == 40,
          "offset_x should increase (vertical swapped to horizontal)"
        assert context.new_scroll.offset_y == 0,
          "offset_y should remain 0"
        :ok
      end
    end

    scenario "Toggle shift state on and off", context do
      given_ "a scroll state", context do
        scroll = create_scroll(direction: :both)
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we toggle shift on then off", context do
        scroll_on = ScrollReducer.set_shift_held(context.scroll, true)
        scroll_off = ScrollReducer.set_shift_held(scroll_on, false)
        {:ok, Map.merge(context, %{scroll_on: scroll_on, scroll_off: scroll_off})}
      end

      then_ "shift state reflects the changes", context do
        assert context.scroll.shift_held == false, "initial state: shift off"
        assert context.scroll_on.shift_held == true, "after set true: shift on"
        assert context.scroll_off.shift_held == false, "after set false: shift off"
        :ok
      end
    end

    scenario "Shift+scroll combines dx and dy for horizontal", context do
      given_ "a bidirectional scroll state with shift held", context do
        scroll = create_scroll(
          viewport_width: 400,
          content_width: 1000,
          direction: :both
        )
        scroll = ScrollReducer.set_shift_held(scroll, true)
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we use smart scroll with both dx and dy input", context do
        # Both dx=1 and dy=1 should combine for horizontal
        new_scroll = ScrollReducer.handle_wheel_smart(context.scroll, 1, 1)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "horizontal gets combined input", context do
        # (dy + dx) * scroll_speed = (1 + 1) * 40 = 80
        assert context.new_scroll.offset_x == 80,
          "offset_x should be (dy + dx) * scroll_speed = 80"
        assert context.new_scroll.offset_y == 0,
          "offset_y should remain 0"
        :ok
      end
    end
  end

  spex "ScrollReducer - Scroll To Show",
    description: "Tests auto-scroll to make rectangles visible",
    tags: [:scroll, :scroll_to_show] do

    scenario "Scroll to show rect below viewport", context do
      given_ "a scroll state at the top", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll to show a rect below the viewport", context do
        # Target rect at y=500, height=50 (bottom at 550)
        new_scroll = ScrollReducer.scroll_to_show(context.scroll, {0, 500, 100, 50})
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "viewport scrolls to show the rect", context do
        # To show rect ending at y=550, offset should be 550 - 300 = 250
        assert context.new_scroll.offset_y == 250,
          "offset_y should scroll to show bottom of rect"
        :ok
      end
    end

    scenario "Scroll to show rect above viewport", context do
      given_ "a scroll state scrolled down", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        scroll = %{scroll | offset_y: 500}
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll to show a rect above the viewport", context do
        # Target rect at y=100, height=50
        new_scroll = ScrollReducer.scroll_to_show(context.scroll, {0, 100, 100, 50})
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "viewport scrolls up to show the rect", context do
        assert context.new_scroll.offset_y == 100,
          "offset_y should scroll to show top of rect"
        :ok
      end
    end

    scenario "Scroll to show with margin", context do
      given_ "a scroll state at the top", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll to show a rect with margin", context do
        # Target rect at y=500, height=50, margin=20
        new_scroll = ScrollReducer.scroll_to_show(context.scroll, {0, 500, 100, 50}, 20)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "viewport scrolls with extra margin", context do
        # To show rect ending at y=550 with margin 20, offset = (550+20) - 300 = 270
        assert context.new_scroll.offset_y == 270,
          "offset_y should include margin"
        :ok
      end
    end

    scenario "Already visible rect does not scroll", context do
      given_ "a scroll state with rect in view", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        scroll = %{scroll | offset_y: 100}
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll to show a rect already visible", context do
        # Target rect at y=150, height=50 (visible when offset is 100-400)
        new_scroll = ScrollReducer.scroll_to_show(context.scroll, {0, 150, 100, 50})
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "offset does not change", context do
        assert context.new_scroll.offset_y == 100,
          "offset_y should not change for visible rect"
        :ok
      end
    end
  end

  spex "ScrollReducer - Content Size Changes",
    description: "Tests behavior when content size changes",
    tags: [:scroll, :content_size] do

    scenario "Shrinking content clamps scroll position", context do
      given_ "a scroll state scrolled to the bottom", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        # Scroll to bottom (max = 700)
        scroll = %{scroll | offset_y: 700}
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "content height shrinks", context do
        # Content shrinks to 500 (new max = 200)
        new_scroll = ScrollState.update_content_size(context.scroll, 400, 500)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "scroll position is clamped to new max", context do
        assert context.new_scroll.offset_y == 200,
          "offset_y should be clamped to new max (500-300=200)"
        :ok
      end
    end

    scenario "Content smaller than viewport has no scroll", context do
      given_ "a scroll state", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 200,  # Smaller than viewport
          direction: :vertical
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we try to scroll", context do
        new_scroll = ScrollReducer.handle_wheel(context.scroll, 5)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "scroll position remains at 0", context do
        assert context.new_scroll.offset_y == 0,
          "offset_y should remain 0 when content fits in viewport"
        :ok
      end
    end
  end

  spex "ScrollReducer - Input Normalization",
    description: "Tests various Scenic input format normalization",
    tags: [:scroll, :input] do

    scenario "Normalize 4-tuple format", context do
      given_ "a cursor_scroll event in 4-tuple format", context do
        input = {:cursor_scroll, {1.0, -1.0, 100.0, 200.0}}
        {:ok, Map.put(context, :input, input)}
      end

      when_ "we normalize the input", context do
        result = ScrollReducer.normalize_input(context.input)
        {:ok, Map.put(context, :result, result)}
      end

      then_ "we get dx and dy", context do
        assert context.result == {1.0, -1.0},
          "should extract dx and dy from 4-tuple"
        :ok
      end
    end

    scenario "Normalize nested tuple format", context do
      given_ "a cursor_scroll event in nested format", context do
        input = {:cursor_scroll, {{0.0, -1.0}, {137.0, 109.0}}}
        {:ok, Map.put(context, :input, input)}
      end

      when_ "we normalize the input", context do
        result = ScrollReducer.normalize_input(context.input)
        {:ok, Map.put(context, :result, result)}
      end

      then_ "we get dx and dy", context do
        assert context.result == {0.0, -1.0},
          "should extract dx and dy from nested tuple"
        :ok
      end
    end

    scenario "Normalize simple 2-tuple format", context do
      given_ "a cursor_scroll event in 2-tuple format", context do
        input = {:cursor_scroll, {1.5, -0.5}}
        {:ok, Map.put(context, :input, input)}
      end

      when_ "we normalize the input", context do
        result = ScrollReducer.normalize_input(context.input)
        {:ok, Map.put(context, :result, result)}
      end

      then_ "we get dx and dy", context do
        assert context.result == {1.5, -0.5},
          "should extract dx and dy from 2-tuple"
        :ok
      end
    end

    scenario "Unknown format returns nil", context do
      given_ "an unknown input format", context do
        input = {:something_else, "data"}
        {:ok, Map.put(context, :input, input)}
      end

      when_ "we normalize the input", context do
        result = ScrollReducer.normalize_input(context.input)
        {:ok, Map.put(context, :result, result)}
      end

      then_ "we get nil", context do
        assert context.result == nil,
          "should return nil for unknown format"
        :ok
      end
    end
  end

  spex "ScrollReducer - Changed Detection",
    description: "Tests scroll state change detection",
    tags: [:scroll, :changed] do

    scenario "Detect offset change", context do
      given_ "two scroll states with different offsets", context do
        scroll1 = create_scroll(direction: :vertical)
        scroll2 = %{scroll1 | offset_y: 100}
        {:ok, Map.merge(context, %{scroll1: scroll1, scroll2: scroll2})}
      end

      when_ "we check if they changed", context do
        changed = ScrollReducer.changed?(context.scroll1, context.scroll2)
        offset_changed = ScrollReducer.offset_changed?(context.scroll1, context.scroll2)
        {:ok, Map.merge(context, %{changed: changed, offset_changed: offset_changed})}
      end

      then_ "change is detected", context do
        assert context.changed == true, "changed? should be true"
        assert context.offset_changed == true, "offset_changed? should be true"
        :ok
      end
    end

    scenario "Detect visibility change", context do
      given_ "two scroll states with different visibility", context do
        scroll1 = create_scroll(direction: :vertical)
        scroll2 = ScrollReducer.show_scrollbars(scroll1)
        {:ok, Map.merge(context, %{scroll1: scroll1, scroll2: scroll2})}
      end

      when_ "we check if they changed", context do
        changed = ScrollReducer.changed?(context.scroll1, context.scroll2)
        offset_changed = ScrollReducer.offset_changed?(context.scroll1, context.scroll2)
        {:ok, Map.merge(context, %{changed: changed, offset_changed: offset_changed})}
      end

      then_ "only general change is detected", context do
        assert context.changed == true, "changed? should be true (visibility changed)"
        assert context.offset_changed == false, "offset_changed? should be false (offset same)"
        :ok
      end
    end

    scenario "No change for identical states", context do
      given_ "two identical scroll states", context do
        scroll1 = create_scroll(direction: :vertical)
        scroll2 = scroll1
        {:ok, Map.merge(context, %{scroll1: scroll1, scroll2: scroll2})}
      end

      when_ "we check if they changed", context do
        changed = ScrollReducer.changed?(context.scroll1, context.scroll2)
        {:ok, Map.put(context, :changed, changed)}
      end

      then_ "no change is detected", context do
        assert context.changed == false, "changed? should be false for identical states"
        :ok
      end
    end
  end

  spex "ScrollReducer - Navigation Functions",
    description: "Tests scroll_to_top, scroll_to_bottom, etc.",
    tags: [:scroll, :navigation] do

    scenario "Scroll to top", context do
      given_ "a scroll state scrolled down", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        scroll = %{scroll | offset_y: 500}
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll to top", context do
        new_scroll = ScrollReducer.scroll_to_top(context.scroll)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "offset_y is 0", context do
        assert context.new_scroll.offset_y == 0,
          "offset_y should be 0 after scroll_to_top"
        :ok
      end
    end

    scenario "Scroll to bottom", context do
      given_ "a scroll state at the top", context do
        scroll = create_scroll(
          viewport_height: 300,
          content_height: 1000,
          direction: :vertical
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll to bottom", context do
        new_scroll = ScrollReducer.scroll_to_bottom(context.scroll)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "offset_y is at max", context do
        assert context.new_scroll.offset_y == 700,
          "offset_y should be max (1000-300=700)"
        :ok
      end
    end

    scenario "Scroll to specific position", context do
      given_ "a scroll state", context do
        scroll = create_scroll(
          viewport_width: 400,
          viewport_height: 300,
          content_width: 1000,
          content_height: 800,
          direction: :both
        )
        {:ok, Map.put(context, :scroll, scroll)}
      end

      when_ "we scroll to a specific position", context do
        new_scroll = ScrollReducer.scroll_to(context.scroll, 200, 150)
        {:ok, Map.put(context, :new_scroll, new_scroll)}
      end

      then_ "both offsets are set", context do
        assert context.new_scroll.offset_x == 200,
          "offset_x should be 200"
        assert context.new_scroll.offset_y == 150,
          "offset_y should be 150"
        :ok
      end
    end
  end
end
