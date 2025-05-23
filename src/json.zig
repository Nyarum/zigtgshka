/// Generic JSON marshaling and unmarshaling library for Zig
///
/// This library provides a clean interface for converting between Zig structs and JSON,
/// eliminating the need for manual JSON string building and parsing.
///
/// ## Features
/// - Generic Marshal function to convert any Zig struct to JSON string
/// - Generic Unmarshal function to convert JSON string to any Zig struct
/// - Automatic JSON escaping and proper formatting
/// - Support for nested structs, arrays, and optional fields
/// - Memory-safe operations with proper cleanup patterns
/// - Type-safe conversions with compile-time checks
///
/// ## Usage
/// ```zig
/// const json = @import("json.zig");
///
/// // Marshal struct to JSON
/// const my_struct = MyStruct{ .field1 = "value", .field2 = 42 };
/// const json_string = try json.marshal(allocator, my_struct);
/// defer allocator.free(json_string);
///
/// // Unmarshal JSON to struct
/// const parsed = try json.unmarshal(MyStruct, allocator, json_string);
/// defer parsed.deinit(allocator);
/// ```
const std = @import("std");
const Allocator = std.mem.Allocator;

/// JSON marshaling and unmarshaling errors
pub const JSONError = error{
    /// Failed to parse JSON string
    ParseError,
    /// Type mismatch during unmarshaling
    TypeMismatch,
    /// Required field is missing
    MissingField,
    /// Memory allocation failed
    OutOfMemory,
    /// Unsupported type for marshaling/unmarshaling
    UnsupportedType,
    /// Invalid JSON format
    InvalidFormat,
};

/// Marshal any Zig value to a JSON string
///
/// This function converts a Zig value to its JSON representation.
/// Supports structs, arrays, slices, optionals, and basic types.
///
/// Args:
///     allocator: Memory allocator for the resulting JSON string
///     value: The value to marshal to JSON
///
/// Returns:
///     JSON string representation (caller owns memory) or error
///
/// Example:
/// ```zig
/// const data = .{ .name = "John", .age = 30, .active = true };
/// const json_str = try marshal(allocator, data);
/// defer allocator.free(json_str);
/// // json_str = {"name":"John","age":30,"active":true}
/// ```
pub fn marshal(allocator: Allocator, value: anytype) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try marshalValue(allocator, &result, value);
    return result.toOwnedSlice();
}

/// Unmarshal JSON string to a Zig type
///
/// This function parses a JSON string and converts it to the specified Zig type.
/// The type must be specified as a comptime parameter.
///
/// Args:
///     comptime T: The target type to unmarshal to
///     allocator: Memory allocator for any heap allocations
///     json_string: JSON string to parse
///
/// Returns:
///     Parsed value of type T or error
///
/// Note: If the type contains allocated fields (strings, arrays),
/// call the appropriate deinit method to free memory.
///
/// Example:
/// ```zig
/// const MyStruct = struct { name: []const u8, age: i32 };
/// const parsed = try unmarshal(MyStruct, allocator, "{\"name\":\"John\",\"age\":30}");
/// defer allocator.free(parsed.name); // Free allocated strings
/// ```
pub fn unmarshal(comptime T: type, allocator: Allocator, json_string: []const u8) !T {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_string, .{});
    defer parsed.deinit();

    return try unmarshalValue(T, allocator, parsed.value);
}

/// Create a parameters map from a struct
///
/// This function converts a struct to a StringHashMap suitable for API requests.
/// It handles type conversion automatically (numbers to strings, etc.).
///
/// Args:
///     allocator: Memory allocator for the map and string conversions
///     value: The struct to convert to parameters
///
/// Returns:
///     StringHashMap with parameter key-value pairs or error
///
/// Note: Caller must call deinit() on the returned map and free any allocated strings
///
/// Example:
/// ```zig
/// const params_struct = .{ .chat_id = 123, .text = "Hello" };
/// var params = try createParams(allocator, params_struct);
/// defer cleanupParams(allocator, &params);
/// ```
pub fn createParams(allocator: Allocator, value: anytype) !std.StringHashMap([]const u8) {
    var params = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        // Clean up any values that were already added on error
        var iterator = params.iterator();
        while (iterator.next()) |entry| {
            // For error cleanup, we need to check each field type individually
            // This is less efficient but necessary for proper cleanup
            const T = @TypeOf(value);
            const type_info = @typeInfo(T);

            if (type_info == .@"struct") {
                inline for (type_info.@"struct".fields) |field| {
                    if (std.mem.eql(u8, field.name, entry.key_ptr.*)) {
                        const field_value = @field(value, field.name);
                        if (needsAllocation(field_value)) {
                            allocator.free(entry.value_ptr.*);
                        }
                        break;
                    }
                }
            }
        }
        params.deinit();
    }

    try addStructToParams(allocator, &params, value);
    return params;
}

