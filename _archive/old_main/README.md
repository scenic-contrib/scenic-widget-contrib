# QuillEx

A simple text-editor (basically a [Gedit](https://wiki.gnome.org/Apps/Gedit) clone) written entirely in Elixir.

#TODO screenshot

## Installing

### Scenic

The graphics in QuillEx are powered by an Elixir library called [Scenic](https://github.com/boydm/scenic). For Scenic to compile. some OpenGL libraries must be present on the system. Please see the Scenic [installation docs](https://hexdocs.pm/scenic/install_dependencies.html) on how to install Scenic on your system.

### Running QuillEx in dev mode

Once you have Scenic, just clone the repo and run in dev mode.

```
git clone #TODO
iex -S mix run
```

## TODO list

* would be cool to be able to call quillex from terminal, e.g. `qlx .`
* currently workin on showing the menubar...

## Known Bugs

### MenuBar

* We use the y-axis boundary to de-activate the menu, but not the x-axis
  of each sub-menu, so you can move the mouse around sideways without
  de-activating the menu - in practice, it's not such a pain or dangerous

## Features I want to support

- unlimited undo/redo capability
- unlimited line length
- global search/replace (on all buffers at once)
- block operations?
- automatic indentation
- word wrapping
- justified line wrap
- delimiter matching
- code folding
- scrolling text boxes
- cut & paste
- search & replace
- memory limit, how much we will pull into memory at any one point of time... Need to use paging if we go over this limit
- highlight current line & current word like VS code does