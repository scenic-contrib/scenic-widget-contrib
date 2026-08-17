# Side Nav prompt

=========================
🎯 overview.md
=========================
Purpose

This document describes a full specification for implementing a Hexdocs-style sidebar + menubar as a Scenic / WidgetWorkbench widget in Elixir.

The component should:

Model the navigation patterns of the docs on hexdocs.pm

Follow structural, visual, and behavioral patterns of ExDoc’s sidebar

Integrate cleanly into WidgetWorkbench

Support expand/collapse, active highlighting, keyboard navigation, search integration hooks, and version selectors.

Deliverables

A reusable Scenic component

Event contracts for parent scenes

Styling + themes (light & dark)

Fully deterministic behavior suitable for predictable AI-agent coding

=========================
📋 requirements.md
=========================
Functional Requirements
1. Sidebar Layout

A vertical, scrollable left-hand navigation panel

Fixed width (configurable)

Renders a tree of:

Modules

Pages / Guides

Tasks

Other user-defined groups

Items may have children (nested)

Collapsible groups with animated or instantaneous collapse

2. Item Behavior

Each item has:

title (string)

id/path (list or dotted string)

optional URL / target

type: module, page, task, group, custom

children: list of items

Items may be expanded or collapsed

Click behavior:

Click on text → select / navigate event

Click on chevron icon → toggle expansion

3. Active Item Tracking

Component highlights the current active item

Automatically expands ancestors of active item

4. Keyboard Navigation

Up/down arrows → move selection

Left arrow → collapse or go to parent

Right arrow → expand or go to first child

Enter → emit navigation event

ESC → clear selection (configurable)

5. Menubar Integration

Supports:

Project name / logo slot

Version dropdown

Search input slot

“Go to latest” button slot

(The widget only provides hooks; the parent app decides whether to use them.)

6. Scroll Behavior

Natural scrolling inside sidebar

Keyboard navigation auto-scrolls selection into view

7. Search (Optional)

Hooks provided:

Input event “filter sidebar tree”

Component filters tree live

Maintains expand state

8. Events Emitted
{:sidebar, :navigate, item}
{:sidebar, :expand, item_id}
{:sidebar, :collapse, item_id}
{:sidebar, :hover, item_id}
{:menubar, :version_change, version}

Nonfunctional Requirements
Performance

Must support hierarchies of 500–1000 items smoothly

Should not re-render the entire graph on every expand

Use subtree rendering

Accessibility

Focus ring for keyboard navigation

High-contrast active and hover states

Clear visual markers for nested levels

Compatiblity

Must work inside Scenic 0.11+

Pure Elixir; no NIF requirements

Works with WidgetWorkbench behaviors

=========================
🧱 dataspec.md
=========================
Core Types
defmodule Sidebar.Item do
  @type t :: %__MODULE__{
    id: String.t(),
    title: String.t(),
    type: :module | :page | :task | :group | :custom,
    url: String.t() | nil,
    children: [t()],
    depth: non_neg_integer(),
    expanded: boolean()
  }

  defstruct [:id, :title, :type, :url, children: [], depth: 0, expanded: false]
end

Sidebar Tree Structure
@type tree :: [Sidebar.Item.t()]

JSON Serialization Example
{
  "project": "MyProject",
  "version": "1.0.0",
  "items": [
    {
      "id": "MyProject",
      "title": "MyProject",
      "type": "module",
      "children": [
        {
          "id": "MyProject.Sub",
          "title": "MyProject.Sub",
          "type": "module",
          "children": []
        }
      ]
    }
  ]
}

Component State
defmodule Sidebar.State do
  defstruct [
    :tree,
    :active_id,
    :focused_id,
    expanded: MapSet.new(),
    settings: %{
      width: 280,
      indent: 16,
      font_size: 16,
      theme: :light
    }
  ]
end

=========================
🔌 api.md
=========================
Public API (Widget)
create/2 — Instantiate widget
add_specs(
  SidebarWidget,
  id: :sidebar,
  tree: tree,
  active_id: String.t(),
  width: integer(),
  theme: :light | :dark
)

update_tree/2

Replace the tree.

