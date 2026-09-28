defmodule ScenicWidgets.TidbitTile.State do
  @moduledoc """
  State management for the TidbitTile component.

  A TidbitTile is a card-like component for displaying a tidbit (similar to
  a Tiddler in TiddlyWiki). It's designed to be used in a Kanban/Trello-like
  interface where tidbits can be organized into columns.

  ## Basic Structure
  - `:id` - Unique identifier for the tidbit
  - `:title` - Display title
  - `:tags` - Optional list of tags (for future use)

  ## Example
      tidbit = %{
        id: "tidbit_123",
        title: "My First Tidbit"
      }
  """

  @type t :: %__MODULE__{
    frame: map(),
    id: String.t() | atom(),
    title: String.t(),
    tags: [String.t()],
    hovered: boolean(),
    selected: boolean(),
    theme: map()
  }

  defstruct [
    :frame,
    id: nil,
    title: "Untitled",
    tags: [],
    hovered: false,
    selected: false,
    theme: %{}
  ]

  @default_theme %{
    # Colors
    background: {255, 255, 255},           # White card background
    background_hover: {250, 250, 250},     # Slightly darker on hover
    background_selected: {232, 240, 254},  # Light blue when selected
    border_color: {220, 220, 220},         # Light gray border
    border_hover_color: {180, 180, 180},   # Darker border on hover
    border_selected_color: {0, 122, 204},  # Blue border when selected
    title_color: {50, 50, 50},             # Dark text
    shadow_color: {0, 0, 0, 30},           # Subtle shadow

    # Dimensions
    border_radius: 4,
    border_width: 1,
    padding: 12,
    min_height: 40,

    # Typography
    font: :roboto_mono,
    title_font_size: 14
  }

  @doc """
  Create a new TidbitTile state from initialization data.
  """
  def new(%Widgex.Frame{} = frame) do
    new(%{frame: frame, title: "Demo Tidbit"})
  end

  def new(%{frame: frame} = data) do
    theme = Map.merge(@default_theme, Map.get(data, :theme, %{}))

    %__MODULE__{
      frame: frame,
      id: Map.get(data, :id, make_ref()),
      title: Map.get(data, :title, "Untitled"),
      tags: Map.get(data, :tags, []),
      hovered: false,
      selected: Map.get(data, :selected, false),
      theme: theme
    }
  end

  @doc """
  Check if a point is inside the tile bounds.
  """
  def point_inside?(%__MODULE__{frame: frame}, {px, py}) do
    width = get_width(frame)
    height = get_height(frame)
    px >= 0 and px <= width and py >= 0 and py <= height
  end

  @doc """
  Get tile width from frame.
  """
  def get_width(%{size: %{width: w}}), do: w
  def get_width(%{size: {w, _h}}), do: w
  def get_width(_), do: 200

  @doc """
  Get tile height from frame.
  """
  def get_height(%{size: %{height: h}}), do: h
  def get_height(%{size: {_w, h}}), do: h
  def get_height(_), do: 60
end
