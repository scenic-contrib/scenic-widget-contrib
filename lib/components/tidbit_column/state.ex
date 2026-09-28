defmodule ScenicWidgets.TidbitColumn.State do
  @moduledoc """
  State for TidbitColumn component.

  Uses the Scrollable macro for scroll state management.
  """

  use Widgex.Scrollable, direction: :vertical

  alias Widgex.Frame

  @item_height 80
  @item_spacing 8
  @padding 10

  defstruct [
    :frame,
    :items,
    :scroll,
    :hovered_id,
    :selected_id,
    theme: %{
      background: {240, 240, 245},
      card_background: {255, 255, 255},
      card_hover: {248, 248, 252},
      card_selected: {230, 240, 255},
      border: {220, 220, 225},
      text: {40, 40, 50},
      text_secondary: {120, 120, 130}
    }
  ]

  @type item :: %{
          id: atom() | String.t(),
          title: String.t(),
          preview: String.t()
        }

  @type t :: %__MODULE__{
          frame: Frame.t(),
          items: [item()],
          scroll: Widgex.Scroll.ScrollState.t(),
          hovered_id: atom() | String.t() | nil,
          selected_id: atom() | String.t() | nil,
          theme: map()
        }

  @doc """
  Create a new TidbitColumn state.

  ## Options

    * `:items` - List of tidbit items (default: [])
    * `:theme` - Theme overrides
  """
  def new(%{frame: %Frame{} = frame} = params) do
    items = Map.get(params, :items, demo_items())
    theme = Map.get(params, :theme, %{})

    content_height = calculate_content_height(items)

    %__MODULE__{
      frame: frame,
      items: items,
      scroll: init_scroll(frame, content_height: content_height),
      hovered_id: nil,
      selected_id: nil,
      theme: Map.merge(%__MODULE__{}.theme, theme)
    }
  end

  @doc """
  Calculate total content height based on items.
  """
  def calculate_content_height(items) do
    count = length(items)
    if count > 0 do
      @padding + count * (@item_height + @item_spacing) - @item_spacing + @padding
    else
      @padding * 2
    end
  end

  @doc """
  Get the height of each item card.
  """
  def item_height, do: @item_height

  @doc """
  Get spacing between items.
  """
  def item_spacing, do: @item_spacing

  @doc """
  Get padding around content.
  """
  def padding, do: @padding

  @doc """
  Calculate bounds for each item for hit testing.
  """
  def item_bounds(%__MODULE__{frame: frame, items: items}) do
    {width, _height} = frame.size.box
    item_width = width - @padding * 2

    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      y = @padding + index * (@item_height + @item_spacing)
      {item.id, %{x: @padding, y: y, width: item_width, height: @item_height}}
    end)
    |> Map.new()
  end

  @doc """
  Hit test to find which item is at coordinates.

  Coordinates should be in content space (accounting for scroll offset).
  """
  def hit_test(%__MODULE__{scroll: scroll} = state, {x, y}) do
    # Convert to content coordinates
    content_y = y + scroll.offset_y

    bounds = item_bounds(state)

    Enum.find_value(bounds, :none, fn {id, b} ->
      if x >= b.x && x <= b.x + b.width &&
         content_y >= b.y && content_y <= b.y + b.height do
        {:item, id}
      else
        nil
      end
    end)
  end

  @doc """
  Check if point is inside the component bounds.
  """
  def point_inside?(%__MODULE__{frame: frame}, {x, y}) do
    {width, height} = frame.size.box
    x >= 0 && x <= width && y >= 0 && y <= height
  end

  @doc """
  Add an item to the column.
  """
  def add_item(%__MODULE__{items: items} = state, item) do
    new_items = items ++ [item]
    new_content_height = calculate_content_height(new_items)

    %{state |
      items: new_items,
      scroll: update_content_size(state.scroll, state.frame.size.width, new_content_height)
    }
  end

  @doc """
  Remove an item from the column.
  """
  def remove_item(%__MODULE__{items: items} = state, item_id) do
    new_items = Enum.reject(items, &(&1.id == item_id))
    new_content_height = calculate_content_height(new_items)

    %{state |
      items: new_items,
      scroll: update_content_size(state.scroll, state.frame.size.width, new_content_height)
    }
  end

  # Demo items for testing
  defp demo_items do
    [
      %{id: :welcome, title: "Welcome", preview: "Getting started with TiddlyWiki concepts..."},
      %{id: :hello, title: "HelloThere", preview: "A simple hello message tidbit."},
      %{id: :concepts, title: "Concepts", preview: "Core concepts and architecture overview."},
      %{id: :filters, title: "Filters", preview: "How to use filters to query tidbits."},
      %{id: :macros, title: "Macros", preview: "Reusable text snippets and templates."},
      %{id: :widgets, title: "Widgets", preview: "Interactive components for your wiki."},
      %{id: :themes, title: "Themes", preview: "Customizing the look and feel."},
      %{id: :plugins, title: "Plugins", preview: "Extending functionality with plugins."},
      %{id: :export, title: "Export", preview: "Saving and sharing your wiki."},
      %{id: :import, title: "Import", preview: "Bringing in external content."},
      %{id: :history, title: "History", preview: "Tracking changes over time."},
      %{id: :search, title: "Search", preview: "Finding content quickly."}
    ]
  end
end
