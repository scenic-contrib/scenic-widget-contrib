defmodule Widgex.Structs.GridLayout do
  @moduledoc """
  Represents a grid layout for organizing components in a 2D structure.

  The `GridLayout` struct provides a way to define a grid with rows and columns, specifying the sizing, gaps, and alignments.

  ## Fields

  - `rows`: A list defining the size of each row. Defaults to `[]`.
  - `columns`: A list defining the size of each column. Defaults to `[]`.
  - `row_gap`: The gap between rows, as a non-negative float. Defaults to `0.0`.
  - `column_gap`: The gap between columns, as a non-negative float. Defaults to `0.0`.
  - `align_items`: Alignment of items along the cross axis. Can be `:start`, `:center`, or `:end`. Defaults to `:start`.
  - `justify_items`: Alignment of items along the main axis. Can be `:start`, `:center`, or `:end`. Defaults to `:start`.
  """

  @type size_spec :: :auto | float()

  @type t :: %__MODULE__{
          rows: [size_spec()],
          columns: [size_spec()],
          row_gap: float(),
          column_gap: float(),
          align_items: :start | :center | :end,
          justify_items: :start | :center | :end
        }

  defstruct rows: [],
            columns: [],
            row_gap: 0.0,
            column_gap: 0.0,
            align_items: :start,
            justify_items: :start
end
