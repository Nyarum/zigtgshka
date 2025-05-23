const std = @import("std");
const telegram = @import("telegram.zig");
const Allocator = std.mem.Allocator;

pub fn getMe(bot: *telegram.Bot) !telegram.User {
    const response = try bot.makeRequest("getMe", std.StringHashMap([]const u8).init(bot.allocator));
    // TODO: Parse JSON response into User struct
    _ = response;
    return telegram.User{
        .id = 0,
        .is_bot = true,
        .first_name = "",
        .last_name = null,
        .username = null,
        .language_code = null,
        .can_join_groups = null,
        .can_read_all_group_messages = null,
        .supports_inline_queries = null,
    };
}

pub fn sendMessage(bot: *telegram.Bot, chat_id: i64, text: []const u8) !telegram.Message {
    var params = std.StringHashMap([]const u8).init(bot.allocator);
    defer params.deinit();

    const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
    defer bot.allocator.free(chat_id_str);

    try params.put("chat_id", chat_id_str);
    try params.put("text", text);

    const response = try bot.makeRequest("sendMessage", params);
    // TODO: Parse JSON response into Message struct
    _ = response;
    return telegram.Message{
        .message_id = 0,
        .from = null,
        .date = 0,
        .chat = telegram.Chat{
            .id = chat_id,
            .type = "private",
            .title = null,
            .username = null,
            .first_name = null,
            .last_name = null,
        },
        .text = null,
    };
}

pub fn getUpdates(bot: *telegram.Bot, offset: ?i32, limit: ?i32, timeout: ?i32) ![]telegram.Update {
    var params = std.StringHashMap([]const u8).init(bot.allocator);
    defer params.deinit();

    if (offset) |o| {
        const offset_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{o});
        defer bot.allocator.free(offset_str);
        try params.put("offset", offset_str);
    }

    if (limit) |l| {
        const limit_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{l});
        defer bot.allocator.free(limit_str);
        try params.put("limit", limit_str);
    }

    if (timeout) |t| {
        const timeout_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{t});
        defer bot.allocator.free(timeout_str);
        try params.put("timeout", timeout_str);
    }

    const response = try bot.makeRequest("getUpdates", params);
    // TODO: Parse JSON response into array of Update structs
    _ = response;
    return &[_]telegram.Update{};
}

pub fn setWebhook(bot: *telegram.Bot, url: []const u8) !void {
    var params = std.StringHashMap([]const u8).init(bot.allocator);
    defer params.deinit();

    try params.put("url", url);

    _ = try bot.makeRequest("setWebhook", params);
}

pub fn deleteWebhook(bot: *telegram.Bot) !void {
    const params = std.StringHashMap([]const u8).init(bot.allocator);
    _ = try bot.makeRequest("deleteWebhook", params);
}
