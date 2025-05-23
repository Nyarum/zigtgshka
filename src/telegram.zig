const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

pub const BotError = error{
    InvalidToken,
    NetworkError,
    APIError,
    JSONError,
    OutOfMemory,
    TelegramAPIError,
};

pub const HTTPClient = struct {
    allocator: Allocator,
    client: std.http.Client,

    pub fn init(allocator: Allocator) !HTTPClient {
        return HTTPClient{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *HTTPClient) void {
        self.client.deinit();
    }
};

pub const Bot = struct {
    token: []const u8,
    debug: bool,
    client: *HTTPClient,
    api_endpoint: []const u8,
    self_user: ?*User,
    allocator: Allocator,

    pub fn init(allocator: Allocator, token: []const u8, client: *HTTPClient) !Bot {
        if (token.len == 0) return BotError.InvalidToken;

        return Bot{
            .token = token,
            .debug = false,
            .client = client,
            .api_endpoint = "https://api.telegram.org",
            .self_user = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Bot) void {
        if (self.self_user) |user| {
            const mutable_user = @constCast(user);
            mutable_user.deinit(self.allocator);
            self.allocator.destroy(mutable_user);
        }
    }

    pub fn setAPIEndpoint(self: *Bot, endpoint: []const u8) void {
        self.api_endpoint = endpoint;
    }

    pub fn makeRequest(self: *Bot, endpoint: []const u8, params: std.StringHashMap([]const u8)) ![]const u8 {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/bot{s}/{s}",
            .{ self.api_endpoint, self.token, endpoint },
        );
        defer self.allocator.free(url);

        const uri = try std.Uri.parse(url);
        var server_header_buffer: [8192]u8 = undefined;

        var req = try self.client.client.open(.POST, uri, .{
            .server_header_buffer = &server_header_buffer,
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Content-Type", .value = "application/json" },
            },
        });
        defer req.deinit();

        // Convert params to JSON
        var json_str = std.ArrayList(u8).init(self.allocator);
        defer json_str.deinit();

        try json_str.append('{');
        var first = true;
        var it = params.iterator();
        while (it.next()) |entry| {
            if (!first) try json_str.append(',');
            // Properly format key-value pairs
            try json_str.writer().print("\"{s}\":\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
            first = false;
        }
        try json_str.append('}');

        std.debug.print("Request JSON: {s}\n", .{json_str.items});

        if (json_str.items.len > 2) { // More than just "{}"
            req.transfer_encoding = .{ .content_length = json_str.items.len };
            try req.send();
            try req.writeAll(json_str.items);
        } else {
            try req.send();
        }

        try req.finish();
        try req.wait();

        const body = try req.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));
        return body;
    }
};

pub const User = struct {
    id: i64,
    is_bot: bool,
    first_name: []const u8,
    last_name: ?[]const u8 = null,
    username: ?[]const u8 = null,
    language_code: ?[]const u8 = null,
    is_premium: ?bool = null,
    added_to_attachment_menu: ?bool = null,
    can_join_groups: ?bool = null,
    can_read_all_group_messages: ?bool = null,
    supports_inline_queries: ?bool = null,
    can_connect_to_business: ?bool = null,
    has_main_web_app: ?bool = null,

    pub fn deinit(self: *User, allocator: Allocator) void {
        allocator.free(self.first_name);
        if (self.last_name) |name| allocator.free(name);
        if (self.username) |name| allocator.free(name);
        if (self.language_code) |code| allocator.free(code);
    }
};

pub const MessageEntity = struct {
    type: []const u8,
    offset: i32,
    length: i32,
    url: ?[]const u8 = null,
    user: ?*const User = null,
    language: ?[]const u8 = null,

    pub fn deinit(self: *MessageEntity, allocator: Allocator) void {
        allocator.free(self.type);
        if (self.url) |url| allocator.free(url);
        if (self.user) |user| {
            var mutable_user = @constCast(user);
            mutable_user.deinit(allocator);
            allocator.destroy(mutable_user);
        }
        if (self.language) |lang| allocator.free(lang);
    }
};

