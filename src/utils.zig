const std = @import("std");
const telegram = @import("telegram.zig");
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
    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();

    var tree = try parser.parse(json_str);
    defer tree.deinit();

    const root = tree.root;
    if (root != .Object) return telegram.BotError.JSONError;

    const ok = if (root.Object.get("ok")) |ok_val| ok_val.Bool else false;
    const result = if (root.Object.get("result")) |result_val| result_val else null;
    const error_code = if (root.Object.get("error_code")) |code_val| code_val.Integer else null;
    const description = if (root.Object.get("description")) |desc_val| desc_val.String else null;

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

    const user = try allocator.create(telegram.User);
    user.* = telegram.User{
        .id = if (obj.get("id")) |id| @intCast(id.integer) else return telegram.BotError.JSONError,
        .is_bot = if (obj.get("is_bot")) |is_bot| is_bot.bool else return telegram.BotError.JSONError,
        .first_name = if (obj.get("first_name")) |name| try allocator.dupe(u8, name.string) else return telegram.BotError.JSONError,
        .last_name = if (obj.get("last_name")) |name| try allocator.dupe(u8, name.string) else null,
        .username = if (obj.get("username")) |name| try allocator.dupe(u8, name.string) else null,
        .language_code = if (obj.get("language_code")) |code| try allocator.dupe(u8, code.string) else null,
        .is_premium = if (obj.get("is_premium")) |premium| premium.bool else null,
        .added_to_attachment_menu = if (obj.get("added_to_attachment_menu")) |added| added.bool else null,
        .can_join_groups = if (obj.get("can_join_groups")) |can| can.bool else null,
        .can_read_all_group_messages = if (obj.get("can_read_all_group_messages")) |can| can.bool else null,
        .supports_inline_queries = if (obj.get("supports_inline_queries")) |supports| supports.bool else null,
        .can_connect_to_business = if (obj.get("can_connect_to_business")) |can| can.bool else null,
        .has_main_web_app = if (obj.get("has_main_web_app")) |has| has.bool else null,
    };
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

    const chat = try allocator.create(telegram.Chat);
    chat.* = telegram.Chat{
        .id = if (obj.get("id")) |id| @intCast(id.integer) else return telegram.BotError.JSONError,
        .type = if (obj.get("type")) |type_str| try allocator.dupe(u8, type_str.string) else return telegram.BotError.JSONError,
        .title = if (obj.get("title")) |title| try allocator.dupe(u8, title.string) else null,
        .username = if (obj.get("username")) |name| try allocator.dupe(u8, name.string) else null,
        .first_name = if (obj.get("first_name")) |name| try allocator.dupe(u8, name.string) else null,
        .last_name = if (obj.get("last_name")) |name| try allocator.dupe(u8, name.string) else null,
    };
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

    return telegram.MessageEntity{
        .type = if (obj.get("type")) |type_str| try allocator.dupe(u8, type_str.string) else return telegram.BotError.JSONError,
        .offset = if (obj.get("offset")) |offset| @intCast(offset.integer) else return telegram.BotError.JSONError,
        .length = if (obj.get("length")) |length| @intCast(length.integer) else return telegram.BotError.JSONError,
        .url = if (obj.get("url")) |url| try allocator.dupe(u8, url.string) else null,
        .user = if (obj.get("user")) |user| try parseUser(allocator, user) else null,
        .language = if (obj.get("language")) |lang| try allocator.dupe(u8, lang.string) else null,
    };
}

pub fn parseMessage(allocator: Allocator, value: std.json.Value) !telegram.Message {
    if (value != .object) return telegram.BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing Message with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    return telegram.Message{
        .message_id = if (obj.get("message_id")) |id| @intCast(id.integer) else return telegram.BotError.JSONError,
        .from = if (obj.get("from")) |from| try parseUser(allocator, from) else null,
        .date = if (obj.get("date")) |date| @intCast(date.integer) else return telegram.BotError.JSONError,
        .chat = if (obj.get("chat")) |chat| try parseChat(allocator, chat) else return telegram.BotError.JSONError,
        .text = if (obj.get("text")) |text| try allocator.dupe(u8, text.string) else null,
        .entities = if (obj.get("entities")) |entities| try parseMessageEntities(allocator, entities) else null,
    };
}

pub fn parseFile(allocator: Allocator, value: std.json.Value) !telegram.files.File {
    if (value != .Object) return telegram.BotError.JSONError;
    const obj = value.Object;

    return telegram.files.File{
        .file_id = if (obj.get("file_id")) |id| try allocator.dupe(u8, id.String) else return telegram.BotError.JSONError,
        .file_unique_id = if (obj.get("file_unique_id")) |id| try allocator.dupe(u8, id.String) else return telegram.BotError.JSONError,
        .file_size = if (obj.get("file_size")) |size| @intCast(size.Integer) else null,
        .file_path = if (obj.get("file_path")) |path| try allocator.dupe(u8, path.String) else null,
    };
}

pub fn parseUpdate(allocator: Allocator, value: std.json.Value) !telegram.Update {
    if (value != .Object) return telegram.BotError.JSONError;
    const obj = value.Object;

    std.debug.print("Parsing Update with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    return telegram.Update{
        .update_id = if (obj.get("update_id")) |id| @intCast(id.Integer) else return telegram.BotError.JSONError,
        .message = if (obj.get("message")) |msg| try parseMessage(allocator, msg) else null,
        .edited_message = if (obj.get("edited_message")) |msg| try parseMessage(allocator, msg) else null,
        .channel_post = if (obj.get("channel_post")) |msg| try parseMessage(allocator, msg) else null,
        .edited_channel_post = if (obj.get("edited_channel_post")) |msg| try parseMessage(allocator, msg) else null,
        .business_message = if (obj.get("business_message")) |msg| try parseMessage(allocator, msg) else null,
        .edited_business_message = if (obj.get("edited_business_message")) |msg| try parseMessage(allocator, msg) else null,
        .business_connection = if (obj.get("business_connection")) |val| val else null,
        .deleted_business_messages = if (obj.get("deleted_business_messages")) |val| val else null,
        .message_reaction = if (obj.get("message_reaction")) |val| val else null,
        .message_reaction_count = if (obj.get("message_reaction_count")) |val| val else null,
        .inline_query = if (obj.get("inline_query")) |val| val else null,
        .chosen_inline_result = if (obj.get("chosen_inline_result")) |val| val else null,
        .callback_query = if (obj.get("callback_query")) |val| val else null,
        .shipping_query = if (obj.get("shipping_query")) |val| val else null,
        .pre_checkout_query = if (obj.get("pre_checkout_query")) |val| val else null,
        .purchased_paid_media = if (obj.get("purchased_paid_media")) |val| val else null,
        .poll = if (obj.get("poll")) |val| val else null,
        .poll_answer = if (obj.get("poll_answer")) |val| val else null,
        .my_chat_member = if (obj.get("my_chat_member")) |val| val else null,
        .chat_member = if (obj.get("chat_member")) |val| val else null,
        .chat_join_request = if (obj.get("chat_join_request")) |val| val else null,
        .chat_boost = if (obj.get("chat_boost")) |val| val else null,
        .removed_chat_boost = if (obj.get("removed_chat_boost")) |val| val else null,
    };
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
