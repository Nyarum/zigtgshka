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

    if (args.len < 4) {
        std.debug.print("Usage: {s} <bot_token> <chat_id> <message>\n", .{args[0]});
        std.debug.print("Example: {s} 123456789:ABC... 12345678 \"Hello, World!\"\n", .{args[0]});
        std.debug.print("\nTo get chat_id:\n", .{});
        std.debug.print("1. Start a conversation with your bot\n", .{});
        std.debug.print("2. Send a message to the bot\n", .{});
        std.debug.print("3. Use the polling_bot example to see the chat_id\n", .{});
        return;
    }

    const token = args[1];
    const chat_id_str = args[2];
    const message = args[3];

    // Parse chat_id
    const chat_id = std.fmt.parseInt(i64, chat_id_str, 10) catch |err| {
        std.debug.print("❌ Invalid chat_id: {s}. Error: {}\n", .{ chat_id_str, err });
        std.debug.print("Chat ID should be a number like: 123456789\n", .{});
        return;
    };

    // Initialize HTTP client
    var client = try telegram.HTTPClient.init(allocator);
    defer client.deinit();

    // Initialize bot
    var bot = try telegram.Bot.init(allocator, token, &client);
    defer bot.deinit();

    std.debug.print("📤 Sending message to chat {d}...\n", .{chat_id});
    std.debug.print("Message: \"{s}\"\n", .{message});

    // Send message
    var reply = telegram.methods.sendMessage(&bot, chat_id, message) catch |err| {
        std.debug.print("❌ Failed to send message: {}\n", .{err});
        switch (err) {
            telegram.BotError.TelegramAPIError => {
                std.debug.print("This could mean:\n", .{});
                std.debug.print("- Invalid chat_id\n", .{});
                std.debug.print("- Bot doesn't have permission to send messages to this chat\n", .{});
                std.debug.print("- Invalid bot token\n", .{});
            },
            telegram.BotError.NetworkError => {
                std.debug.print("Check your internet connection\n", .{});
            },
            else => {},
        }
        return;
    };
    defer reply.deinit(allocator);

    std.debug.print("\n✅ Message sent successfully!\n", .{});
    std.debug.print("   Message ID: {d}\n", .{reply.message_id});
    std.debug.print("   Date: {d}\n", .{reply.date});
    std.debug.print("   Chat ID: {d}\n", .{reply.chat.id});
    std.debug.print("   Chat Type: {s}\n", .{reply.chat.type});

    if (reply.from) |from| {
        std.debug.print("   From Bot: {s}\n", .{from.first_name});
        if (from.username) |username| {
            std.debug.print("   Bot Username: @{s}\n", .{username});
        }
    }

    if (reply.text) |text| {
        std.debug.print("   Message Text: \"{s}\"\n", .{text});
    }

    std.debug.print("\n🎉 Done!\n", .{});
}
