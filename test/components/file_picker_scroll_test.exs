defmodule ScenicWidgets.FilePicker.ScrollTest do
  use ExUnit.Case, async: true

  alias ScenicWidgets.FilePicker.{Reducer, State}
  alias Widgex.Scroll.ScrollState

  test "wheel-down moves the file list toward later entries" do
    scroll = %ScrollState{
      offset_y: 100,
      content_height: 1_000,
      viewport_height: 200,
      direction: :vertical,
      scroll_speed: 40
    }

    state = %State{scroll: scroll}

    assert {:state, updated} =
             Reducer.process_input(state, {:cursor_scroll, {{0, -1}, {20, 20}}})

    assert updated.scroll.offset_y > scroll.offset_y
  end

  test "location shortcuts navigate to project, home, and disk roots" do
    temp_root = System.tmp_dir!()
    project_root = Path.join(temp_root, "file-picker-project")
    home_path = Path.join(temp_root, "file-picker-home")
    File.mkdir_p!(project_root)
    File.mkdir_p!(home_path)

    state =
      State.new(%{
        frame: Widgex.Frame.new(pin: {0, 0}, size: {640, 480}),
        start_path: temp_root,
        project_root: project_root,
        home_path: home_path
      })

    assert {:state, project_state} = Reducer.process_event(:project_root_button, state)
    assert project_state.current_path == Path.expand(project_root)

    assert {:state, home_state} = Reducer.process_event(:home_button, state)
    assert home_state.current_path == Path.expand(home_path)

    assert {:state, disk_state} = Reducer.process_event(:disk_root_button, state)
    assert disk_state.current_path == state.disk_root
  end

  test "defaults the picker and project shortcut to the current working directory" do
    state = State.new(%{frame: Widgex.Frame.new(pin: {0, 0}, size: {640, 480})})

    assert state.current_path == File.cwd!()
    assert state.project_root == Path.expand(File.cwd!())
    assert state.home_path == Path.expand(System.user_home!())
    assert File.dir?(state.disk_root)
  end

  test "shows the shared scrollbar immediately when a directory overflows" do
    path =
      Path.join(System.tmp_dir!(), "file-picker-scroll-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    for index <- 1..8, do: File.write!(Path.join(path, "file-#{index}.txt"), "")

    state =
      State.new(%{
        frame: Widgex.Frame.new(pin: {0, 0}, size: {640, 500}),
        start_path: path
      })

    assert state.scroll.scrollbar_visible
    assert state.scroll.scrollbar_opacity == 255
  end
end
