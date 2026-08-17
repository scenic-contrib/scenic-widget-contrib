defmodule ScenicWidgets.SideNav.StateTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.SideNav.{Item, State}
  alias Widgex.Frame

  test "reserves bottom clearance only when horizontal scrolling is present" do
    item = %Item{id: "wide", title: String.duplicate("wide ", 20), type: :page}

    narrow_state = State.new(%{frame: Frame.new(pin: {0, 0}, size: {100, 100}), tree: [item]})
    wide_state = State.new(%{frame: Frame.new(pin: {0, 0}, size: {1_000, 100}), tree: [item]})

    assert narrow_state.scroll.content_width > narrow_state.scroll.viewport_width
    assert narrow_state.scroll.content_height == 48

    assert wide_state.scroll.content_width <= wide_state.scroll.viewport_width
    assert wide_state.scroll.content_height == 28
  end

  test "shows scrollbars as soon as expansion makes the tree overflow" do
    children =
      for index <- 1..10 do
        %Item{id: "file-#{index}", title: "file-#{index}", type: :page}
      end

    directory = %Item{id: "dir", title: "dir", type: :group, children: children}
    state = State.new(%{frame: Frame.new(pin: {0, 0}, size: {200, 100}), tree: [directory]})

    refute state.scroll.scrollbar_visible
    assert state.scroll.scrollbar_opacity == 0

    expanded = State.toggle_expanded(state, "dir")

    assert expanded.scroll.content_height > expanded.scroll.viewport_height
    assert expanded.scroll.scrollbar_visible
    assert expanded.scroll.scrollbar_opacity == 255
  end

  test "collapsed descendants do not create phantom horizontal overflow" do
    long_child = %Item{
      id: "long-child",
      title: String.duplicate("very-long-name-", 8),
      type: :page
    }

    directory = %Item{id: "dir", title: "dir", type: :group, children: [long_child]}
    state = State.new(%{frame: Frame.new(pin: {0, 0}, size: {250, 120}), tree: [directory]})

    assert state.scroll.content_width <= state.scroll.viewport_width
    assert state.scroll.content_height == 28

    expanded = State.toggle_expanded(state, "dir")

    assert expanded.scroll.content_width > expanded.scroll.viewport_width
    assert expanded.scroll.content_height == 76
  end

  test "vertical scrollbar adds end clearance to an existing horizontal overflow" do
    long_title = String.duplicate("wide-", 12)
    wide_item = %Item{id: "wide", title: long_title, type: :page}
    frame = Frame.new(pin: {0, 0}, size: {200, 100})

    horizontal_only = State.new(%{frame: frame, tree: [wide_item]})

    both_axes =
      State.new(%{
        frame: frame,
        tree: [wide_item | for(index <- 1..8, do: %Item{id: index, title: "short", type: :page})]
      })

    assert horizontal_only.scroll.content_width > horizontal_only.scroll.viewport_width
    assert horizontal_only.scroll.content_height <= horizontal_only.scroll.viewport_height
    assert both_axes.scroll.content_height > both_axes.scroll.viewport_height
    assert both_axes.scroll.content_width == horizontal_only.scroll.content_width + 16
  end

  test "plain, ctrl, and shift selection remain separate from the active item" do
    tree =
      for index <- 1..5 do
        %Item{id: "file-#{index}", title: "file-#{index}", type: :page}
      end

    state =
      State.new(%{
        frame: Frame.new(pin: {0, 0}, size: {200, 200}),
        tree: tree,
        active_id: "file-5"
      })

    one = State.select(state, "file-1")
    assert one.selected_ids == MapSet.new(["file-1"])
    assert one.active_id == "file-5"

    toggled = State.select(one, "file-3", [:ctrl])
    assert toggled.selected_ids == MapSet.new(["file-1", "file-3"])

    untoggled = State.select(toggled, "file-3", [:ctrl])
    assert untoggled.selected_ids == MapSet.new(["file-1"])

    anchored = State.select(one, "file-2")
    ranged = State.select(anchored, "file-4", [:shift])
    assert ranged.selected_ids == MapSet.new(["file-2", "file-3", "file-4"])
    assert ranged.active_id == "file-5"
  end

  test "driver-specific control and shift modifier names build visible selection" do
    tree =
      for index <- 1..4 do
        %Item{id: "file-#{index}", title: "file-#{index}", type: :page}
      end

    state = State.new(%{frame: Frame.new(pin: {0, 0}, size: {200, 200}), tree: tree})
    state = State.select(state, "file-1")
    state = State.select(state, "file-3", [:key_left_control])
    assert state.selected_ids == MapSet.new(["file-1", "file-3"])

    state = State.select(state, "file-4", [:key_left_shift])
    assert state.selected_ids == MapSet.new(["file-3", "file-4"])
  end

  test "tree refresh remaps expanded and selected paths after a directory move" do
    old_root = "/project/source"
    destination = "/project/target/source"
    old_child = Path.join(old_root, "child.txt")
    new_child = Path.join(destination, "child.txt")

    old_tree = [
      %Item{
        id: old_root,
        title: "source",
        type: :group,
        children: [%Item{id: old_child, title: "child.txt", type: :page}]
      }
    ]

    state =
      State.new(%{frame: Frame.new(pin: {0, 0}, size: {250, 200}), tree: old_tree})
      |> State.toggle_expanded(old_root)
      |> State.select(old_child)

    state = %{state | pending_path_moves: [{old_root, destination}]}

    new_tree = [
      %Item{
        id: destination,
        title: "source",
        type: :group,
        children: [%Item{id: new_child, title: "child.txt", type: :page}]
      }
    ]

    refreshed = ScenicWidgets.SideNav.Api.update_tree(state, new_tree)
    assert MapSet.member?(refreshed.expanded, destination)
    assert refreshed.selected_ids == MapSet.new([new_child])
    assert refreshed.selection_anchor == new_child
    assert refreshed.pending_path_moves == []
  end

  test "active id may arrive before a refreshed tree contains it" do
    state =
      State.new(%{
        frame: Frame.new(pin: {0, 0}, size: {200, 200}),
        tree: [%Item{id: "old.txt", title: "old.txt", type: :page}]
      })

    updated = State.set_active(state, "renamed.txt")

    assert updated.active_id == "renamed.txt"
    assert updated.expanded == state.expanded
  end
end
