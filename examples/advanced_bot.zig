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
    } else if (std.mem.startsWith(u8, callback_data, "media_")) {
        const media_type = callback_data[6..];
        try handleMediaCallback(bot, callback_query.message.?.chat.id, media_type, bot_stats);
    } else if (std.mem.startsWith(u8, callback_data, "admin_")) {
        const admin_action = callback_data[6..];
        try handleAdminCallback(bot, callback_query.message.?.chat.id, admin_action, bot_stats);
    } else if (std.mem.eql(u8, callback_data, "back_admin")) {
        try showAdminMenu(bot, callback_query.message.?.chat.id, bot_stats);
    } else if (std.mem.startsWith(u8, callback_data, "danger_")) {
        const danger_action = callback_data[7..];
        try handleDangerCallback(bot, callback_query.message.?.chat.id, danger_action, bot_stats);
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
    } else if (std.mem.eql(u8, text, "/media")) {
        try showMediaMenu(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/admin")) {
        try showAdminMenu(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/test_all")) {
        try runAPITests(bot, message, bot_stats);
    } else if (std.mem.eql(u8, text, "/location")) {
        try sendTestLocation(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/contact")) {
        try sendTestContact(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/poll")) {
        try sendTestPoll(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/dice")) {
        try sendTestDice(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/typing")) {
        try testChatActions(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/chat_info")) {
        try getChatInfo(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/commands_test")) {
        try testBotCommands(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/webhook_info")) {
        try getWebhookStatus(bot, chat_id, bot_stats);
    } else if (std.mem.startsWith(u8, text, "/forward ")) {
        const args = text[9..];
        try testForwardMessage(bot, message, args, bot_stats);
    } else if (std.mem.startsWith(u8, text, "/copy ")) {
        const args = text[6..];
        try testCopyMessage(bot, message, args, bot_stats);
    } else if (std.mem.eql(u8, text, "/edit_test")) {
        try testEditMessage(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, text, "/pin_test")) {
        try testPinMessage(bot, chat_id, bot_stats);
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
        \\📚 **Available Commands:**
        \\
        \\🔧 **Basic Commands:**
        \\/start - Welcome message
        \\/help - Show this help
        \\/info - Show chat information
        \\/ping - Test bot responsiveness
        \\/time - Get current time
        \\
        \\🎮 **Interactive Commands:**
        \\/echo - Start interactive echo mode
        \\/echo <text> - Echo specific text
        \\/cancel - Cancel current action
        \\
        \\⌨️ **Inline Keyboard Commands:**
        \\/keyboard - Show main keyboard demo
        \\/confirm - Show confirmation dialog
        \\/counter - Interactive counter
        \\
        \\📊 **Information & Stats:**
        \\/stats - Show bot statistics
        \\/chat_info - Get current chat information
        \\/webhook_info - Show webhook status
        \\
        \\📱 **Media Commands:**
        \\/media - Show media menu
        \\/location - Send test location
        \\/contact - Send test contact
        \\/poll - Send test poll
        \\/dice - Send dice (random emoji)
        \\
        \\👑 **Admin Commands:**
        \\/admin - Show admin menu (be careful!)
        \\/pin_test - Test message pinning
        \\
        \\🔧 **API Testing:**
        \\/test_all - Run comprehensive API tests
        \\/typing - Test chat actions (typing indicators)
        \\/commands_test - Test bot command management
        \\/edit_test - Test message editing
        \\/forward <msg_id> - Forward a message
        \\/copy <msg_id> - Copy a message
        \\
        \\💡 **Tips:**
        \\• Send any text for message analysis
        \\• Try the interactive keyboards!
        \\• The bot tracks usage statistics
        \\• All operations use proper memory management
        \\• State is maintained per user
        \\• New: 42 API methods implemented!
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

// ===== NEW API TESTING FUNCTIONS =====

fn showMediaMenu(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    // Create media menu keyboard
    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "📷 Photo Test"),
        .callback_data = try allocator.dupe(u8, "media_photo"),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🎵 Audio Test"),
        .callback_data = try allocator.dupe(u8, "media_audio"),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "📄 Document Test"),
        .callback_data = try allocator.dupe(u8, "media_document"),
    };
    row2[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🎬 Video Test"),
        .callback_data = try allocator.dupe(u8, "media_video"),
    };

    var row3 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row3[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🎭 Animation Test"),
        .callback_data = try allocator.dupe(u8, "media_animation"),
    };
    row3[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🎤 Voice Test"),
        .callback_data = try allocator.dupe(u8, "media_voice"),
    };

    var row4 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row4[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "📹 Video Note"),
        .callback_data = try allocator.dupe(u8, "media_videonote"),
    };
    row4[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🎯 Sticker"),
        .callback_data = try allocator.dupe(u8, "media_sticker"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 4);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;
    keyboard_rows[2] = row3;
    keyboard_rows[3] = row4;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "📱 **Media Testing Menu**\n\nChoose a media type to test (using sample URLs/file_ids):";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send media menu: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
}

fn showAdminMenu(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "👥 Chat Info"),
        .callback_data = try allocator.dupe(u8, "admin_chatinfo"),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "📊 Member Count"),
        .callback_data = try allocator.dupe(u8, "admin_membercount"),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "📌 Pin Test"),
        .callback_data = try allocator.dupe(u8, "admin_pin"),
    };
    row2[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "📌 Unpin All"),
        .callback_data = try allocator.dupe(u8, "admin_unpin_all"),
    };

    var row3 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row3[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔗 Export Invite Link"),
        .callback_data = try allocator.dupe(u8, "admin_invite"),
    };

    var row4 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row4[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "⚠️ Danger Zone"),
        .callback_data = try allocator.dupe(u8, "admin_danger"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 4);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;
    keyboard_rows[2] = row3;
    keyboard_rows[3] = row4;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "👑 **Admin Menu**\n\n⚠️ **Warning:** Some operations may affect the chat!\nUse with caution in group chats.";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send admin menu: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
}

fn runAPITests(bot: *telegram.Bot, message: telegram.Message, bot_stats: *BotStats) !void {
    const chat_id = message.chat.id;

    var test_buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&test_buffer);
    const writer = fbs.writer();

    try writer.print("🔧 **Comprehensive API Test Report**\n\n", .{});

    // Test getMe
    const me = telegram.methods.getMe(bot) catch |err| {
        try writer.print("❌ getMe: {}\n", .{err});
        const error_text = fbs.getWritten();
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer {
        var user_copy = me;
        user_copy.deinit(bot.allocator);
    }
    try writer.print("✅ getMe: @{s}\n", .{me.username orelse me.first_name});

    // Test chat info
    const chat_info = telegram.methods.getChat(bot, chat_id) catch |err| {
        try writer.print("❌ getChat: {}\n", .{err});
        const error_text = fbs.getWritten();
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer {
        var chat_copy = chat_info;
        chat_copy.deinit(bot.allocator);
    }
    try writer.print("✅ getChat: {s}\n", .{chat_info.type});

    // Test member count (only for groups)
    if (std.mem.eql(u8, chat_info.type, "group") or std.mem.eql(u8, chat_info.type, "supergroup")) {
        const member_count = telegram.methods.getChatMemberCount(bot, chat_id) catch |err| {
            try writer.print("❌ getChatMemberCount: {}\n", .{err});
            const error_text = fbs.getWritten();
            try sendMessage(bot, chat_id, error_text, bot_stats);
            return;
        };
        try writer.print("✅ getChatMemberCount: {d} members\n", .{member_count});
    } else {
        try writer.print("⚠️  getChatMemberCount: Skipped (private chat)\n", .{});
    }

    // Test webhook info
    const webhook_info = telegram.methods.getWebhookInfo(bot) catch |err| {
        try writer.print("❌ getWebhookInfo: {}\n", .{err});
        const error_text = fbs.getWritten();
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer {
        var webhook_copy = webhook_info;
        webhook_copy.deinit(bot.allocator);
    }
    if (webhook_info.url.len > 0) {
        try writer.print("✅ getWebhookInfo: {s}\n", .{webhook_info.url});
    } else {
        try writer.print("✅ getWebhookInfo: No webhook set (polling mode)\n", .{});
    }

    // Test bot commands
    const commands = telegram.methods.getMyCommands(bot) catch |err| {
        try writer.print("❌ getMyCommands: {}\n", .{err});
        const error_text = fbs.getWritten();
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer {
        for (commands) |*cmd| {
            cmd.deinit(bot.allocator);
        }
        bot.allocator.free(commands);
    }
    try writer.print("✅ getMyCommands: {d} commands\n", .{commands.len});

    try writer.print("\n🎯 **Summary:** Core API methods working!\n", .{});
    try writer.print("📝 Try specific tests: /media, /admin, /typing, /location\n", .{});

    const test_result = fbs.getWritten();
    try sendMessage(bot, chat_id, test_result, bot_stats);
}

fn sendTestLocation(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    // Send location of Zig Software Foundation (approximate)
    const latitude: f64 = 40.7589; // New York latitude
    const longitude: f64 = -73.9851; // New York longitude

    var location_message = telegram.methods.sendLocation(bot, chat_id, latitude, longitude) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to send location: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer location_message.deinit(bot.allocator);

    bot_stats.recordSent();
    try sendMessage(bot, chat_id, "📍 Test location sent! (New York coordinates)", bot_stats);
}

fn sendTestContact(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    var contact_message = telegram.methods.sendContact(bot, chat_id, "+1234567890", "Test Bot") catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to send contact: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer contact_message.deinit(bot.allocator);

    bot_stats.recordSent();
    try sendMessage(bot, chat_id, "📞 Test contact sent!", bot_stats);
}

fn sendTestPoll(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const question = "What's your favorite programming language?";
    var options = [_][]const u8{ "Zig", "Rust", "Go", "Python", "JavaScript" };

    var poll_message = telegram.methods.sendPoll(bot, chat_id, question, options[0..]) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to send poll: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer poll_message.deinit(bot.allocator);

    bot_stats.recordSent();
    try sendMessage(bot, chat_id, "📊 Test poll sent! Vote above!", bot_stats);
}

fn sendTestDice(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const dice_emojis = [_][]const u8{ "🎲", "🎯", "🏀", "⚽", "🎳", "🎰" };
    const random_emoji = dice_emojis[@as(usize, @intCast(std.time.timestamp())) % dice_emojis.len];

    var dice_message = telegram.methods.sendDice(bot, chat_id, random_emoji) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to send dice: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer dice_message.deinit(bot.allocator);

    bot_stats.recordSent();
    var dice_buffer: [64]u8 = undefined;
    const dice_text = try std.fmt.bufPrint(&dice_buffer, "🎲 Dice sent! Emoji: {s}", .{random_emoji});
    try sendMessage(bot, chat_id, dice_text, bot_stats);
}

fn testChatActions(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const actions = [_][]const u8{ "typing", "upload_photo", "record_video", "upload_document", "choose_sticker" };

    try sendMessage(bot, chat_id, "⌨️ Testing chat actions...", bot_stats);

    for (actions) |action| {
        _ = telegram.methods.sendChatAction(bot, chat_id, action) catch |err| {
            var error_buffer: [128]u8 = undefined;
            const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed action {s}: {}", .{ action, err });
            try sendMessage(bot, chat_id, error_text, bot_stats);
            continue;
        };

        var action_buffer: [64]u8 = undefined;
        const action_text = try std.fmt.bufPrint(&action_buffer, "✅ {s}", .{action});
        try sendMessage(bot, chat_id, action_text, bot_stats);

        std.time.sleep(2 * std.time.ns_per_s);
    }

    try sendMessage(bot, chat_id, "🎯 Chat actions test completed!", bot_stats);
}

fn getChatInfo(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const chat_info = telegram.methods.getChat(bot, chat_id) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to get chat info: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer {
        var chat_copy = chat_info;
        chat_copy.deinit(bot.allocator);
    }

    var info_buffer: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&info_buffer);
    const writer = fbs.writer();

    try writer.print("💬 **Extended Chat Information:**\n\n", .{});
    try writer.print("🆔 ID: {d}\n", .{chat_info.id});
    try writer.print("📁 Type: {s}\n", .{chat_info.type});

    if (chat_info.title) |title| {
        try writer.print("📝 Title: {s}\n", .{title});
    }
    if (chat_info.username) |username| {
        try writer.print("👤 Username: @{s}\n", .{username});
    }
    if (chat_info.first_name) |first_name| {
        try writer.print("👤 First Name: {s}\n", .{first_name});
    }
    if (chat_info.last_name) |last_name| {
        try writer.print("👤 Last Name: {s}\n", .{last_name});
    }

    // Get member count for groups
    if (std.mem.eql(u8, chat_info.type, "group") or std.mem.eql(u8, chat_info.type, "supergroup")) {
        const member_count = telegram.methods.getChatMemberCount(bot, chat_id) catch |err| {
            try writer.print("❌ Member count error: {}\n", .{err});
            const info_text = fbs.getWritten();
            try sendMessage(bot, chat_id, info_text, bot_stats);
            return;
        };
        try writer.print("👥 Members: {d}\n", .{member_count});
    }

    const info_text = fbs.getWritten();
    try sendMessage(bot, chat_id, info_text, bot_stats);
}

fn testBotCommands(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    try sendMessage(bot, chat_id, "🔧 Testing bot command management...", bot_stats);

    // Create test commands
    const test_commands = [_]telegram.BotCommand{
        telegram.BotCommand{
            .command = "start",
            .description = "Start the bot",
        },
        telegram.BotCommand{
            .command = "help",
            .description = "Show help message",
        },
        telegram.BotCommand{
            .command = "test",
            .description = "Run tests",
        },
    };

    // Set commands
    const set_result = telegram.methods.setMyCommands(bot, &test_commands) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to set commands: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };

    if (set_result) {
        try sendMessage(bot, chat_id, "✅ Test commands set successfully!", bot_stats);
    } else {
        try sendMessage(bot, chat_id, "❌ Failed to set commands", bot_stats);
        return;
    }

    // Get commands to verify
    const commands = telegram.methods.getMyCommands(bot) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to get commands: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer {
        for (commands) |*cmd| {
            cmd.deinit(bot.allocator);
        }
        bot.allocator.free(commands);
    }

    var cmd_buffer: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&cmd_buffer);
    const writer = fbs.writer();

    try writer.print("📋 **Current Bot Commands ({d}):**\n\n", .{commands.len});
    for (commands) |cmd| {
        try writer.print("/{s} - {s}\n", .{ cmd.command, cmd.description });
    }

    const cmd_text = fbs.getWritten();
    try sendMessage(bot, chat_id, cmd_text, bot_stats);
}

fn getWebhookStatus(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const webhook_info = telegram.methods.getWebhookInfo(bot) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to get webhook info: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer {
        var webhook_copy = webhook_info;
        webhook_copy.deinit(bot.allocator);
    }

    var info_buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&info_buffer);
    const writer = fbs.writer();

    try writer.print("🔗 **Webhook Information:**\n\n", .{});

    if (webhook_info.url.len > 0) {
        try writer.print("📍 URL: {s}\n", .{webhook_info.url});
        try writer.print("🔐 Custom Certificate: {}\n", .{webhook_info.has_custom_certificate});
        try writer.print("📊 Pending Updates: {d}\n", .{webhook_info.pending_update_count});

        if (webhook_info.ip_address) |ip| {
            try writer.print("🌐 IP Address: {s}\n", .{ip});
        }
        if (webhook_info.last_error_message) |error_msg| {
            try writer.print("❌ Last Error: {s}\n", .{error_msg});
        }
        if (webhook_info.max_connections) |max_conn| {
            try writer.print("🔗 Max Connections: {d}\n", .{max_conn});
        }
    } else {
        try writer.print("📊 Status: **No webhook set (using polling)**\n", .{});
        try writer.print("📈 Pending Updates: {d}\n", .{webhook_info.pending_update_count});
    }

    const info_text = fbs.getWritten();
    try sendMessage(bot, chat_id, info_text, bot_stats);
}

fn testForwardMessage(bot: *telegram.Bot, message: telegram.Message, args: []const u8, bot_stats: *BotStats) !void {
    const chat_id = message.chat.id;

    const message_id = std.fmt.parseInt(i32, args, 10) catch {
        try sendMessage(bot, chat_id, "❌ Invalid message ID. Usage: /forward <message_id>", bot_stats);
        return;
    };

    var forwarded = telegram.methods.forwardMessage(bot, chat_id, chat_id, message_id) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to forward message: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer forwarded.deinit(bot.allocator);

    bot_stats.recordSent();
    try sendMessage(bot, chat_id, "✅ Message forwarded successfully!", bot_stats);
}

fn testCopyMessage(bot: *telegram.Bot, message: telegram.Message, args: []const u8, bot_stats: *BotStats) !void {
    const chat_id = message.chat.id;

    const message_id = std.fmt.parseInt(i32, args, 10) catch {
        try sendMessage(bot, chat_id, "❌ Invalid message ID. Usage: /copy <message_id>", bot_stats);
        return;
    };

    const new_message_id = telegram.methods.copyMessage(bot, chat_id, chat_id, message_id) catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to copy message: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };

    var copy_buffer: [128]u8 = undefined;
    const copy_text = try std.fmt.bufPrint(&copy_buffer, "✅ Message copied! New message ID: {d}", .{new_message_id});
    try sendMessage(bot, chat_id, copy_text, bot_stats);
}

