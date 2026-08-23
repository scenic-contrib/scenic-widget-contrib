# MenuBar Spex Test Fixes

## Fixed Issues

### 1. MenuBar Comprehensive Spex (`menu_bar_comprehensive_spex.exs`)
- **Added proper startup**: Now starts Widget Workbench in `setup_all` like simple_workbench_spex does
- **Fixed deprecated single-quoted strings**: Changed `'localhost'` to `~c"localhost"`
- **Fixed unused variables**: 
  - Changed `for _i <- 1..3` to `for _ <- 1..3`
  - Prefixed unused `context` parameters with underscore where not used

### 2. Simple Workbench Spex (`simple_workbench_spex.exs`)
- **Removed non-existent module references**: Replaced `SexySpex.Helpers` calls with proper Application module functions
- **Fixed duplicate comment**: Removed duplicate "Verify the application is running" comment
- **Fixed unused variables**: Prefixed unused `context` parameters with underscore where not used

## How Tests Now Work

Both tests now follow the same pattern:

1. **setup_all**: 
   - Ensures scenic_widget_contrib application is started
   - Starts Widget Workbench with proper size and title
   - Registers cleanup callback to stop workbench on exit

2. **Test Flow**:
   - Verify workbench is running
   - Use ScenicMcp.Probes for all interactions (clicks, screenshots, etc.)
   - Use ScriptInspector to verify rendered content

## Running the Tests

```bash
# Run individual spex tests
mix spex test/spex/simple_workbench_spex.exs
mix spex test/spex/menu_bar_comprehensive_spex.exs

# Run all spex tests
mix spex
```

The tests should now run without warnings and properly start/stop the Widget Workbench.