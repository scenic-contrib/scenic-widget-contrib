## How to import `scenic-widget-contrib` components

This is a good first step if you are customizing or contributing to a component.

#### Step 1 - add to `mix.exs`

Clone the repo next to wherever your Scenic project is running, so the
directory structure looks like:

```
/dir                        <-- use `git clone` from here
- /your_project             <-- this is where your Scenic app is
- /scenic-widget-contrib    <-- here is where the widget-lib got cloned to
```

and then import it by adding the following line to your `mix.exs` file:

```elixir
{:scenic_widget_contrib, path: "../scenic-widget-contrib", override: true},
```

This references your local clone of the repo - any components you add
inside the `scenic-widget-contrib` repo can now be used from within your
other Scenic application.

#### Step 2 - add the custom components to your Scenic.Graph

```elixir
graph
|> ScenicWidgets.TestPattern.add_to_graph(%{} = _args)
```

## Tips & guidelines for developing custom Scenic components

### Using %Frame{} structs

A `%Frame{}` struct is meant to formalize the rectangular size of a component -
if a component accepts a Frame, it should scissor it's own frame so that
it doesn't draw outside the frame.

### Use one high-level group for a component

If you wrap all your component graph up inside one outer-group, this will
let you translate the entire component as one unit.