fn testEditMessage(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    // Send a message first
    var original = telegram.methods.sendMessage(bot, chat_id, "🔄 This message will be edited in 3 seconds...") catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to send message: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer original.deinit(bot.allocator);

    bot_stats.recordSent();

    // Wait 3 seconds
    std.time.sleep(3 * std.time.ns_per_s);

    // Edit the message
    var edited = telegram.methods.editMessageText(bot, chat_id, original.message_id, "✅ Message successfully edited! Edit functionality working.") catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to edit message: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer edited.deinit(bot.allocator);

    bot_stats.recordSent();
}

fn testPinMessage(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    // Send a message to pin
    var message_to_pin = telegram.methods.sendMessage(bot, chat_id, "📌 This message will be pinned (if I have admin rights)") catch |err| {
        var error_buffer: [128]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to send message: {}", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };
    defer message_to_pin.deinit(bot.allocator);

    bot_stats.recordSent();

    // Try to pin it
    const pin_result = telegram.methods.pinChatMessage(bot, chat_id, message_to_pin.message_id) catch |err| {
        var error_buffer: [256]u8 = undefined;
        const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to pin message: {}\n(Note: Bot needs admin rights to pin messages)", .{err});
        try sendMessage(bot, chat_id, error_text, bot_stats);
        return;
    };

    if (pin_result) {
        try sendMessage(bot, chat_id, "✅ Message pinned successfully!", bot_stats);

        // Wait and then unpin
        std.time.sleep(3 * std.time.ns_per_s);

        const unpin_result = telegram.methods.unpinChatMessage(bot, chat_id, message_to_pin.message_id) catch |err| {
            var error_buffer: [128]u8 = undefined;
            const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to unpin message: {}", .{err});
            try sendMessage(bot, chat_id, error_text, bot_stats);
            return;
        };

        if (unpin_result) {
            try sendMessage(bot, chat_id, "✅ Message unpinned successfully!", bot_stats);
        }
    } else {
        try sendMessage(bot, chat_id, "❌ Failed to pin message (insufficient permissions)", bot_stats);
    }
}

// ===== CALLBACK HANDLERS FOR NEW MENUS =====

fn handleMediaCallback(bot: *telegram.Bot, chat_id: i64, media_type: []const u8, bot_stats: *BotStats) !void {
    if (std.mem.eql(u8, media_type, "photo")) {
        // Use a sample photo URL for testing
        var photo_message = telegram.methods.sendPhoto(bot, chat_id, "https://picsum.photos/400/300", "📷 Test photo from Lorem Picsum") catch |err| {
            var error_buffer: [128]u8 = undefined;
            const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to send photo: {}", .{err});
            try sendMessage(bot, chat_id, error_text, bot_stats);
            return;
        };
        defer photo_message.deinit(bot.allocator);
        bot_stats.recordSent();
    } else if (std.mem.eql(u8, media_type, "audio")) {
        try sendMessage(bot, chat_id, "🎵 Audio test: Use file_id or URL for actual audio files", bot_stats);
    } else if (std.mem.eql(u8, media_type, "document")) {
        try sendMessage(bot, chat_id, "📄 Document test: Use file_id or URL for actual documents", bot_stats);
    } else if (std.mem.eql(u8, media_type, "video")) {
        try sendMessage(bot, chat_id, "🎬 Video test: Use file_id or URL for actual video files", bot_stats);
    } else if (std.mem.eql(u8, media_type, "animation")) {
        try sendMessage(bot, chat_id, "🎭 Animation test: Use file_id or URL for actual GIF/MP4 animations", bot_stats);
    } else if (std.mem.eql(u8, media_type, "voice")) {
        try sendMessage(bot, chat_id, "🎤 Voice test: Use file_id for actual voice messages", bot_stats);
    } else if (std.mem.eql(u8, media_type, "videonote")) {
        try sendMessage(bot, chat_id, "📹 Video note test: Use file_id for actual video notes", bot_stats);
    } else if (std.mem.eql(u8, media_type, "sticker")) {
        try sendMessage(bot, chat_id, "🎯 Sticker test: Use file_id for actual stickers", bot_stats);
    } else {
        var response_buffer: [128]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buffer, "❓ Unknown media type: {s}", .{media_type});
        try sendMessage(bot, chat_id, response, bot_stats);
    }
}

