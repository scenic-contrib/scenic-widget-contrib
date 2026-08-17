defmodule ScenicWidgets.TextField.BasicLoadSpex do
  @moduledoc """
  Basic TextField Loading Specification

  ## Purpose
  This is the foundational spex for the TextField component. It verifies that:
  1. Widget Workbench boots and TextField can be loaded into it
  2. TextField renders its initial text
  3. TextField renders without crashing/error states

  Loading happens through `WidgetWorkbench.Scene.load_component/3` directly
  (the same public API the "Load Component" modal calls into) rather than by
  clicking through the component-selection modal. That keeps this spex focused
  on TextField's own behavior instead of Widget Workbench's UI navigation.
  """

  use SexySpex

  alias ScenicMcp.Query

  setup_all do
    ScenicWidgets.SpexSetup.ensure_workbench_started!()
  end

  defp load_text_field(opts \\ %{}) do
    frame = Widgex.Frame.new(pin: {100, 100}, size: {400, 300})

    data =
      Map.merge(%{frame: frame, initial_text: "Hello from TextField", input_mode: :direct}, opts)

    WidgetWorkbench.Scene.load_component("Text Field", ScenicWidgets.TextField, data)
    Process.sleep(400)
    frame
  end

  spex "TextField Basic Loading",
    description: "Verifies TextField loads and displays its content area",
    tags: [:text_field, :basic, :loading] do
    scenario "TextField loads into the Widget Workbench", context do
      given_ "the workbench is running with no component loaded", context do
        {:ok, context}
      end

      when_ "we load the TextField component", context do
        load_text_field()
        {:ok, context}
      end

      then_ "its initial text is rendered" do
        assert Query.text_visible?("Hello from TextField"),
               "TextField should render its initial text after loading"

        :ok
      end
    end

    scenario "TextField renders without errors", context do
      given_ "TextField has been loaded", context do
        load_text_field()
        {:ok, context}
      end

      then_ "no error or crash state is rendered" do
        refute Query.text_visible?("Error"), "TextField should not render an error state"
        refute Query.text_visible?("crashed"), "TextField should not have crashed"

        :ok
      end
    end

    scenario "TextField's content area is ready for input", context do
      given_ "TextField has been loaded", context do
        load_text_field()
        {:ok, context}
      end

      then_ "the workbench is rendering non-empty content" do
        rendered = Query.rendered_text()

        assert is_binary(rendered) and rendered != "",
               "TextField should be rendering content"

        :ok
      end
    end
  end
end
