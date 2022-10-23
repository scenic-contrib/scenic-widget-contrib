# ScenicWidgets - TextPad

This creates a text-input interface like Notepad/Gedit.

As much as possible, this Component is just a "thin" rendering component.
ALl logic like editing the component is done at a "higher level" and then
the graphics are updated by casting messages to this Component.

## TODO future features

- line wrap
- make arrow navigation work for non-monospaced fonts
- mouse click to move cursor
- selectable text using mouse
- cut & paste?
- Automtically scroll when the cursor movement goes close to the edge of the screen
- Mouse-draggable scroll bars


  # Scroll wrapping - for this, I can go ahead with existing text (which wraps),
  # but treat it as larger than another container. However, ultimately
  # I want to be able to disable the scroll-wrapping talked about above,
  # so that I can render  continuous line, & potentially scroll it

  # Other unimplemented cases: Max 1 line height (e.g. KommandBuffer)

  # new, update & remove