/// Clean up a parameters map created by createParams
///
/// This function properly frees all allocated strings in the parameter map
/// and deinitializes the map itself.
///
/// Args:
///     allocator: The allocator used to create the map
///     params: Pointer to the parameters map to clean up
///     original_value: The original struct value used to create the params (for type checking)
pub fn cleanupParamsWithValue(allocator: Allocator, params: *std.StringHashMap([]const u8), original_value: anytype) void {
    const T = @TypeOf(original_value);
    const type_info = @typeInfo(T);

    if (type_info == .@"struct") {
        var iterator = params.iterator();
        while (iterator.next()) |entry| {
            // Find the corresponding field in the struct
            inline for (type_info.@"struct".fields) |field| {
                if (std.mem.eql(u8, field.name, entry.key_ptr.*)) {
                    const field_value = @field(original_value, field.name);
                    if (needsAllocation(field_value)) {
                        allocator.free(entry.value_ptr.*);
                    }
                    break;
                }
            }
        }
    }
    params.deinit();
}

/// Clean up a parameters map created by createParams (legacy version)
///
/// This function properly frees all allocated strings in the parameter map
/// and deinitializes the map itself.
///
/// Args:
///     allocator: The allocator used to create the map
///     params: Pointer to the parameters map to clean up
pub fn cleanupParams(allocator: Allocator, params: *std.StringHashMap([]const u8)) void {
    var iterator = params.iterator();
    while (iterator.next()) |entry| {
        // For backwards compatibility, try to detect allocated strings
        // This is not perfect but works for simple integer types
        const value = entry.value_ptr.*;

        // Check if it looks like a number (simple heuristic)
        var is_number = true;
        if (value.len == 0) {
            is_number = false;
        } else {
            for (value) |char| {
                if (!std.ascii.isDigit(char) and char != '-' and char != '.') {
                    is_number = false;
                    break;
                }
            }
        }

        // If it looks like a number, it was probably allocated by std.fmt.allocPrint
        if (is_number and value.len > 0) {
            allocator.free(value);
        }
    }
    params.deinit();
}

// ===== PRIVATE HELPER FUNCTIONS =====

