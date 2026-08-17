defmodule ScenicWidgets.Menu.Model do
  @moduledoc "Typed data-only menu/popover contract."

  defmodule Item do
    @enforce_keys [:id, :label]
    defstruct [:id, :label, :icon, :shortcut, :tooltip, enabled?: true]
  end

  defmodule Toggle do
    @enforce_keys [:id, :label, :checked?]
    defstruct [:id, :label, :checked?, :tooltip, enabled?: true]
  end

  defmodule Radio do
    @enforce_keys [:id, :label, :group, :value, :selected?]
    defstruct [:id, :label, :group, :value, :selected?, :tooltip, enabled?: true]
  end

  defmodule Slider do
    @enforce_keys [:id, :label, :value, :min, :max]
    defstruct [:id, :label, :value, :min, :max, :tooltip, step: 1, enabled?: true]
  end

  defmodule Divider do
    @moduledoc "A non-interactive horizontal separator between groups of menu rows."
    @enforce_keys [:id]
    defstruct [:id, enabled?: false]
  end

  defmodule Select do
    @moduledoc "An inline dropdown selector with a finite set of choices."
    @enforce_keys [:id, :label, :value, :options]
    defstruct [
      :id,
      :label,
      :value,
      :options,
      :tooltip,
      expanded?: false,
      scroll_offset: 0,
      enabled?: true
    ]
  end

  defmodule Stepper do
    @moduledoc "A numeric menu control with reusable decrement and increment buttons."
    @enforce_keys [:id, :label, :value, :min, :max]
    defstruct [:id, :label, :value, :min, :max, :tooltip, step: 1, enabled?: true]
  end

  defmodule Submenu do
    @enforce_keys [:id, :label, :rows]
    defstruct [:id, :label, :rows, :tooltip, enabled?: true]
  end

  defmodule Section do
    @enforce_keys [:id, :label]
    defstruct [:id, :label, enabled?: false]
  end

  @enforce_keys [:id, :rows]
  defstruct [:id, :rows, autohide?: true]

  def validate(%__MODULE__{id: id, rows: rows} = model) when is_atom(id) and is_list(rows) do
    with :ok <- unique_ids(rows), :ok <- valid_rows(rows), do: {:ok, model}
  end

  def validate(_), do: {:error, :invalid_menu}

  def event(%__MODULE__{id: menu_id}, %{id: item_id}, value \\ :activate),
    do: {:menu_action, menu_id, item_id, value}

  defp unique_ids(rows) do
    ids = Enum.flat_map(rows, &row_ids/1)
    if length(ids) == length(Enum.uniq(ids)), do: :ok, else: {:error, :duplicate_id}
  end

  defp row_ids(%Submenu{id: id, rows: rows}), do: [id | Enum.flat_map(rows, &row_ids/1)]
  defp row_ids(%{id: id}), do: [id]
  defp row_ids(_), do: []

  defp valid_rows(rows),
    do: if(Enum.all?(rows, &valid_row?/1), do: :ok, else: {:error, :invalid_row})

  defp valid_row?(%Submenu{rows: rows}), do: valid_rows(rows) == :ok

  defp valid_row?(%Slider{min: min, max: max, value: value, step: step}),
    do: is_number(value) and is_number(step) and step > 0 and value >= min and value <= max

  defp valid_row?(%module{})
       when module in [Item, Toggle, Radio, Section, Divider, Select, Stepper],
       do: true

  defp valid_row?(row) when row in [:divider, :space], do: true
  defp valid_row?(_), do: false
end
