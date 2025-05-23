/// Telegram Bot API library for Zig
///
/// This library provides a comprehensive implementation of the Telegram Bot API,
/// allowing you to create and manage Telegram bots with full feature support.
///
/// ## Features
/// - Complete Bot API method coverage (100+ methods)
/// - Type-safe message handling with proper Zig error handling
/// - Inline keyboard support with callback query handling
/// - File operations (send/receive photos, documents, videos, etc.)
/// - Webhook management and long polling support
/// - Memory-safe operations with proper cleanup patterns
/// - Chat management (ban/unban users, set titles, etc.)
/// - Bot command management
/// - Poll creation and management
/// - Location and contact sharing
/// - Comprehensive error handling with descriptive error types
///
/// ## Quick Start
/// ```zig
/// const std = @import("std");
/// const telegram = @import("telegram.zig");
///
/// pub fn main() !void {
///     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
///     defer _ = gpa.deinit();
///     const allocator = gpa.allocator();
///
///     // Initialize HTTP client
///     var client = try telegram.HTTPClient.init(allocator);
///     defer client.deinit();
///
///     // Initialize bot
///     var bot = try telegram.Bot.init(allocator, "YOUR_BOT_TOKEN", &client);
///     defer bot.deinit();
///
///     // Get bot information
///     const me = try bot.methods.getMe();
///     defer me.deinit(allocator);
///     std.debug.print("Bot username: {s}\n", .{me.username orelse "none"});
///
///     // Send a message
///     const message = try bot.methods.sendMessage(chat_id, "Hello, World!");
///     defer message.deinit(allocator);
///
///     // Poll for updates
///     var offset: i32 = 0;
///     while (true) {
///         const updates = try bot.methods.getUpdates(offset, 10, 30);
///         defer {
///             for (updates) |*update| update.deinit(allocator);
///             allocator.free(updates);
///         }
///
///         for (updates) |update| {
///             offset = update.update_id + 1;
///
///             if (update.message) |msg| {
///                 if (msg.text) |text| {
///                     _ = try bot.methods.sendMessage(msg.chat.id, text);
///                 }
///             }
///         }
///     }
/// }
/// ```
///
/// ## Memory Management
/// This library follows Zig's explicit memory management patterns:
///
/// - All structs that allocate memory have a `deinit(allocator)` method
/// - Caller is responsible for calling `deinit()` on returned objects
/// - String fields in structs are owned by the struct and will be freed in `deinit()`
/// - Arrays and nested structs are recursively freed
/// - Use `defer` statements to ensure cleanup happens even on errors
///
/// ## Error Handling
/// The library uses Zig's error union types for robust error handling:
///
/// - `BotError.InvalidToken` - Bot token is invalid or empty
/// - `BotError.NetworkError` - Network or HTTP request failed
/// - `BotError.APIError` - General API error from Telegram
/// - `BotError.JSONError` - JSON parsing failed
/// - `BotError.TelegramAPIError` - Specific Telegram API error (check response)
/// - `BotError.OutOfMemory` - Memory allocation failed
///
/// ## Thread Safety
/// This library is NOT thread-safe. If you need to use it from multiple threads,
/// you must provide your own synchronization mechanisms.
///
/// ## API Coverage
/// This library implements the full Telegram Bot API as of 2024, including:
/// - Basic bot operations (getMe, getUpdates)
/// - Message sending (text, media, location, contact, polls)
/// - Message editing and deletion
/// - Inline keyboards and callback queries
/// - Chat management and administration
/// - File operations and media handling
/// - Webhook configuration
/// - Bot command management
/// - And much more...
///
/// For the complete API reference, see: https://core.telegram.org/bots/api
const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const utils = @import("utils.zig");
const json_utils = @import("json.zig");

/// Error types that can occur during Bot API operations
pub const BotError = error{
    /// Bot token is invalid or empty
    InvalidToken,
    /// Network connection or HTTP request failed
    NetworkError,
    /// General API error from Telegram servers
    APIError,
    /// JSON parsing or serialization failed
    JSONError,
    /// Memory allocation failed
    OutOfMemory,
    /// Specific Telegram API error (check response description)
    TelegramAPIError,
};