pub const Message = struct {
    message_id: i32,
    from: ?*const User,
    date: i64,
    chat: *const Chat,
    text: ?[]const u8,
    entities: ?[]MessageEntity = null,

    pub fn deinit(self: *Message, allocator: Allocator) void {
        if (self.from) |user| {
            var mutable_user = @constCast(user);
            mutable_user.deinit(allocator);
            allocator.destroy(mutable_user);
        }
        var mutable_chat = @constCast(self.chat);
        mutable_chat.deinit(allocator);
        allocator.destroy(mutable_chat);
        if (self.text) |text| allocator.free(text);
        if (self.entities) |entities| {
            for (entities) |*entity| {
                entity.deinit(allocator);
            }
            allocator.free(entities);
        }
    }
};

pub const Chat = struct {
    id: i64,
    type: []const u8,
    title: ?[]const u8,
    username: ?[]const u8,
    first_name: ?[]const u8,
    last_name: ?[]const u8,

    pub fn deinit(self: *Chat, allocator: Allocator) void {
        allocator.free(self.type);
        if (self.title) |title| allocator.free(title);
        if (self.username) |name| allocator.free(name);
        if (self.first_name) |name| allocator.free(name);
        if (self.last_name) |name| allocator.free(name);
    }
};

pub const Update = struct {
    update_id: i32,
    message: ?Message = null,
    edited_message: ?Message = null,
    channel_post: ?Message = null,
    edited_channel_post: ?Message = null,
    business_connection: ?std.json.Value = null,
    business_message: ?Message = null,
    edited_business_message: ?Message = null,
    deleted_business_messages: ?std.json.Value = null,
    message_reaction: ?std.json.Value = null,
    message_reaction_count: ?std.json.Value = null,
    inline_query: ?std.json.Value = null,
    chosen_inline_result: ?std.json.Value = null,
    callback_query: ?std.json.Value = null,
    shipping_query: ?std.json.Value = null,
    pre_checkout_query: ?std.json.Value = null,
    purchased_paid_media: ?std.json.Value = null,
    poll: ?std.json.Value = null,
    poll_answer: ?std.json.Value = null,
    my_chat_member: ?std.json.Value = null,
    chat_member: ?std.json.Value = null,
    chat_join_request: ?std.json.Value = null,
    chat_boost: ?std.json.Value = null,
    removed_chat_boost: ?std.json.Value = null,

    pub fn deinit(self: *Update, allocator: Allocator) void {
        if (self.message) |*msg| msg.deinit(allocator);
        if (self.edited_message) |*msg| msg.deinit(allocator);
        if (self.channel_post) |*msg| msg.deinit(allocator);
        if (self.edited_channel_post) |*msg| msg.deinit(allocator);
        if (self.business_message) |*msg| msg.deinit(allocator);
        if (self.edited_business_message) |*msg| msg.deinit(allocator);
        // Note: std.json.Value fields will be cleaned up automatically by the parsed response deinit
    }
};

pub const APIResponse = struct {
    ok: bool,
    error_code: ?i32 = null,
    description: ?[]const u8 = null,

    pub fn deinit(self: *APIResponse, allocator: Allocator) void {
        if (self.description) |desc| allocator.free(desc);
    }
};

pub const APIResponseWithResult = struct {
    ok: bool,
    result: ?std.json.Value = null,
    error_code: ?i32 = null,
    description: ?[]const u8 = null,

    pub fn deinit(self: *APIResponseWithResult, allocator: Allocator) void {
        if (self.result) |*result| result.deinit();
        if (self.description) |desc| allocator.free(desc);
    }
};

