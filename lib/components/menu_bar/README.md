# ScenicWidgets - MenuBar

This component renders a drop-down menu bar with configurable
menu contents.

Demo video (5 minutes): https://youtu.be/k1kiCL9oMf4

## How to use the MenuBar component in your Scenic app

This is an example of all the code required to render a MenuBar.
Setting `pin: {0, 0}` places the MenuBar in the top-left corner.

```
vp_width = 800 # need to pass in the ViewPort width

Scenic.Graph.build()
|> ScenicWidgets.MenuBar.add_to_graph( %{
        frame: ScenicWidgets.Core.Structs.Frame.new(
            pin: {0, 0},
            size: {vp_width, _menu_bar_height = 60}),
        menu_map: [
            {:sub_menu, "Ice Cream", [
                {"Chocolate", fn -> IO.puts "clicked: `Chocolate`!" end},
                {"Vanilla", fn -> IO.puts "clicked: `Vanilla`!" end}
            ]},
            {:sub_menu, "Ninja Turtles", [
                {"Leonardo", fn -> IO.puts "clicked: `Leonardo`!" end},
                {"Raphael", fn -> IO.puts "clicked: `Raphael`!" end},
                {"Donatello", fn -> IO.puts "clicked: `Donatello`!" end},
                {"Michelangelo", fn -> IO.puts "clicked: `Michelangelo`!" end},
            ]}
        ]
})
```

`ScenicWidgets.Core.Structs.Frame` is a struct also defined inside
ScenicContrib, it is just a fancy definition for a rectangular box.

### Defining the MenuMap

The actual contents of the MenuBar is completely customizable, but
you need to pass in a specifically shaped tree (made out of lists).
The first layer must contain a list of :sub_menu tuples which look
like: `{:sub_menu, "the label", item_list}`. The label is what gets
shown for this sub-menu and the item list is another list of exactly
the same format. You can define sub-menus inside sub-menus just by
nesting this format, for example:

```
def calc_menu_map() do
    [
        {:sub_menu, "Test Menu", [
            {"Item One", fn -> IO.puts "clicked: `Item One`!" end},
            {"Item Two", fn -> IO.puts "clicked: `Item Two`!" end},
            {:sub_menu, "Dropdown", [
                {"Dropdown 1", fn -> IO.puts "clicked: `Dropdown 1`!" end},
                {"Dropdown 2", fn -> IO.puts "clicked: `Dropdown 2`!" end}
            ]},
            {"Item Three", fn -> IO.puts "clicked: `Item Three`!" end},
            {:sub_menu, "Another Menu", [
                {"Dropdown 1", fn -> IO.puts "clicked: `Dropdown 1`!" end},
                {:sub_menu, "Inner Menu", [
                    {"Inner Menu 1", fn -> IO.puts "clicked: `Inner Menu 1`!" end},
                    {"Inner Menu 2", fn -> IO.puts "clicked: `Inner Menu 2`!" end}
                ]},
                {"Dropdown 2", fn -> IO.puts "clicked: `Dropdown 2`!" end}
            ]}
        ]},
        {:sub_menu, "Ice Cream", [
            {"Chocolate", fn -> IO.puts "clicked: `Chocolate`!" end},
            {"Vanilla", fn -> IO.puts "clicked: `Vanilla`!" end}
        ]}
    ]
end
```

