const std = @import("std");
const telegram = @import("telegram");

// Bot state to track conversation flow
const BotState = struct {
    allocator: std.mem.Allocator,
    user_states: std.AutoHashMap(i64, UserState),

    const UserState = enum {
        normal,
        waiting_for_echo,
        waiting_for_broadcast,
        keyboard_demo,
        settings_menu,
        confirmation_pending,
    };

    pub fn init(allocator: std.mem.Allocator) BotState {
        return BotState{
            .allocator = allocator,
            .user_states = std.AutoHashMap(i64, UserState).init(allocator),
        };
    }

    pub fn deinit(self: *BotState) void {
        self.user_states.deinit();
    }

    pub fn setState(self: *BotState, user_id: i64, state: UserState) !void {
        try self.user_states.put(user_id, state);
    }

    pub fn getState(self: *BotState, user_id: i64) UserState {
        return self.user_states.get(user_id) orelse .normal;
    }

    pub fn clearState(self: *BotState, user_id: i64) void {
        _ = self.user_states.remove(user_id);
    }
};

// Statistics tracking
const BotStats = struct {
    messages_received: u64 = 0,
    messages_sent: u64 = 0,
    callback_queries_received: u64 = 0,
    unique_users: std.AutoHashMap(i64, void),
    start_time: i64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BotStats {
        return BotStats{
            .unique_users = std.AutoHashMap(i64, void).init(allocator),
            .start_time = std.time.timestamp(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BotStats) void {
        self.unique_users.deinit();
    }

    pub fn recordMessage(self: *BotStats, user_id: i64) !void {
        self.messages_received += 1;
        try self.unique_users.put(user_id, {});
    }

    pub fn recordCallback(self: *BotStats, user_id: i64) !void {
        self.callback_queries_received += 1;
        try self.unique_users.put(user_id, {});
    }

    pub fn recordSent(self: *BotStats) void {
        self.messages_sent += 1;
    }

    pub fn getUptime(self: *BotStats) i64 {
        return std.time.timestamp() - self.start_time;
    }
};

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get bot token from command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <bot_token>\n", .{args[0]});
        std.debug.print("Example: {s} 123456789:ABCdefGhiJklmnoPQRstuv222\n", .{args[0]});
        return;
    }

    const token = args[1];

    // Initialize HTTP client
    var client = try telegram.HTTPClient.init(allocator);
    defer client.deinit();

    // Initialize bot
    var bot = try telegram.Bot.init(allocator, token, &client);
    defer bot.deinit();

    // Initialize bot state and stats
    var bot_state = BotState.init(allocator);
    defer bot_state.deinit();

    var bot_stats = BotStats.init(allocator);
    defer bot_stats.deinit();

    std.debug.print("🚀 Advanced Telegram Bot Starting...\n", .{});

    // Get bot information
    const me = telegram.methods.getMe(&bot) catch |err| {
        std.debug.print("❌ Failed to get bot info: {}\n", .{err});
        return;
    };
    defer {
        var user_copy = me;
        user_copy.deinit(allocator);
    }

    std.debug.print("✅ Bot @{s} is online!\n", .{me.username orelse me.first_name});
    std.debug.print("📊 Features enabled:\n", .{});
    std.debug.print("   • Message handling with state management\n", .{});
    std.debug.print("   • Interactive commands\n", .{});
    std.debug.print("   • Inline keyboard support\n", .{});
    std.debug.print("   • Callback query handling\n", .{});
    std.debug.print("   • User statistics tracking\n", .{});
    std.debug.print("   • Conversation flow control\n", .{});
    std.debug.print("   • Error handling and recovery\n", .{});

    // Delete webhook to ensure polling mode
    _ = telegram.methods.deleteWebhook(&bot) catch |err| {
        std.debug.print("⚠️  Warning: Failed to delete webhook: {}\n", .{err});
    };

    var offset: i32 = 0;
    const limit: i32 = 100;
    const timeout: i32 = 30;

    std.debug.print("\n🔄 Entering main loop (send /help to see available commands)...\n", .{});

    while (true) {
        // Get updates
        const updates = telegram.methods.getUpdates(&bot, offset, limit, timeout) catch |err| {
            std.debug.print("❌ Failed to get updates: {}\n", .{err});
            std.time.sleep(5 * std.time.ns_per_s);
            continue;
        };
        defer {
            for (updates) |*update| {
                update.deinit(allocator);
            }
            allocator.free(updates);
        }

        // Process each update
        for (updates) |update| {
            offset = update.update_id + 1;

            if (update.message) |message| {
                try handleMessage(&bot, message, &bot_state, &bot_stats);
            } else if (update.edited_message) |message| {
                std.debug.print("✏️  Message edited by user {d}\n", .{message.from.?.id});
            } else if (update.callback_query) |callback_query| {
                try handleCallbackQuery(&bot, callback_query, &bot_state, &bot_stats);
            }
        }

        // Show periodic stats
        if (bot_stats.messages_received > 0 and bot_stats.messages_received % 10 == 0) {
            showStats(&bot_stats);
        }

        if (updates.len == 0) {
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }
}

fn handleMessage(bot: *telegram.Bot, message: telegram.Message, bot_state: *BotState, bot_stats: *BotStats) !void {
    const user_id = message.from.?.id;
    const chat_id = message.chat.id;

    // Record statistics
    try bot_stats.recordMessage(user_id);

    // Get user's current state
    const state = bot_state.getState(user_id);

    std.debug.print("💬 Message from {s} [ID: {d}] in chat {d}\n", .{ message.from.?.first_name, user_id, chat_id });

    if (message.text) |text| {
        std.debug.print("   Text: \"{s}\"\n", .{text});

        // Handle different states
        switch (state) {
            .waiting_for_echo => {
                try handleEchoInput(bot, chat_id, text, user_id, bot_state, bot_stats);
                return;
            },
            .waiting_for_broadcast => {
                try handleBroadcastInput(bot, chat_id, text, user_id, bot_state, bot_stats);
                return;
            },
            .normal, .keyboard_demo, .settings_menu, .confirmation_pending => {
                // Handle normal commands
                if (std.mem.startsWith(u8, text, "/")) {
                    try handleCommand(bot, message, text, bot_state, bot_stats);
                } else {
                    try handleRegularMessage(bot, message, bot_stats);
                }
            },
        }
    }
}

fn handleCallbackQuery(bot: *telegram.Bot, callback_query: telegram.CallbackQuery, bot_state: *BotState, bot_stats: *BotStats) !void {
    const user_id = callback_query.from.id;
    const callback_data = callback_query.data orelse "no_data";

    // Record statistics
    try bot_stats.recordCallback(user_id);

    std.debug.print("🔘 Callback query from {s} [ID: {d}] with data: \"{s}\"\n", .{ callback_query.from.first_name, user_id, callback_data });

    // Answer the callback query first to remove loading state
    _ = telegram.methods.answerCallbackQuery(bot, callback_query.id, null, false) catch |err| {
        std.debug.print("❌ Failed to answer callback query: {}\n", .{err});
    };

    // Handle different callback data
    if (std.mem.eql(u8, callback_data, "demo_simple")) {
        try showSimpleKeyboard(bot, callback_query.message.?.chat.id, bot_stats);
    } else if (std.mem.eql(u8, callback_data, "demo_complex")) {
        try showComplexKeyboard(bot, callback_query.message.?.chat.id, bot_stats);
    } else if (std.mem.eql(u8, callback_data, "demo_urls")) {
        try showUrlKeyboard(bot, callback_query.message.?.chat.id, bot_stats);
    } else if (std.mem.eql(u8, callback_data, "settings")) {
        try bot_state.setState(user_id, .settings_menu);
        try showSettingsMenu(bot, callback_query.message.?.chat.id, bot_stats);
    } else if (std.mem.eql(u8, callback_data, "back_main")) {
        bot_state.clearState(user_id);
        try showMainKeyboard(bot, callback_query.message.?.chat.id, bot_stats);
    } else if (std.mem.eql(u8, callback_data, "confirm_action")) {
        try handleConfirmation(bot, callback_query.message.?.chat.id, user_id, true, bot_state, bot_stats);
    } else if (std.mem.eql(u8, callback_data, "cancel_action")) {
        try handleConfirmation(bot, callback_query.message.?.chat.id, user_id, false, bot_state, bot_stats);
    } else if (std.mem.startsWith(u8, callback_data, "option_")) {
        const option_num = callback_data[7..];
        try handleOptionSelection(bot, callback_query.message.?.chat.id, option_num, bot_stats);
    } else if (std.mem.startsWith(u8, callback_data, "count_")) {
        const count_str = callback_data[6..];
        try handleCounterButton(bot, callback_query.message.?.chat.id, count_str, bot_stats);
    } else {
        var response_buffer: [256]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buffer, "🔘 You pressed: {s}", .{callback_data});
        try sendMessage(bot, callback_query.message.?.chat.id, response, bot_stats);
    }
}