/// Marshal a single value to JSON, appending to the result ArrayList
fn marshalValue(allocator: Allocator, result: *std.ArrayList(u8), value: anytype) !void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .bool => {
            if (value) {
                try result.appendSlice("true");
            } else {
                try result.appendSlice("false");
            }
        },
        .int, .comptime_int => {
            try result.writer().print("{d}", .{value});
        },
        .float, .comptime_float => {
            try result.writer().print("{d}", .{value});
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .slice => {
                    if (ptr_info.child == u8) {
                        // String slice
                        try result.append('"');
                        try appendEscapedString(result, value);
                        try result.append('"');
                    } else {
                        // Array slice
                        try result.append('[');
                        for (value, 0..) |item, i| {
                            if (i > 0) try result.append(',');
                            try marshalValue(allocator, result, item);
                        }
                        try result.append(']');
                    }
                },
                .one => {
                    // Pointer to single item
                    try marshalValue(allocator, result, value.*);
                },
                else => return JSONError.UnsupportedType,
            }
        },
        .array => |array_info| {
            if (array_info.child == u8) {
                // String array (treat as string)
                try result.append('"');
                try appendEscapedString(result, value[0..]);
                try result.append('"');
            } else {
                // Regular array
                try result.append('[');
                for (value, 0..) |item, i| {
                    if (i > 0) try result.append(',');
                    try marshalValue(allocator, result, item);
                }
                try result.append(']');
            }
        },
        .optional => {
            if (value) |val| {
                try marshalValue(allocator, result, val);
            } else {
                try result.appendSlice("null");
            }
        },
        .@"struct" => |struct_info| {
            try result.append('{');
            var first = true;

            inline for (struct_info.fields) |field| {
                const field_value = @field(value, field.name);

                // Handle optional fields at comptime
                const is_optional = comptime @typeInfo(field.type) == .optional;

                // Use separate logic paths for optional and non-optional fields
                const should_include_field = if (comptime is_optional)
                    field_value != null
                else
                    true;

                if (should_include_field) {
                    if (!first) try result.append(',');

                    // Add field name
                    try result.append('"');
                    try result.appendSlice(field.name);
                    try result.appendSlice("\":");

                    // Add field value
                    try marshalValue(allocator, result, field_value);
                    first = false;
                }
            }

            try result.append('}');
        },
        .@"enum" => {
            // Marshal enum as string
            try result.append('"');
            try result.appendSlice(@tagName(value));
            try result.append('"');
        },
        else => return JSONError.UnsupportedType,
    }
}

/// Unmarshal a JSON value to a specific Zig type
pub fn unmarshalValue(comptime T: type, allocator: Allocator, json_value: std.json.Value) JSONError!T {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .bool => {
            return switch (json_value) {
                .bool => |b| b,
                else => JSONError.TypeMismatch,
            };
        },
        .int => {
            return switch (json_value) {
                .integer => |i| @intCast(i),
                .float => |f| @intFromFloat(f),
                else => JSONError.TypeMismatch,
            };
        },
        .float => {
            return switch (json_value) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => JSONError.TypeMismatch,
            };
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .slice => {
                    if (ptr_info.child == u8) {
                        // String slice
                        return switch (json_value) {
                            .string => |s| try allocator.dupe(u8, s),
                            else => JSONError.TypeMismatch,
                        };
                    } else {
                        // Array slice
                        return switch (json_value) {
                            .array => |arr| {
                                var result = try allocator.alloc(ptr_info.child, arr.items.len);
                                for (arr.items, 0..) |item, i| {
                                    result[i] = try unmarshalValue(ptr_info.child, allocator, item);
                                }
                                return result;
                            },
                            else => JSONError.TypeMismatch,
                        };
                    }
                },
                .one => {
                    // Pointer to single item
                    const ptr = try allocator.create(ptr_info.child);
                    ptr.* = try unmarshalValue(ptr_info.child, allocator, json_value);
                    return ptr;
                },
                else => return JSONError.UnsupportedType,
            }
        },
        .optional => |opt_info| {
            return switch (json_value) {
                .null => null,
                else => try unmarshalValue(opt_info.child, allocator, json_value),
            };
        },
        .@"struct" => |struct_info| {
            return switch (json_value) {
                .object => |obj| {
                    var result: T = undefined;

                    inline for (struct_info.fields) |field| {
                        if (obj.get(field.name)) |field_value| {
                            @field(result, field.name) = try unmarshalValue(field.type, allocator, field_value);
                        } else {
                            // Handle missing fields
                            if (@typeInfo(field.type) == .optional) {
                                @field(result, field.name) = null;
                            } else if (field.defaultValue()) |default| {
                                @field(result, field.name) = default;
                            } else {
                                return JSONError.MissingField;
                            }
                        }
                    }

                    return result;
                },
                else => JSONError.TypeMismatch,
            };
        },
        .@"enum" => |enum_info| {
            return switch (json_value) {
                .string => |s| {
                    inline for (enum_info.fields) |field| {
                        if (std.mem.eql(u8, field.name, s)) {
                            return @field(T, field.name);
                        }
                    }
                    return JSONError.TypeMismatch;
                },
                else => JSONError.TypeMismatch,
            };
        },
        else => return JSONError.UnsupportedType,
    }
}

