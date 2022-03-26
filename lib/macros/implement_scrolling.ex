defmodule ScenicWidgets.Macros.ImplementScrolling do
  @moduledoc """
  Use this macro inside a Scenic component to automatically add
  vertical scrolling.

  Use it like this:


  ```
  ScenicWidgets.Macros.VerticalScroll
  ```

  Just remember, you still need to request the input, this has to be
  done inside `init/3` (maybe I will use a continue or something, I
  dunno, it's not that big of a deal).

  Inside the `init/3` for the component using this macro, do this:

  ```
  request_input(new_scene, [:cursor_scroll])
  ```

  """
  defmacro __using__(_params) do
    quote do
      # minimum scroll, which we can't go below
      @min_position_cap {0, 0}
      # how much gap to put between each item in the layout
      @spacing_buffer 25

      def handle_cast(
            {:new_component_bounds, {id, bounds} = new_component_bounds},
            %{assigns: %{state: state}} = scene
          ) do
        # this callback is received when a component boots successfully -
        # it register itself to this component (parent-child relationship,
        # which ought to be able to handle props aswell!) including it's
        # own size (since I want TidBits to grow organizally based on their
        # size, and only wrap/clip in the most extreme circumstancses and/or
        # boundary conditions)

        # NOTE: This callback `:new_component_bounds` is only useful
        #      for keping track of all the scrollable components. If
        #      you need something else to happen when a sub-component
        #      finished rendering (like say, rendering the next item,
        #      in a list layout if these items were dynamically large)
        #      then you will need to make your Components send _additional_
        #      messages to the parent component, triggering whatever
        #      other event it is you want to trigger on completion of
        #      the sub-component rendering. This callback does not assume
        #      responsibility for forwarding messages or any other messiness.

        new_scroll_state =
          state.scroll
          |> Map.put(:components, state.scroll.components ++ [new_component_bounds])

        new_state = %{state | scroll: new_scroll_state}

        {:noreply, new_state}
      end

      def handle_input(
            {:cursor_scroll, {{_x_scroll, y_scroll} = delta_scroll, coords}},
            _context,
            %{
              assigns: %{
                state:
                  %{
                    scroll: %{
                      accumulator: {_x, _y} = current_scroll,
                      direction: :vertical
                    }
                  } = current_state
              }
            } = scene
          ) do
        # IO.puts "YESYES"
        # fast_scroll = {0, 3 * y_scroll}

        # new_cumulative_scroll =
        #     cap_position(scene, Scenic.Math.Vector2.add(current_scroll, fast_scroll))

        # new_scroll_state =
        #     scene.assigns.state.scroll |> Map.put(:accumulator, new_cumulative_scroll)

        # new_state = %{current_state | scroll: new_scroll_state}

        # new_graph = scene.assigns.graph
        #   |> IO.inspect
        #   |> Scenic.Graph.modify(
        #     __MODULE__,
        #     &Scenic.Primitives.update_opts(&1, translate: new_state.scroll.accumulator)
        #   )
        #   |> IO.inspect

        # new_scene = scene
        #   |> assign(graph: new_graph)
        #   |> assign(state: new_state)
        #   |> push_graph(new_graph)

        {:noreply, new_scene}
      end

      def handle_input({:cursor_scroll, {_delta_scroll, _coords}}, _context, scene) do
        Logger.error("#{__MODULE__} received :scroll, but it does not have a `state.scroll`")
        IO.inspect(scene)
        {:noreply, scene}
      end

      # <3 @vacarsu
      def cap_position(%{assigns: %{frame: frame}} = scene, coord) do
        # NOTE: We must keep track of components, because one could
        #      get yanked out the middle.
        height = calc_acc_height(scene)
        # height = scene.assigns.state.scroll.acc_length
        if height > frame.dimensions.height do
          coord
          |> calc_floor({0, -height + frame.dimensions.height / 2})
          |> calc_ceil({0, 0})
        else
          coord
          |> calc_floor(@min_position_cap)
          |> calc_ceil(@min_position_cap)
        end
      end

      def calc_acc_height(%{assigns: %{state: %{scroll: %{components: components}}}}) do
        do_calc_acc_height(0, components)
      end

      def do_calc_acc_height(acc, []), do: acc

      def do_calc_acc_height(acc, [{_id, bounds} = c | rest]) do
        # top is less than bottom, because the axis starts in top-left corner
        {_left, top, _right, bottom} = bounds
        component_height = bottom - top

        new_acc = acc + component_height + @spacing_buffer
        do_calc_acc_height(new_acc, rest)
      end

      defp calc_floor({x, y}, {min_x, min_y}), do: {max(x, min_x), max(y, min_y)}

      defp calc_ceil({x, y}, {max_x, max_y}), do: {min(x, max_x), min(y, max_y)}
    end

    # do quote
  end

  # do defmacro
end

# do defmodule