/// HTTP client wrapper for making API requests
///
/// This struct manages the underlying HTTP client and provides
/// a clean interface for the Bot to make requests.
pub const HTTPClient = struct {
    /// Memory allocator used for HTTP operations
    allocator: Allocator,
    /// Underlying standard library HTTP client
    client: std.http.Client,

    /// Initialize a new HTTP client
    ///
    /// Args:
    ///     allocator: Memory allocator to use for HTTP operations
    ///
    /// Returns:
    ///     Initialized HTTPClient or error if allocation fails
    pub fn init(allocator: Allocator) !HTTPClient {
        return HTTPClient{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    /// Clean up HTTP client resources
    ///
    /// Must be called when the client is no longer needed to prevent memory leaks.
    pub fn deinit(self: *HTTPClient) void {
        self.client.deinit();
    }
};

/// Main Bot structure representing a Telegram bot instance
///
/// This is the primary interface for interacting with the Telegram Bot API.
/// All API methods are available through the `methods` namespace.
pub const Bot = struct {
    /// Bot authentication token from @BotFather
    token: []const u8,
    /// Enable debug output for API calls
    debug: bool,
    /// HTTP client for making API requests
    client: *HTTPClient,
    /// Telegram API endpoint URL (default: https://api.telegram.org)
    api_endpoint: []const u8,
    /// Cached information about the bot user (filled by getMe())
    self_user: ?*User,
    /// Memory allocator for bot operations
    allocator: Allocator,

    // Helper functions for number formatting without heap allocation
    /// Format an i64 to string using a stack buffer
    /// Returns a slice into the provided buffer
    fn formatI64(value: i64, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "{d}", .{value}) catch unreachable;
    }

    /// Format an i32 to string using a stack buffer
    /// Returns a slice into the provided buffer
    fn formatI32(value: i32, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "{d}", .{value}) catch unreachable;
    }

    /// Format an f64 to string using a stack buffer
    /// Returns a slice into the provided buffer
    fn formatF64(value: f64, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "{d}", .{value}) catch unreachable;
    }

    /// Initialize a new Bot instance
    ///
    /// Args:
    ///     allocator: Memory allocator for bot operations
    ///     token: Bot token obtained from @BotFather
    ///     client: HTTP client for API requests
    ///
    /// Returns:
    ///     Initialized Bot instance or InvalidToken error if token is empty
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

    /// Clean up Bot resources
    ///
    /// Frees any cached user information. Must be called when the bot
    /// is no longer needed to prevent memory leaks.
    pub fn deinit(self: *Bot) void {
        if (self.self_user) |user| {
            const mutable_user = @constCast(user);
            mutable_user.deinit(self.allocator);
            self.allocator.destroy(mutable_user);
        }
    }

    /// Set a custom API endpoint URL
    ///
    /// Useful for using local Bot API servers or testing environments.
    ///
    /// Args:
    ///     endpoint: Custom API endpoint URL (e.g., "http://localhost:8081")
    pub fn setAPIEndpoint(self: *Bot, endpoint: []const u8) void {
        self.api_endpoint = endpoint;
    }

    /// Make an HTTP request to the Telegram Bot API
    ///
    /// This is the core method that handles all API communication.
    /// It constructs the URL, serializes parameters to JSON, and handles the response.
    ///
    /// Args:
    ///     endpoint: API method name (e.g., "sendMessage", "getUpdates")
    ///     params: Key-value pairs of parameters for the API call
    ///
    /// Returns:
    ///     Raw JSON response from the API (caller owns memory) or error
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

        // Convert params HashMap to a struct-like representation and then to JSON
        // Use the json_utils library for clean JSON marshaling
        const json_str = if (params.count() > 0)
            try json_utils.marshalStringHashMap(self.allocator, params)
        else
            try self.allocator.dupe(u8, "{}");
        defer self.allocator.free(json_str);

        std.debug.print("Request JSON: {s}\n", .{json_str});

        if (json_str.len > 2) { // More than just "{}"
            req.transfer_encoding = .{ .content_length = json_str.len };
            try req.send();
            try req.writeAll(json_str);
        } else {
            try req.send();
        }

        try req.finish();
        try req.wait();

        const body = try req.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));
        return body;
    }

    /// Create parameters using the new json_utils module
    /// This is much cleaner and more maintainable than the old manual approach
    fn createParams(bot: *Bot, value: anytype) !std.StringHashMap([]const u8) {
        return json_utils.createParams(bot.allocator, value);
    }

    /// Clean up parameters created with createParams
    fn cleanupParams(bot: *Bot, params: *std.StringHashMap([]const u8), original_value: anytype) void {
        json_utils.cleanupParamsWithValue(bot.allocator, params, original_value);
    }

    /// Simple cleanup for basic parameter maps
    fn cleanupParamsSimple(params: *std.StringHashMap([]const u8)) void {
        params.deinit();
    }
};

/// Represents a Telegram user or bot
///
/// This struct contains all information about a user as returned by the Telegram API.
/// String fields are owned by this struct and must be freed with deinit().
pub const User = struct {
    /// Unique identifier for this user or bot
    id: i64,
    /// True if this user is a bot
    is_bot: bool,
    /// User's or bot's first name
    first_name: []const u8,
    /// User's or bot's last name (optional)
    last_name: ?[]const u8 = null,
    /// User's or bot's username (optional)
    username: ?[]const u8 = null,
    /// IETF language tag of the user's language (optional)
    language_code: ?[]const u8 = null,
    /// True if this user is a Telegram Premium user (optional)
    is_premium: ?bool = null,
    /// True if this user added the bot to the attachment menu (optional)
    added_to_attachment_menu: ?bool = null,
    /// True if the bot can be invited to groups (optional, bot only)
    can_join_groups: ?bool = null,
    /// True if privacy mode is disabled for the bot (optional, bot only)
    can_read_all_group_messages: ?bool = null,
    /// True if the bot supports inline queries (optional, bot only)
    supports_inline_queries: ?bool = null,
    /// True if the bot can be connected to a Telegram Business account (optional, bot only)
    can_connect_to_business: ?bool = null,
    /// True if the bot has a main Web App (optional, bot only)
    has_main_web_app: ?bool = null,

    /// Free all allocated memory for this User
    ///
    /// Must be called when the User is no longer needed to prevent memory leaks.
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
    pub fn deinit(self: *User, allocator: Allocator) void {
        allocator.free(self.first_name);
        if (self.last_name) |name| allocator.free(name);
        if (self.username) |name| allocator.free(name);
        if (self.language_code) |code| allocator.free(code);
    }
};

