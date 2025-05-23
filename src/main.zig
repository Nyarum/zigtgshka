//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");

pub fn main() !void {
    // Get an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Create a TCP server
    const address = try std.net.Address.parseIp("127.0.0.1", 8080);
    var server = try address.listen(.{});
    defer server.deinit();

    std.debug.print("Server listening on http://{}\n", .{address});

    // Accept and handle connections
    while (true) {
        const connection = try server.accept();
        try handleConnection(connection);
    }
}

fn handleConnection(connection: std.net.Server.Connection) !void {
    defer connection.stream.close();

    var read_buffer: [4096]u8 = undefined;
    var http_server = std.http.Server.init(connection, &read_buffer);

    while (http_server.state == .ready) {
        // Receive request
        var request = http_server.receiveHead() catch |err| switch (err) {
            error.HttpHeadersInvalid => continue,
            error.HttpConnectionClosing => break,
            else => return err,
        };

        // Handle different routes
        if (std.mem.eql(u8, request.head.target, "/")) {
            // Get a reader to properly handle the request body
            _ = try request.reader();

            try request.respond("Welcome to Zig HTTP Server!\n", .{
                .extra_headers = &[_]std.http.Header{
                    .{ .name = "content-type", .value = "text/plain" },
                },
                .keep_alive = false,
            });
        } else if (std.mem.eql(u8, request.head.target, "/json")) {
            // Get a reader to properly handle the request body
            _ = try request.reader();

            try request.respond(
                \\{"message": "Hello from Zig!"}
                \\
            , .{
                .extra_headers = &[_]std.http.Header{
                    .{ .name = "content-type", .value = "application/json" },
                },
                .keep_alive = false,
            });
        } else {
            // Get a reader to properly handle the request body
            _ = try request.reader();

            try request.respond("404 Not Found\n", .{
                .status = .not_found,
                .keep_alive = false,
            });
        }

        if (!request.head.keep_alive) break;
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("zigtgshka_lib");