fn handleAdminCallback(bot: *telegram.Bot, chat_id: i64, admin_action: []const u8, bot_stats: *BotStats) !void {
    if (std.mem.eql(u8, admin_action, "chatinfo")) {
        try getChatInfo(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, admin_action, "membercount")) {
        const member_count = telegram.methods.getChatMemberCount(bot, chat_id) catch |err| {
            var error_buffer: [128]u8 = undefined;
            const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to get member count: {}", .{err});
            try sendMessage(bot, chat_id, error_text, bot_stats);
            return;
        };

        var count_buffer: [64]u8 = undefined;
        const count_text = try std.fmt.bufPrint(&count_buffer, "👥 Chat has {d} members", .{member_count});
        try sendMessage(bot, chat_id, count_text, bot_stats);
    } else if (std.mem.eql(u8, admin_action, "pin")) {
        try testPinMessage(bot, chat_id, bot_stats);
    } else if (std.mem.eql(u8, admin_action, "unpin_all")) {
        const unpin_result = telegram.methods.unpinAllChatMessages(bot, chat_id) catch |err| {
            var error_buffer: [256]u8 = undefined;
            const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to unpin all messages: {}\n(Note: Bot needs admin rights)", .{err});
            try sendMessage(bot, chat_id, error_text, bot_stats);
            return;
        };

        if (unpin_result) {
            try sendMessage(bot, chat_id, "✅ All messages unpinned successfully!", bot_stats);
        } else {
            try sendMessage(bot, chat_id, "❌ Failed to unpin messages (insufficient permissions)", bot_stats);
        }
    } else if (std.mem.eql(u8, admin_action, "invite")) {
        const invite_link = telegram.methods.exportChatInviteLink(bot, chat_id) catch |err| {
            var error_buffer: [256]u8 = undefined;
            const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to export invite link: {}\n(Note: Bot needs admin rights)", .{err});
            try sendMessage(bot, chat_id, error_text, bot_stats);
            return;
        };
        try sendMessage(bot, chat_id, invite_link, bot_stats);
    } else if (std.mem.eql(u8, admin_action, "danger")) {
        try showDangerZone(bot, chat_id, bot_stats);
    } else {
        var response_buffer: [128]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buffer, "❓ Unknown admin action: {s}", .{admin_action});
        try sendMessage(bot, chat_id, response, bot_stats);
    }
}

