# Meta-Prompt for Opus4: Creating an AI Enhancement Prompt for Spex Writing

## Your Task

Create a comprehensive, reusable prompt that can be given to AI agents (like Claude, GPT-4, or other LLMs) to dramatically improve their ability to write high-quality Spex (Specification by Example) test files for Scenic GUI applications in Elixir.

## Background

Spex files are BDD-style executable specifications that:
- Use the SexySpex DSL with Given/When/Then structure
- Test Scenic GUI components through ScenicMcp.Probes
- Serve as both tests and living documentation
- Must handle asynchronous UI behavior correctly
- Should follow established UI/UX patterns for each component type

## Current Challenges

AI agents often struggle with:
1. Understanding the nuances of GUI testing vs unit testing
2. Properly handling timing/synchronization in UI tests
3. Knowing standard UI patterns (e.g., menubars use click-to-open, not hover)
4. Writing comprehensive scenarios that catch real bugs
5. Structuring tests for maintainability
6. Using the SexySpex DSL idiomatically

## What Makes a Good Spex File

Review these example patterns:

### Successful Pattern (from comprehensive_text_editing_spex.exs):
```elixir
scenario "Basic character input and display", context do
  given_ "empty buffer ready for input", context do
    ScenicMcp.Probes.send_keys("a", [:ctrl])  # Clear content
    Process.sleep(50)
    baseline_screenshot = ScenicMcp.Probes.take_screenshot("baseline")
    {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
  end

  when_ "user types various characters", context do
    test_string = "Hello World! 123"
    ScenicMcp.Probes.send_text(test_string)
    Process.sleep(100)
    {:ok, Map.merge(context, %{test_string: test_string})}
  end

  then_ "all characters should be displayed correctly", context do
    assert ScriptInspector.rendered_text_contains?(context.test_string),
           "Expected: '#{context.test_string}'"
    :ok
  end
end
```

### Key Elements:
- Clear scenario focus
- Proper state management through context
- Realistic user actions
- Appropriate timing delays
- Visual verification via screenshots
- Descriptive assertions

## Your Deliverable

Create a comprehensive prompt (2000-3000 words) that:

1. **Teaches Core Concepts**:
   - SexySpex DSL syntax and idioms
   - ScenicMcp.Probes API and when to use each function
   - GUI testing principles vs unit testing
   - Context management between test steps

2. **Provides Patterns and Examples**:
   - Common UI component test patterns (menus, text input, buttons, etc.)
   - Timing and synchronization strategies
   - Screenshot strategies for visual regression testing
   - Helper function patterns for DRY code

3. **Includes Component-Specific Guidance**:
   - Standard desktop menubar behaviors
   - Text editor patterns (cursor, selection, clipboard)
   - Form input validation patterns
   - Modal and dialog behaviors

4. **Emphasizes Best Practices**:
   - One behavior per scenario
   - Comprehensive edge case coverage
   - Self-documenting test descriptions
   - Proper error messages in assertions

5. **Provides a Structured Approach**:
   - Research phase (understanding standard UI patterns)
   - Planning phase (identifying scenarios)
   - Implementation phase (writing the spex)
   - Validation phase (ensuring completeness)

## Format Requirements

The prompt should:
- Be self-contained (no external references needed)
- Include concrete examples for each concept
- Have a clear structure with sections and subsections
- Be written in an instructional tone
- Include a "quick reference" section for common patterns
- End with a checklist for validating spex quality

## Success Criteria

An AI agent using your prompt should be able to:
1. Write a complete spex file that passes on first run
2. Cover all standard behaviors for the component type
3. Handle edge cases and error conditions
4. Produce tests that actually catch bugs
5. Create documentation-quality test descriptions

Please generate this comprehensive prompt that will elevate any AI agent's ability to write professional-quality Spex files for Scenic applications.