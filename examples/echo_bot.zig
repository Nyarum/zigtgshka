const std = @import("std");
const telegram = @import("telegram");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize HTTP client
    var client = try telegram.HTTPClient.init(allocator);
    defer client.deinit();

    // Initialize bot with your token
    var bot = try telegram.Bot.init(
        allocator,
        "8140640292:AAHSUoPAzCr2nhjE7CJrimpmTdhTSyIoAfg", // Replace with your bot token
        &client,
    );
    defer bot.deinit();

    // Get bot information
    const me = try telegram.methods.getMe(&bot);
    defer {
        var user_copy = me;
        user_copy.deinit(allocator);
    }
    std.debug.print("Bot started: @{s}\n", .{me.username orelse me.first_name});

    // Delete any existing webhook to enable getUpdates
    _ = try telegram.methods.deleteWebhook(&bot);
    std.debug.print("Webhook deleted, starting polling...\n", .{});

    // Simple update polling loop
    var last_update_id: i32 = 0;
    while (true) {
        // Get updates with long polling (30 seconds timeout)
        const updates = try telegram.methods.getUpdates(
            &bot,
            last_update_id + 1, // Offset
            100, // Limit
            30, // Timeout
        );
        defer {
            for (updates) |*update| {
                update.deinit(allocator);
            }
            allocator.free(updates);
        }

        // Process updates
        for (updates) |update| {
            if (update.message) |msg| {
                if (msg.text) |text| {
                    std.debug.print(
                        "Received message from {s}: {s}\n",
                        .{ msg.from.?.first_name, text },
                    );

                    // Handle commands
                    if (text.len > 0 and text[0] == '/') {
                        if (std.mem.eql(u8, text, "/start")) {
                            var reply = try telegram.methods.sendMessage(
                                &bot,
                                msg.chat.id,
                                "Hello! I'm an echo bot. Send me any message and I'll send it back to you.",
                            );
                            defer reply.deinit(allocator);
                            std.debug.print("Sent reply with id: {d}\n", .{reply.message_id});
                        }
                    } else if (text.len > 0) {
                        // Echo non-command messages back
                        var reply = try telegram.methods.sendMessage(
                            &bot,
                            msg.chat.id,
                            text,
                        );
                        defer reply.deinit(allocator);
                        std.debug.print("Sent reply with id: {d}\n", .{reply.message_id});
                    }
                }
            }
            last_update_id = update.update_id;
        }
    }
}