/// Represents one special entity in a text message
///
/// For example, hashtags, usernames, URLs, etc.
pub const MessageEntity = struct {
    /// Type of the entity (e.g., "mention", "hashtag", "url", "bold", etc.)
    type: []const u8,
    /// Offset in UTF-16 code units to the start of the entity
    offset: i32,
    /// Length of the entity in UTF-16 code units
    length: i32,
    /// URL that will be opened after user taps on the text (optional, for "text_link" only)
    url: ?[]const u8 = null,
    /// The mentioned user (optional, for "text_mention" only)
    user: ?*const User = null,
    /// Programming language of the entity text (optional, for "pre" only)
    language: ?[]const u8 = null,

    /// Free all allocated memory for this MessageEntity
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
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

/// Represents a message in Telegram
///
/// This struct contains all information about a message, including its content,
/// sender, chat, and metadata. All string and nested struct fields are owned
/// by this struct and must be properly freed.
pub const Message = struct {
    /// Unique message identifier inside this chat
    message_id: i32,
    /// Sender of the message (optional, empty for messages sent to channels)
    from: ?*const User,
    /// Date the message was sent in Unix timestamp
    date: i64,
    /// Conversation the message belongs to
    chat: *const Chat,
    /// Actual UTF-8 text of the message (optional, for text messages)
    text: ?[]const u8,
    /// Special entities like usernames, URLs, bot commands, etc. (optional)
    entities: ?[]MessageEntity = null,
    /// Message that this message is a reply to (optional)
    pinned_message: ?*const Message = null,

    /// Free all allocated memory for this Message
    ///
    /// Recursively frees all nested structures including User, Chat, entities, etc.
    ///
    /// Args:
    ///     allocator: The allocator used to create the message and its fields
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

/// Represents a chat in Telegram
///
/// Can be a private chat, group, supergroup, or channel.
pub const Chat = struct {
    /// Unique identifier for this chat
    id: i64,
    /// Type of chat ("private", "group", "supergroup", or "channel")
    type: []const u8,
    /// Title for supergroups, channels and group chats (optional)
    title: ?[]const u8,
    /// Username for private chats, supergroups and channels if available (optional)
    username: ?[]const u8,
    /// First name of the other party in a private chat (optional)
    first_name: ?[]const u8,
    /// Last name of the other party in a private chat (optional)
    last_name: ?[]const u8,

    /// Free all allocated memory for this Chat
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
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
    /// Label text on the button
    text: []const u8,
    /// HTTP or tg:// URL to be opened when the button is pressed (optional)
    url: ?[]const u8 = null,
    /// Data to be sent in a callback query to the bot when button is pressed (optional)
    callback_data: ?[]const u8 = null,
    /// Inline query that will be inserted in the input field (optional)
    switch_inline_query: ?[]const u8 = null,
    /// Inline query for current chat only (optional)
    switch_inline_query_current_chat: ?[]const u8 = null,

    /// Free all allocated memory for this InlineKeyboardButton
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
    pub fn deinit(self: *InlineKeyboardButton, allocator: Allocator) void {
        allocator.free(self.text);
        if (self.url) |url| allocator.free(url);
        if (self.callback_data) |data| allocator.free(data);
        if (self.switch_inline_query) |query| allocator.free(query);
        if (self.switch_inline_query_current_chat) |query| allocator.free(query);
    }
};

/// Represents an inline keyboard markup
///
/// An inline keyboard is a set of buttons that appear below a message.
/// Buttons are arranged in rows, and each row can contain multiple buttons.
pub const InlineKeyboardMarkup = struct {
    /// Array of button rows, each row is an array of InlineKeyboardButton objects
    inline_keyboard: [][]InlineKeyboardButton,

    /// Free all allocated memory for this InlineKeyboardMarkup
    ///
    /// Recursively frees all buttons and their associated strings.
    ///
    /// Args:
    ///     allocator: The allocator used to create the keyboard and buttons
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

/// Represents an incoming callback query from a callback button in an inline keyboard
///
/// When a user presses an inline keyboard button with callback_data,
/// your bot will receive this update.
pub const CallbackQuery = struct {
    /// Unique identifier for this query
    id: []const u8,
    /// User who pressed the callback button
    from: *const User,
    /// Message with the callback button that originated the query (optional)
    message: ?*const Message = null,
    /// Identifier of the message sent via the bot in inline mode (optional)
    inline_message_id: ?[]const u8 = null,
    /// Global identifier corresponding to the chat to which the message belongs
    chat_instance: []const u8,
    /// Data associated with the callback button (optional)
    data: ?[]const u8 = null,
    /// Short name of a Game to be returned (optional)
    game_short_name: ?[]const u8 = null,

    /// Free all allocated memory for this CallbackQuery
    ///
    /// Args:
    ///     allocator: The allocator used to create the callback query and its fields
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

/// Represents an incoming update from Telegram
///
/// This object represents one kind of update that your bot can receive.
/// Only one of the optional fields will be present for each update.
pub const Update = struct {
    /// Unique identifier for this update
    update_id: i32,
    /// New incoming message of any kind — text, photo, sticker, etc. (optional)
    message: ?Message = null,
    /// New version of a message that is known to the bot and was edited (optional)
    edited_message: ?Message = null,
    /// New incoming channel post of any kind — text, photo, sticker, etc. (optional)
    channel_post: ?Message = null,
    /// New version of a channel post that is known to the bot and was edited (optional)
    edited_channel_post: ?Message = null,
    /// The bot was connected to or disconnected from a business account (optional)
    business_connection: ?std.json.Value = null,
    /// New message from a connected business account (optional)
    business_message: ?Message = null,
    /// New version of a message from a connected business account (optional)
    edited_business_message: ?Message = null,
    /// Messages were deleted from a connected business account (optional)
    deleted_business_messages: ?std.json.Value = null,
    /// A reaction to a message was changed by a user (optional)
    message_reaction: ?std.json.Value = null,
    /// Reactions to a message with anonymous reactions were changed (optional)
    message_reaction_count: ?std.json.Value = null,
    /// New incoming inline query (optional)
    inline_query: ?std.json.Value = null,
    /// Result of an inline query that was chosen by a user (optional)
    chosen_inline_result: ?std.json.Value = null,
    /// New incoming callback query (optional)
    callback_query: ?CallbackQuery = null,
    /// New incoming shipping query (optional)
    shipping_query: ?std.json.Value = null,
    /// New incoming pre-checkout query (optional)
    pre_checkout_query: ?std.json.Value = null,
    /// A user purchased paid media with a non-empty payload (optional)
    purchased_paid_media: ?std.json.Value = null,
    /// New poll state (optional)
    poll: ?std.json.Value = null,
    /// User changed their answer in a non-anonymous poll (optional)
    poll_answer: ?std.json.Value = null,
    /// Bot's chat member status was updated in a chat (optional)
    my_chat_member: ?std.json.Value = null,
    /// Chat member's status was updated in a chat (optional)
    chat_member: ?std.json.Value = null,
    /// A request to join the chat has been sent (optional)
    chat_join_request: ?std.json.Value = null,
    /// A chat boost was added or changed (optional)
    chat_boost: ?std.json.Value = null,
    /// A boost was removed from a chat (optional)
    removed_chat_boost: ?std.json.Value = null,

    /// Free all allocated memory for this Update
    ///
    /// Cleans up any present message or callback query data.
    ///
    /// Args:
    ///     allocator: The allocator used to create the update and its fields
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

/// Basic API response structure
///
/// All Telegram Bot API responses have this basic structure indicating
/// success or failure of the request.
pub const APIResponse = struct {
    /// True if the request was successful
    ok: bool,
    /// Error code in case of an unsuccessful request (optional)
    error_code: ?i32 = null,
    /// Human-readable description of the result or error (optional)
    description: ?[]const u8 = null,

    /// Free all allocated memory for this APIResponse
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
    pub fn deinit(self: *APIResponse, allocator: Allocator) void {
        if (self.description) |desc| allocator.free(desc);
    }
};

/// API response with a result field
///
/// Used for API methods that return data. The result field contains
/// the actual response data as a JSON value.
pub const APIResponseWithResult = struct {
    /// True if the request was successful
    ok: bool,
    /// The result of the query as a JSON value (optional)
    result: ?std.json.Value = null,
    /// Error code in case of an unsuccessful request (optional)
    error_code: ?i32 = null,
    /// Human-readable description of the result or error (optional)
    description: ?[]const u8 = null,

    /// Free all allocated memory for this APIResponseWithResult
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
    pub fn deinit(self: *APIResponseWithResult, allocator: Allocator) void {
        if (self.result) |*result| result.deinit();
        if (self.description) |desc| allocator.free(desc);
    }
};

// Bot command definition
pub const BotCommand = struct {
    /// Text of the command (1-32 characters, only lowercase letters, digits and underscores)
    command: []const u8,
    /// Description of the command (1-256 characters)
    description: []const u8,

    /// Free all allocated memory for this BotCommand
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
    pub fn deinit(self: *BotCommand, allocator: Allocator) void {
        allocator.free(self.command);
        allocator.free(self.description);
    }
};

// File information
pub const File = struct {
    /// Identifier for this file, which can be used to download or reuse the file
    file_id: []const u8,
    /// Unique identifier for this file, supposed to be the same over time and for different bots
    file_unique_id: []const u8,
    /// File size in bytes (optional)
    file_size: ?i32 = null,
    /// File path on Telegram servers, use to download the file (optional)
    file_path: ?[]const u8 = null,

    /// Free all allocated memory for this File
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
    pub fn deinit(self: *File, allocator: Allocator) void {
        allocator.free(self.file_id);
        allocator.free(self.file_unique_id);
        if (self.file_path) |path| allocator.free(path);
    }
};

// Webhook information
pub const WebhookInfo = struct {
    /// Webhook URL, may be empty if webhook is not set up
    url: []const u8,
    /// True if a custom certificate was provided for webhook certificate checks
    has_custom_certificate: bool,
    /// Number of updates awaiting delivery
    pending_update_count: i32,
    /// Currently used webhook IP address (optional)
    ip_address: ?[]const u8 = null,
    /// Unix timestamp of the most recent error (optional)
    last_error_date: ?i64 = null,
    /// Error message in human readable format for the most recent error (optional)
    last_error_message: ?[]const u8 = null,
    /// Unix timestamp of the most recent error that happened when synchronizing (optional)
    last_synchronization_error_date: ?i64 = null,
    /// Maximum allowed number of simultaneous HTTPS connections to the webhook (optional)
    max_connections: ?i32 = null,
    /// A list of update types the bot is subscribed to (optional)
    allowed_updates: ?[][]const u8 = null,

    /// Free all allocated memory for this WebhookInfo
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
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
    /// Identifier for this file, which can be used to download or reuse the file
    file_id: []const u8,
    /// Unique identifier for this file
    file_unique_id: []const u8,
    /// Photo width
    width: i32,
    /// Photo height
    height: i32,
    /// File size in bytes (optional)
    file_size: ?i32 = null,

    /// Free all allocated memory for this PhotoSize
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
    pub fn deinit(self: *PhotoSize, allocator: Allocator) void {
        allocator.free(self.file_id);
        allocator.free(self.file_unique_id);
    }
};

// User profile photos
pub const UserProfilePhotos = struct {
    /// Total number of profile pictures the target user has
    total_count: i32,
    /// Requested profile pictures (in up to 4 sizes each)
    photos: [][]PhotoSize,

    /// Free all allocated memory for this UserProfilePhotos
    ///
    /// Args:
    ///     allocator: The allocator used to create the photo arrays
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
    /// Type of the result (e.g., "article", "photo", "gif", etc.)
    type: []const u8,
    /// Unique identifier for this result (1-64 bytes)
    id: []const u8,

    /// Free all allocated memory for this InlineQueryResult
    ///
    /// Args:
    ///     allocator: The allocator used to create the string fields
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

        // Use stack buffers for number formatting - i32 max is 11 chars including sign
        var offset_buffer: [16]u8 = undefined;
        var limit_buffer: [16]u8 = undefined;
        var timeout_buffer: [16]u8 = undefined;

        const offset_str = Bot.formatI32(offset, &offset_buffer);
        const limit_str = Bot.formatI32(limit, &limit_buffer);
        const timeout_str = Bot.formatI32(timeout, &timeout_buffer);

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

    /// Remove webhook integration
    ///
    /// Use this method to remove webhook integration if you decide to switch back to getUpdates.
    /// Returns True on success.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///
    /// Returns:
    ///     True if the webhook was successfully deleted, or error if the request failed
    ///
    /// Example:
    /// ```zig
    /// const success = try bot.methods.deleteWebhook();
    /// if (success) {
    ///     std.debug.print("Webhook deleted successfully\n");
    /// }
    /// ```
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

    /// Send text message
    ///
    /// Use this method to send text messages. On success, the sent Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat or username of the target channel
    ///     text: Text of the message to be sent (1-4096 characters)
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    ///
    /// Note: Caller is responsible for freeing the returned Message with deinit()
    ///
    /// Example:
    /// ```zig
    /// const message = try bot.methods.sendMessage(chat_id, "Hello, World!");
    /// defer message.deinit(allocator);
    /// std.debug.print("Message sent with ID: {d}\n", .{message.message_id});
    /// ```
    pub fn sendMessage(bot: *Bot, chat_id: i64, text: []const u8) !Message {
        if (text.len == 0) return BotError.TelegramAPIError;

        // Create parameters using struct approach
        const MessageParams = struct {
            chat_id: i64,
            text: []const u8,
        };

        const params_struct = MessageParams{
            .chat_id = chat_id,
            .text = text,
        };

        var params = try bot.createParams(params_struct);
        defer bot.cleanupParams(&params, params_struct);

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
            result.from = try utils.parseUser(bot.allocator, from_val);
        } else {
            result.from = null;
        }

        // Handle chat field
        if (message_obj.get("chat")) |chat_val| {
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
            result.entities = try utils.parseMessageEntities(bot.allocator, entities_val);
        } else {
            result.entities = null;
        }

        // Initialize pinned_message field to null (this should be explicit)
        result.pinned_message = null;

        return result;
    }

    /// Send text message with inline keyboard
    ///
    /// Use this method to send text messages with custom inline keyboards.
    /// On success, the sent Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     text: Text of the message to be sent (1-4096 characters)
    ///     keyboard: Inline keyboard to be shown below the message
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    ///
    /// Note: Caller is responsible for freeing the returned Message with deinit()
    ///
    /// Example:
    /// ```zig
    /// var buttons = [_]InlineKeyboardButton{
    ///     InlineKeyboardButton{ .text = "Click me!", .callback_data = "button_clicked" }
    /// };
    /// var row = [_][]InlineKeyboardButton{&buttons};
    /// const keyboard = InlineKeyboardMarkup{ .inline_keyboard = &row };
    ///
    /// const message = try bot.methods.sendMessageWithKeyboard(chat_id, "Choose an option:", keyboard);
    /// defer message.deinit(allocator);
    /// ```
    pub fn sendMessageWithKeyboard(bot: *Bot, chat_id: i64, text: []const u8, keyboard: InlineKeyboardMarkup) !Message {
        if (text.len == 0) return BotError.TelegramAPIError;

        // Create parameters using struct approach
        const MessageParams = struct {
            chat_id: i64,
            text: []const u8,
        };

        const params_struct = MessageParams{
            .chat_id = chat_id,
            .text = text,
        };

        var params = try bot.createParams(params_struct);
        defer bot.cleanupParams(&params, params_struct);

        // Use the json_utils library to marshal the keyboard
        const keyboard_json = try json_utils.marshal(bot.allocator, keyboard);
        defer bot.allocator.free(keyboard_json);
        try params.put("reply_markup", keyboard_json);

        const response = try bot.makeRequest("sendMessage", params);
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
            result.from = try utils.parseUser(bot.allocator, from_val);
        } else {
            result.from = null;
        }

        // Handle chat field
        if (message_obj.get("chat")) |chat_val| {
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
            result.entities = try utils.parseMessageEntities(bot.allocator, entities_val);
        } else {
            result.entities = null;
        }

        // Initialize pinned_message field to null (this should be explicit)
        result.pinned_message = null;

        return result;
    }

    /// Answer callback query
    ///
    /// Use this method to send answers to callback queries sent from inline keyboards.
    /// The answer will be displayed to the user as a notification at the top of the chat screen
    /// or as an alert.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     callback_query_id: Unique identifier for the query to be answered
    ///     text: Text of the notification (optional, 0-200 characters)
    ///     show_alert: If True, an alert will be shown instead of a notification
    ///
    /// Returns:
    ///     True on success, or error if the request failed
    ///
    /// Example:
    /// ```zig
    /// // Simple notification
    /// _ = try bot.methods.answerCallbackQuery(query.id, "Button clicked!", false);
    ///
    /// // Alert popup
    /// _ = try bot.methods.answerCallbackQuery(query.id, "Important message!", true);
    /// ```
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
    /// Forward message from one chat to another
    ///
    /// Use this method to forward messages of any kind. Service messages can't be forwarded.
    /// On success, the sent Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     from_chat_id: Unique identifier for the chat where the original message was sent
    ///     message_id: Message identifier in the chat specified in from_chat_id
    ///
    /// Returns:
    ///     Forwarded Message object or error if the request failed
    pub fn forwardMessage(bot: *Bot, chat_id: i64, from_chat_id: i64, message_id: i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffers for number formatting
        var chat_id_buffer: [32]u8 = undefined;
        var from_chat_id_buffer: [32]u8 = undefined;
        var message_id_buffer: [16]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        const from_chat_id_str = Bot.formatI64(from_chat_id, &from_chat_id_buffer);
        const message_id_str = Bot.formatI32(message_id, &message_id_buffer);

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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    /// Copy message from one chat to another
    ///
    /// Use this method to copy messages of any kind. Service messages and invoice messages can't be copied.
    /// The method is analogous to the method forwardMessage, but the copied message doesn't have a link
    /// to the original message.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     from_chat_id: Unique identifier for the chat where the original message was sent
    ///     message_id: Message identifier in the chat specified in from_chat_id
    ///
    /// Returns:
    ///     MessageId of the sent message or error if the request failed
    pub fn copyMessage(bot: *Bot, chat_id: i64, from_chat_id: i64, message_id: i32) !i32 {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffers for number formatting
        var chat_id_buffer: [32]u8 = undefined;
        var from_chat_id_buffer: [32]u8 = undefined;
        var message_id_buffer: [16]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        const from_chat_id_str = Bot.formatI64(from_chat_id, &from_chat_id_buffer);
        const message_id_str = Bot.formatI32(message_id, &message_id_buffer);

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
    /// Edit text of a message
    ///
    /// Use this method to edit text and game messages. On success, the edited Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     message_id: Identifier of the message to edit
    ///     text: New text of the message (1-4096 characters)
    ///
    /// Returns:
    ///     Edited Message object or error if the request failed
    pub fn editMessageText(bot: *Bot, chat_id: i64, message_id: i32, text: []const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        // Use stack buffer for message_id formatting

        var message_id_buffer: [16]u8 = undefined;

        const message_id_str = Bot.formatI32(message_id, &message_id_buffer);

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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    /// Edit reply markup of a message
    ///
    /// Use this method to edit only the reply markup of messages. On success, the edited Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     message_id: Identifier of the message to edit
    ///     keyboard: New inline keyboard (pass null to remove keyboard)
    ///
    /// Returns:
    ///     Edited Message object or error if the request failed
    pub fn editMessageReplyMarkup(bot: *Bot, chat_id: i64, message_id: i32, keyboard: ?InlineKeyboardMarkup) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        // Use stack buffer for message_id formatting

        var message_id_buffer: [16]u8 = undefined;

        const message_id_str = Bot.formatI32(message_id, &message_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("message_id", message_id_str);

        if (keyboard) |kb| {
            // Use the json_utils library to marshal the keyboard
            const keyboard_json = try json_utils.marshal(bot.allocator, kb);
            defer bot.allocator.free(keyboard_json);
            try params.put("reply_markup", keyboard_json);
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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    /// Delete a message
    ///
    /// Use this method to delete a message, including service messages, with the following limitations:
    /// - A message can only be deleted if it was sent less than 48 hours ago
    /// - A dice message in a private chat can only be deleted if it was sent more than 24 hours ago
    /// - Bots can delete outgoing messages in private chats, groups, and supergroups
    /// - Bots can delete incoming messages in private chats
    /// - Bots granted can_post_messages permissions can delete outgoing messages in channels
    /// - If the bot is an administrator of a group, it can delete any message there
    /// - If the bot has can_delete_messages permission in a supergroup or a channel, it can delete any message there
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     message_id: Identifier of the message to delete
    ///
    /// Returns:
    ///     True on success, or error if the request failed
    pub fn deleteMessage(bot: *Bot, chat_id: i64, message_id: i32) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        // Use stack buffer for message_id formatting

        var message_id_buffer: [16]u8 = undefined;

        const message_id_str = Bot.formatI32(message_id, &message_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("message_id", message_id_str);

        const response = try bot.makeRequest("deleteMessage", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // Chat actions
    /// Send chat action
    ///
    /// Use this method when you need to tell the user that something is happening on the bot's side.
    /// The status is set for 5 seconds or less (when a message arrives from your bot, Telegram clients clear its typing status).
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     action: Type of action to broadcast (e.g., "typing", "upload_photo", "record_video", etc.)
    ///
    /// Returns:
    ///     True on success, or error if the request failed
    ///
    /// Available actions:
    /// - "typing" - for text messages
    /// - "upload_photo" - for photos
    /// - "record_video" or "upload_video" - for videos
    /// - "record_voice" or "upload_voice" - for voice notes
    /// - "upload_document" - for general files
    /// - "choose_sticker" - for stickers
    /// - "find_location" - for location data
    /// - "record_video_note" or "upload_video_note" - for video notes
    pub fn sendChatAction(bot: *Bot, chat_id: i64, action: []const u8) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("action", action);

        const response = try bot.makeRequest("sendChatAction", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    // Location and contact
    /// Send location
    ///
    /// Use this method to send point on the map. On success, the sent Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     latitude: Latitude of the location
    ///     longitude: Longitude of the location
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    pub fn sendLocation(bot: *Bot, chat_id: i64, latitude: f64, longitude: f64) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffers for number formatting
        var chat_id_buffer: [32]u8 = undefined;
        var latitude_buffer: [64]u8 = undefined;
        var longitude_buffer: [64]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        const latitude_str = Bot.formatF64(latitude, &latitude_buffer);
        const longitude_str = Bot.formatF64(longitude, &longitude_buffer);

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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    /// Send contact
    ///
    /// Use this method to send phone contacts. On success, the sent Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     phone_number: Contact's phone number
    ///     first_name: Contact's first name
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    pub fn sendContact(bot: *Bot, chat_id: i64, phone_number: []const u8, first_name: []const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    // Polls
    /// Send a poll
    ///
    /// Use this method to send a native poll. On success, the sent Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     question: Poll question (1-300 characters)
    ///     options: Array of answer options (2-10 strings, 1-100 characters each)
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    pub fn sendPoll(bot: *Bot, chat_id: i64, question: []const u8, options: [][]const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        // Create options JSON array using json_utils.marshal
        const options_json = try json_utils.marshal(bot.allocator, options);
        defer bot.allocator.free(options_json);

        try params.put("chat_id", chat_id_str);
        try params.put("question", question);
        try params.put("options", options_json);

        const response = try bot.makeRequest("sendPoll", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    // Chat management
    /// Get chat information
    ///
    /// Use this method to get up to date information about the chat. Returns a Chat object on success.
    pub fn getChat(bot: *Bot, chat_id: i64) !Chat {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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

        const chat_ptr = try utils.parseChat(bot.allocator, parsed.value.result);
        defer bot.allocator.destroy(chat_ptr);
        return chat_ptr.*;
    }

    pub fn getChatMemberCount(bot: *Bot, chat_id: i64) !i32 {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        // Use stack buffer for user_id formatting

        var user_id_buffer: [32]u8 = undefined;

        const user_id_str = Bot.formatI64(user_id, &user_id_buffer);

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

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        // Use stack buffer for user_id formatting

        var user_id_buffer: [32]u8 = undefined;

        const user_id_str = Bot.formatI64(user_id, &user_id_buffer);

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

        // Use stack buffers for number formatting
        var chat_id_buffer: [32]u8 = undefined;
        var message_id_buffer: [16]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);
        const message_id_str = Bot.formatI32(message_id, &message_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("message_id", message_id_str);

        const response = try bot.makeRequest("pinChatMessage", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn unpinChatMessage(bot: *Bot, chat_id: i64, message_id: ?i32) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting
        var chat_id_buffer: [32]u8 = undefined;
        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);

        var message_id_str: ?[]const u8 = null;
        if (message_id) |msg_id| {
            var message_id_buffer: [16]u8 = undefined;
            message_id_str = Bot.formatI32(msg_id, &message_id_buffer);
            try params.put("message_id", message_id_str.?);
        }

        const response = try bot.makeRequest("unpinChatMessage", params);

        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        return api_response.value.ok;
    }

    pub fn unpinAllChatMessages(bot: *Bot, chat_id: i64) !bool {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting
        var chat_id_buffer: [32]u8 = undefined;
        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);

        const response = try bot.makeRequest("unpinAllChatMessages", params);

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

        // Create commands JSON array using json_utils.marshal
        const commands_json = try json_utils.marshal(bot.allocator, commands);
        defer bot.allocator.free(commands_json);

        try params.put("commands", commands_json);

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

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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

        // Use stack buffer for user_id formatting

        var user_id_buffer: [32]u8 = undefined;

        const user_id_str = Bot.formatI64(user_id, &user_id_buffer);

        try params.put("user_id", user_id_str);

        if (offset) |o| {
            // Use stack buffer for o formatting

            var offset_buffer: [16]u8 = undefined;

            const offset_str = Bot.formatI32(o, &offset_buffer);
            try params.put("offset", offset_str);
        }

        if (limit) |l| {
            // Use stack buffer for l formatting

            var limit_buffer: [16]u8 = undefined;

            const limit_str = Bot.formatI32(l, &limit_buffer);
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
    /// Send photo
    ///
    /// Use this method to send photos. On success, the sent Message is returned.
    /// Bots can currently send photos up to 50 MB in size.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     photo: Photo to send (pass a file_id as String to send a photo that exists on Telegram servers, or a URL)
    ///     caption: Photo caption (optional, 0-1024 characters)
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    pub fn sendPhoto(bot: *Bot, chat_id: i64, photo: []const u8, caption: ?[]const u8) !Message {
        if (photo.len == 0) return BotError.TelegramAPIError;

        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting
        var chat_id_buffer: [32]u8 = undefined;
        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("photo", photo);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        const response = try bot.makeRequest("sendPhoto", params);

        defer bot.allocator.free(response);

        // Debug: print the raw JSON response
        std.debug.print("sendPhoto JSON response: {s}\n", .{response});

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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    /// Send audio file
    ///
    /// Use this method to send audio files, if you want Telegram clients to display them
    /// in the music player. Your audio must be in the .MP3 or .M4A format.
    /// On success, the sent Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     audio: Audio file to send (pass a file_id or URL)
    ///     caption: Audio caption (optional, 0-1024 characters)
    ///     duration: Duration of the audio in seconds (optional)
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    pub fn sendAudio(bot: *Bot, chat_id: i64, audio: []const u8, caption: ?[]const u8, duration: ?i32) !Message {
        if (audio.len == 0) return BotError.TelegramAPIError;

        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("audio", audio);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        if (duration) |dur| {
            // Use stack buffer for dur formatting

            var duration_buffer: [16]u8 = undefined;

            const duration_str = Bot.formatI32(dur, &duration_buffer);
            try params.put("duration", duration_str);
        }

        const response = try bot.makeRequest("sendAudio", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            const error_msg = api_response.value.description orelse "Unknown API error";
            std.debug.print("API Error: {s}\n", .{error_msg});
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    /// Send general file
    ///
    /// Use this method to send general files. On success, the sent Message is returned.
    /// Bots can currently send files of any type of up to 50 MB in size.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     document: File to send (pass a file_id or URL)
    ///     caption: Document caption (optional, 0-1024 characters)
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    pub fn sendDocument(bot: *Bot, chat_id: i64, document: []const u8, caption: ?[]const u8) !Message {
        if (document.len == 0) return BotError.TelegramAPIError;

        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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
            const error_msg = api_response.value.description orelse "Unknown API error";
            std.debug.print("API Error: {s}\n", .{error_msg});
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    /// Send video file
    ///
    /// Use this method to send video files, Telegram clients support mp4 videos.
    /// On success, the sent Message is returned.
    ///
    /// Args:
    ///     bot: Bot instance to use for the request
    ///     chat_id: Unique identifier for the target chat
    ///     video: Video to send (pass a file_id or URL)
    ///     caption: Video caption (optional, 0-1024 characters)
    ///     duration: Duration of sent video in seconds (optional)
    ///     width: Video width (optional)
    ///     height: Video height (optional)
    ///
    /// Returns:
    ///     Sent Message object or error if the request failed
    pub fn sendVideo(bot: *Bot, chat_id: i64, video: []const u8, caption: ?[]const u8, duration: ?i32, width: ?i32, height: ?i32) !Message {
        if (video.len == 0) return BotError.TelegramAPIError;

        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("video", video);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        if (duration) |dur| {
            // Use stack buffer for dur formatting

            var duration_buffer: [16]u8 = undefined;

            const duration_str = Bot.formatI32(dur, &duration_buffer);
            try params.put("duration", duration_str);
        }

        if (width) |w| {
            // Use stack buffer for w formatting

            var width_buffer: [16]u8 = undefined;

            const width_str = Bot.formatI32(w, &width_buffer);
            try params.put("width", width_str);
        }

        if (height) |h| {
            // Use stack buffer for h formatting

            var height_buffer: [16]u8 = undefined;

            const height_str = Bot.formatI32(h, &height_buffer);
            try params.put("height", height_str);
        }

        const response = try bot.makeRequest("sendVideo", params);
        defer bot.allocator.free(response);

        const api_response = try std.json.parseFromSlice(APIResponse, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer api_response.deinit();

        if (!api_response.value.ok) {
            const error_msg = api_response.value.description orelse "Unknown API error";
            std.debug.print("API Error: {s}\n", .{error_msg});
            return BotError.TelegramAPIError;
        }

        const parsed = try std.json.parseFromSlice(struct { result: std.json.Value }, bot.allocator, response, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendAnimation(bot: *Bot, chat_id: i64, animation: []const u8, caption: ?[]const u8, duration: ?i32, width: ?i32, height: ?i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("animation", animation);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        if (duration) |dur| {
            // Use stack buffer for dur formatting

            var duration_buffer: [16]u8 = undefined;

            const duration_str = Bot.formatI32(dur, &duration_buffer);
            try params.put("duration", duration_str);
        }

        if (width) |w| {
            // Use stack buffer for w formatting

            var width_buffer: [16]u8 = undefined;

            const width_str = Bot.formatI32(w, &width_buffer);
            try params.put("width", width_str);
        }

        if (height) |h| {
            // Use stack buffer for h formatting

            var height_buffer: [16]u8 = undefined;

            const height_str = Bot.formatI32(h, &height_buffer);
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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendVoice(bot: *Bot, chat_id: i64, voice: []const u8, caption: ?[]const u8, duration: ?i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("voice", voice);

        if (caption) |cap| {
            try params.put("caption", cap);
        }

        if (duration) |dur| {
            // Use stack buffer for dur formatting

            var duration_buffer: [16]u8 = undefined;

            const duration_str = Bot.formatI32(dur, &duration_buffer);
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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendVideoNote(bot: *Bot, chat_id: i64, video_note: []const u8, duration: ?i32, length: ?i32) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

        try params.put("chat_id", chat_id_str);
        try params.put("video_note", video_note);

        if (duration) |dur| {
            // Use stack buffer for dur formatting

            var duration_buffer: [16]u8 = undefined;

            const duration_str = Bot.formatI32(dur, &duration_buffer);
            try params.put("duration", duration_str);
        }

        if (length) |len| {
            // Use stack buffer for len formatting

            var length_buffer: [16]u8 = undefined;

            const length_str = Bot.formatI32(len, &length_buffer);
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

        return utils.parseMessage(bot.allocator, parsed.value.result);
    }

    pub fn sendSticker(bot: *Bot, chat_id: i64, sticker: []const u8) !Message {
        var params = std.StringHashMap([]const u8).init(bot.allocator);
        defer params.deinit();

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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
            // Use stack buffer for ct formatting

            var cache_time_buffer: [32]u8 = undefined;

            const cache_time_str = Bot.formatI64(ct, &cache_time_buffer);
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

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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

        // Use stack buffer for chat_id formatting

        var chat_id_buffer: [32]u8 = undefined;

        const chat_id_str = Bot.formatI64(chat_id, &chat_id_buffer);

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

/// Parse a JSON value into an Update struct
///
/// This function converts a JSON value received from the Telegram Bot API
/// into a properly typed Update struct. It handles all update types and
/// properly allocates memory for nested structures.
///
/// Args:
///     allocator: Memory allocator for creating the Update and its nested structures
///     value: JSON value containing the update data
///
/// Returns:
///     Parsed Update struct or error if parsing fails
///
/// Note: The caller is responsible for calling deinit() on the returned Update
/// to free all allocated memory.
///
/// Example:
/// ```zig
/// // Usually called internally by getUpdates(), but can be used directly:
/// const update = try parseUpdate(allocator, json_value);
/// defer update.deinit(allocator);
/// ```
pub fn parseUpdate(allocator: Allocator, value: std.json.Value) !Update {
    if (value != .object) return BotError.JSONError;
    const obj = value.object;

    std.debug.print("Parsing Update with fields: {any}\n", .{obj.keys()});
    for (obj.keys()) |key| {
        const val = obj.get(key).?;
        std.debug.print("Field {s}: {any}\n", .{ key, val });
    }

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
