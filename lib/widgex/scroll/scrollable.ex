defmodule Widgex.Scrollable do
  @moduledoc """
  Macro-based scrolling behavior for Scenic components.

  Add `use Widgex.Scrollable` to your component's State, Reducer, or Renderer
  modules to get scroll-related functions injected.

  ## Quick Start

  1. Add scroll state to your component:

      ```elixir
      defmodule MyComponent.State do
        use Widgex.Scrollable, direction: :vertical

        defstruct [:frame, :items, :scroll]

        def new(%{frame: frame, items: items}) do
          content_height = length(items) * 60

          %__MODULE__{
            frame: frame,
            items: items,
            scroll: init_scroll(frame, content_height: content_height)
          }
        end
      end
      ```

  2. Handle scroll input in your reducer:

      ```elixir
      defmodule MyComponent.Reducer do
        use Widgex.Scrollable

        def process_input(state, {:cursor_scroll, {_dx, dy, _x, _y}}) do
          new_scroll = handle_scroll(state.scroll, dy)
          {:noop, %{state | scroll: new_scroll}}
        end
      end
      ```

  3. Render scrollable content:

      ```elixir
      defmodule MyComponent.Renderer do
        use Widgex.Scrollable

        def initial_render(graph, state) do
          graph
          |> scrollable_group(state.scroll, state.frame, fn g ->
            render_items(g, state)
          end, id: :content)
          |> render_scrollbars(state.scroll, state.frame)
        end
      end
      ```

  ## Options

    * `:direction` - Default scroll direction: `:vertical`, `:horizontal`, or `:both`
    * `:scroll_speed` - Default pixels per scroll tick (default: 40)

  ## Available Functions

  After `use Widgex.Scrollable`, these functions are available:

  ### State Functions
    * `init_scroll/2` - Create scroll state from frame
    * `update_content_size/3` - Update content dimensions

  ### Reducer Functions
    * `handle_scroll/2` - Process scroll wheel input
    * `scroll_to_show/3` - Auto-scroll to make rect visible
    * `scroll_changed?/2` - Check if scroll offset changed

  ### Renderer Functions
    * `scrollable_group/5` - Create scissored, translated group
    * `update_scroll_transform/4` - Update scroll position efficiently
    * `render_scrollbars/4` - Render scrollbar overlays
    * `update_scrollbars/4` - Update scrollbar position/visibility

  ## Scrollbar Fade Animation

  To enable fade-on-idle scrollbars, add this to your component:

      def handle_info(:scrollbar_fade, scene) do
        new_scroll = Widgex.Scroll.ScrollReducer.hide_scrollbars(scene.assigns.state.scroll)
        new_state = %{scene.assigns.state | scroll: new_scroll}
        # Update graph and push...
      end

  And schedule the timer after scrolling:

      # In your scroll handler, after updating state:
      if state.scroll.scrollbar_fade_timer do
        Process.cancel_timer(state.scroll.scrollbar_fade_timer)
      end
      timer = Process.send_after(self(), :scrollbar_fade, Widgex.Scroll.ScrollState.fade_delay())
      %{state | scroll: %{state.scroll | scrollbar_fade_timer: timer}}
  """

  alias Widgex.Scroll.{ScrollState, ScrollReducer, ScrollRenderer}

  defmacro __using__(opts \\ []) do
    quote location: :keep, bind_quoted: [opts: opts] do
      # Store options as module attributes for default values
      @scroll_direction Keyword.get(opts, :direction, :vertical)
      @scroll_speed Keyword.get(opts, :scroll_speed, 40)

      # Import aliases for cleaner code
      alias Widgex.Scroll.ScrollState
      alias Widgex.Scroll.ScrollReducer
      alias Widgex.Scroll.ScrollRenderer
      alias Widgex.Frame

      # ============================================================
      # State Functions
      # ============================================================

      @doc """
      Initialize scroll state from a frame.

      Uses module defaults for direction and speed unless overridden in opts.

      ## Options

        * `:content_width` - Width of scrollable content
        * `:content_height` - Height of scrollable content
        * `:direction` - Override default direction
        * `:scroll_speed` - Override default scroll speed

      ## Example

          scroll = init_scroll(frame, content_height: 1000)
      """
      def init_scroll(%Frame{} = frame, opts \\ []) do
        opts =
          opts
          |> Keyword.put_new(:direction, @scroll_direction)
          |> Keyword.put_new(:scroll_speed, @scroll_speed)

        ScrollState.new(frame, opts)
      end

      @doc """
      Update the content size in scroll state.

      Call this when content changes (items added/removed, etc.)
      """
      def update_content_size(%ScrollState{} = scroll, width, height) do
        ScrollState.update_content_size(scroll, width, height)
      end

      # ============================================================
      # Reducer Functions
      # ============================================================

      @doc """
      Handle scroll wheel input and update scroll state (vertical only).

      Returns updated scroll state with scrollbars shown.

      ## Example

          def process_input(state, {:cursor_scroll, {_dx, dy, _x, _y}}) do
            new_scroll = handle_scroll(state.scroll, dy)
            {:noop, %{state | scroll: new_scroll}}
          end
      """
      def handle_scroll(%ScrollState{} = scroll, delta_y) do
        ScrollReducer.handle_wheel(scroll, delta_y)
      end

      @doc """
      Handle horizontal scroll input.
      """
      def handle_scroll_x(%ScrollState{} = scroll, delta_x) do
        ScrollReducer.handle_wheel_x(scroll, delta_x)
      end

      @doc """
      Handle 2D scroll input (both horizontal and vertical).

      For trackpads or when direction is :both, use this to handle both axes.

      ## Example

          def process_input(state, {:cursor_scroll, {{dx, dy}, _coords}}) do
            new_scroll = handle_scroll_2d(state.scroll, dx, dy)
            {:noop, %{state | scroll: new_scroll}}
          end
      """
      def handle_scroll_2d(%ScrollState{} = scroll, delta_x, delta_y) do
        ScrollReducer.handle_wheel_2d(scroll, delta_x, delta_y)
      end

      @doc """
      Smart scroll handling that respects Shift key state.

      When Shift is held and direction supports horizontal scrolling,
      vertical scroll input is converted to horizontal scrolling.
      This enables Shift+scroll for horizontal scrolling.

      ## Example

          def process_input(state, {:cursor_scroll, {{dx, dy}, _coords}}) do
            new_scroll = handle_scroll_smart(state.scroll, dx, dy)
            {:noop, %{state | scroll: new_scroll}}
          end
      """
      def handle_scroll_smart(%ScrollState{} = scroll, delta_x, delta_y) do
        ScrollReducer.handle_wheel_smart(scroll, delta_x, delta_y)
      end

      @doc """
      Set the Shift key held state for scroll behavior.

      Call this when handling Shift key press/release events.

      ## Example

          # On Shift press
          def process_input(state, {:key, {:key_leftshift, 1, _}}) do
            new_scroll = set_scroll_shift(state.scroll, true)
            {:noop, %{state | scroll: new_scroll}}
          end

          # On Shift release
          def process_input(state, {:key, {:key_leftshift, 0, _}}) do
            new_scroll = set_scroll_shift(state.scroll, false)
            {:noop, %{state | scroll: new_scroll}}
          end
      """
      def set_scroll_shift(%ScrollState{} = scroll, held) do
        ScrollReducer.set_shift_held(scroll, held)
      end

      @doc """
      Scroll to make a rectangle visible within the viewport.

      Useful for ensuring selected items or cursor positions are visible.

      ## Example

          # Ensure cursor line is visible
          scroll = scroll_to_show(state.scroll, {0, cursor_y, width, line_height}, 10)
      """
      def scroll_to_show(%ScrollState{} = scroll, rect, margin \\ 0) do
        ScrollReducer.scroll_to_show(scroll, rect, margin)
      end

      @doc """
      Check if scroll state has changed (for determining re-render needs).
      """
      def scroll_changed?(%ScrollState{} = old_scroll, %ScrollState{} = new_scroll) do
        ScrollReducer.changed?(old_scroll, new_scroll)
      end

      @doc """
      Show scrollbars (full opacity).
      """
      def show_scrollbars(%ScrollState{} = scroll) do
        ScrollReducer.show_scrollbars(scroll)
      end

      @doc """
      Hide scrollbars (zero opacity).
      """
      def hide_scrollbars(%ScrollState{} = scroll) do
        ScrollReducer.hide_scrollbars(scroll)
      end

      # ============================================================
      # Renderer Functions
      # ============================================================

      @doc """
      Create a scrollable group with scissor clipping.

      The content function receives the graph and should add content primitives.

      ## Options

        * `:id` - ID for the scroll group (required for updates)

      ## Example

          graph
          |> scrollable_group(state.scroll, state.frame, fn g ->
            g |> Primitives.text("Hello", translate: {0, 20})
          end, id: :content)
      """
      def scrollable_group(graph, %ScrollState{} = scroll, %Frame{} = frame, content_fn, opts \\ []) do
        ScrollRenderer.scrollable_group(graph, scroll, frame, content_fn, opts)
      end

      @doc """
      Update the scroll transform on an existing group.

      Uses Graph.modify for efficient updates without re-rendering content.
      """
      def update_scroll_transform(graph, group_id, %ScrollState{} = old_scroll, %ScrollState{} = new_scroll) do
        ScrollRenderer.update_scroll_transform(graph, group_id, old_scroll, new_scroll)
      end

      @doc """
      Render scrollbars based on current scroll state.

      ## Options

        * `:color` - Scrollbar color as `{r, g, b}` tuple
      """
      def render_scrollbars(graph, %ScrollState{} = scroll, %Frame{} = frame, opts \\ []) do
        ScrollRenderer.render_scrollbars(graph, scroll, frame, opts)
      end

      @doc """
      Update scrollbar position and visibility.
      """
      def update_scrollbars(graph, %ScrollState{} = old_scroll, %ScrollState{} = new_scroll, %Frame{} = frame, opts \\ []) do
        ScrollRenderer.update_scrollbars(graph, old_scroll, new_scroll, frame, opts)
      end

      @doc """
      Update only the scrollbar visibility/opacity (for fade animation).
      """
      def update_scrollbar_visibility(graph, %ScrollState{} = scroll, opts \\ []) do
        ScrollRenderer.update_scrollbar_visibility(graph, scroll, opts)
      end
    end
  end
end
