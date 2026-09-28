# Scenic ViewPort.register_semantic Fix - Task Prompt

**Priority**: HIGH - Blocking Widget Workbench component loading
**Estimated Time**: 20-40 minutes
**Context**: Widget Workbench starts but crashes when trying to register MCP semantic elements

---

## 🎯 Problem Statement

Widget Workbench starts successfully but crashes when loading the component modal:

```
[error] GenServer #PID<0.874.0> terminating
** (UndefinedFunctionError) function Scenic.ViewPort.register_semantic/4 is undefined or private
    (scenic 0.12.0-rc.0) Scenic.ViewPort.register_semantic(%Scenic.ViewPort{...}, :_root_, :component_icon_button, %{...})
    (scenic_widget_contrib 0.1.0) lib/widget_workbench/widget_wkb_scene.ex:2122: anonymous fn/4 in WidgetWorkbench.Scene.register_modal_components_for_mcp/1
```

## 📋 Task Objective

Fix the `register_semantic` function calls so that:
1. Widget Workbench can register MCP semantic elements without crashing
2. Components (MenuBar, SideNav) can register their elements
3. MCP automation can interact with the GUI via semantic IDs

## 🔍 Root Cause Analysis

### The Issue

`Scenic.ViewPort.register_semantic/4` doesn't exist in core Scenic `0.12.0-rc.0`.

### Likely Causes

1. **Function is in scenic_mcp, not core Scenic** (Most Likely)
   - MCP functionality is provided by `scenic_mcp` package
   - Function probably in `ScenicMcp.ViewPort` or similar module

2. **Function has different name/arity**
   - API might have changed
   - Could be `register_element`, `add_semantic`, etc.

3. **Function not yet implemented**
   - scenic_mcp might not have this feature yet
   - Needs to be added or is work-in-progress

## 🔍 Investigation Steps

### 1. Find where register_semantic is defined

```bash
cd /Users/luke/workbench/flx/scenic-widget-contrib

# Search scenic_mcp for the function
grep -rn "def register_semantic" ../scenic_mcp*/
grep -rn "defdelegate register_semantic" ../scenic_mcp*/

# Search for any semantic-related functions
grep -rn "semantic" ../scenic_mcp*/lib/ | grep "def "

# Check if it's in Scenic core (unlikely based on error)
grep -rn "def register_semantic" ../scenic_local/
```

### 2. Check ScenicMcp module structure

```bash
# List scenic_mcp modules
ls -la ../scenic_mcp*/lib/scenic_mcp/
ls -la ../scenic_mcp_experimental/lib/scenic_mcp/

# Look for ViewPort-related modules
find ../scenic_mcp* -name "*viewport*" -o -name "*view_port*"
```

### 3. Find all call sites

```bash
# Find everywhere register_semantic is called
grep -rn "register_semantic" lib/ test/

# This will show all places that need to be updated
```

## 🛠️ Likely Solutions (Try in Order)

### Solution 1: Use ScenicMcp.ViewPort instead of Scenic.ViewPort

**Most Likely Fix**: The function exists in `ScenicMcp.ViewPort`, not `Scenic.ViewPort`

**Find and replace pattern**:

```bash
# Check if this exists
grep -rn "ScenicMcp.ViewPort" ../scenic_mcp*/lib/
```

**If found**, update all call sites:

**From**:
```elixir
Scenic.ViewPort.register_semantic(viewport, graph_key, semantic_id, metadata)
```

**To**:
```elixir
ScenicMcp.ViewPort.register_semantic(viewport, graph_key, semantic_id, metadata)
```

**Files to update**:
1. `lib/widget_workbench/widget_wkb_scene.ex:2122` (and nearby calls)
2. `lib/components/menu_bar/menu_bar.ex:~325`
3. `lib/components/side_nav/side_nav.ex:~323`
4. Any other components using semantic registration

### Solution 2: Use ScenicMcp.register_semantic/4 (Module function)

If it's a module-level function instead of ViewPort method:

**From**:
```elixir
Scenic.ViewPort.register_semantic(viewport, graph_key, semantic_id, metadata)
```