fn handleCommand(bot: *telegram.Bot, message: telegram.Message, text: []const u8, bot_state: *BotState, bot_stats: *BotStats) !void {
    const chat_id = message.chat.id;
    const user_id = message.from.?.id;

    if (std.mem.eql(u8, text, "/start")) {
        try sendStartMessage(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/help")) {
        try sendHelpMessage(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/keyboard")) {
        try showMainKeyboard(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/confirm")) {
        try bot_state.setState(user_id, .confirmation_pending);
        try showConfirmationKeyboard(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/counter")) {
        try showCounterKeyboard(bot, chat_id, 0, bot_stats);
    } else if (std.mem.eql(u8, text, "/echo")) {
        try startEchoMode(bot, chat_id, user_id, bot_state, bot_stats);
    } else if (std.mem.eql(u8, text, "/info")) {
        try sendUserInfo(bot, message, bot_stats);
    } else if (std.mem.eql(u8, text, "/stats")) {
        try sendDetailedStats(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/cancel")) {
        try cancelCurrentAction(bot, chat_id, user_id, bot_state, bot_stats);
    } else if (std.mem.eql(u8, text, "/time")) {
        try sendCurrentTime(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/ping")) {
        try sendPong(bot, chat_id, bot_stats);
    } else if (std.mem.startsWith(u8, text, "/echo ")) {
        const echo_text = text[6..];
        try sendEcho(bot, chat_id, echo_text, bot_stats);
    } else {
        try sendUnknownCommand(bot, chat_id, text, bot_stats);
    }
}

fn handleRegularMessage(bot: *telegram.Bot, message: telegram.Message, bot_stats: *BotStats) !void {
    const chat_id = message.chat.id;

    if (message.text) |text| {
        // Analyze the message
        var response_buffer: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&response_buffer);
        const writer = fbs.writer();

        try writer.print("📝 Message Analysis:\n\n", .{});
        try writer.print("Length: {d} characters\n", .{text.len});
        try writer.print("Words: ~{d}\n", .{countWords(text)});

        if (containsURL(text)) {
            try writer.print("🔗 Contains URL\n", .{});
        }
        if (containsMention(text)) {
            try writer.print("👤 Contains @mention\n", .{});
        }
        if (containsHashtag(text)) {
            try writer.print("# Contains #hashtag\n", .{});
        }

        try writer.print("\nTip: Use /help to see available commands!", .{});

        const response = fbs.getWritten();
        try sendMessage(bot, chat_id, response, bot_stats);
    }
}

fn startEchoMode(bot: *telegram.Bot, chat_id: i64, user_id: i64, bot_state: *BotState, bot_stats: *BotStats) !void {
    try bot_state.setState(user_id, .waiting_for_echo);
    const message = "🔄 Echo mode activated! Send me any message and I'll repeat it back.\nSend /cancel to exit echo mode.";
    try sendMessage(bot, chat_id, message, bot_stats);
}

fn handleEchoInput(bot: *telegram.Bot, chat_id: i64, text: []const u8, user_id: i64, bot_state: *BotState, bot_stats: *BotStats) !void {
    if (std.mem.eql(u8, text, "/cancel")) {
        try cancelCurrentAction(bot, chat_id, user_id, bot_state, bot_stats);
        return;
    }

    var echo_buffer: [1024]u8 = undefined;
    const echo_message = try std.fmt.bufPrint(&echo_buffer, "🔊 Echo: {s}", .{text});

    try sendMessage(bot, chat_id, echo_message, bot_stats);
}

fn handleBroadcastInput(bot: *telegram.Bot, chat_id: i64, text: []const u8, user_id: i64, bot_state: *BotState, bot_stats: *BotStats) !void {
    _ = text; // For future implementation
    bot_state.clearState(user_id);
    try sendMessage(bot, chat_id, "📢 Broadcast feature not implemented yet!", bot_stats);
}

fn cancelCurrentAction(bot: *telegram.Bot, chat_id: i64, user_id: i64, bot_state: *BotState, bot_stats: *BotStats) !void {
    bot_state.clearState(user_id);
    try sendMessage(bot, chat_id, "✅ Action cancelled. Back to normal mode.", bot_stats);
}

fn sendStartMessage(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const start_text =
        \\🤖 **Welcome to the Advanced Telegram Bot!**
        \\
        \\This bot demonstrates the full capabilities of the zigtgshka library:
        \\
        \\🚀 **Features:**
        \\• Interactive conversation flows
        \\• **Inline keyboard support** ⌨️
        \\• **Callback query handling** 🔘
        \\• Message analysis and statistics
        \\• State management
        \\• Error handling
        \\• Real-time updates
        \\
        \\🎮 **Try the interactive keyboards:**
        \\• `/keyboard` - Main keyboard demo
        \\• `/confirm` - Confirmation dialog
        \\• `/counter` - Interactive counter
        \\
        \\Type `/help` to see all available commands!
    ;
    try sendMessage(bot, chat_id, start_text, bot_stats);
}

fn sendHelpMessage(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const help_text =
        \\📚 Available Commands:
        \\
        \\🔧 Basic Commands:
        \\/start - Welcome message
        \\/help - Show this help
        \\/info - Show chat information
        \\/ping - Test bot responsiveness
        \\/time - Get current time
        \\
        \\🎮 Interactive Commands:
        \\/echo - Start interactive echo mode
        \\/echo <text> - Echo specific text
        \\/cancel - Cancel current action
        \\
        \\⌨️ Inline Keyboard Commands:
        \\/keyboard - Show main keyboard demo
        \\/confirm - Show confirmation dialog
        \\/counter - Interactive counter
        \\
        \\📊 Information:
        \\/stats - Show bot statistics
        \\
        \\💡 Tips:
        \\• Send any text for message analysis
        \\• Try the interactive keyboards!
        \\• The bot tracks usage statistics
        \\• All operations use proper memory management
        \\• State is maintained per user
    ;
    try sendMessage(bot, chat_id, help_text, bot_stats);
}

fn sendUserInfo(bot: *telegram.Bot, message: telegram.Message, bot_stats: *BotStats) !void {
    var info_buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&info_buffer);
    const writer = fbs.writer();

    try writer.print("👤 User & Chat Information:\n\n", .{});

    // Chat info
    try writer.print("💬 Chat:\n", .{});
    try writer.print("🆔 ID: {d}\n", .{message.chat.id});
    try writer.print("📁 Type: {s}\n", .{message.chat.type});
    if (message.chat.title) |title| {
        try writer.print("📝 Title: {s}\n", .{title});
    }
    if (message.chat.username) |username| {
        try writer.print("👤 Username: @{s}\n", .{username});
    }

    // User info
    if (message.from) |from| {
        try writer.print("\n👤 User:\n", .{});
        try writer.print("🆔 ID: {d}\n", .{from.id});
        try writer.print("📝 Name: {s}", .{from.first_name});
        if (from.last_name) |last_name| {
            try writer.print(" {s}", .{last_name});
        }
        try writer.print("\n", .{});
        if (from.username) |username| {
            try writer.print("👤 Username: @{s}\n", .{username});
        }
        try writer.print("🤖 Is Bot: {}\n", .{from.is_bot});
        if (from.language_code) |lang| {
            try writer.print("🌍 Language: {s}\n", .{lang});
        }
    }

    // Message info
    try writer.print("\n📨 Message:\n", .{});
    try writer.print("🆔 ID: {d}\n", .{message.message_id});
    try writer.print("🕐 Date: {d}\n", .{message.date});

    const info_text = fbs.getWritten();
    try sendMessage(bot, message.chat.id, info_text, bot_stats);
}

fn sendDetailedStats(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    var stats_buffer: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&stats_buffer);
    const writer = fbs.writer();

    const uptime = bot_stats.getUptime();
    const hours = @divTrunc(uptime, 3600);
    const minutes = @divTrunc(@rem(uptime, 3600), 60);
    const seconds = @rem(uptime, 60);

    try writer.print("📊 Bot Statistics:\n\n", .{});
    try writer.print("📨 Messages Received: {d}\n", .{bot_stats.messages_received});
    try writer.print("📤 Messages Sent: {d}\n", .{bot_stats.messages_sent});
    try writer.print("🔘 Callback Queries: {d}\n", .{bot_stats.callback_queries_received});
    try writer.print("👥 Unique Users: {d}\n", .{bot_stats.unique_users.count()});
    try writer.print("⏱️  Uptime: {d}h {d}m {d}s\n", .{ hours, minutes, seconds });

    if (bot_stats.messages_received > 0) {
        const avg_response = @as(f64, @floatFromInt(bot_stats.messages_sent)) / @as(f64, @floatFromInt(bot_stats.messages_received));
        try writer.print("📈 Avg Responses/Message: {d:.2}\n", .{avg_response});
    }

    if (bot_stats.callback_queries_received > 0) {
        const total_interactions = bot_stats.messages_received + bot_stats.callback_queries_received;
        const callback_ratio = @as(f64, @floatFromInt(bot_stats.callback_queries_received)) / @as(f64, @floatFromInt(total_interactions)) * 100.0;
        try writer.print("🔘 Callback Ratio: {d:.1}%\n", .{callback_ratio});
    }

    const stats_text = fbs.getWritten();
    try sendMessage(bot, chat_id, stats_text, bot_stats);
}

fn sendCurrentTime(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const timestamp = std.time.timestamp();
    var time_buffer: [64]u8 = undefined;
    const time_message = try std.fmt.bufPrint(&time_buffer, "🕐 Current Unix timestamp: {d}", .{timestamp});
    try sendMessage(bot, chat_id, time_message, bot_stats);
}

fn sendPong(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    try sendMessage(bot, chat_id, "🏓 Pong! Bot is responsive.", bot_stats);
}

fn sendEcho(bot: *telegram.Bot, chat_id: i64, text: []const u8, bot_stats: *BotStats) !void {
    var echo_buffer: [1024]u8 = undefined;
    const echo_message = try std.fmt.bufPrint(&echo_buffer, "🔊 {s}", .{text});
    try sendMessage(bot, chat_id, echo_message, bot_stats);
}

fn sendUnknownCommand(bot: *telegram.Bot, chat_id: i64, command: []const u8, bot_stats: *BotStats) !void {
    var error_buffer: [256]u8 = undefined;
    const error_message = try std.fmt.bufPrint(&error_buffer, "❓ Unknown command: {s}\n\nType /help to see available commands.", .{command});
    try sendMessage(bot, chat_id, error_message, bot_stats);
}

fn sendMessage(bot: *telegram.Bot, chat_id: i64, text: []const u8, bot_stats: *BotStats) !void {
    var reply = telegram.methods.sendMessage(bot, chat_id, text) catch |err| {
        std.debug.print("❌ Failed to send message: {}\n", .{err});
        return;
    };
    defer reply.deinit(bot.allocator);

    bot_stats.recordSent();
    std.debug.print("✅ Sent message to chat {d}\n", .{chat_id});
}

fn showStats(bot_stats: *BotStats) void {
    const uptime = bot_stats.getUptime();
    std.debug.print("\n📊 Quick Stats: {d} messages, {d} callbacks, {d} users, {d}s uptime\n", .{
        bot_stats.messages_received,
        bot_stats.callback_queries_received,
        bot_stats.unique_users.count(),
        uptime,
    });
}

// Utility functions for message analysis
fn countWords(text: []const u8) u32 {
    var count: u32 = 0;
    var in_word = false;

    for (text) |char| {
        if (char == ' ' or char == '\t' or char == '\n') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            count += 1;
        }
    }

    return count;
}

fn containsURL(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "http://") != null or
        std.mem.indexOf(u8, text, "https://") != null or
        std.mem.indexOf(u8, text, "www.") != null;
}

fn containsMention(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "@") != null;
}

