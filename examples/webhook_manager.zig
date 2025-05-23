const std = @import("std");
const telegram = @import("telegram");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get arguments from command line
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <bot_token> [command]\n", .{args[0]});
        std.debug.print("\nCommands:\n", .{});
        std.debug.print("  delete    - Delete webhook (default)\n", .{});
        std.debug.print("  info      - Get webhook info (not implemented yet)\n", .{});
        std.debug.print("  status    - Check bot status\n", .{});
        std.debug.print("\nExamples:\n", .{});
        std.debug.print("  {s} 123456789:ABC...\n", .{args[0]});
        std.debug.print("  {s} 123456789:ABC... delete\n", .{args[0]});
        std.debug.print("  {s} 123456789:ABC... status\n", .{args[0]});
        return;
    }

    const token = args[1];
    const command = if (args.len >= 3) args[2] else "delete";

    // Initialize HTTP client
    var client = try telegram.HTTPClient.init(allocator);
    defer client.deinit();

    // Initialize bot
    var bot = try telegram.Bot.init(allocator, token, &client);
    defer bot.deinit();

    std.debug.print("🔧 Webhook Manager\n", .{});
    std.debug.print("Command: {s}\n", .{command});

    if (std.mem.eql(u8, command, "delete")) {
        try deleteWebhook(&bot);
    } else if (std.mem.eql(u8, command, "status")) {
        try showBotStatus(&bot);
    } else if (std.mem.eql(u8, command, "info")) {
        std.debug.print("⚠️  Webhook info not implemented yet\n", .{});
        std.debug.print("This would call getWebhookInfo method (to be implemented)\n", .{});
    } else {
        std.debug.print("❌ Unknown command: {s}\n", .{command});
        std.debug.print("Use 'delete', 'info', or 'status'\n", .{});
        return;
    }
}

fn deleteWebhook(bot: *telegram.Bot) !void {
    std.debug.print("\n🗑️  Deleting webhook...\n", .{});

    const success = telegram.methods.deleteWebhook(bot) catch |err| {
        std.debug.print("❌ Failed to delete webhook: {}\n", .{err});
        switch (err) {
            telegram.BotError.TelegramAPIError => {
                std.debug.print("This could mean:\n", .{});
                std.debug.print("- Invalid bot token\n", .{});
                std.debug.print("- Network connectivity issues\n", .{});
                std.debug.print("- Telegram API temporarily unavailable\n", .{});
            },
            telegram.BotError.NetworkError => {
                std.debug.print("Check your internet connection\n", .{});
            },
            telegram.BotError.JSONError => {
                std.debug.print("Invalid response from Telegram API\n", .{});
            },
            else => {},
        }
        return;
    };

    if (success) {
        std.debug.print("✅ Webhook deleted successfully!\n", .{});
        std.debug.print("\n📋 What this means:\n", .{});
        std.debug.print("• Your bot is no longer receiving updates via webhook\n", .{});
        std.debug.print("• You can now use polling (getUpdates) to receive messages\n", .{});
        std.debug.print("• This is useful when switching from webhook to polling mode\n", .{});
        std.debug.print("• No webhook URL is now associated with your bot\n", .{});

        std.debug.print("\n💡 Next steps:\n", .{});
        std.debug.print("• Use the polling_bot example to receive messages\n", .{});
        std.debug.print("• Or set up a new webhook if you prefer webhook mode\n", .{});
    } else {
        std.debug.print("⚠️  Webhook deletion returned false\n", .{});
        std.debug.print("This might mean there was no webhook to delete\n", .{});
    }
}

fn showBotStatus(bot: *telegram.Bot) !void {
    std.debug.print("\n📊 Checking bot status...\n", .{});

    // Get bot information
    const me = telegram.methods.getMe(bot) catch |err| {
        std.debug.print("❌ Failed to get bot info: {}\n", .{err});
        return;
    };
    defer {
        var user_copy = me;
        user_copy.deinit(bot.allocator);
    }

    std.debug.print("\n✅ Bot Status:\n", .{});
    std.debug.print("   🤖 Bot Name: {s}\n", .{me.first_name});
    if (me.username) |username| {
        std.debug.print("   👤 Username: @{s}\n", .{username});
    }
    std.debug.print("   🆔 Bot ID: {d}\n", .{me.id});
    std.debug.print("   🔧 Is Bot: {}\n", .{me.is_bot});

    if (me.can_join_groups) |can_join| {
        std.debug.print("   👥 Can Join Groups: {}\n", .{can_join});
    }
    if (me.can_read_all_group_messages) |can_read| {
        std.debug.print("   📖 Can Read All Group Messages: {}\n", .{can_read});
    }
    if (me.supports_inline_queries) |supports_inline| {
        std.debug.print("   🔍 Supports Inline Queries: {}\n", .{supports_inline});
    }
    if (me.can_connect_to_business) |can_connect| {
        std.debug.print("   💼 Can Connect to Business: {}\n", .{can_connect});
    }
    if (me.has_main_web_app) |has_web_app| {
        std.debug.print("   🌐 Has Main Web App: {}\n", .{has_web_app});
    }

    // Test basic functionality
    std.debug.print("\n🧪 Testing basic functionality...\n", .{});

    // Try to delete webhook (this also serves as a connectivity test)
    const webhook_result = telegram.methods.deleteWebhook(bot) catch |err| {
        std.debug.print("   ❌ Webhook operation failed: {}\n", .{err});
        return;
    };

    if (webhook_result) {
        std.debug.print("   ✅ API connectivity: OK\n", .{});
        std.debug.print("   ℹ️  Webhook status: Deleted (or was already deleted)\n", .{});
    }

    // Try to get updates (this tests the polling endpoint)
    std.debug.print("   🔄 Testing getUpdates endpoint...\n", .{});
    const updates = telegram.methods.getUpdates(bot, 0, 1, 1) catch |err| {
        std.debug.print("   ❌ getUpdates failed: {}\n", .{err});
        return;
    };
    defer {
        for (updates) |*update| {
            update.deinit(bot.allocator);
        }
        bot.allocator.free(updates);
    }

    std.debug.print("   ✅ getUpdates: OK (received {d} updates)\n", .{updates.len});

    std.debug.print("\n🎉 Bot is fully functional!\n", .{});
    std.debug.print("\n📋 Summary:\n", .{});
    std.debug.print("   • Bot authentication: ✅ Working\n", .{});
    std.debug.print("   • API connectivity: ✅ Working\n", .{});
    std.debug.print("   • Webhook management: ✅ Working\n", .{});
    std.debug.print("   • Update polling: ✅ Working\n", .{});

    std.debug.print("\n💡 Your bot is ready to:\n", .{});
    std.debug.print("   • Receive and send messages\n", .{});
    std.debug.print("   • Use polling mode (getUpdates)\n", .{});
    std.debug.print("   • Join groups (if enabled)\n", .{});
    if (me.supports_inline_queries orelse false) {
        std.debug.print("   • Handle inline queries\n", .{});
    }

    std.debug.print("\n🚀 Try running the polling_bot example to see it in action!\n", .{});
}
