# Unit Tests for Telegram Bot API Library

This document describes the comprehensive unit tests added to the `src/telegram.zig` file, covering the most critical functionality of the Telegram Bot API library.

## Overview

The unit tests follow Zig's standard testing patterns and ensure that the core bot functionality works correctly. All tests use proper memory management with explicit cleanup to prevent memory leaks.

## Test Coverage

### 1. Bot Initialization and Cleanup (`test "Bot initialization and cleanup"`)

**Purpose**: Verifies that the Bot and HTTPClient can be properly initialized and cleaned up.

**What it tests**:
- HTTPClient initialization and cleanup
- Valid bot initialization with proper token
- Invalid bot initialization (empty token should return `BotError.InvalidToken`)
- Custom API endpoint configuration
- Proper field initialization (debug mode, API endpoint, etc.)

**Key assertions**:
```zig
try testing.expect(bot.token.len > 0);
try testing.expectEqualStrings("123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11", bot.token);
try testing.expectEqual(false, bot.debug);
try testing.expectEqualStrings("https://api.telegram.org", bot.api_endpoint);
try testing.expectError(BotError.InvalidToken, Bot.init(allocator, "", &client));
```

### 2. Request Parameter Creation and Formatting (`test "Request parameter creation and formatting"`)

**Purpose**: Ensures that number formatting and parameter creation work correctly for API requests.

**What it tests**:
- i64 number formatting (positive and negative)
- i32 number formatting
- f64 number formatting
- Parameter creation using the json_utils module
- Parameter count and value verification

**Key assertions**:
```zig
try testing.expectEqualStrings("123456789012345", Bot.formatI64(123456789012345, &buffer));
try testing.expectEqualStrings("-123456789", Bot.formatI64(-123456789, &buffer));
try testing.expectEqualStrings("123456789", params.get("chat_id").?);
try testing.expectEqual(@as(usize, 3), params.count());
```

### 3. Update Parsing from JSON (`test "Update parsing from JSON"`)

**Purpose**: Verifies that incoming Telegram updates can be correctly parsed from JSON.

**What it tests**:
- Message update parsing with all required fields
- Callback query update parsing
- Proper field extraction and type conversion
- Invalid JSON handling (should return `error.SyntaxError`)
- Memory management for nested structures

**Key assertions**:
```zig
try testing.expectEqual(@as(i32, 123456), update.update_id);
try testing.expect(update.message != null);
try testing.expectEqualStrings("Hello, bot!", update.message.?.text.?);
try testing.expectEqual(@as(i64, 987654321), update.message.?.from.?.id);
try testing.expectError(error.SyntaxError, invalid_json_result);
```

### 4. API Response Structure Parsing (`test "API response structure parsing"`)

**Purpose**: Ensures that Telegram API responses can be correctly parsed and validated.

**What it tests**:
- Successful API response parsing (`ok: true`)
- Error API response parsing (`ok: false` with error codes and descriptions)
- APIResponseWithResult structure for complex responses
- Proper JSON field extraction and type checking

**Key assertions**:
```zig
try testing.expectEqual(true, parsed.value.ok);
try testing.expectEqual(false, error_response.ok);
try testing.expectEqual(@as(i32, 400), error_response.error_code.?);
try testing.expectEqualStrings("Bad Request: chat not found", error_response.description.?);
try testing.expect(result_response.result.?.array.items.len == 2);
```

### 5. Memory Management and Cleanup (`test "Memory management and cleanup"`)

**Purpose**: Verifies that all data structures properly manage memory and can be safely cleaned up.

**What it tests**:
- User struct creation and cleanup
- Chat struct creation and cleanup
- MessageEntity struct creation and cleanup
- InlineKeyboardButton struct creation and cleanup
- File struct creation and cleanup
- Proper string duplication and deallocation

**Key assertions**:
```zig
try testing.expectEqual(@as(i64, 123456789), user.id);
try testing.expectEqualStrings("Test User", user.first_name);
try testing.expectEqualStrings("private", chat.type);
try testing.expectEqualStrings("mention", entity.type);
try testing.expectEqualStrings("Click Me", button.text);
try testing.expectEqualStrings("BAADBAADrQADBREAAYlIjHkZFYSNAg", file.file_id);
```

## Testing Patterns Used

### Memory Safety
- All tests use `defer` statements to ensure cleanup happens even on test failures
- Proper allocator usage with `testing.allocator`
- String duplication and cleanup for owned strings

### Error Handling
- Tests verify that appropriate errors are returned for invalid inputs
- Both successful and failure cases are tested
- Proper error type checking with `expectError`

### JSON Handling
- Real-world JSON structures are used in tests
- Both valid and invalid JSON parsing is tested
- Complex nested structures are properly validated

### Type Safety
- Explicit type casting where needed (`@as(i32, 123456)`)
- Proper optional field handling (`?.field`)
- Null pointer checks and optional unwrapping

## Running the Tests

```bash
# Run all tests in the telegram.zig file
zig test src/telegram.zig

# Run through the build system
zig build test

# Run with verbose output
zig test src/telegram.zig --verbose
```

## Test Output

When all tests pass, you should see:
```
All 9 tests passed.
```

The debug output shows the JSON parsing process, which helps verify that the parsing logic is working correctly.

## Integration with Existing Code

These tests follow the same patterns established in the `src/json.zig` file and integrate seamlessly with the existing codebase. They respect the project's principles:

- **KISS (Keep It Simple, Stupid)**: Tests are straightforward and focus on one thing at a time
- **DRY (Don't Repeat Yourself)**: Common patterns are reused across tests
- **Memory Safety**: All allocations are properly cleaned up
- **Error Handling**: Explicit error testing with appropriate error types

## Future Considerations

These tests provide a solid foundation for the library. Additional tests could be added for:
- HTTP request/response handling (would require mocking)
- More complex API method testing
- Edge cases and boundary conditions
- Performance benchmarks
- Integration tests with real Telegram API (requiring test tokens)

The current test suite ensures that the core functionality is robust and reliable, following Zig's philosophy of explicit behavior and memory safety. 