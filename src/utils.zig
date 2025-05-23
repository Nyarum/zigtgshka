const std = @import("std");
const telegram = @import("telegram.zig");
const json = @import("json.zig");
const Allocator = std.mem.Allocator;

pub const APIResponse = struct {
    ok: bool,
    result: ?std.json.Value,
    error_code: ?i32,
    description: ?[]const u8,

    pub fn deinit(self: *APIResponse, allocator: Allocator) void {
        if (self.result) |*result| {
            result.deinit(allocator);
        }
        if (self.description) |desc| {
            allocator.free(desc);
        }
    }
};

pub fn parseResponse(allocator: Allocator, json_str: []const u8) !APIResponse {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return telegram.BotError.JSONError;

    const obj = root.object;
    const ok = if (obj.get("ok")) |ok_val| ok_val.bool else false;
    const result = if (obj.get("result")) |result_val| result_val else null;
    const error_code = if (obj.get("error_code")) |code_val| code_val.integer else null;
    const description = if (obj.get("description")) |desc_val| desc_val.string else null;

    return APIResponse{
        .ok = ok,
        .result = result,
        .error_code = if (error_code) |code| @intCast(code) else null,
        .description = if (description) |desc| try allocator.dupe(u8, desc) else null,
    };
}

pub fn parseUser(allocator: Allocator, value: std.json.Value) !*telegram.User {
    if (value != .object) return telegram.BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing User with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    // Use json.unmarshalValue to parse the User struct directly
    const user_data = try json.unmarshalValue(telegram.User, allocator, value);
    const user = try allocator.create(telegram.User);
    user.* = user_data;
    return user;
}

pub fn parseChat(allocator: Allocator, value: std.json.Value) !*telegram.Chat {
    if (value != .object) return telegram.BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing Chat with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    // Use json.unmarshalValue to parse the Chat struct directly
    const chat_data = try json.unmarshalValue(telegram.Chat, allocator, value);
    const chat = try allocator.create(telegram.Chat);
    chat.* = chat_data;
    return chat;
}

pub fn parseMessageEntity(allocator: Allocator, value: std.json.Value) !telegram.MessageEntity {
    if (value != .object) return telegram.BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing MessageEntity with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    // Use json.unmarshalValue to parse the MessageEntity struct directly
    return try json.unmarshalValue(telegram.MessageEntity, allocator, value);
}

pub fn parseMessage(allocator: Allocator, value: std.json.Value) !telegram.Message {
    return parseMessageWithDepth(allocator, value, 0);
}

fn parseMessageWithDepth(allocator: Allocator, value: std.json.Value, depth: u32) !telegram.Message {
    if (value != .object) return telegram.BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing Message with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    // Limit recursion depth to prevent stack overflow
    const max_depth = 3;

    // Parse the base message structure using json.unmarshalValue
    var message = try json.unmarshalValue(telegram.Message, allocator, value);

    // Handle pinned_message recursion manually to control depth
    if (obj.get("pinned_message")) |pinned| {
        if (depth >= max_depth) {
            std.debug.print("Max recursion depth reached for pinned_message, skipping\n", .{});
            message.pinned_message = null;
        } else {
            const pinned_ptr = try allocator.create(telegram.Message);
            pinned_ptr.* = try parseMessageWithDepth(allocator, pinned, depth + 1);
            message.pinned_message = pinned_ptr;
        }
    } else {
        message.pinned_message = null;
    }

    return message;
}

pub fn parseCallbackQuery(allocator: Allocator, value: std.json.Value) !telegram.CallbackQuery {
    if (value != .object) return telegram.BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing CallbackQuery with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    // Use json.unmarshalValue to parse the CallbackQuery struct directly
    var callback_query = try json.unmarshalValue(telegram.CallbackQuery, allocator, value);

    // Handle the message field manually since it needs special pointer handling for recursion
    if (obj.get("message")) |msg| {
        const message_ptr = try allocator.create(telegram.Message);
        message_ptr.* = try parseMessage(allocator, msg);
        callback_query.message = message_ptr;
    }

    return callback_query;
}

pub fn parseFile(allocator: Allocator, value: std.json.Value) !telegram.files.File {
    if (value != .object) return telegram.BotError.JSONError;

    // Use json.unmarshalValue to parse the File struct directly
    return try json.unmarshalValue(telegram.files.File, allocator, value);
}

pub fn parseUpdate(allocator: Allocator, value: std.json.Value) !telegram.Update {
    if (value != .object) return telegram.BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing Update with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    // Use json.unmarshalValue for the base Update structure
    var update = try json.unmarshalValue(telegram.Update, allocator, value);

    // Handle message fields that need special parsing with recursion control
    if (obj.get("message")) |msg| {
        update.message = try parseMessage(allocator, msg);
    }
    if (obj.get("edited_message")) |msg| {
        update.edited_message = try parseMessage(allocator, msg);
    }
    if (obj.get("channel_post")) |msg| {
        update.channel_post = try parseMessage(allocator, msg);
    }
    if (obj.get("edited_channel_post")) |msg| {
        update.edited_channel_post = try parseMessage(allocator, msg);
    }
    if (obj.get("business_message")) |msg| {
        update.business_message = try parseMessage(allocator, msg);
    }
    if (obj.get("edited_business_message")) |msg| {
        update.edited_business_message = try parseMessage(allocator, msg);
    }
    if (obj.get("callback_query")) |val| {
        update.callback_query = try parseCallbackQuery(allocator, val);
    }

    return update;
}

pub fn parseMessageEntities(allocator: Allocator, value: std.json.Value) ![]telegram.MessageEntity {
    if (value != .array) return telegram.BotError.JSONError;
    const array = value.array;

    std.debug.print("Parsing MessageEntities array with length: {d}\n", .{array.items.len});

    var entities = try allocator.alloc(telegram.MessageEntity, array.items.len);
    for (array.items, 0..) |item, i| {
        entities[i] = try parseMessageEntity(allocator, item);
    }
    return entities;
}