fn containsHashtag(text: []const u8) bool {
    return std.mem.indexOf(u8, text, "#") != null;
}

// Inline keyboard demonstration functions
fn showMainKeyboard(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    // Create inline keyboard buttons
    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "📋 Simple Demo"),
        .callback_data = try allocator.dupe(u8, "demo_simple"),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🎛️ Complex Demo"),
        .callback_data = try allocator.dupe(u8, "demo_complex"),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔗 URL Demo"),
        .callback_data = try allocator.dupe(u8, "demo_urls"),
    };

    var row3 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row3[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "⚙️ Settings"),
        .callback_data = try allocator.dupe(u8, "settings"),
    };

    // Create keyboard markup
    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 3);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;
    keyboard_rows[2] = row3;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "🎮 **Inline Keyboard Demo**\n\nChoose an option to see different keyboard types:";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send keyboard message: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
    std.debug.print("✅ Sent main keyboard to chat {d}\n", .{chat_id});
}

fn showSimpleKeyboard(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    // Create simple Yes/No keyboard
    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "✅ Yes"),
        .callback_data = try allocator.dupe(u8, "option_yes"),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "❌ No"),
        .callback_data = try allocator.dupe(u8, "option_no"),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔙 Back"),
        .callback_data = try allocator.dupe(u8, "back_main"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 2);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "📋 **Simple Keyboard Demo**\n\nThis is a basic Yes/No keyboard. Choose an option:";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send simple keyboard: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
    std.debug.print("✅ Sent simple keyboard to chat {d}\n", .{chat_id});
}