/// Add struct fields to a parameters map
fn addStructToParams(allocator: Allocator, params: *std.StringHashMap([]const u8), value: anytype) !void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    if (type_info != .@"struct") {
        return JSONError.UnsupportedType;
    }

    inline for (type_info.@"struct".fields) |field| {
        const field_value = @field(value, field.name);

        // Handle optional fields at comptime
        const is_optional = comptime @typeInfo(field.type) == .optional;

        // Use separate logic paths for optional and non-optional fields
        const should_include_field = if (comptime is_optional)
            field_value != null
        else
            true;

        if (should_include_field) {
            const value_str = try valueToString(allocator, field_value);
            try params.put(field.name, value_str);
        }
    }
}

/// Convert any value to its string representation
fn valueToString(allocator: Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int, .comptime_int => {
            return try std.fmt.allocPrint(allocator, "{d}", .{value});
        },
        .float, .comptime_float => {
            return try std.fmt.allocPrint(allocator, "{d}", .{value});
        },
        .bool => {
            return if (value) "true" else "false";
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                // String slice - return as is (don't allocate)
                return value;
            }
        },
        .array => |array_info| {
            if (array_info.child == u8) {
                // String array - return as slice
                return value[0..];
            }
        },
        .optional => {
            if (value) |val| {
                return try valueToString(allocator, val);
            } else {
                return "null";
            }
        },
        .@"enum" => {
            return @tagName(value);
        },
        else => {},
    }

    return JSONError.UnsupportedType;
}

/// Append an escaped string to the result
fn appendEscapedString(result: *std.ArrayList(u8), str: []const u8) !void {
    for (str) |char| {
        switch (char) {
            '"' => try result.appendSlice("\\\""),
            '\\' => try result.appendSlice("\\\\"),
            '\n' => try result.appendSlice("\\n"),
            '\r' => try result.appendSlice("\\r"),
            '\t' => try result.appendSlice("\\t"),
            '\x08' => try result.appendSlice("\\b"), // backspace
            '\x0C' => try result.appendSlice("\\f"), // form feed
            0x00...0x07, 0x0B, 0x0E...0x1F => try result.writer().print("\\u{x:0>4}", .{char}), // Other control chars
            else => try result.append(char),
        }
    }
}

/// Check if a string was allocated (heuristic based on common patterns)
fn isAllocatedString(str: []const u8) bool {
    // This is a simple heuristic - in practice you might want a more sophisticated approach
    // For now, we'll assume strings longer than a typical stack buffer size were allocated
    return str.len > 64;
}

/// Check if a value needs allocation when converted to string
fn needsAllocation(value: anytype) bool {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int, .comptime_int => return true, // Numbers need allocation via std.fmt.allocPrint
        .float, .comptime_float => return true, // Floats need allocation via std.fmt.allocPrint
        .bool => return false, // "true"/"false" are static strings
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return false; // String slices don't need allocation, they're passed through
            }
            return false;
        },
        .array => |array_info| {
            if (array_info.child == u8) {
                return false; // String arrays don't need allocation
            }
            return false;
        },
        .optional => {
            if (value) |val| {
                return needsAllocation(val);
            } else {
                return false; // "null" is static
            }
        },
        .@"enum" => return false, // @tagName returns static strings
        else => return false,
    }
}

// ===== CONVENIENCE FUNCTIONS =====

/// Marshal a StringHashMap to JSON object
///
/// This function converts a StringHashMap([]const u8) to a JSON object string.
/// All values are treated as strings and properly escaped for JSON.
/// This is specifically useful for Telegram Bot API parameters.
///
/// Args:
///     allocator: Memory allocator for the JSON string
///     map: StringHashMap to convert to JSON
///
/// Returns:
///     JSON object string (caller owns memory) or error
///
/// Example:
/// ```zig
/// var params = std.StringHashMap([]const u8).init(allocator);
/// try params.put("chat_id", "123");
/// try params.put("text", "Hello");
/// const json = try marshalStringHashMap(allocator, params);
/// defer allocator.free(json);
/// // json = {"chat_id":"123","text":"Hello"}
/// ```
pub fn marshalStringHashMap(allocator: Allocator, map: std.StringHashMap([]const u8)) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.append('{');
    var first = true;
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        if (!first) try result.append(',');

        // Add key (always quoted and escaped)
        try result.append('"');
        try appendEscapedString(&result, entry.key_ptr.*);
        try result.appendSlice("\":");

        // Add value (always quoted and escaped for Telegram API compatibility)
        try result.append('"');
        try appendEscapedString(&result, entry.value_ptr.*);
        try result.append('"');

        first = false;
    }
    try result.append('}');

    return result.toOwnedSlice();
}