Note that each actual item (that isn't a sub-menu) is defined by
a tuple which looks like `{"item label", function/0}`. This function
will be executed when the menu item gets clicked, and can be anything
you like, although there's no way to dynamically send it arguments
at this time, so it must have an arity of zero (but you could go and
fetch data from somewhere else if you so wished, just wrap that
function inside an arity-zero one, e.g. `fn -> do_whatever(x) end`)

Note that functions MUST have side-effects to even work... this is
because the function gets executed in the context of the MenuBar process,
and whatever it returns gets discarded, so if your zero-arity function
is simply returning some data, this will basically do nothing. The best
way is to simply send a message to whatever other part of your software
is supposed to react to the button click, e.g.

```
{:sub_menu, "Ice Cream", [
        {"Chocolate", fn ->
            IO.puts "clicked: `Chocolate`!"
            send IceCreamManager, {:clicked, :chocolate}
        end},
        {"Vanilla", fn ->
            IO.puts "clicked: `Vanilla`!"
            send IceCreamManager, {:clicked, :chocolate}
        end}
]}
```

Using `IO.puts` just ensures that a message shows up in the IEx console
and is not necessary, just sometimes useful.

To call a zero-arity defined in a different module, simply use
the function-capture syntax native to Elixir, e.g.

```
{"Strawberry", &IceCream.Flavour.strawberry/0}
```

## Dynamically changing the menu-map

The MenuBar can have it's contents updated at any time - this is especially
useful for making context-aware menus, e.g. if one of your sub-menus showed
a list of open files (as is the case for [Flamelex](https://github.com/JediLuke/flamelex)) then opening
a new file should update the menu-bar to show this new file (which Flamelex does!)

To update the menu map, simply cast to the component with a new MenuMap.

```
# the Component is automatically registered with this name
GenServer.cast(ScenicWidgets.MenuBar, {:put_menu_map, new_menu_map})

# alternatively, if you render this component from within another
# scenic component, you can use `cast_children/2`
cast_children(scene, {:put_menu_map, new_menu_map})
```

As hinted at above by the `calc_menu_map()` function, you can
compute the MenuMap tree based on whatever state you like, and use
this method to compute new Menu mappings whenever you want to change
them, based on whatever your application is doing.

### Optional args

There are a number of customizations to the MenuBar which are possible
by passing them in as arguments when creating the Graph.

Here is an example of using all of the extended options

```
vp_width = 1000         # fetch the viewport width from Scenic
menu_bar_height = 40    # pick whatever you like
{:fixed, 220}           # sets how wide the columns of the menus are

# Note: IBM Plex Mono is open source and can be downloaded at:
# https://fonts.google.com/specimen/IBM+Plex+Mono
{:ok, ibm_plex_mono_metrics} =
  TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

font = %{
  name: :ibm_plex_mono,   # pass in the custom font here
  size: 36,               # This is the size of the font for the main MenuBar (not sub-menus)
  metrics: ibm_plex_mono_metrics      # pass in the FontMetrics we calculated above
}

sub_menu_options = %{
  height: 40,         # the block-height of sub-menu item rectangles
  font_size: 22       # font-size to use in the sub-menus
}

Scenic.Graph.build()
|> ScenicWidgets.MenuBar.add_to_graph( %{
  frame: ScenicWidgets.Core.Structs.Frame.new(
    pin: {0, 0},
    size: {vp_width, menu_bar_height}
  ),
  menu_map: menu_map,
  item_width: {:fixed, 180},
  font: menubar_font,
  sub_menu: sub_menu_options
})
```

One shortcut, if you just want to use a custom font but are happy to
keep the default size, is to pass in the font's name (as an atom):

```
Scenic.Graph.build()
|> ScenicWidgets.MenuBar.add_to_graph(%{
  frame: ScenicWidgets.Core.Structs.Frame.new(
    pin: {0, 0},
    size: {vp_width, menu_bar_height}
  ),
  menu_map: menu_map(),
  font: :ibm_plex_mono
})
```


### MenuBar controls

Hover over an item to activate a sub-menu, click an item to execute
the function defined against that item in the menu-map.

Press escape to close the menu from the keyboard. Move the mouse below
the longest open sub-menu to automatically close the menu.

Right now the MenuBar doesn't recognize when you move the mouse horizontally
away from a sub-menu, so it stays open. This is technically a bug, but
surprisingly it is no issue in practice (at least for me).


## Bonus - a trick to show arity/0 functions in the menu

Declaring entire menu maps by hand is boring! Luckily we have
some tools for automatically generating them.

### Generating a list of zero-arity functions in a module

Imagine we have this module:

```
defmodule ArityZeroDemo do
  def custom_fn do
    IO.puts("You called the custom fn!")
  end

  def my_fave_fn do
    IO.puts("This is my favourite function...")
  end

  def arity_one(x) do
    IO.puts("You passed in: #{inspect x}")
  end
end
```

To automatically create a sub-menu of all the zero-arity functions
in this module (it has to be the zero-arity functions, since there's
no way of passing in extra arguments), you can do this:

```
{:sub_menu, "arity/0 demo", ScenicWidgets.MenuBar.zero_arity_functions(ArityZeroDemo)}
```

This will populate the `arity/0 demo` sub menu with 2 functions,
`custom_fn` and `my_fave_fn`, and will execute the logic defined
inside them when you click on the button.

### Generating an entire tree of sub-menus from Elixir module definitions

The function described above will generate a sub-menu one layer deep,
but what if we want to be able to define entire trees of sub-menus?
Well, we can!

Here is a tiny example:

```
defmodule Flamelex.API do
  def one_func, do: IO.puts "Clicked 1"
  def two_func, do: IO.puts "Clicked 2"
end

defmodule Flamelex.API.FirstSub do
  def one_func, do: IO.puts "Clicked FirstSub - 1"
  def two_func, do: IO.puts "Clicked FirstSub - 2"
end

defmodule Flamelex.API.SecondSub do
  def one_func, do: IO.puts "Clicked SecondSub - 1"
  def two_func, do: IO.puts "Clicked SecondSub - 2"
end

defmodule Flamelex.API.SecondSub.Nested do
  def one_func, do: IO.puts "Clicked SecondSub.Nested - 1"
  def two_func, do: IO.puts "Clicked SecondSub.Nested - 2"
end
```

To generate a menu tree which looks like this:

```
API
- FirstSub
  - one_func
  - two_func
- SecondSub
  - Nested
    - one_func
    - two_func
  - one_func
  - two_func
- one_func
- two_func
```

We can define a sub-menu as follows:

```
{:sub_menu, "API", ScenicWidgets.MenuBar.modules_and_zero_arity_functions("Elixir.Flamelex.API")}
```

This will look through all the available modules under the namespacing
convention `FirstLevel.SecondLevel.Third` and nest them inside each other
as further sub-menus, with the zero-arity functions added at the end.
