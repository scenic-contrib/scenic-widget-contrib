defmodule Widgex.Frame.Grid do
  @moduledoc """
  Provides CSS Grid-like layout functionality using `Widgex.Frame`.

  Allows defining a grid layout with rows and columns, similar to CSS Grid,
  and calculates appropriately sized and positioned frames for use in GUI components.
  """

  # {row, col, row_span, col_span}

  alias Widgex.Frame
  alias Widgex.Structs.{Coordinates, Dimensions}

  defstruct [
    # The overall frame within which the grid exists
    :frame,
    # List of row heights (proportions or fixed sizes)
    :rows,
    # List of column widths (proportions or fixed sizes)
    :columns,
    # Gap size between rows
    :row_gaps,
    # Gap size between columns
    :column_gaps,
    # Map of area names to grid positions
    :areas
  ]

  @type t :: %__MODULE__{
          frame: Frame.t(),
          rows: list(),
          columns: list(),
          row_gaps: non_neg_integer(),
          column_gaps: non_neg_integer(),
          areas: map()
        }

  @doc """
  Creates a new grid within the given frame.

  ## Parameters

    - `frame`: The `Widgex.Frame` within which the grid is defined.

  ## Example

      iex> grid = Widgex.Frame.Grid.new(parent_frame)
  """
  def new(%Frame{} = frame) do
    %__MODULE__{
      frame: frame,
      rows: [],
      columns: [],
      row_gaps: 0,
      column_gaps: 0,
      areas: %{}
    }
  end

  @doc """
  Sets the number of rows in the grid, optionally with proportional heights.

  ## Parameters

    - `grid`: The grid struct.
    - `rows`: A list of row sizes. Sizes can be proportions (floats summing to 1.0) or fixed pixel sizes.

  ## Example

      iex> grid = grid |> Widgex.Frame.Grid.rows([0.5, 0.5])
  """
  #TODO there's a bug here where if we pass [1] for rows it doesn't calculate height correctly
  def rows(%__MODULE__{} = grid, row_sizes) when is_list(row_sizes) do
    %{grid | rows: row_sizes}
  end

  @doc """
  Sets the number of columns in the grid, optionally with proportional widths.

  ## Parameters

    - `grid`: The grid struct.
    - `columns`: A list of column sizes. Sizes can be proportions (floats summing to 1.0) or fixed pixel sizes.

  ## Example

      iex> grid = grid |> Widgex.Frame.Grid.columns([0.33, 0.33, 0.34])
  """
  def columns(%__MODULE__{} = grid, column_sizes) when is_list(column_sizes) do
    %{grid | columns: column_sizes}
  end

  @doc """
  Sets the gap size between rows.

  ## Parameters

    - `grid`: The grid struct.
    - `gap`: The gap size in pixels.

  ## Example

      iex> grid = grid |> Widgex.Frame.Grid.row_gap(10)
  """
  def row_gap(%__MODULE__{} = grid, gap) when is_integer(gap) and gap >= 0 do
    %{grid | row_gaps: gap}
  end

  @doc """
  Sets the gap size between columns.

  ## Parameters

    - `grid`: The grid struct.
    - `gap`: The gap size in pixels.

  ## Example

      iex> grid = grid |> Widgex.Frame.Grid.column_gap(10)
  """
  def column_gap(%__MODULE__{} = grid, gap) when is_integer(gap) and gap >= 0 do
    %{grid | column_gaps: gap}
  end

  @doc """
  Defines named grid areas for easier component placement.

  ## Parameters

    - `grid`: The grid struct.
    - `areas`: A map where keys are area names (atoms or strings) and values are tuples `{row, col, row_span, col_span}`.

  ## Example

      iex> grid = grid |> Widgex.Frame.Grid.define_areas(%{
      ...>   header: {0, 0, 1, 3},
      ...>   sidebar: {1, 0, 2, 1},
      ...>   content: {1, 1, 2, 2}
      ...> })
  """
  def define_areas(%__MODULE__{} = grid, areas) when is_map(areas) do
    %{grid | areas: areas}
  end

  # def calculate_grid_frames(frame, row_specs, column_specs, area_definitions) do
  #   # Create the grid
  #   grid =
  #     Widgex.Frame.Grid.new(frame)
  #     |> Widgex.Frame.Grid.rows(row_specs)
  #     |> Widgex.Frame.Grid.columns(column_specs)
  #     |> Widgex.Frame.Grid.define_areas(area_definitions)

  #   # Calculate all cell frames
  #   cell_frames = Widgex.Frame.Grid.calculate(grid)

  #   # Generate a map of frames for all defined areas
  #   area_definitions
  #   |> Map.keys()
  #   |> Enum.reduce(%{}, fn area_name, acc ->
  #     Map.put(acc, area_name, Widgex.Frame.Grid.area_frame(grid, cell_frames, area_name))
  #   end)
  # end

  @doc """
  Calculates frames for all grid cells based on the grid definition.

  ## Parameters

    - `grid`: The grid struct.

  ## Returns

    - A map where keys are `{row_index, col_index}` tuples and values are `Widgex.Frame` structs.

  ## Example

      iex> cell_frames = Widgex.Frame.Grid.calculate(grid)
  """
  def calculate(%__MODULE__{rows: [], columns: []}) do
    raise "Grid must have at least one row and one column defined."
  end

  def calculate(%__MODULE__{} = grid) do
    %__MODULE__{
      frame: %Frame{
        pin: %Coordinates{x: frame_x, y: frame_y},
        size: %Dimensions{width: frame_width, height: frame_height}
      },
      rows: row_sizes,
      columns: col_sizes,
      row_gaps: row_gap,
      column_gaps: col_gap
    } = grid

    # Calculate total gap sizes
    total_row_gaps = row_gap * (length(row_sizes) - 1)
    total_col_gaps = col_gap * (length(col_sizes) - 1)

    # Calculate available width and height after subtracting gaps
    available_width = frame_width - total_col_gaps
    available_height = frame_height - total_row_gaps

    # Calculate actual row heights and column widths
    row_heights = calculate_sizes(row_sizes, available_height)
    col_widths = calculate_sizes(col_sizes, available_width)

    # Build frames for each cell
    cell_frames =
      for row_index <- 0..(length(row_heights) - 1),
          col_index <- 0..(length(col_widths) - 1),
          into: %{} do
        x_offset =
          frame_x +
            Enum.sum(Enum.slice(col_widths, 0, col_index)) +
            col_gap * col_index

        y_offset =
          frame_y +
            Enum.sum(Enum.slice(row_heights, 0, row_index)) +
            row_gap * row_index

        cell_width = Enum.at(col_widths, col_index)
        cell_height = Enum.at(row_heights, row_index)

        cell_frame =
          Frame.new(%{
            pin: {x_offset, y_offset},
            size: {cell_width, cell_height}
          })

        {{row_index, col_index}, cell_frame}
      end

    cell_frames
  end

  @doc """
  Retrieves a frame for a specific cell in the grid.

  ## Parameters

    - `cell_frames`: The map of cell frames returned by `calculate/1`.
    - `row_index`: The zero-based index of the row.
    - `col_index`: The zero-based index of the column.

  ## Returns

    - The `Widgex.Frame` for the specified cell.

  ## Example

      iex> frame = Widgex.Frame.Grid.cell_frame(cell_frames, 1, 2)
  """
  def cell_frame(cell_frames, row_index, col_index) do
    Map.get(cell_frames, {row_index, col_index})
  end

  @doc """
  Retrieves a frame for a named area in the grid.

  ## Parameters

    - `grid`: The grid struct.
    - `cell_frames`: The map of cell frames returned by `calculate/1`.
    - `area_name`: The name of the area as defined in `define_areas/2`.

  ## Returns

    - A `Widgex.Frame` that spans the specified area.

  ## Example

      iex> frame = Widgex.Frame.Grid.area_frame(grid, cell_frames, :header)
  """
  def area_frame(%__MODULE__{areas: areas}, cell_frames, area_name) do
    case Map.get(areas, area_name) do
      {start_row, start_col, row_span, col_span} ->
        frames =
          for row <- start_row..(start_row + row_span - 1),
              col <- start_col..(start_col + col_span - 1),
              do: Map.get(cell_frames, {row, col})

        merge_frames(frames)

      nil ->
        raise "Area #{inspect(area_name)} is not defined in the grid."
    end
  end

  # Helper function to calculate actual sizes based on proportions or fixed sizes
  defp calculate_sizes(sizes, total_available) do
    total_fixed = Enum.sum(Enum.filter(sizes, &is_integer/1))
    auto_count = Enum.count(Enum.filter(sizes, &(&1 == :auto)))
    remaining_space = total_available - total_fixed

    Enum.map(sizes, fn
      size when is_integer(size) -> size
      :auto -> remaining_space / auto_count
      proportion when is_float(proportion) -> remaining_space * proportion
    end)
  end

  # defp calculate_sizes(sizes, total_available) do
  #   if Enum.all?(sizes, &is_number/1) and Enum.sum(sizes) == 1.0 do
  #     # Proportional sizes
  #     Enum.map(sizes, fn proportion -> total_available * proportion end)
  #   else
  #     # Fixed sizes or mixed
  #     total_fixed = Enum.sum(Enum.filter(sizes, &is_integer/1))
  #     total_proportion = Enum.sum(Enum.filter(sizes, &is_float/1))

  #     remaining_space = total_available - total_fixed

  #     Enum.map(sizes, fn
  #       size when is_integer(size) -> size
  #       proportion when is_float(proportion) -> remaining_space * proportion / total_proportion
  #     end)
  #   end
  # end

  # Helper function to merge multiple frames into one encompassing frame
  defp merge_frames(frames) do
    pins_x = Enum.map(frames, fn %Frame{pin: %Coordinates{x: x}} -> x end)
    pins_y = Enum.map(frames, fn %Frame{pin: %Coordinates{y: y}} -> y end)
    widths = Enum.map(frames, fn %Frame{size: %Dimensions{width: w}} -> w end)
    heights = Enum.map(frames, fn %Frame{size: %Dimensions{height: h}} -> h end)

    min_x = Enum.min(pins_x)
    min_y = Enum.min(pins_y)
    max_x = Enum.max(Enum.zip(pins_x, widths) |> Enum.map(fn {x, w} -> x + w end))
    max_y = Enum.max(Enum.zip(pins_y, heights) |> Enum.map(fn {y, h} -> y + h end))

    Frame.new(%{
      pin: {min_x, min_y},
      size: {max_x - min_x, max_y - min_y}
    })
  end
