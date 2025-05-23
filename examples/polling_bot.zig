const std = @import("std");
const telegram = @import("telegram");

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

    std.debug.print("🤖 Starting polling bot...\n", .{});
    std.debug.print("Send messages to your bot to see them appear here!\n", .{});
    std.debug.print("Press Ctrl+C to stop.\n\n", .{});

    // Get bot info to display
    const me = telegram.methods.getMe(&bot) catch |err| {
        std.debug.print("❌ Failed to get bot info: {}\n", .{err});
        return;
    };
    defer {
        var user_copy = me;
        user_copy.deinit(allocator);
    }

    std.debug.print("✅ Bot @{s} is online!\n", .{me.username orelse me.first_name});

    // Delete webhook to ensure we're using polling
    _ = telegram.methods.deleteWebhook(&bot) catch |err| {
        std.debug.print("⚠️  Warning: Failed to delete webhook: {}\n", .{err});
    };

    var offset: i32 = 0;
    const limit: i32 = 100;
    const timeout: i32 = 30; // 30 seconds long polling

    while (true) {
        std.debug.print("📡 Polling for updates (offset: {d})...\n", .{offset});

        // Get updates
        const updates = telegram.methods.getUpdates(&bot, offset, limit, timeout) catch |err| {
            std.debug.print("❌ Failed to get updates: {}\n", .{err});
            // Wait a bit before retrying
            std.time.sleep(5 * std.time.ns_per_s);
            continue;
        };
        defer {
            for (updates) |*update| {
                update.deinit(allocator);
            }
            allocator.free(updates);
        }

        if (updates.len > 0) {
            std.debug.print("📨 Received {d} update(s)\n", .{updates.len});
        }

        // Process each update
        for (updates) |update| {
            std.debug.print("\n🔄 Processing update {d}\n", .{update.update_id});

            // Update offset to acknowledge this update
            offset = update.update_id + 1;

            // Handle different types of updates
            if (update.message) |message| {
                try handleMessage(&bot, message, "message");
            } else if (update.edited_message) |message| {
                try handleMessage(&bot, message, "edited_message");
            } else if (update.channel_post) |message| {
                try handleMessage(&bot, message, "channel_post");
            } else if (update.edited_channel_post) |message| {
                try handleMessage(&bot, message, "edited_channel_post");
            } else if (update.business_message) |message| {
                try handleMessage(&bot, message, "business_message");
            } else if (update.edited_business_message) |message| {
                try handleMessage(&bot, message, "edited_business_message");
            } else if (update.inline_query) |_| {
                std.debug.print("📝 Received inline query (not implemented)\n", .{});
            } else if (update.callback_query) |_| {
                std.debug.print("🔘 Received callback query (not implemented)\n", .{});
            } else {
                std.debug.print("❓ Received unknown update type\n", .{});
            }
        }

        // If no updates, add a small delay
        if (updates.len == 0) {
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }
}

fn handleMessage(bot: *telegram.Bot, message: telegram.Message, update_type: []const u8) !void {
    std.debug.print("💬 {s}:\n", .{update_type});
    std.debug.print("   Message ID: {d}\n", .{message.message_id});
    std.debug.print("   Date: {d}\n", .{message.date});
    std.debug.print("   Chat ID: {d} (type: {s})\n", .{ message.chat.id, message.chat.type });

    // Display chat information
    if (message.chat.title) |title| {
        std.debug.print("   Chat Title: {s}\n", .{title});
    }
    if (message.chat.username) |username| {
        std.debug.print("   Chat Username: @{s}\n", .{username});
    }
    if (message.chat.first_name) |first_name| {
        std.debug.print("   Chat First Name: {s}\n", .{first_name});
    }

    // Display sender information
    if (message.from) |from| {
        std.debug.print("   From: {s}", .{from.first_name});
        if (from.last_name) |last_name| {
            std.debug.print(" {s}", .{last_name});
        }
        if (from.username) |username| {
            std.debug.print(" (@{s})", .{username});
        }
        std.debug.print(" [ID: {d}]\n", .{from.id});
        if (from.is_bot) {
            std.debug.print("   ↳ This is a bot\n", .{});
        }
        if (from.language_code) |lang| {
            std.debug.print("   ↳ Language: {s}\n", .{lang});
        }
    }

    // Display message content
    if (message.text) |text| {
        std.debug.print("   Text: \"{s}\"\n", .{text});

        // Handle specific commands
        if (std.mem.eql(u8, text, "/start")) {
            try sendWelcomeMessage(bot, message.chat.id);
        } else if (std.mem.eql(u8, text, "/help")) {
            try sendHelpMessage(bot, message.chat.id);
        } else if (std.mem.eql(u8, text, "/info")) {
            try sendChatInfo(bot, message);
        } else if (std.mem.startsWith(u8, text, "/echo ")) {
            const echo_text = text[6..]; // Remove "/echo "
            _ = telegram.methods.sendMessage(bot, message.chat.id, echo_text) catch |err| {
                std.debug.print("   ❌ Failed to send echo: {}\n", .{err});
            };
        }
    }

    // Display message entities (formatting, links, etc.)
    if (message.entities) |entities| {
        if (entities.len > 0) {
            std.debug.print("   Entities:\n", .{});
            for (entities) |entity| {
                std.debug.print("     - {s} (offset: {d}, length: {d})\n", .{ entity.type, entity.offset, entity.length });
                if (entity.url) |url| {
                    std.debug.print("       URL: {s}\n", .{url});
                }
                if (entity.user) |user| {
                    std.debug.print("       User: {s} [ID: {d}]\n", .{ user.first_name, user.id });
                }
            }
        }
    }
}

