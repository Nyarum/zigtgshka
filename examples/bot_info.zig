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

    std.debug.print("🤖 Getting bot information...\n", .{});

    // Get bot information
    const me = telegram.methods.getMe(&bot) catch |err| {
        std.debug.print("❌ Failed to get bot info: {}\n", .{err});
        return;
    };
    defer {
        var user_copy = me;
        user_copy.deinit(allocator);
    }

    // Display bot information
    std.debug.print("\n✅ Bot Information:\n", .{});
    std.debug.print("   ID: {d}\n", .{me.id});
    std.debug.print("   Name: {s}\n", .{me.first_name});
    if (me.last_name) |last_name| {
        std.debug.print("   Last Name: {s}\n", .{last_name});
    }
    if (me.username) |username| {
        std.debug.print("   Username: @{s}\n", .{username});
    }
    std.debug.print("   Is Bot: {}\n", .{me.is_bot});
    if (me.language_code) |lang| {
        std.debug.print("   Language: {s}\n", .{lang});
    }
    if (me.is_premium) |premium| {
        std.debug.print("   Premium: {}\n", .{premium});
    }
    if (me.can_join_groups) |can_join| {
        std.debug.print("   Can Join Groups: {}\n", .{can_join});
    }
    if (me.can_read_all_group_messages) |can_read| {
        std.debug.print("   Can Read All Group Messages: {}\n", .{can_read});
    }
    if (me.supports_inline_queries) |supports_inline| {
        std.debug.print("   Supports Inline Queries: {}\n", .{supports_inline});
    }
    if (me.can_connect_to_business) |can_connect| {
        std.debug.print("   Can Connect to Business: {}\n", .{can_connect});
    }
    if (me.has_main_web_app) |has_web_app| {
        std.debug.print("   Has Main Web App: {}\n", .{has_web_app});
    }

    std.debug.print("\n🎉 Bot is ready to use!\n", .{});
}