/// Marshal a struct specifically for Telegram API parameters
///
/// This function creates a JSON object suitable for Telegram Bot API requests.
/// It automatically handles type conversions and skips null optional fields.
///
/// Args:
///     allocator: Memory allocator for the JSON string
///     params: Struct containing API parameters
///
/// Returns:
///     JSON string ready for API request (caller owns memory) or error
pub fn marshalTelegramParams(allocator: Allocator, params: anytype) ![]const u8 {
    return marshal(allocator, params);
}

/// Unmarshal a Telegram API response
///
/// This function handles the standard Telegram API response format with
/// "ok", "result", "error_code", and "description" fields.
///
/// Args:
///     comptime T: The expected result type
///     allocator: Memory allocator for any heap allocations
///     json_string: JSON response from Telegram API
///
/// Returns:
///     Parsed result of type T or error if API call failed
pub fn unmarshalTelegramResponse(comptime T: type, allocator: Allocator, json_string: []const u8) !T {
    const APIResponse = struct {
        ok: bool,
        result: ?T = null,
        error_code: ?i32 = null,
        description: ?[]const u8 = null,
    };

    const response = try unmarshal(APIResponse, allocator, json_string);
    defer if (response.description) |desc| allocator.free(desc);

    if (!response.ok) {
        std.debug.print("Telegram API Error: {s}\n", .{response.description orelse "Unknown error"});
        return JSONError.ParseError;
    }

    return response.result orelse JSONError.MissingField;
}

// ===== TESTS =====

test "marshal basic types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test integer
    {
        const result = try marshal(allocator, @as(i32, 42));
        defer allocator.free(result);
        try testing.expectEqualStrings("42", result);
    }

    // Test string
    {
        const result = try marshal(allocator, "hello");
        defer allocator.free(result);
        try testing.expectEqualStrings("\"hello\"", result);
    }

    // Test boolean
    {
        const result = try marshal(allocator, true);
        defer allocator.free(result);
        try testing.expectEqualStrings("true", result);
    }
}

test "marshal struct" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestStruct = struct {
        name: []const u8,
        age: i32,
        active: bool,
        nickname: ?[]const u8 = null,
    };

    const data = TestStruct{
        .name = "John",
        .age = 30,
        .active = true,
    };

    const result = try marshal(allocator, data);
    defer allocator.free(result);

    // The order of fields in JSON might vary, so we check for key components
    try testing.expect(std.mem.indexOf(u8, result, "\"name\":\"John\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"age\":30") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"active\":true") != null);
    // Should not include null optional field
    try testing.expect(std.mem.indexOf(u8, result, "nickname") == null);
}

test "unmarshal basic types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test integer
    {
        const result = try unmarshal(i32, allocator, "42");
        try testing.expectEqual(@as(i32, 42), result);
    }

    // Test string
    {
        const result = try unmarshal([]const u8, allocator, "\"hello\"");
        defer allocator.free(result);
        try testing.expectEqualStrings("hello", result);
    }

    // Test boolean
    {
        const result = try unmarshal(bool, allocator, "true");
        try testing.expectEqual(true, result);
    }
}

test "createParams" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const TestParams = struct {
        chat_id: i64,
        text: []const u8,
        timeout: ?i32 = null,
    };

    const params_struct = TestParams{
        .chat_id = 123456789,
        .text = "Hello World",
        .timeout = 30,
    };

    var params = try createParams(allocator, params_struct);
    defer cleanupParams(allocator, &params);

    try testing.expectEqualStrings("123456789", params.get("chat_id").?);
    try testing.expectEqualStrings("Hello World", params.get("text").?);
    try testing.expectEqualStrings("30", params.get("timeout").?);
}