**To**:
```elixir
ScenicMcp.register_semantic(viewport, graph_key, semantic_id, metadata)
```

### Solution 3: Make register_semantic calls optional/safe

If the function isn't available yet, wrap calls in safe guards:

```elixir
defp register_semantic_safe(viewport, graph_key, semantic_id, metadata) do
  if function_exported?(ScenicMcp.ViewPort, :register_semantic, 4) do
    ScenicMcp.ViewPort.register_semantic(viewport, graph_key, semantic_id, metadata)
  else
    # Log warning but don't crash
    require Logger
    Logger.debug("Semantic registration skipped - ScenicMcp.ViewPort.register_semantic/4 not available")
    :ok
  end
end

# Then use:
register_semantic_safe(viewport, graph_key, semantic_id, metadata)
```

This allows the app to run without MCP semantic registration if the function isn't available.

### Solution 4: Check scenic_mcp version and update

```bash
cd ../scenic_mcp  # or scenic_mcp_experimental
git log --oneline -20  # Check recent commits
git pull origin main   # Update if needed
mix compile
```

Then back in scenic-widget-contrib:
```bash
mix deps.compile scenic_mcp --force
mix compile
```

## 📝 Files to Update

### Primary Files (Confirmed Call Sites)

1. **`lib/widget_workbench/widget_wkb_scene.ex`**
   - Line ~2122: `register_modal_components_for_mcp/1`
   - Likely other calls in this file
   - Search for all `register_semantic` in file

2. **`lib/components/menu_bar/menu_bar.ex`**
   - Line ~325: `register_semantic_elements/2`
   - Used to register menu buttons for MCP

3. **`lib/components/side_nav/side_nav.ex`**
   - Line ~323: `register_semantic_elements/2`
   - Used to register sidebar items for MCP

### Pattern for Updates

**Create a helper module** (recommended approach):

Create `lib/scenic_widgets/mcp_helper.ex`:

```elixir
defmodule ScenicWidgets.McpHelper do
  @moduledoc """
  Helper functions for MCP semantic element registration.
  Handles compatibility across different scenic_mcp versions.
  """

  require Logger

  @doc """
  Register a semantic element with MCP if available.
  Falls back gracefully if scenic_mcp not available or function missing.
  """
  def register_semantic(viewport, graph_key, semantic_id, metadata) do
    cond do
      # Try ScenicMcp.ViewPort first
      function_exported?(ScenicMcp.ViewPort, :register_semantic, 4) ->
        ScenicMcp.ViewPort.register_semantic(viewport, graph_key, semantic_id, metadata)

      # Try ScenicMcp module-level function
      function_exported?(ScenicMcp, :register_semantic, 4) ->
        ScenicMcp.register_semantic(viewport, graph_key, semantic_id, metadata)

      # Try Scenic.ViewPort (for newer versions)
      function_exported?(Scenic.ViewPort, :register_semantic, 4) ->
        Scenic.ViewPort.register_semantic(viewport, graph_key, semantic_id, metadata)

      # Function not available
      true ->
        Logger.debug(
          "MCP semantic registration skipped for #{inspect(semantic_id)} - " <>
          "register_semantic/4 not available in current scenic_mcp version"
        )
        :ok
    end
  end
end
```

Then update all call sites to use:
```elixir
alias ScenicWidgets.McpHelper

# Instead of:
Scenic.ViewPort.register_semantic(...)

# Use:
McpHelper.register_semantic(...)
```

## ✅ Success Criteria

After fix:

1. **Widget Workbench starts** ✅ (Already working)
2. **Component modal opens** ✅ (Should work after fix)
3. **Components load without crashing** ✅ (Target)
4. **No GenServer termination errors** ✅ (Target)
5. **MCP semantic registration works OR degrades gracefully** ✅ (Target)

## 🧪 Verification Steps

### 1. Test Widget Workbench Startup

```bash
cd scenic-widget-contrib
iex -S mix
```

**Expected**: No crash, window opens

### 2. Test Component Modal

