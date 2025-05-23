const std = @import("std");
const telegram = @import("telegram.zig");
const Allocator = std.mem.Allocator;

pub const InputFile = struct {
    name: []const u8,
    data: union(enum) {
        bytes: []const u8,
        path: []const u8,
        file_id: []const u8,
        url: []const u8,
    },

    pub fn fromBytes(name: []const u8, bytes: []const u8) InputFile {
        return .{
            .name = name,
            .data = .{ .bytes = bytes },
        };
    }

    pub fn fromPath(path: []const u8) InputFile {
        return .{
            .name = std.fs.path.basename(path),
            .data = .{ .path = path },
        };
    }

    pub fn fromFileId(file_id: []const u8) InputFile {
        return .{
            .name = "file",
            .data = .{ .file_id = file_id },
        };
    }

    pub fn fromUrl(url: []const u8) InputFile {
        return .{
            .name = "file",
            .data = .{ .url = url },
        };
    }
};

pub const File = struct {
    file_id: []const u8,
    file_unique_id: []const u8,
    file_size: ?i32,
    file_path: ?[]const u8,

    pub fn deinit(self: *File, allocator: Allocator) void {
        allocator.free(self.file_id);
        allocator.free(self.file_unique_id);
        if (self.file_path) |path| allocator.free(path);
    }
};

pub fn sendPhoto(bot: *telegram.Bot, chat_id: i64, photo: InputFile, caption: ?[]const u8) !telegram.Message {
    var params = std.StringHashMap([]const u8).init(bot.allocator);
    defer params.deinit();

    const chat_id_str = try std.fmt.allocPrint(bot.allocator, "{d}", .{chat_id});
    defer bot.allocator.free(chat_id_str);
    try params.put("chat_id", chat_id_str);

    switch (photo.data) {
        .file_id => |id| try params.put("photo", id),
        .url => |url| try params.put("photo", url),
        .bytes, .path => {
            // TODO: Implement multipart form data upload
            return telegram.BotError.APIError;
        },
    }

    if (caption) |c| {
        try params.put("caption", c);
    }

    const response = try bot.makeRequest("sendPhoto", params);
    // TODO: Parse JSON response into Message struct
    _ = response;
    return telegram.Message{
        .message_id = 0,
        .from = null,
        .date = 0,
        .chat = telegram.Chat{
            .id = chat_id,
            .type = "private",
            .title = null,
            .username = null,
            .first_name = null,
            .last_name = null,
        },
        .text = null,
    };
}

pub fn getFile(bot: *telegram.Bot, file_id: []const u8) !File {
    var params = std.StringHashMap([]const u8).init(bot.allocator);
    defer params.deinit();

    try params.put("file_id", file_id);

    const response = try bot.makeRequest("getFile", params);
    // TODO: Parse JSON response into File struct
    _ = response;
    return File{
        .file_id = "",
        .file_unique_id = "",
        .file_size = null,
        .file_path = null,
    };
}

pub fn downloadFile(bot: *telegram.Bot, file: File, writer: anytype) !void {
    const file_path = file.file_path orelse return telegram.BotError.APIError;

    const url = try std.fmt.allocPrint(
        bot.allocator,
        "{s}/file/bot{s}/{s}",
        .{ bot.api_endpoint, bot.token, file_path },
    );
    defer bot.allocator.free(url);

    var headers = std.http.Headers.init(bot.allocator);
    defer headers.deinit();

    var req = try bot.client.client.request(.GET, url, headers, .{});
    defer req.deinit();

    try req.start();
    try req.wait();

    var reader = req.reader();
    try reader.streamUntilEof(writer);
}