fn sendWelcomeMessage(bot: *telegram.Bot, chat_id: i64) !void {
    const welcome_text =
        \\🤖 Welcome to the Polling Bot!
        \\
        \\Available commands:
        \\/start - Show this welcome message
        \\/help - Show help information
        \\/info - Show chat information
        \\/echo <text> - Echo your message
        \\
        \\Send me any message and I'll show you detailed information about it!
    ;

    var reply = telegram.methods.sendMessage(bot, chat_id, welcome_text) catch |err| {
        std.debug.print("   ❌ Failed to send welcome message: {}\n", .{err});
        return;
    };
    defer reply.deinit(bot.allocator);
    std.debug.print("   ✅ Sent welcome message\n", .{});
}

fn sendHelpMessage(bot: *telegram.Bot, chat_id: i64) !void {
    const help_text =
        \\📚 Help Information:
        \\
        \\This bot demonstrates the zigtgshka Telegram library capabilities:
        \\
        \\🔍 Message Analysis:
        \\- Shows message ID, date, and chat information
        \\- Displays sender details (name, username, language)
        \\- Analyzes message entities (links, mentions, formatting)
        \\
        \\⚙️ Technical Details:
        \\- Uses long polling (30-second timeout)
        \\- Handles different update types
        \\- Processes text messages and commands
        \\- Demonstrates proper memory management
        \\
        \\💡 Try sending different types of content:
        \\- Plain text messages
        \\- Messages with @mentions
        \\- Messages with URLs
        \\- Formatted text (bold, italic)
    ;

    var reply = telegram.methods.sendMessage(bot, chat_id, help_text) catch |err| {
        std.debug.print("   ❌ Failed to send help message: {}\n", .{err});
        return;
    };
    defer reply.deinit(bot.allocator);
    std.debug.print("   ✅ Sent help message\n", .{});
}

fn sendChatInfo(bot: *telegram.Bot, message: telegram.Message) !void {
    var info_buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&info_buffer);
    const writer = fbs.writer();

    try writer.print("💬 Chat Information:\n\n", .{});
    try writer.print("🆔 Chat ID: {d}\n", .{message.chat.id});
    try writer.print("📁 Type: {s}\n", .{message.chat.type});

    if (message.chat.title) |title| {
        try writer.print("📝 Title: {s}\n", .{title});
    }
    if (message.chat.username) |username| {
        try writer.print("👤 Username: @{s}\n", .{username});
    }
    if (message.chat.first_name) |first_name| {
        try writer.print("👤 First Name: {s}\n", .{first_name});
    }
    if (message.chat.last_name) |last_name| {
        try writer.print("👤 Last Name: {s}\n", .{last_name});
    }

    if (message.from) |from| {
        try writer.print("\n👤 Message From:\n", .{});
        try writer.print("🆔 User ID: {d}\n", .{from.id});
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

    const info_text = fbs.getWritten();
    var reply = telegram.methods.sendMessage(bot, message.chat.id, info_text) catch |err| {
        std.debug.print("   ❌ Failed to send chat info: {}\n", .{err});
        return;
    };
    defer reply.deinit(bot.allocator);
    std.debug.print("   ✅ Sent chat info\n", .{});
}