pub const methods = struct {
    pub fn getMe(bot: *Bot) !User {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const response = try bot.makeRequest("getMe", params);
        defer bot.allocator.free(response);

        // Debug: print the raw JSON response
        std.debug.print("getMe JSON response: {s}\n", .{response});

        // First check if the API call was successful
        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            const error_msg = api_response.value.description orelse "Unknown API error";
            std.debug.print("API Error: {s}\n", .{error_msg});
            return BotError.TelegramAPIError;
        }

        // Parse response JSON for User data
        const parsed = try std.json.parseFromSlice(struct { result: User }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        // Make a copy of the result
        var result = parsed.value.result;
        result.first_name = try bot.allocator.dupe(u8, result.first_name);
        if (result.last_name) |name| result.last_name = try bot.allocator.dupe(u8, name);
        if (result.username) |name| result.username = try bot.allocator.dupe(u8, name);
        if (result.language_code) |code| result.language_code = try bot.allocator.dupe(u8, code);

        return result;
    }

    pub fn getUpdates(bot: *Bot, offset: i32, limit: i32, timeout: i32) ![]Update {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const offset_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{offset});
        defer bot.allocator.free(offset_str);
        const limit_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{limit});
        defer bot.allocator.free(limit_str);
        const timeout_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{timeout});
        defer bot.allocator.free(timeout_str);

        try params.put("offset", offset_str);
        try params.put("limit", limit_str);
        try params.put("timeout", timeout_str);

        const response = try bot.makeRequest("getUpdates", params);
        defer bot.allocator.free(response);

        // Debug: print the raw JSON response
        std.debug.print("getUpdates JSON response: {s}\n", .{response});

        // First check if the API call was successful
        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            const error_msg = api_response.value.description orelse "Unknown API error";
            std.debug.print("API Error: {s}\n", .{error_msg});
            return BotError.TelegramAPIError;
        }

        // Parse response JSON into std.json.Value first
        const parsed = try std.json.parseFromSlice(struct { result: []std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        // Make a copy of the result
        var updates = try bot.allocator.alloc(Update, parsed.value.result.len);
        for (parsed.value.result, 0..) |update_val, i| {
            std.debug.print("Parsing update {d}:\n", .{i});
            updates[i] = try parseUpdate(bot.allocator, update_val);
        }

        return updates;
    }

    pub fn deleteWebhook(bot: *Bot) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const response = try bot.makeRequest("deleteWebhook", params);
        defer bot.allocator.free(response);

        // Debug: print the raw JSON response
        std.debug.print("deleteWebhook JSON response: {s}\n", .{response});

        // First check if the API call was successful
        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            const error_msg = api_response.value.description orelse "Unknown API error";
            std.debug.print("API Error: {s}\n", .{error_msg});
            return BotError.TelegramAPIError;
        }

        return true;
    }

    pub fn sendMessage(bot: *Bot, chat_id: i64, text: []const u8) !Message {
        if (text.len == 0) return BotError.TelegramAPIError;

        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("text", text);

        const response = try bot.makeRequest("sendMessage", params);
        defer bot.allocator.free(response);

        // Debug: print the raw JSON response
        std.debug.print("sendMessage JSON response: {s}\n", .{response});

        // First check if the API call was successful
        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            const error_msg = api_response.value.description orelse "Unknown API error";
            std.debug.print("API Error: {s}\n", .{error_msg});
            return BotError.TelegramAPIError;
        }

        // Parse response JSON into std.json.Value first
        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        // Extract message data from JSON value
        const message_obj = parsed.value.result.object;

        var result: Message = undefined;
        result.message_id = @intCast(message_obj.get("message_id").?.integer);
        result.date = @intCast(message_obj.get("date").?.integer);

        // Handle from field
        if (message_obj.get("from")) |from_val| {
            const utils = @import("utils.zig");
            result.from = try utils.parseUser(bot.allocator, from_val);
        } else {
            result.from = null;
        }

        // Handle chat field
        if (message_obj.get("chat")) |chat_val| {
            const utils = @import("utils.zig");
            result.chat = try utils.parseChat(bot.allocator, chat_val);
        } else {
            return BotError.JSONError; // Chat is required
        }

        // Handle text field
        if (message_obj.get("text")) |text_val| {
            result.text = try bot.allocator.dupe(u8, text_val.string);
        } else {
            result.text = null;
        }

        // Handle entities field
        if (message_obj.get("entities")) |entities_val| {
            const utils = @import("utils.zig");
            result.entities = try utils.parseMessageEntities(bot.allocator, entities_val);
        } else {
            result.entities = null;
        }

        return result;
    }
};

pub fn parseUpdate(allocator: Allocator, value: std.json.Value) !Update {
    if (value != .object) return BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing Update with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

    const utils = @import("utils.zig");
    return Update{
        .update_id = if (obj.get("update_id")) |id| @intCast(id.integer) else return BotError.JSONError,
        .message = if (obj.get("message")) |msg| try utils.parseMessage(allocator, msg) else null,
        .edited_message = if (obj.get("edited_message")) |msg| try utils.parseMessage(allocator, msg) else null,
        .channel_post = if (obj.get("channel_post")) |msg| try utils.parseMessage(allocator, msg) else null,
        .edited_channel_post = if (obj.get("edited_channel_post")) |msg| try utils.parseMessage(allocator, msg) else null,
        .business_message = if (obj.get("business_message")) |msg| try utils.parseMessage(allocator, msg) else null,
        .edited_business_message = if (obj.get("edited_business_message")) |msg| try utils.parseMessage(allocator, msg) else null,
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
