# AI Agent Enhancement Prompt: Writing High-Quality Spex Files for Scenic Applications

## Context
You are tasked with creating a comprehensive prompt that will enhance AI agents' ability to write Spex (Specification by Example) files for Scenic GUI applications in Elixir. Spex files serve as both executable specifications and acceptance tests, following BDD (Behavior-Driven Development) principles.

## Objective
Generate a detailed prompt that teaches AI agents how to write production-ready Spex files that:
1. Follow SexySpex DSL conventions perfectly
2. Test real UI behaviors comprehensively 
3. Are maintainable and self-documenting
4. Catch edge cases and prevent regressions
5. Serve as living documentation for the component

## Required Knowledge Areas

### 1. SexySpex DSL Structure
```elixir
spex "Feature Name", description: "What this validates", tags: [:tag1, :tag2] do
  scenario "Scenario description", context do
    given_ "initial state description", context do
      # Setup code
      {:ok, Map.put(context, :key, value)}
    end
    
    when_ "action description", context do
      # Action code
      {:ok, Map.merge(context, %{result: result})}
    end
    
    then_ "expected outcome description", context do
      # Assertion code
      assert condition, "Error message"
      :ok
    end
    
    and_ "additional outcome", context do
      # More assertions
      :ok
    end
  end
end
```

### 2. ScenicMcp.Probes API
- `send_text(text)` - Type text string
- `send_keys(key, modifiers \\ [])` - Send special keys
- `send_mouse_click(x, y, button \\ :left)` - Click at position
- `send_mouse_move(x, y)` - Move mouse cursor
- `take_screenshot(name)` - Capture visual state
- `script_table()` - Get rendering data

### 3. ScriptInspector Helpers
- `get_rendered_text_string()` - Extract all rendered text
- `rendered_text_contains?(text)` - Check if text is visible
- Pattern matching on script data for detailed assertions

### 4. Standard UI Testing Patterns

#### State Management
- Use context map to pass data between steps
- Take screenshots at key points for visual verification
- Always return `{:ok, updated_context}` or `:ok`

#### Timing and Synchronization
```elixir
Process.sleep(100)  # Allow UI to update
# Use longer delays for complex operations
```

#### Comprehensive Coverage
1. Happy path scenarios
2. Edge cases (empty data, boundaries)
3. Error conditions
4. Rapid interactions
5. State transitions

### 5. Component-Specific Patterns

#### For Menu Components
- Test click-to-open behavior (not hover)
- Verify hover navigation after activation
- Test click-outside-to-close
- Check z-order/layering
- Validate keyboard shortcuts

#### For Text Input Components
- Test character input/display
- Cursor movement
- Selection (keyboard and mouse)
- Clipboard operations
- Multi-line handling

#### For Interactive Components
- Mouse interactions (click, drag, hover)
- Keyboard navigation
- Focus management
- Event propagation
- Visual feedback

### 6. Best Practices

#### Scenario Organization
```elixir
# =============================================================================
# 1. FEATURE CATEGORY (e.g., BASIC RENDERING)
# =============================================================================

scenario "Specific behavior being tested", context do
  # Focused test of one aspect
end
```

#### Assertions
- Use descriptive error messages
- Test both positive and negative cases
- Verify visual and behavioral aspects

#### Screenshots
```elixir
screenshot = ScenicMcp.Probes.take_screenshot("descriptive_name")
{:ok, Map.put(context, :screenshot_key, screenshot)}
```

#### Helper Functions
```elixir
defp calculate_element_position(base_x, base_y, item_index) do
  # Reusable position calculations
end

defp verify_element_visible(element_text) do
  # Common verification patterns
end
```

## Prompt Template

When writing Spex files for Scenic components:

1. **Start with Research**: Understand the standard behaviors for the UI component type (research desktop application patterns)

2. **Structure Comprehensively**:
   - Basic rendering and layout
   - User interactions (mouse, keyboard)
   - State management
   - Edge cases
   - Performance scenarios

3. **Follow the Pattern**:
   ```elixir
   given_ "clear initial state"
   when_ "specific user action"
   then_ "expected visual/behavioral outcome"
   and_ "additional verifications"
   ```

4. **Test Real Behaviors**: Focus on what users actually do, not implementation details

5. **Use Visual Verification**: Take screenshots at critical points

6. **Handle Timing**: Add appropriate delays for UI updates

7. **Write Self-Documenting Tests**: Scenario descriptions should explain the why, not just the what

## Example Analysis

Good Spex characteristics:
- Tests one specific behavior per scenario
- Uses realistic test data
- Verifies both visual and functional aspects
- Handles asynchronous UI updates
- Provides clear failure messages
- Serves as usage documentation

## Output Requirements

The AI should produce Spex files that:
1. Pass on first run (no debugging needed)
2. Catch real bugs (not just superficial checks)
3. Are maintainable as the component evolves
4. Serve as comprehensive documentation
5. Follow established UI/UX standards

## Validation Checklist

Before considering a Spex file complete, verify:
- [ ] All standard behaviors for the component type are tested
- [ ] Edge cases are covered
- [ ] Screenshots are taken at key points
- [ ] Timing issues are handled
- [ ] Helper functions reduce duplication
- [ ] Assertions have descriptive messages
- [ ] Code is well-organized with clear sections
- [ ] The file serves as good documentation