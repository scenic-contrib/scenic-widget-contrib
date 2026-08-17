defmodule ScenicWidgets.MenuBar.MenuActionsSpex do
  @moduledoc """
  MenuBar Actions and Closing-Behavior Specification

  ## Purpose
  Verifies that:
  1. Clicking a menu item executes its action callback and closes the menu
  2. Different items trigger their own distinct actions
  3. Pressing Escape closes an open dropdown
  4. Clicking outside the menu bar closes an open dropdown

  ## Action verification strategy
  `ScenicWidgets.MenuBar` supports a 3-tuple item format,
  `{item_id, label, action_fun}`, documented in its moduledoc: the callback
  runs synchronously when the item is clicked. Each item here closes over the
  spex process's own pid so the fired action can be observed deterministically
  with `assert_receive`, instead of only inferring success from the dropdown
  closing.
  """

  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  defp menu_map(test_pid) do
    [
      {:sub_menu, "File",
       [
         {"new_file", "New File", fn -> send(test_pid, {:menu_action, :new_file}) end},
         {"quit", "Quit", fn -> send(test_pid, {:menu_action, :quit}) end}
       ]},
      {:sub_menu, "Edit", [{"undo", "Undo", fn -> send(test_pid, {:menu_action, :undo}) end}]}
    ]
  end

  defp load_menu_bar do
    frame = Widgex.Frame.new(pin: {0, 0}, size: {300, 40})
    data = %{frame: frame, menu_map: menu_map(self())}

    WidgetWorkbench.Scene.load_component("Menu Bar", ScenicWidgets.MenuBar, data)
    Process.sleep(400)
  end

  spex "MenuBar item actions and dropdown-closing behavior",
    description: "Verifies clicked items fire their action and menus close on Escape/outside-click",
    tags: [:menu_bar, :actions, :keyboard] do
    scenario "Clicking a menu item executes its action and closes the menu", context do
      given_ "the File dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        assert Query.text_visible?("New File")
        {:ok, context}
      end

      when_ "we click the New File item", context do
        Probes.click_element("menu_file_new_file")
        {:ok, context}
      end

      then_ "the New File action fires and the dropdown closes" do
        assert_receive {:menu_action, :new_file}, 500
        refute Query.text_visible?("New File"), "File dropdown should close after clicking an item"

        :ok
      end
    end

    scenario "Different menu items fire their own distinct actions", context do
      given_ "the File dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        assert Query.text_visible?("Quit")
        {:ok, context}
      end

      when_ "we click the Quit item", context do
        Probes.click_element("menu_file_quit")
        {:ok, context}
      end

      then_ "the Quit action fires (and not New File's)" do
        assert_receive {:menu_action, :quit}, 500
        refute_received {:menu_action, :new_file}

        :ok
      end
    end

    scenario "Pressing Escape closes an open dropdown", context do
      given_ "the Edit dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_edit")
        Process.sleep(200)
        assert Query.text_visible?("Undo")
        {:ok, context}
      end

      when_ "we press Escape", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the dropdown closes without firing any action" do
        refute Query.text_visible?("Undo"), "Edit dropdown should close on Escape"
        refute_received {:menu_action, _}

        :ok
      end
    end

    scenario "Clicking outside the menu bar closes an open dropdown", context do
      given_ "the File dropdown is open", context do
        load_menu_bar()
        Probes.click_element("menu_file")
        Process.sleep(200)
        assert Query.text_visible?("New File")
        {:ok, context}
      end

      when_ "we click far outside the menu bar and its dropdown", context do
        Probes.click(500, 400)
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the dropdown closes without firing any action" do
        refute Query.text_visible?("New File"), "File dropdown should close on an outside click"
        refute_received {:menu_action, _}

        :ok
      end
    end
  end
end
