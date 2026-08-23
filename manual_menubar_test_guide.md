# Manual MenuBar Testing Guide for Widget Workbench

Since Widget Workbench is already running, follow these steps to thoroughly test the MenuBar component:

## 1. Load MenuBar Component

1. Click the **"Load Component"** button in the right pane (constructor area)
2. From the modal that appears, click on **"Menu Bar"**
3. The MenuBar should appear in the main area

## Expected Results:
- MenuBar should be positioned at **(80, 80)** - not in the top-left corner
- MenuBar height should be **60 pixels**
- Menu items should show: File, Edit, View (or similar based on configuration)

## 2. Test Hover Effects

1. Move your mouse over the "File" menu item
2. The background should change color immediately (hover effect)
3. Move mouse away - the hover effect should disappear

## Expected Results:
- Immediate visual feedback on hover (no delay)
- Clean transitions when mouse enters/leaves

## 3. Test Dropdown Functionality

1. Click on the "File" menu
2. A dropdown should appear with options like:
   - New File
   - Open File
   - Save
   - Quit

## Expected Results:
- Dropdown appears below the menu item
- All menu items are visible and properly formatted
- Text uses strings (not atoms) - no crashes

## 4. Critical Z-Order Test

**This tests the bug you mentioned about overlapping components:**

1. With the File dropdown open, look for areas where it might overlap with workbench controls
2. Click in an area where the dropdown overlaps with another component
3. Only the dropdown item should activate, NOT both components

## Expected Results:
- Single click = single component activation
- No "click-through" to components underneath
- Proper z-order layering

## 5. Test Component Isolation

1. Try various edge cases:
   - Click outside the menu area
   - Rapidly move mouse across menu items
   - Click multiple times quickly on menu items
   
2. Click the **"Reset Scene"** button

## Expected Results:
- MenuBar handles all interactions gracefully
- No crashes affect the Widget Workbench
- Reset Scene clears the component and returns to green circle

## 6. Data Format Compatibility Test

1. After resetting, load MenuBar again
2. Verify it loads without errors

## Expected Results:
- No "Invalid Translation Received" errors
- MenuBar appears at correct position (80, 80)
- All data formats are properly converted

## Issues to Watch For:

### ❌ Known Issues:
1. **Flickering**: When hovering between menu items or dropdowns
2. **Click-through**: Clicking on dropdown activates multiple components
3. **Position**: MenuBar appears at (0, 0) instead of configured position
4. **Translation errors**: Coordinates struct vs tuple format issues

### ✅ Fixed Issues:
1. Menu items now use strings instead of atoms
2. IconButton translation format fixed
3. Component data preparation handles Widgex.Frame properly

## Notes:
- The comprehensive spex file (`test/spex/menu_bar_comprehensive_spex.exs`) automates all these tests
- Once scenic_mcp connection issues are resolved, the spex can run automatically
- The goal is to fix any issues found before integrating MenuBar back into Flamelex