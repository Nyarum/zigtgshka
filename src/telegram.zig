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

    // Helper function to escape JSON strings
    fn escapeJsonString(self: *Bot, input: []const u8) ![]const u8 {
        // Handle empty input safely
        if (input.len == 0) {
            return try self.allocator.dupe(u8, "");
        }

        var result = std.ArrayList(u8).init(self.allocator);
        // Remove defer - we'll transfer ownership with toOwnedSlice()

        for (input) |char| {
            switch (char) {
                '"' => try result.appendSlice("\\\""),
                '\\' => try result.appendSlice("\\\\"),
                '\n' => try result.appendSlice("\\n"),
                '\r' => try result.appendSlice("\\r"),
                '\t' => try result.appendSlice("\\t"),
                '\x08' => try result.appendSlice("\\b"), // backspace
                '\x0C' => try result.appendSlice("\\f"), // form feed
                else => try result.append(char),
            }
        }

        return result.toOwnedSlice();
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

            // Safety checks before escaping
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Skip null or invalid entries
            if (key.len == 0) continue;

            // Properly escape both key and value
            const escaped_key = try self.escapeJsonString(key);
            defer self.allocator.free(escaped_key);
            const escaped_value = try self.escapeJsonString(value);
            defer self.allocator.free(escaped_value);
            try json_str.writer().print("\"{s}\":\"{s}\"", .{ escaped_key, escaped_value });
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

    // Helper function to create params with proper memory management
    fn createParams(bot: *Bot, comptime FieldType: type, fields: FieldType) !std.StringHashMap([]const u8) {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        errdefer params.deinit();

        inline for (@typeInfo(FieldType).Struct.fields) |field| {
            const value = @field(fields, field.name);
            const T = @TypeOf(value);

            if (T == i64 or T == i32) {
                const str = try std.fmt.allocPrint(bot.allocator, "{d}", .{value});
                try params.put(field.name, str);
            } else if (T == []const u8) {
                try params.put(field.name, value);
            } else if (@typeInfo(T) == .Optional) {
                if (value) |v| {
                    const InnerT = @TypeOf(v);
                    if (InnerT == i64 or InnerT == i32) {
                        const str = try std.fmt.allocPrint(bot.allocator, "{d}", .{v});
                        try params.put(field.name, str);
                    } else if (InnerT == []const u8) {
                        try params.put(field.name, v);
                    }
                }
            }
        }

        return params;
    }

    // Helper function to cleanup allocated param strings
    fn cleanupParams(bot: *Bot, params: *std.StringHashMap([]const u8), comptime FieldType: type, fields: FieldType) void {
        inline for (@typeInfo(FieldType).Struct.fields) |field| {
            const value = @field(fields, field.name);
            const T = @TypeOf(value);

            if (T == i64 or T == i32) {
                if (params.get(field.name)) |str| {
                    bot.allocator.free(str);
                }
            } else if (@typeInfo(T) == .Optional) {
                if (value) |v| {
                    const InnerT = @TypeOf(v);
                    if (InnerT == i64 or InnerT == i32) {
                        if (params.get(field.name)) |str| {
                            bot.allocator.free(str);
                        }
                    }
                }
            }
        }
        params.deinit();
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
    pinned_message: ?*const Message = null,

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
        if (self.pinned_message) |pinned| {
            var mutable_pinned = @constCast(pinned);
            mutable_pinned.deinit(allocator);
            allocator.destroy(mutable_pinned);
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

// Inline keyboard support
pub const InlineKeyboardButton = struct {
    text: []const u8,
    url: ?[]const u8 = null,
    callback_data: ?[]const u8 = null,
    switch_inline_query: ?[]const u8 = null,
    switch_inline_query_current_chat: ?[]const u8 = null,

    pub fn deinit(self: *InlineKeyboardButton, allocator: Allocator) void {
        allocator.free(self.text);
        if (self.url) |url| allocator.free(url);
        if (self.callback_data) |data| allocator.free(data);
        if (self.switch_inline_query) |query| allocator.free(query);
        if (self.switch_inline_query_current_chat) |query| allocator.free(query);
    }
};

pub const InlineKeyboardMarkup = struct {
    inline_keyboard: [][]InlineKeyboardButton,

    pub fn deinit(self: *InlineKeyboardMarkup, allocator: Allocator) void {
        for (self.inline_keyboard) |row| {
            for (row) |*button| {
                button.deinit(allocator);
            }
            allocator.free(row);
        }
        allocator.free(self.inline_keyboard);
    }
};

pub const CallbackQuery = struct {
    id: []const u8,
    from: *const User,
    message: ?*const Message = null,
    inline_message_id: ?[]const u8 = null,
    chat_instance: []const u8,
    data: ?[]const u8 = null,
    game_short_name: ?[]const u8 = null,

    pub fn deinit(self: *CallbackQuery, allocator: Allocator) void {
        allocator.free(self.id);
        var mutable_user = @constCast(self.from);
        mutable_user.deinit(allocator);
        allocator.destroy(mutable_user);
        if (self.message) |message| {
            var mutable_message = @constCast(message);
            mutable_message.deinit(allocator);
            allocator.destroy(mutable_message);
        }
        if (self.inline_message_id) |id| allocator.free(id);
        allocator.free(self.chat_instance);
        if (self.data) |data| allocator.free(data);
        if (self.game_short_name) |name| allocator.free(name);
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
    callback_query: ?CallbackQuery = null,
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
        if (self.callback_query) |*query| query.deinit(allocator);
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

// Bot command definition
pub const BotCommand = struct {
    command: []const u8,
    description: []const u8,

    pub fn deinit(self: *BotCommand, allocator: Allocator) void {
        allocator.free(self.command);
        allocator.free(self.description);
    }
};

// File information
pub const File = struct {
    file_id: []const u8,
    file_unique_id: []const u8,
    file_size: ?i32 = null,
    file_path: ?[]const u8 = null,

    pub fn deinit(self: *File, allocator: Allocator) void {
        allocator.free(self.file_id);
        allocator.free(self.file_unique_id);
        if (self.file_path) |path| allocator.free(path);
    }
};

// Webhook information
pub const WebhookInfo = struct {
    url: []const u8,
    has_custom_certificate: bool,
    pending_update_count: i32,
    ip_address: ?[]const u8 = null,
    last_error_date: ?i64 = null,
    last_error_message: ?[]const u8 = null,
    last_synchronization_error_date: ?i64 = null,
    max_connections: ?i32 = null,
    allowed_updates: ?[][]const u8 = null,

    pub fn deinit(self: *WebhookInfo, allocator: Allocator) void {
        allocator.free(self.url);
        if (self.ip_address) |ip| allocator.free(ip);
        if (self.last_error_message) |msg| allocator.free(msg);
        if (self.allowed_updates) |updates| {
            for (updates) |update| {
                allocator.free(update);
            }
            allocator.free(updates);
        }
    }
};

// Photo size
pub const PhotoSize = struct {
    file_id: []const u8,
    file_unique_id: []const u8,
    width: i32,
    height: i32,
    file_size: ?i32 = null,

    pub fn deinit(self: *PhotoSize, allocator: Allocator) void {
        allocator.free(self.file_id);
        allocator.free(self.file_unique_id);
    }
};

// User profile photos
pub const UserProfilePhotos = struct {
    total_count: i32,
    photos: [][]PhotoSize,

    pub fn deinit(self: *UserProfilePhotos, allocator: Allocator) void {
        for (self.photos) |photo_row| {
            for (photo_row) |*photo| {
                photo.deinit(allocator);
            }
            allocator.free(photo_row);
        }
        allocator.free(self.photos);
    }
};

// Inline query result (base type - this would need specific implementations)
pub const InlineQueryResult = struct {
    type: []const u8,
    id: []const u8,

    pub fn deinit(self: *InlineQueryResult, allocator: Allocator) void {
        allocator.free(self.type);
        allocator.free(self.id);
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

        try params.put("chat_id", chat_id_str);
        try params.put("text", text);

        const response = try bot.makeRequest("sendMessage", params);

        // Now it's safe to free the allocated string after makeRequest is done
        defer bot.allocator.free(chat_id_str);
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

        // Initialize pinned_message field to null (this should be explicit)
        result.pinned_message = null;

        return result;
    }

    pub fn sendMessageWithKeyboard(bot: *Bot, chat_id: i64, text: []const u8, keyboard: InlineKeyboardMarkup) !Message {
        if (text.len == 0) return BotError.TelegramAPIError;

        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});

        // Create a temporary arena allocator for JSON serialization
        var arena = std.heap.ArenaAllocator.init(bot.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Create the reply_markup JSON string manually to avoid null fields
        var keyboard_json = std.ArrayList(u8).init(arena_allocator);
        defer keyboard_json.deinit();

        try keyboard_json.appendSlice("{\"inline_keyboard\":[");

        for (keyboard.inline_keyboard, 0..) |row, row_index| {
            if (row_index > 0) try keyboard_json.append(',');
            try keyboard_json.append('[');

            for (row, 0..) |button, button_index| {
                if (button_index > 0) try keyboard_json.append(',');
                try keyboard_json.append('{');

                // Always include text field - properly escaped
                const escaped_text = try bot.escapeJsonString(button.text);
                defer bot.allocator.free(escaped_text);
                try keyboard_json.writer().print("\"text\":\"{s}\"", .{escaped_text});

                // Only include fields that are not null - properly escaped
                if (button.url) |url| {
                    const escaped_url = try bot.escapeJsonString(url);
                    defer bot.allocator.free(escaped_url);
                    try keyboard_json.writer().print(",\"url\":\"{s}\"", .{escaped_url});
                }
                if (button.callback_data) |data| {
                    const escaped_data = try bot.escapeJsonString(data);
                    defer bot.allocator.free(escaped_data);
                    try keyboard_json.writer().print(",\"callback_data\":\"{s}\"", .{escaped_data});
                }
                if (button.switch_inline_query) |query| {
                    const escaped_query = try bot.escapeJsonString(query);
                    defer bot.allocator.free(escaped_query);
                    try keyboard_json.writer().print(",\"switch_inline_query\":\"{s}\"", .{escaped_query});
                }
                if (button.switch_inline_query_current_chat) |query| {
                    const escaped_query = try bot.escapeJsonString(query);
                    defer bot.allocator.free(escaped_query);
                    try keyboard_json.writer().print(",\"switch_inline_query_current_chat\":\"{s}\"", .{escaped_query});
                }

                try keyboard_json.append('}');
            }

            try keyboard_json.append(']');
        }

        try keyboard_json.appendSlice("]}");

        try params.put("chat_id", chat_id_str);
        try params.put("text", text);
        try params.put("reply_markup", keyboard_json.items);

        const response = try bot.makeRequest("sendMessage", params);

        // Now it's safe to free the allocated string after makeRequest is done
        defer bot.allocator.free(chat_id_str);
        defer bot.allocator.free(response);

        // Debug: print the raw JSON response
        std.debug.print("sendMessageWithKeyboard JSON response: {s}\n", .{response});

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

        // Initialize pinned_message field to null (this should be explicit)
        result.pinned_message = null;

        return result;
    }

    pub fn answerCallbackQuery(bot: *Bot, callback_query_id: []const u8, text: ?[]const u8, show_alert: bool) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        try params.put("callback_query_id", callback_query_id);

        if (text) |txt| {
            try params.put("text", txt);
        }

        const show_alert_str = if (show_alert) "true" else "false";
        try params.put("show_alert", show_alert_str);

        const response = try bot.makeRequest("answerCallbackQuery", params);
        defer bot.allocator.free(response);

        // Debug: print the raw JSON response
        std.debug.print("answerCallbackQuery JSON response: {s}\n", .{response});

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

    // ===== NEW API METHODS =====

    // Message forwarding and copying
    pub fn forwardMessage(bot: *Bot, chat_id: i64, from_chat_id: i64, message_id: i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);
        const from_chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{from_chat_id});
        defer bot.allocator.free(from_chat_id_str);
        const message_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{message_id});
        defer bot.allocator.free(message_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("from_chat_id", from_chat_id_str);
        try params.put("message_id", message_id_str);

        const response = try bot.makeRequest("forwardMessage", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn copyMessage(bot: *Bot, chat_id: i64, from_chat_id: i64, message_id: i32) !i32 {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);
        const from_chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{from_chat_id});
        defer bot.allocator.free(from_chat_id_str);
        const message_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{message_id});
        defer bot.allocator.free(message_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("from_chat_id", from_chat_id_str);
        try params.put("message_id", message_id_str);

        const response = try bot.makeRequest("copyMessage", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: struct { message_id: i32 } }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return parsed.value.result.message_id;
    }

    // Message editing
    pub fn editMessageText(bot: *Bot, chat_id: i64, message_id: i32, text: []const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);
        const message_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{message_id});
        defer bot.allocator.free(message_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("message_id", message_id_str);
        try params.put("text", text);

        const response = try bot.makeRequest("editMessageText", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn editMessageReplyMarkup(bot: *Bot, chat_id: i64, message_id: i32, keyboard: ?InlineKeyboardMarkup) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);
        const message_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{message_id});
        defer bot.allocator.free(message_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("message_id", message_id_str);

        if (keyboard) |kb| {
            var arena = std.heap.ArenaAllocator.init(bot.allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            var keyboard_json = std.ArrayList(u8).init(arena_allocator);
            defer keyboard_json.deinit();

            try keyboard_json.appendSlice("{\"inline_keyboard\":[");
            for (kb.inline_keyboard, 0..) |row, row_index| {
                if (row_index > 0) try keyboard_json.append(',');
                try keyboard_json.append('[');
                for (row, 0..) |button, button_index| {
                    if (button_index > 0) try keyboard_json.append(',');
                    try keyboard_json.append('{');

                    const escaped_text = try bot.escapeJsonString(button.text);
                    defer bot.allocator.free(escaped_text);
                    try keyboard_json.writer().print("\"text\":\"{s}\"", .{escaped_text});

                    if (button.callback_data) |data| {
                        const escaped_data = try bot.escapeJsonString(data);
                        defer bot.allocator.free(escaped_data);
                        try keyboard_json.writer().print(",\"callback_data\":\"{s}\"", .{escaped_data});
                    }

                    try keyboard_json.append('}');
                }
                try keyboard_json.append(']');
            }
            try keyboard_json.appendSlice("]}");

            try params.put("reply_markup", keyboard_json.items);
        } else {
            try params.put("reply_markup", "{}");
        }

        const response = try bot.makeRequest("editMessageReplyMarkup", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn deleteMessage(bot: *Bot, chat_id: i64, message_id: i32) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);
        const message_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{message_id});
        defer bot.allocator.free(message_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("message_id", message_id_str);

        const response = try bot.makeRequest("deleteMessage", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // Chat actions
    pub fn sendChatAction(bot: *Bot, chat_id: i64, action: []const u8) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("action", action);

        const response = try bot.makeRequest("sendChatAction", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // Location and contact
    pub fn sendLocation(bot: *Bot, chat_id: i64, latitude: f64, longitude: f64) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);
        const latitude_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{latitude});
        defer bot.allocator.free(latitude_str);
        const longitude_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{longitude});
        defer bot.allocator.free(longitude_str);

        try params.put("chat_id", chat_id_str);
        try params.put("latitude", latitude_str);
        try params.put("longitude", longitude_str);

        const response = try bot.makeRequest("sendLocation", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendContact(bot: *Bot, chat_id: i64, phone_number: []const u8, first_name: []const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("phone_number", phone_number);
        try params.put("first_name", first_name);

        const response = try bot.makeRequest("sendContact", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    // Polls
    pub fn sendPoll(bot: *Bot, chat_id: i64, question: []const u8, options: [][]const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        // Create options JSON array
        var arena = std.heap.ArenaAllocator.init(bot.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var options_json = std.ArrayList(u8).init(arena_allocator);
        defer options_json.deinit();

        try options_json.append('[');
        for (options, 0..) |option, i| {
            if (i > 0) try options_json.append(',');
            const escaped_option = try bot.escapeJsonString(option);
            defer bot.allocator.free(escaped_option);
            try options_json.writer().print("\"{s}\"", .{escaped_option});
        }
        try options_json.append(']');

        try params.put("chat_id", chat_id_str);
        try params.put("question", question);
        try params.put("options", options_json.items);

        const response = try bot.makeRequest("sendPoll", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    // Chat management
    pub fn getChat(bot: *Bot, chat_id: i64) !Chat {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);

        const response = try bot.makeRequest("getChat", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        const chat_ptr = try utils.parseChat(bot.allocator, parsed.value.result);
        defer bot.allocator.destroy(chat_ptr);
        return chat_ptr.*;
    }

    pub fn getChatMemberCount(bot: *Bot, chat_id: i64) !i32 {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);

        const response = try bot.makeRequest("getChatMemberCount", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: i32 }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return parsed.value.result;
    }

    pub fn leaveChat(bot: *Bot, chat_id: i64) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);

        const response = try bot.makeRequest("leaveChat", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // Chat member management
    pub fn banChatMember(bot: *Bot, chat_id: i64, user_id: i64) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);
        const user_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{user_id});
        defer bot.allocator.free(user_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("user_id", user_id_str);

        const response = try bot.makeRequest("banChatMember", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn unbanChatMember(bot: *Bot, chat_id: i64, user_id: i64) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);
        const user_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{user_id});
        defer bot.allocator.free(user_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("user_id", user_id_str);

        const response = try bot.makeRequest("unbanChatMember", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // Message pinning
    pub fn pinChatMessage(bot: *Bot, chat_id: i64, message_id: i32) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        const message_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{message_id});

        try params.put("chat_id", chat_id_str);
        try params.put("message_id", message_id_str);

        const response = try bot.makeRequest("pinChatMessage", params);

        // Now it's safe to free the strings after makeRequest is done
        defer bot.allocator.free(chat_id_str);
        defer bot.allocator.free(message_id_str);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn unpinChatMessage(bot: *Bot, chat_id: i64, message_id: ?i32) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});

        try params.put("chat_id", chat_id_str);

        var message_id_str: ?[]const u8 = null;
        if (message_id) |msg_id| {
            message_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{msg_id});
            try params.put("message_id", message_id_str.?);
        }

        const response = try bot.makeRequest("unpinChatMessage", params);

        // Now it's safe to free the strings after makeRequest is done
        defer bot.allocator.free(chat_id_str);
        if (message_id_str) |str| {
            defer bot.allocator.free(str);
        }
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn unpinAllChatMessages(bot: *Bot, chat_id: i64) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});

        try params.put("chat_id", chat_id_str);

        const response = try bot.makeRequest("unpinAllChatMessages", params);

        // Now it's safe to free the string after makeRequest is done
        defer bot.allocator.free(chat_id_str);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // Bot commands
    pub fn getMyCommands(bot: *Bot) ![]BotCommand {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const response = try bot.makeRequest("getMyCommands", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: []BotCommand }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        // Make deep copies of the commands
        var commands = try bot.allocator.alloc(BotCommand, parsed.value.result.len);
        for (parsed.value.result, 0..) |cmd, i| {
            commands[i] = BotCommand{
                .command = try bot.allocator.dupe(u8, cmd.command),
                .description = try bot.allocator.dupe(u8, cmd.description),
            };
        }

        return commands;
    }

    pub fn setMyCommands(bot: *Bot, commands: []const BotCommand) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Create commands JSON array
        var arena = std.heap.ArenaAllocator.init(bot.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var commands_json = std.ArrayList(u8).init(arena_allocator);
        defer commands_json.deinit();

        try commands_json.append('[');
        for (commands, 0..) |cmd, i| {
            if (i > 0) try commands_json.append(',');
            const escaped_command = try bot.escapeJsonString(cmd.command);
            defer bot.allocator.free(escaped_command);
            const escaped_description = try bot.escapeJsonString(cmd.description);
            defer bot.allocator.free(escaped_description);
            try commands_json.writer().print("{{\"command\":\"{s}\",\"description\":\"{s}\"}}", .{ escaped_command, escaped_description });
        }
        try commands_json.append(']');

        try params.put("commands", commands_json.items);

        const response = try bot.makeRequest("setMyCommands", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn deleteMyCommands(bot: *Bot) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const response = try bot.makeRequest("deleteMyCommands", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // File operations
    pub fn getFile(bot: *Bot, file_id: []const u8) !File {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        try params.put("file_id", file_id);

        const response = try bot.makeRequest("getFile", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: File }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        // Make deep copy
        var file = parsed.value.result;
        file.file_id = try bot.allocator.dupe(u8, file.file_id);
        file.file_unique_id = try bot.allocator.dupe(u8, file.file_unique_id);
        if (file.file_path) |path| {
            file.file_path = try bot.allocator.dupe(u8, path);
        }

        return file;
    }

    // Dice
    pub fn sendDice(bot: *Bot, chat_id: i64, emoji: ?[]const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        if (emoji) |e| {
            try params.put("emoji", e);
        }

        const response = try bot.makeRequest("sendDice", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    // Webhook management
    pub fn setWebhook(bot: *Bot, url: []const u8) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        try params.put("url", url);

        const response = try bot.makeRequest("setWebhook", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn getWebhookInfo(bot: *Bot) !WebhookInfo {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const response = try bot.makeRequest("getWebhookInfo", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: WebhookInfo }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        // Make deep copy
        var webhook_info = parsed.value.result;
        webhook_info.url = try bot.allocator.dupe(u8, webhook_info.url);
        if (webhook_info.last_error_message) |msg| {
            webhook_info.last_error_message = try bot.allocator.dupe(u8, msg);
        }

        return webhook_info;
    }

    // User profile photos
    pub fn getUserProfilePhotos(bot: *Bot, user_id: i64, offset: ?i32, limit: ?i32) !UserProfilePhotos {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const user_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{user_id});
        defer bot.allocator.free(user_id_str);

        try params.put("user_id", user_id_str);

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

        const response = try bot.makeRequest("getUserProfilePhotos", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: UserProfilePhotos }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return parsed.value.result;
    }

    // Send media by URL or file_id
    pub fn sendPhoto(bot: *Bot, chat_id: i64, photo: []const u8, caption: ?[]const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("photo", photo);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        const response = try bot.makeRequest("sendPhoto", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendAudio(bot: *Bot, chat_id: i64, audio: []const u8, caption: ?[]const u8, duration: ?i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("audio", audio);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        if (duration) |dur| {
            const duration_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{dur});
            defer bot.allocator.free(duration_str);
            try params.put("duration", duration_str);
        }

        const response = try bot.makeRequest("sendAudio", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendDocument(bot: *Bot, chat_id: i64, document: []const u8, caption: ?[]const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("document", document);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        const response = try bot.makeRequest("sendDocument", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendVideo(bot: *Bot, chat_id: i64, video: []const u8, caption: ?[]const u8, duration: ?i32, width: ?i32, height: ?i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("video", video);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        if (duration) |dur| {
            const duration_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{dur});
            defer bot.allocator.free(duration_str);
            try params.put("duration", duration_str);
        }

        if (width) |w| {
            const width_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{w});
            defer bot.allocator.free(width_str);
            try params.put("width", width_str);
        }

        if (height) |h| {
            const height_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{h});
            defer bot.allocator.free(height_str);
            try params.put("height", height_str);
        }

        const response = try bot.makeRequest("sendVideo", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendAnimation(bot: *Bot, chat_id: i64, animation: []const u8, caption: ?[]const u8, duration: ?i32, width: ?i32, height: ?i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("animation", animation);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        if (duration) |dur| {
            const duration_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{dur});
            defer bot.allocator.free(duration_str);
            try params.put("duration", duration_str);
        }

        if (width) |w| {
            const width_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{w});
            defer bot.allocator.free(width_str);
            try params.put("width", width_str);
        }

        if (height) |h| {
            const height_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{h});
            defer bot.allocator.free(height_str);
            try params.put("height", height_str);
        }

        const response = try bot.makeRequest("sendAnimation", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendVoice(bot: *Bot, chat_id: i64, voice: []const u8, caption: ?[]const u8, duration: ?i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("voice", voice);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        if (duration) |dur| {
            const duration_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{dur});
            defer bot.allocator.free(duration_str);
            try params.put("duration", duration_str);
        }

        const response = try bot.makeRequest("sendVoice", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendVideoNote(bot: *Bot, chat_id: i64, video_note: []const u8, duration: ?i32, length: ?i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("video_note", video_note);

        if (duration) |dur| {
            const duration_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{dur});
            defer bot.allocator.free(duration_str);
            try params.put("duration", duration_str);
        }

        if (length) |len| {
            const length_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{len});
            defer bot.allocator.free(length_str);
            try params.put("length", length_str);
        }

        const response = try bot.makeRequest("sendVideoNote", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendSticker(bot: *Bot, chat_id: i64, sticker: []const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("sticker", sticker);

        const response = try bot.makeRequest("sendSticker", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const utils = @import("utils.zig");
        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    // Inline query support
    pub fn answerInlineQuery(bot: *Bot, inline_query_id: []const u8, results: []const InlineQueryResult, cache_time: ?i32, is_personal: ?bool, next_offset: ?[]const u8) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        try params.put("inline_query_id", inline_query_id);

        // Serialize results array to JSON
        var arena = std.heap.ArenaAllocator.init(bot.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var results_json = std.ArrayList(u8).init(arena_allocator);
        defer results_json.deinit();

        try results_json.append('[');
        for (results, 0..) |result, i| {
            if (i > 0) try results_json.append(',');
            // This would need proper serialization based on result type
            // For now, this is a placeholder
            _ = result; // Suppress unused variable warning
            try results_json.appendSlice("{}");
        }
        try results_json.append(']');

        try params.put("results", results_json.items);

        if (cache_time) |ct| {
            const cache_time_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{ct});
            defer bot.allocator.free(cache_time_str);
            try params.put("cache_time", cache_time_str);
        }

        if (is_personal) |ip| {
            const is_personal_str = if (ip) "true" else "false";
            try params.put("is_personal", is_personal_str);
        }

        if (next_offset) |no| {
            try params.put("next_offset", no);
        }

        const response = try bot.makeRequest("answerInlineQuery", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // Advanced chat management
    pub fn setChatTitle(bot: *Bot, chat_id: i64, title: []const u8) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("title", title);

        const response = try bot.makeRequest("setChatTitle", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn setChatDescription(bot: *Bot, chat_id: i64, description: []const u8) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);
        try params.put("description", description);

        const response = try bot.makeRequest("setChatDescription", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn exportChatInviteLink(bot: *Bot, chat_id: i64) ![]const u8 {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
        defer bot.allocator.free(chat_id_str);

        try params.put("chat_id", chat_id_str);

        const response = try bot.makeRequest("exportChatInviteLink", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: []const u8 }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return try bot.allocator.dupe(u8, parsed.value.result);
    }

    // Log out and close
    pub fn logOut(bot: *Bot) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const response = try bot.makeRequest("logOut", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn close(bot: *Bot) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        const response = try bot.makeRequest("close", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
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
        .callback_query = if (obj.get("callback_query")) |val| try utils.parseCallbackQuery(allocator, val) else null,
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