In the GUI:
1. Click "Load Component" button
2. Modal should open showing component list
3. No error messages in console

**Expected**: Modal opens, components listed, no crashes

### 3. Test Component Loading

1. Select "Menu Bar" from list
2. Component should load and render
3. Check console for any errors

**Expected**: Component loads, renders, no semantic registration errors

### 4. Test MCP Registration (if applicable)

If scenic_mcp tools available:
```bash
# In another terminal
cd scenic_mcp
# Try to list semantic elements (if command exists)
```

## 🔗 Related Context

- **Previous fix**: Added scenic_mcp as dependency (`WIDGET_WORKBENCH_STARTUP_FIX.md`)
- **Current status**: Widget Workbench starts but crashes on component registration
- **Blocking**: Manual testing of SideNav component
- **Related files**: All components using semantic registration

## 🎯 Quick Start Commands

```bash
cd /Users/luke/workbench/flx/scenic-widget-contrib

# 1. Find where register_semantic is defined
grep -rn "def register_semantic" ../scenic_mcp*/lib/

# 2. Find all call sites in our code
grep -rn "register_semantic" lib/

# 3. Check scenic_mcp modules
ls -la ../scenic_mcp*/lib/scenic_mcp/

# 4. Try the most likely fix (update call sites)
# Edit files: widget_wkb_scene.ex, menu_bar.ex, side_nav.ex
# Change: Scenic.ViewPort.register_semantic → ScenicMcp.ViewPort.register_semantic

# 5. Test
mix compile
iex -S mix
```

## 💡 Expected Findings

Based on the error and common patterns:

**Most Likely**: `register_semantic` is in `ScenicMcp.ViewPort`, not `Scenic.ViewPort`

**Why**: MCP (Model Context Protocol) is an extension to Scenic, not part of core Scenic. Functions for MCP should be in the scenic_mcp package.

**Similar Pattern**: Like how we had to add scenic_mcp dependency to access `ScenicMcp.Config`, we need to use `ScenicMcp.ViewPort` to access semantic registration.

## 🚨 Fallback Plan

If the function truly doesn't exist in scenic_mcp:

1. **Comment out semantic registration temporarily**
   - Wrap in `try/rescue`
   - Or use the helper with graceful degradation
   - App will work but MCP automation won't have semantic IDs

2. **Test without MCP features**
   - Manual testing will still work
   - Just can't use MCP automation for this component

3. **File issue with scenic_mcp**
   - Document the missing feature
   - Or implement it if needed

## 📚 Reference

### Working MCP Registration Pattern

From test files that work:
```elixir
# This pattern works in spex tests
viewport = scene.viewport
Scenic.ViewPort.register_semantic(viewport, ...)
```

**But**: Spex tests might not actually call register_semantic, or might have different setup.

### Check MenuBar Implementation

The MenuBar component has working semantic registration (at least before), check how it's currently implemented:

```bash
grep -A 20 "def register_semantic_elements" lib/components/menu_bar/menu_bar.ex
```

---

## 🚀 TL;DR - Quick Fix

**Most Likely Solution**:

1. **Find the correct module**:
   ```bash
   grep -rn "def register_semantic" ../scenic_mcp*/lib/
   ```

2. **Update call sites** (probably needs to be `ScenicMcp.ViewPort`):
   ```elixir
   # Change all instances:
   Scenic.ViewPort.register_semantic(...)
   # To:
   ScenicMcp.ViewPort.register_semantic(...)
   ```

3. **Files to update**:
   - `lib/widget_workbench/widget_wkb_scene.ex`
   - `lib/components/menu_bar/menu_bar.ex`
   - `lib/components/side_nav/side_nav.ex`

4. **Test**:
   ```bash
   mix compile && iex -S mix
   ```

**Alternative**: Use the safe helper pattern (Solution 3) if function doesn't exist yet.

---

**Created**: 2025-11-23
**Priority**: HIGH
**Blocking**: Component loading in Widget Workbench
**Previous Issue**: ✅ Fixed - scenic_mcp dependency added