fn showDangerZone(bot: *telegram.Bot, chat_id: i64, bot_stats: *BotStats) !void {
    const allocator = bot.allocator;

    var row1 = try allocator.alloc(telegram.InlineKeyboardButton, 2);
    row1[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🚪 Leave Chat"),
        .callback_data = try allocator.dupe(u8, "danger_leave"),
    };
    row1[1] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔄 Log Out Bot"),
        .callback_data = try allocator.dupe(u8, "danger_logout"),
    };

    var row2 = try allocator.alloc(telegram.InlineKeyboardButton, 1);
    row2[0] = telegram.InlineKeyboardButton{
        .text = try allocator.dupe(u8, "🔙 Back to Admin"),
        .callback_data = try allocator.dupe(u8, "back_admin"),
    };

    var keyboard_rows = try allocator.alloc([]telegram.InlineKeyboardButton, 2);
    keyboard_rows[0] = row1;
    keyboard_rows[1] = row2;

    var keyboard = telegram.InlineKeyboardMarkup{
        .inline_keyboard = keyboard_rows,
    };
    defer keyboard.deinit(allocator);

    const text = "⚠️ **DANGER ZONE** ⚠️\n\n🚨 **WARNING:** These actions are irreversible!\n\n• Leave Chat: Bot will leave this chat\n• Log Out: Bot will log out completely\n\nUse with extreme caution!";

    var reply = telegram.methods.sendMessageWithKeyboard(bot, chat_id, text, keyboard) catch |err| {
        std.debug.print("❌ Failed to send danger zone menu: {}\n", .{err});
        return;
    };
    defer reply.deinit(allocator);

    bot_stats.recordSent();
}