fn showComplexKeyboard(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    // Create complex multi-row keyboard
    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 3);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "1️⃣"),
        .callback_data = try allocator.dupe(u8, "option_1"),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "2️⃣"),
        .callback_data = try allocator.dupe(u8, "option_2"),
    };
    row1[2] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "3️⃣"),
        .callback_data = try allocator.dupe(u8, "option_3"),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 3);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "4️⃣"),
        .callback_data = try allocator.dupe(u8, "option_4"),
    };
    row2[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "5️⃣"),
        .callback_data = try allocator.dupe(u8, "option_5"),
    };
    row2[2] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "6️⃣"),
        .callback_data = try allocator.dupe(u8, "option_6"),
    };

    var row3 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row3[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔙 Back to Main"),
        .callback_data = try allocator.dupe(u8, "back_main"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 3);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;
    keyboard_rows[2] = row3;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "🎛️ **Complex Keyboard Demo**\n\nThis keyboard has multiple rows and columns. Pick a number:";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send complex keyboard: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
    std.debug.print("✅ Sent complex keyboard to chat {d}\n", .{chat_id});
}

fn showUrlKeyboard(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    // Create keyboard with URL buttons
    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🐙 GitHub"),
        .url = try allocator.dupe(u8, "https://github.com"),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🦀 Zig Language"),
        .url = try allocator.dupe(u8, "https://ziglang.org"),
    };

    var row3 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row3[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "📋 Callback Demo"),
        .callback_data = try allocator.dupe(u8, "demo_simple"),
    };
    row3[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔙 Back"),
        .callback_data = try allocator.dupe(u8, "back_main"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 3);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;
    keyboard_rows[2] = row3;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "🔗 **URL Keyboard Demo**\n\nThese buttons will open external links or trigger callbacks:";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send URL keyboard: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
    std.debug.print("✅ Sent URL keyboard to chat {d}\n", .{chat_id});
}