end

# defmodule Widgex.Structs.GridLayout do
#   @moduledoc """
#   Represents a grid layout for organizing components in a 2D structure.

#   The `GridLayout` struct provides a way to define a grid with rows and columns, specifying the sizing, gaps, and alignments.

#   ## Fields

#   - `rows`: A list defining the size of each row. Defaults to `[]`.
#   - `columns`: A list defining the size of each column. Defaults to `[]`.
#   - `row_gap`: The gap between rows, as a non-negative float. Defaults to `0.0`.
#   - `column_gap`: The gap between columns, as a non-negative float. Defaults to `0.0`.
#   - `align_items`: Alignment of items along the cross axis. Can be `:start`, `:center`, or `:end`. Defaults to `:start`.
#   - `justify_items`: Alignment of items along the main axis. Can be `:start`, `:center`, or `:end`. Defaults to `:start`.
#   """

#   @type size_spec :: :auto | float()

#   @type t :: %__MODULE__{
#           rows: [size_spec()],
#           columns: [size_spec()],
#           row_gap: float(),
#           column_gap: float(),
#           align_items: :start | :center | :end,
#           justify_items: :start | :center | :end
#         }

#   defstruct rows: [],
#             columns: [],
#             row_gap: 0.0,
#             column_gap: 0.0,
#             align_items: :start,
#             justify_items: :start
# end