fn handleDangerCallback(bot: *telegram.Bot, chat_id: i64, danger_action: []const u8, bot_stats: *BotStats) !void {
    if (std.mem.eql(u8, danger_action, "leave")) {
        const leave_result = telegram.methods.leaveChat(bot, chat_id) catch |err| {
            var error_buffer: [256]u8 = undefined;
            const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to leave chat: {}\n(Note: This might not work in private chats)", .{err});
            try sendMessage(bot, chat_id, error_text, bot_stats);
            return;
        };

        if (leave_result) {
            try sendMessage(bot, chat_id, "👋 Bot is leaving this chat. Goodbye!", bot_stats);
        } else {
            try sendMessage(bot, chat_id, "❌ Failed to leave chat", bot_stats);
        }
    } else if (std.mem.eql(u8, danger_action, "logout")) {
        try sendMessage(bot, chat_id, "🔄 Bot is logging out... This will disconnect the bot from Telegram servers.", bot_stats);

        const logout_result = telegram.methods.logOut(bot) catch |err| {
            var error_buffer: [128]u8 = undefined;
            const error_text = try std.fmt.bufPrint(&error_buffer, "❌ Failed to log out: {}", .{err});
            try sendMessage(bot, chat_id, error_text, bot_stats);
            return;
        };

        if (logout_result) {
            std.debug.print("🔄 Bot logged out successfully\n", .{});
            std.process.exit(0);
        } else {
            try sendMessage(bot, chat_id, "❌ Failed to log out", bot_stats);
        }
    } else {
        var response_buffer: [128]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buffer, "❓ Unknown danger action: {s}", .{danger_action});
        try sendMessage(bot, chat_id, response, bot_stats);
    }
}