fn showSettingsMenu(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    // Create settings menu keyboard
    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔔 Notifications"),
        .callback_data = try allocator.dupe(u8, "setting_notifications"),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🌍 Language"),
        .callback_data = try allocator.dupe(u8, "setting_language"),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🎨 Theme"),
        .callback_data = try allocator.dupe(u8, "setting_theme"),
    };
    row2[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔒 Privacy"),
        .callback_data = try allocator.dupe(u8, "setting_privacy"),
    };

    var row3 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row3[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔙 Back to Main"),
        .callback_data = try allocator.dupe(u8, "back_main"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 3);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;
    keyboard_rows[2] = row3;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "⚙️ **Settings Menu**\n\nChoose a setting category:";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send settings menu: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
    std.debug.print("✅ Sent settings menu to chat {d}\n", .{chat_id});
}

fn showConfirmationKeyboard(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    // Create confirmation keyboard
    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "✅ Confirm"),
        .callback_data = try allocator.dupe(u8, "confirm_action"),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "❌ Cancel"),
        .callback_data = try allocator.dupe(u8, "cancel_action"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 1);
    keyboard_rows[0] = row1;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "⚠️ **Confirmation Required**\n\nAre you sure you want to proceed with this action?";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send confirmation keyboard: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
    std.debug.print("✅ Sent confirmation keyboard to chat {d}\n", .{chat_id});
}

