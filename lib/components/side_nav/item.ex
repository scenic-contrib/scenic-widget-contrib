defmodule ScenicWidgets.SideNav.Item do
  @moduledoc """
  Represents a single item in the sidebar navigation tree.

  Matches the dataspec from side_nav_prompt.md:
  - id: Unique identifier
  - title: Display text
  - type: :module | :page | :task | :group | :custom
  - url: Optional navigation target
  - children: List of child items
  - depth: Nesting level (calculated)
  - expanded: Expansion state (managed by State)
  """

  defstruct [
    :id,
    :title,
    :type,
    :url,
    :action,      # Optional callback function on click
    children: [],
    depth: 0,
    expanded: false
  ]

  @type item_type :: :module | :page | :task | :group | :custom
  @type t :: %__MODULE__{
    id: String.t(),
    title: String.t(),
    type: item_type(),
    url: String.t() | nil,
    action: (-> any()) | nil,
    children: [t()],
    depth: non_neg_integer(),
    expanded: boolean()
  }

  @doc """
  Create a new sidebar item.
  """
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Get the ID of an item.
  """
  def get_id(%__MODULE__{id: id}), do: id

  @doc """
  Get the title of an item.
  """
  def get_title(%__MODULE__{title: title}), do: title

  @doc """
  Get the children of an item.
  """
  def get_children(%__MODULE__{children: children}), do: children

  @doc """
  Check if an item has children.
  """
  def has_children?(%__MODULE__{children: children}), do: length(children) > 0

  @doc """
  Check if an item is marked as initially expanded.
  """
  def is_expanded?(%__MODULE__{expanded: expanded}), do: expanded == true

  @doc """
  Get the type of an item.
  """
  def get_type(%__MODULE__{type: type}), do: type

  @doc """
  Get the action callback (if any).
  """
  def get_action(%__MODULE__{action: action}), do: action

  @doc """
  Build a test tree structure for development.
  Returns a HexDocs-style documentation tree.
  """
  def test_tree do
    [
      %__MODULE__{
        id: "getting_started",
        title: "GETTING STARTED",
        type: :group,
        children: [
          %__MODULE__{
            id: "introduction",
            title: "Introduction",
            type: :page,
            url: "/intro"
          },
          %__MODULE__{
            id: "installation",
            title: "Installation",
            type: :page,
            url: "/install"
          },
          %__MODULE__{
            id: "interactive_mode",
            title: "Interactive mode",
            type: :page,
            url: "/iex"
          }
        ]
      },
      %__MODULE__{
        id: "basic_types",
        title: "Basic types",
        type: :page,
        url: "/basic-types"
      },
      %__MODULE__{
        id: "lists_and_tuples",
        title: "Lists and tuples",
        type: :group,
        children: [
          %__MODULE__{
            id: "linked_lists",
            title: "(Linked) Lists",
            type: :page,
            url: "/lists"
          },
          %__MODULE__{
            id: "tuples",
            title: "Tuples",
            type: :page,
            url: "/tuples"
          },
          %__MODULE__{
            id: "lists_or_tuples",
            title: "Lists or tuples?",
            type: :page,
            url: "/lists-vs-tuples"
          }
        ]
      },
      %__MODULE__{
        id: "pattern_matching",
        title: "Pattern matching",
        type: :page,
        url: "/pattern-matching"
      },
      %__MODULE__{
        id: "case_cond_if",
        title: "case, cond, and if",
        type: :page,
        url: "/case-cond-if"
      },
      %__MODULE__{
        id: "anonymous_functions",
        title: "Anonymous functions",
        type: :group,
        children: [
          %__MODULE__{
            id: "identifying_functions",
            title: "Identifying functions and docu...",
            type: :page,
            url: "/functions"
          },
          %__MODULE__{
            id: "defining_functions",
            title: "Defining anonymous functions",
            type: :page,
            url: "/anon-functions"
          },
          %__MODULE__{
            id: "closures",
            title: "Closures",
            type: :page,
            url: "/closures"
          }
        ]
      }
    ]
  end

  @doc """
  Build a minimal test tree with just a few items.
  """
  def minimal_tree do
    [
      %__MODULE__{
        id: "parent1",
        title: "Parent 1",
        type: :group,
        children: [
          %__MODULE__{
            id: "child1_1",
            title: "Child 1.1",
            type: :page,
            url: "/child1-1"
          },
          %__MODULE__{
            id: "child1_2",
            title: "Child 1.2",
            type: :page,
            url: "/child1-2"
          }
        ]
      },
      %__MODULE__{
        id: "parent2",
        title: "Parent 2",
        type: :page,
        url: "/parent2"
      }
    ]
  end

  @doc """
  Build a deep test tree with 4 levels of nesting.
  Demonstrates both callback types:
  - :action callback for leaf items
  - Parent message via {:sidebar, :navigate, item_id}
  """
  def deep_test_tree do
    [
      %__MODULE__{
        id: "level1_docs",
        title: "Documentation",
        type: :group,
        children: [
          %__MODULE__{
            id: "level2_guides",
            title: "Guides",
            type: :group,
            children: [
              %__MODULE__{
                id: "level3_getting_started",
                title: "Getting Started",
                type: :group,
                children: [
                  %__MODULE__{
                    id: "level4_install",
                    title: "Installation",
                    type: :page,
                    url: "/docs/guides/getting-started/install",
                    # Action callback - logs when clicked
                    action: fn ->
                      require Logger
                      Logger.debug("🎯 ACTION CALLBACK: Installation leaf clicked!")
                    end
                  },
                  %__MODULE__{
                    id: "level4_config",
                    title: "Configuration",
                    type: :page,
                    url: "/docs/guides/getting-started/config"
                    # No action - will send parent message instead
                  },
                  %__MODULE__{
                    id: "level4_first_app",
                    title: "Your First App",
                    type: :page,
                    url: "/docs/guides/getting-started/first-app",
                    action: fn ->
                      require Logger
                      Logger.debug("🎯 ACTION CALLBACK: First App leaf clicked!")
                    end
                  }
                ]
              },
              %__MODULE__{
                id: "level3_advanced",
                title: "Advanced Topics",
                type: :group,
                children: [
                  %__MODULE__{
                    id: "level4_perf",
                    title: "Performance",
                    type: :page,
                    url: "/docs/guides/advanced/perf"
                  },
                  %__MODULE__{
                    id: "level4_testing",
                    title: "Testing",
                    type: :page,
                    url: "/docs/guides/advanced/testing",
                    action: fn ->
                      require Logger
                      Logger.debug("🎯 ACTION CALLBACK: Testing leaf clicked!")
                    end
                  }
                ]
              }
            ]
          },
          %__MODULE__{
            id: "level2_api",
            title: "API Reference",
            type: :group,
            children: [
              %__MODULE__{
                id: "level3_modules",
                title: "Modules",
                type: :page,
                url: "/docs/api/modules"
              },
              %__MODULE__{
                id: "level3_types",
                title: "Types",
                type: :page,
                url: "/docs/api/types"
              }
            ]
          }
        ]
      },
      %__MODULE__{
        id: "level1_examples",
        title: "Examples",
        type: :group,
        children: [
          %__MODULE__{
            id: "level2_basic",
            title: "Basic Examples",
            type: :page,
            url: "/examples/basic"
          },
          %__MODULE__{
            id: "level2_advanced",
            title: "Advanced Examples",
            type: :group,
            children: [
              %__MODULE__{
                id: "level3_components",
                title: "Components",
                type: :group,
                children: [
                  %__MODULE__{
                    id: "level4_buttons",
                    title: "Buttons",
                    type: :page,
                    url: "/examples/advanced/components/buttons",
                    action: fn ->
                      require Logger
                      Logger.debug("🎯 ACTION CALLBACK: Buttons example clicked!")
                    end
                  },
                  %__MODULE__{
                    id: "level4_forms",
                    title: "Forms",
                    type: :page,
                    url: "/examples/advanced/components/forms"
                  }
                ]
              }
            ]
          }
        ]
      },
      %__MODULE__{
        id: "level1_changelog",
        title: "Changelog",
        type: :page,
        url: "/changelog"
        # Top-level leaf - no action, will send parent message
      }
    ]
  end

  @doc """
  Find an item by ID in a tree.
  """
  def find_by_id(tree, target_id) when is_list(tree) do
    do_find_by_id(tree, target_id)
  end

  defp do_find_by_id([], _target_id), do: nil

  defp do_find_by_id([%__MODULE__{id: id} = item | rest], target_id) do
    cond do
      id == target_id ->
        item

      has_children?(item) ->
        case do_find_by_id(item.children, target_id) do
          nil -> do_find_by_id(rest, target_id)
          found -> found
        end

      true ->
        do_find_by_id(rest, target_id)
    end
  end

  @doc """
  Flatten a tree into a list of items (depth-first).
  """
  def flatten(tree) when is_list(tree) do
    do_flatten(tree, [])
  end

  defp do_flatten([], acc), do: Enum.reverse(acc)

  defp do_flatten([item | rest], acc) do
    new_acc = [item | acc]

    acc_with_children = if has_children?(item) do
      # Add children (reversed since we're building backwards)
      do_flatten(item.children, new_acc)
    else
      new_acc
    end

    do_flatten(rest, acc_with_children)
  end
end
