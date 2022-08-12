defmodule ScenicWidgets.MenuBar.FloatButton do
  use Scenic.Component
  require Logger

  @moduledoc """
  This module is really not that different from a normal Scenic Button,
  just customized a little bit.
  """

  def validate(
        %{label: _l, unique_id: _n, frame: _f, margin: _m, font: %{name: _fn, size: _fns} = _fs, hover_highlight?: _hh} =
          data
      ) do
    # Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
    if Map.get(data, :draw_sub_menu_triangle?, false) do
      {:ok, data}
    else
      {:ok, data |> Map.merge(%{draw_sub_menu_triangle?: false})}
    end
  end

  def validate(args) do
    validate(args |> Map.merge(%{hover_highlight?: false}))
  end

  def init(scene, args, opts) do
    # Logger.debug "#{__MODULE__} initializing..."

    theme =
      (opts[:theme] || Scenic.Primitive.Style.Theme.preset(:light))
      |> Scenic.Primitive.Style.Theme.normalize()

    init_graph = render(args, theme)

    init_scene =
      scene
      |> assign(graph: init_graph)
      |> assign(frame: args.frame)
      |> assign(theme: theme)
      |> assign(
        state: %{
          mode: :inactive,
          font: args.font,
          unique_id: args.unique_id
        }
      )
      |> push_graph(init_graph)

    request_input(init_scene, [:cursor_pos, :cursor_button])

    {:ok, init_scene}
  end

  def bounds(%{frame: %{pin: {top_left_x, top_left_y}, size: {width, height}}}, _opts) do
    # NOTE: Because we use this bounds/2 function to calculate whether or
    # not the mouse is hovering over any particular button, we can't
    # translate entire groups of sub-menus around. We ned to explicitely
    # draw buttons in their correct order, and not translate them around,
    # because bounds/2 doesn't seem to work correctly with translated elements
    # TODO talk to Boyd and see if I'm wrong about this, or maybe we can improve Scenic to work with it
    {top_left_x, top_left_y, top_left_x + width, top_left_y + height}
  end

  def render(args, theme) do
    {width, height} = args.frame.size

    # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
    vpos = height / 2 + args.font.ascent / 2 + args.font.descent / 3

    new_graph =
      Scenic.Graph.build()
      |> Scenic.Primitives.group(
        fn graph ->
          graph
          |> Scenic.Primitives.rect(args.frame.size,
            id: :background,
            fill: if(args.hover_highlight?, do: theme.highlight, else: theme.active)
          )
          |> Scenic.Primitives.text(args.label,
            id: :label,
            font: args.font.name,
            font_size: args.font.size,
            translate: {args.margin, vpos},
            fill: theme.text
          )
        end,
        id: {:float_button, args.unique_id},
        translate: args.frame.pin
      )

    if args.draw_sub_menu_triangle? do
      # TODO dunno why we need to do this, why cant we go args.frame.top_left_x?
      {top_left_x, top_left_y} = args.frame.pin

      pop_out_icon_height = 0.6 * height

      pop_out_icon_coords = %{
        x: top_left_x + 0.87 * width,
        y: top_left_y + (height - pop_out_icon_height) / 2
      }

      # draw the sub-menu & sigils over the top of the carry_graph
      new_graph
      |> ScenicWidgets.Utils.Shapes.right_pointing_triangle(%{
        top_left: pop_out_icon_coords,
        height: pop_out_icon_height,
        color: theme.border
      })
    else
      new_graph
    end
  end

  # TODO accept clicks, send msg bck up to menu bar??
  def handle_input({:cursor_pos, {_x, _y} = coords}, _context, scene) do
    bounds = Scenic.Graph.bounds(scene.assigns.graph)
    # theme = scene.assigns.theme

    if coords |> ScenicWidgets.Utils.inside?(bounds) do
      # Logger.debug "Detec'd hover: #{inspect scene.assigns.state.unique_id}, bounds: #{inspect bounds}"
      GenServer.cast(ScenicWidgets.MenuBar, {:hover, scene.assigns.state.unique_id})
    end

    # new_graph =
    #   if coords |> ScenicWidgets.Utils.inside?(bounds) do
    #     GenServer.cast(ScenicWidgets.MenuBar, {:hover, scene.assigns.state.unique_id})

    #     scene.assigns.graph
    #     # TODO and change text to black
    #     |> Scenic.Graph.modify(
    #       :background,
    #       &Scenic.Primitives.update_opts(&1, fill: theme.highlight, color: :black) #TODO use theme here
    #     )
    #   else
    #     # GenServer.cast(ScenicWidgets.MenuBar, {:cancel, {:hover, scene.assigns.state.unique_id}})
    #     scene.assigns.graph
    #     |> Scenic.Graph.modify(
    #       :background,
    #       &Scenic.Primitives.update_opts(&1, fill: theme.active) #TODO use color: theme.something here
    #     )
    #   end

    # new_scene =
    #   scene
    #   |> assign(graph: new_graph)
    #   |> push_graph(new_graph)

    # {:noreply, new_scene}

    {:noreply, scene}
  end

  def handle_input({:cursor_button, {:btn_left, 0, [], click_coords}}, _context, scene) do
    bounds = Scenic.Graph.bounds(scene.assigns.graph)

    if click_coords |> ScenicWidgets.Utils.inside?(bounds) do
      GenServer.cast(ScenicWidgets.MenuBar, {:click, scene.assigns.state.unique_id})
    end

    {:noreply, scene}
  end

  def handle_input(_input, _context, scene) do
    # Logger.debug "#{__MODULE__} ignoring input: #{inspect input}..."
    {:noreply, scene}
  end
end