fn showCounterKeyboard(bot: *telegram.Bot, chat_id: i64, current_count: i32, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    // Create counter keyboard
    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 3);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "➖"),
        .callback_data = try std.fmt.allocPrint(allocator, "count_{d}", .{current_count - 1}),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try std.fmt.allocPrint(allocator, "{d}", .{current_count}),
        .callback_data = try allocator.dupe(u8, "count_current"),
    };
    row1[2] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "➕"),
        .callback_data = try std.fmt.allocPrint(allocator, "count_{d}", .{current_count + 1}),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔄 Reset"),
        .callback_data = try allocator.dupe(u8, "count_0"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 2);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    var text_buffer: [128]u8 = undefined;
    const text = try std.fmt.bufPrint(&text_buffer, "🔢 **Interactive Counter**\n\nCurrent value: **{d}**\n\nUse the buttons to change the value:", .{current_count});

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send counter keyboard: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
    std.debug.print("✅ Sent counter keyboard to chat {d}\n", .{chat_id});
}

// Callback handler functions
fn handleOptionSelection(bot: *telegram.Bot, chat_id: i64, option: []const u8, bot_stats: *BotStats) !void {
    var response_buffer: [256]u8 = undefined;
    const response = try std.fmt.bufPrint(&response_buffer, "🎯 You selected option: **{s}**\n\nGreat choice!", .{option});
    try sendMessage(bot, chat_id, response, bot_stats);
}

fn handleConfirmation(bot: *telegram.Bot, chat_id: i64, user_id: i64, confirmed: bool, bot_state: *BotState, bot_stats: *BotStats) !void {
    bot_state.clearState(user_id);

    const response = if (confirmed)
        "✅ **Action Confirmed!**\n\nYour action has been successfully processed."
    else
        "❌ **Action Cancelled**\n\nNo changes have been made.";

    try sendMessage(bot, chat_id, response, bot_stats);
}

fn handleCounterButton(bot: *telegram.Bot, chat_id: i64, count_str: []const u8, bot_stats: *BotStats) !void {
    if (std.mem.eql(u8, count_str, "current")) {
        try sendMessage(bot, chat_id, "ℹ️ This is the current count value.", bot_stats);
        return;
    }

    const new_count = std.fmt.parseInt(i32, count_str, 10) catch {
        try sendMessage(bot, chat_id, "❌ Invalid count value", bot_stats);
        return;
    };

    try showCounterKeyboard(bot, chat_id, new_count, bot_stats);
}
