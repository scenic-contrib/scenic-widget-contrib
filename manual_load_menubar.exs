# This script will click in the correct position to load Menu Bar

# First, close any open modals by clicking outside
ScenicMcp.Probes.send_mouse_click(100, 100)
Process.sleep(500)

# Click Load Component button again
IO.puts("🖱️  Clicking Load Component button...")
ScenicMcp.Probes.send_mouse_click(900, 290)
Process.sleep(1000)

# Menu Bar should be the 5th item (index 4) in the modal
# Based on the component ordering, calculate the position
# Modal starts at y=60, each button is 40px + 5px margin
menu_bar_y = 240 + 60 + (4 * 45) + 20  # 240 is modal top, 60 is header, 4th index, 20 is center offset
menu_bar_x = 600  # Center of modal

IO.puts("🖱️  Clicking Menu Bar at position (#{menu_bar_x}, #{menu_bar_y})...")
ScenicMcp.Probes.send_mouse_click(menu_bar_x, menu_bar_y)
Process.sleep(1000)

# Take screenshot to verify
ScenicMcp.Probes.take_screenshot("menubar_finally_loaded")
IO.puts("✅ Menu Bar should now be loaded\!")