SidebarWidget.update_tree(pid_or_id, new_tree)

set_active/2

Highlight active item.

SidebarWidget.set_active(pid_or_id, item_id)

toggle_expand/2

Toggle expanded/collapsed.

SidebarWidget.toggle_expand(pid_or_id, item_id)

set_theme/2
SidebarWidget.set_theme(pid_or_id, :light)

set_filter/2
SidebarWidget.set_filter(pid_or_id, "MyProject.Submodule")

=========================
🎨 rendering.md
=========================
Layout Rules

Fixed-width vertical rectangle for sidebar (default 280px)

Inside: a scroll_group

Each item rendered as:

translate x = depth * indent

icon (chevron) if children present

text label

active background highlight rectangle

hover highlight overlay

Item Components
Chevron Icon

Right-facing when collapsed

Down-facing when expanded

12×12 px

Click sensitive

No text drag interference

Text Label

Font: project’s configured UI font

Size: 14–16px

Weight:

top-level: semibold

nested: regular

Indentation
depth * indent
indent default = 16px

Active Item Styling

Background rectangle: theme-specific highlight color

Bold text

Slight left accent bar (2–3 px width)

Hover State

Light hover background

Cursor change optional (if supported on target runtime)

=========================
🧠 behavior.md
=========================
Expand/Collapse

Click on chevron toggles expanded state

Click on text does not collapse/expand (Hexdocs behavior)

Toggling re-renders only affected subtree

Navigation Behavior
Mouse

Click → {:sidebar, :navigate, item} event

Hover → highlight

Keyboard
Up:    previous visible item
Down:  next visible item
Left:  collapse OR go to parent
Right: expand OR go to first child
Enter: navigate event
Home:  jump to first item
End:   jump to last item

Auto-scroll Behavior

When the focused or active item moves outside the viewport, adjust scroll offset.

Focus Ring

A rectangle or outline around focused item in keyboard mode only.

=========================
🎨 theming.md
=========================
Light Theme
Element	Color
Background	#F8F8F8
Text	#222222
Active bg	#E5F2FF
Active bar	#0070D6
Hover bg	#EDEDED
Chevron	#545454
Dark Theme
Element	Color
Background	#1C1C1E
Text	#ECECEC
Active bg	#2D2D31
Active bar	#4DA3FF
Hover bg	#2A2A2D
Chevron	#CCCCCC
Typography

Font Size: 16px top-level, 15px nested

Line height: 20–22px

Spacing between items: 4–6px

=========================
🛠️ implementation_plan.md
=========================
Phase 1 — Scaffolding

Create module SidebarWidget

Define state struct

Build static rendering for non-interactive tree

Phase 2 — Interaction

Add click handlers

Add expand/collapse support

Add active state

Phase 3 — Keyboard Navigation

Track focus

Implement movement logic

Implement auto-scroll

Phase 4 — Menubar

Version dropdown

Search slot

Branding slot

Phase 5 — Theming

Light/dark mode

Configurable fonts

Phase 6 — Optimization

Subtree re-render

Virtualization (if needed)

Phase 7 — Final Polish

Animations

Custom scrollbars

Accessibility refinements

=========================
🧪 test_plan.md
=========================
Test Categories
1. Rendering Tests

Basic tree renders correctly

All nested levels show proper indentation

Active item highlight correct

2. Interaction Tests

Chevron toggles expansion

Click selects item

Hover highlights

Keyboard navigation:

- movement
- expand/collapse
- parent fallback
- auto-scroll into view

3. Filtering / Search

Filtered list only shows matching items

Expanded state persists

4. Performance

1k item tree renders < 60ms

Expand/collapse re-render < 16ms

5. Theme Switching

Colors change immediately

No artifacts

=========================
📚 glossary.md
=========================

Active Item: The currently selected documentation entry

Focused Item: Item selected by keyboard navigation

Tree: Hierarchical list of sidebar items

Subtree: A child branch of the tree

Chevron Icon: Expand/collapse indicator

Sidebar: Vertical navigation component

Menubar: Horizontal top bar with version/search features

Slot: A region parent app can provide content for

WidgetWorkbench: Scenic extension for structured widget creation