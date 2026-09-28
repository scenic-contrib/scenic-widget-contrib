defmodule ScenicWidgets.DatePicker do
  @moduledoc """
  A date picker component for selecting dates.

  Displays a compact button showing the current date (or placeholder text).
  When clicked, shows a dropdown calendar for date selection.

  ## Usage

      DatePicker.add_to_graph(graph, %{
        frame: frame,
        id: :due_date,
        selected: ~D[2025-01-15],  # or nil
        placeholder: "Select due date"
      })

  ## Events

  Sends to parent:
  - `{:date_selected, id, %Date{}}` - When a date is selected
  - `{:date_cleared, id}` - When the date is cleared
  """

  use Scenic.Component, has_children: false
  require Logger

  import Scenic.Primitives
  alias Scenic.Graph
  alias Widgex.Frame

  # Colors
  @bg {50, 50, 60}
  @bg_hover {60, 60, 75}
  @bg_open {55, 55, 68}
  @border {80, 80, 95}
  @border_focus {100, 150, 200}
  @text_color :white
  @text_muted {150, 150, 150}
  @dropdown_bg {45, 48, 58}
  @day_bg {55, 55, 65}
  @day_hover {70, 80, 100}
  @day_selected {80, 120, 180}
  @day_today {70, 130, 100}
  @day_other_month {40, 40, 45}
  @nav_btn {60, 60, 70}
  @nav_btn_hover {75, 75, 90}
  @clear_btn {120, 60, 60}

  # Layout
  @dropdown_width 240
  @dropdown_height 260
  @day_cell_size 30
  @header_height 35

  @day_names ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

  # ============================================================
  # Component Callbacks
  # ============================================================

  @impl Scenic.Component
  def validate(%{frame: %Frame{}, id: _} = data), do: {:ok, data}
  def validate(%{frame: %{size: size}, id: _} = data) do
    pin = Map.get(data.frame, :pin, {0, 0})
    frame = Frame.new(pin: pin, size: size)
    {:ok, %{data | frame: frame}}
  end
  def validate(data), do: {:error, "DatePicker requires frame and id. Got: #{inspect(data)}"}

  @impl Scenic.Scene
  def init(scene, data, _opts) do
    # Handle both tuple and Dimensions struct for size
    {width, height} = case data.frame.size do
      %{width: w, height: h} -> {w, h}
      %{box: {w, h}} -> {w, h}
      {w, h} -> {w, h}
    end
    selected = Map.get(data, :selected)
    placeholder = Map.get(data, :placeholder, "Select date")

    state = %{
      id: data.id,
      width: width,
      height: height,
      selected: selected,
      placeholder: placeholder,
      open: false,
      hover: nil,  # :button, :prev, :next, :clear, or {:day, date}
      display_month: selected || Date.utc_today() |> Date.beginning_of_month()
    }

    graph = render(state)

    scene =
      scene
      |> assign(state: state)
      |> push_graph(graph)

    request_input(scene, [:cursor_button, :cursor_pos])

    {:ok, scene}
  end

  @impl Scenic.Scene
  def handle_update(data, _opts, scene) do
    # Called when parent pushes new data - update selected date without recreating
    state = scene.assigns.state
    new_selected = Map.get(data, :selected)

    if new_selected != state.selected do
      new_state = %{state |
        selected: new_selected,
        display_month: new_selected || state.display_month
      }
      graph = render(new_state)
      {:noreply, scene |> assign(state: new_state) |> push_graph(graph)}
    else
      {:noreply, scene}
    end
  end

  @impl Scenic.Scene
  def handle_input({:cursor_button, {:btn_left, 1, _, {x, y}}}, _context, scene) do
    state = scene.assigns.state

    cond do
      # Click on main button - toggle dropdown
      not state.open and in_button?(x, y, state) ->
        new_state = %{state | open: true}
        graph = render(new_state)
        {:noreply, scene |> assign(state: new_state) |> push_graph(graph)}

      # Dropdown is open - handle clicks inside
      state.open ->
        handle_dropdown_click(scene, state, x, y)

      true ->
        {:noreply, scene}
    end
  end

  def handle_input({:cursor_pos, {x, y}}, _context, scene) do
    state = scene.assigns.state
    new_hover = get_hover_target(x, y, state)

    if new_hover != state.hover do
      new_state = %{state | hover: new_hover}
      graph = render(new_state)
      {:noreply, scene |> assign(state: new_state) |> push_graph(graph)}
    else
      {:noreply, scene}
    end
  end

  def handle_input(_input, _context, scene), do: {:noreply, scene}

  # ============================================================
  # Click Handling
  # ============================================================

  defp handle_dropdown_click(scene, state, x, y) do
    dropdown_x = 0
    dropdown_y = state.height + 2

    local_x = x - dropdown_x
    local_y = y - dropdown_y

    cond do
      # Click outside dropdown - close it
      local_x < 0 or local_x > @dropdown_width or local_y < 0 or local_y > @dropdown_height ->
        new_state = %{state | open: false}
        graph = render(new_state)
        {:noreply, scene |> assign(state: new_state) |> push_graph(graph)}

      # Previous month button
      local_x >= 10 and local_x <= 35 and local_y >= 8 and local_y <= 28 ->
        new_month = Date.add(state.display_month, -30) |> Date.beginning_of_month()
        new_state = %{state | display_month: new_month}
        graph = render(new_state)
        {:noreply, scene |> assign(state: new_state) |> push_graph(graph)}

      # Next month button
      local_x >= @dropdown_width - 35 and local_x <= @dropdown_width - 10 and local_y >= 8 and local_y <= 28 ->
        new_month = Date.add(state.display_month, 32) |> Date.beginning_of_month()
        new_state = %{state | display_month: new_month}
        graph = render(new_state)
        {:noreply, scene |> assign(state: new_state) |> push_graph(graph)}

      # Clear button (if date selected)
      state.selected != nil and local_x >= @dropdown_width - 60 and local_x <= @dropdown_width - 10 and
        local_y >= @dropdown_height - 30 and local_y <= @dropdown_height - 8 ->
        new_state = %{state | selected: nil, open: false}
        graph = render(new_state)
        send_parent_event(scene, {:date_cleared, state.id})
        {:noreply, scene |> assign(state: new_state) |> push_graph(graph)}

      # Day cell click
      local_y >= @header_height + 20 and local_y < @dropdown_height - 35 ->
        case get_day_at_position(local_x, local_y, state) do
          nil ->
            {:noreply, scene}
          date ->
            new_state = %{state | selected: date, open: false, display_month: Date.beginning_of_month(date)}
            graph = render(new_state)
            send_parent_event(scene, {:date_selected, state.id, date})
            {:noreply, scene |> assign(state: new_state) |> push_graph(graph)}
        end

      true ->
        {:noreply, scene}
    end
  end

  defp get_day_at_position(x, y, state) do
    grid_x = 10
    grid_y = @header_height + 20
    cell_spacing = 2

    col = trunc((x - grid_x) / (@day_cell_size + cell_spacing))
    row = trunc((y - grid_y) / (@day_cell_size + cell_spacing))

    if col >= 0 and col < 7 and row >= 0 and row < 6 do
      weeks = get_calendar_weeks(state.display_month)
      case Enum.at(weeks, row) do
        nil -> nil
        week ->
          case Enum.at(week, col) do
            {date, _in_month} -> date
            _ -> nil
          end
      end
    else
      nil
    end
  end

  # ============================================================
  # Hover Detection
  # ============================================================

  defp get_hover_target(x, y, state) do
    cond do
      not state.open and in_button?(x, y, state) ->
        :button

      state.open ->
        dropdown_x = 0
        dropdown_y = state.height + 2
        local_x = x - dropdown_x
        local_y = y - dropdown_y

        cond do
          local_x >= 10 and local_x <= 35 and local_y >= 8 and local_y <= 28 ->
            :prev

          local_x >= @dropdown_width - 35 and local_x <= @dropdown_width - 10 and local_y >= 8 and local_y <= 28 ->
            :next

          state.selected != nil and local_x >= @dropdown_width - 60 and local_y >= @dropdown_height - 30 ->
            :clear

          local_y >= @header_height + 20 and local_y < @dropdown_height - 35 ->
            case get_day_at_position(local_x, local_y, state) do
              nil -> nil
              date -> {:day, date}
            end

          true ->
            nil
        end

      true ->
        nil
    end
  end

  defp in_button?(x, y, state) do
    x >= 0 and x <= state.width and y >= 0 and y <= state.height
  end

  # ============================================================
  # Rendering
  # ============================================================

  defp render(state) do
    Graph.build()
    |> render_button(state)
    |> maybe_render_dropdown(state)
  end

  defp render_button(graph, state) do
    bg = cond do
      state.open -> @bg_open
      state.hover == :button -> @bg_hover
      true -> @bg
    end

    border = if state.open, do: @border_focus, else: @border

    display_text = if state.selected do
      Calendar.strftime(state.selected, "%b %d, %Y")
    else
      state.placeholder
    end

    text_color = if state.selected, do: @text_color, else: @text_muted

    graph
    |> rrect({state.width, state.height, 4},
      fill: bg,
      stroke: {1, border}
    )
    |> text(display_text,
      translate: {10, state.height / 2 + 5},
      fill: text_color,
      font_size: 13
    )
    # Dropdown arrow
    |> triangle({{state.width - 20, state.height / 2 - 3},
                 {state.width - 10, state.height / 2 - 3},
                 {state.width - 15, state.height / 2 + 3}},
      fill: @text_muted
    )
  end

  defp maybe_render_dropdown(graph, %{open: false}), do: graph
  defp maybe_render_dropdown(graph, state) do
    dropdown_y = state.height + 2
    today = Date.utc_today()
    month_name = Calendar.strftime(state.display_month, "%B %Y")

    graph
    |> group(fn g ->
      g
      # Background
      |> rrect({@dropdown_width, @dropdown_height, 6},
        fill: @dropdown_bg,
        stroke: {1, @border}
      )
      # Header with month/year and nav
      |> render_nav_button(10, 8, "<", state.hover == :prev)
      |> text(month_name,
        translate: {@dropdown_width / 2 - String.length(month_name) * 4, 25},
        fill: @text_color,
        font_size: 14
      )
      |> render_nav_button(@dropdown_width - 35, 8, ">", state.hover == :next)
      # Day names header
      |> render_day_names()
      # Calendar grid
      |> render_calendar_grid(state, today)
      # Clear button (if date selected)
      |> maybe_render_clear_button(state)
    end, translate: {0, dropdown_y})
  end

  defp render_nav_button(graph, x, y, label, is_hover) do
    bg = if is_hover, do: @nav_btn_hover, else: @nav_btn

    graph
    |> rrect({25, 20, 3}, fill: bg, translate: {x, y})
    |> text(label, translate: {x + 9, y + 15}, fill: @text_color, font_size: 14)
  end

  defp render_day_names(graph) do
    @day_names
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {name, idx}, g ->
      x = 10 + idx * (@day_cell_size + 2) + 5
      text(g, name, translate: {x, @header_height + 12}, fill: @text_muted, font_size: 10)
    end)
  end

  defp render_calendar_grid(graph, state, today) do
    weeks = get_calendar_weeks(state.display_month)
    grid_y = @header_height + 20

    weeks
    |> Enum.with_index()
    |> Enum.reduce(graph, fn {week, row_idx}, week_g ->
      week
      |> Enum.with_index()
      |> Enum.reduce(week_g, fn {{date, in_month}, col_idx}, day_g ->
        x = 10 + col_idx * (@day_cell_size + 2)
        y = grid_y + row_idx * (@day_cell_size + 2)

        render_day_cell(day_g, date, x, y, in_month, state, today)
      end)
    end)
  end

  defp render_day_cell(graph, date, x, y, in_month, state, today) do
    is_selected = date == state.selected
    is_today = date == today
    is_hovered = state.hover == {:day, date}

    bg = cond do
      is_selected -> @day_selected
      is_today -> @day_today
      is_hovered and in_month -> @day_hover
      in_month -> @day_bg
      true -> @day_other_month
    end

    text_color = if in_month, do: @text_color, else: @text_muted

    graph
    |> rrect({@day_cell_size, @day_cell_size, 3}, fill: bg, translate: {x, y})
    |> text(Integer.to_string(date.day),
      translate: {x + (if date.day < 10, do: 11, else: 7), y + 20},
      fill: text_color,
      font_size: 12
    )
  end

  defp maybe_render_clear_button(graph, %{selected: nil}), do: graph
  defp maybe_render_clear_button(graph, state) do
    bg = if state.hover == :clear, do: {150, 70, 70}, else: @clear_btn
    y = @dropdown_height - 30

    graph
    |> rrect({50, 22, 3}, fill: bg, translate: {@dropdown_width - 60, y})
    |> text("Clear", translate: {@dropdown_width - 50, y + 15}, fill: @text_color, font_size: 11)
  end

  # ============================================================
  # Calendar Helpers
  # ============================================================

  defp get_calendar_weeks(first_of_month) do
    # Day of week for first day (1=Monday, 7=Sunday in Elixir)
    first_dow = Date.day_of_week(first_of_month)
    # Convert to Sunday-start (0=Sunday, 6=Saturday)
    days_before = rem(first_dow, 7)

    # Start from the Sunday of the first week
    start_date = Date.add(first_of_month, -days_before)
    current_month = first_of_month.month

    0..41
    |> Enum.map(fn offset ->
      date = Date.add(start_date, offset)
      in_month = date.month == current_month
      {date, in_month}
    end)
    |> Enum.chunk_every(7)
  end

end
