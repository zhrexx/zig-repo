const std = @import("std");
const builtin = @import("builtin");

fn parseContentLength(buf: []const u8) !usize {
    const prefix = "Content-Length:";
    var it = std.mem.tokenizeAny(u8, buf, "\r\n");
    while (it.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, prefix)) {
            const value = std.mem.trim(u8, line[prefix.len..], " \t");
            return try std.fmt.parseInt(usize, value, 10);
        }
    }
    return error.NoContentLen;
}

fn parseLocation(allocator: std.mem.Allocator, buf: []const u8) !?[]const u8 {
    const prefix = "Location:";
    var it = std.mem.tokenizeAny(u8, buf, "\r\n");
    while (it.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, prefix)) {
            const value = std.mem.trim(u8, line[prefix.len..], " \t");
            return try allocator.dupe(u8, value);
        }
    }
    return null;
}

fn flushStdout() void {
    const stdout = std.io.getStdOut().writer();
    stdout.context.sync() catch {};
}


fn downloadZig(allocator: std.mem.Allocator, version: []const u8, os_name: []const u8, arch: []const u8) !void {
    const ending = if (std.mem.eql(u8, os_name, "windows")) "zip" else "tar.xz";
    const url = try std.fmt.allocPrint(allocator, "https://github.com/zhrexx/zig-repo/releases/download/RELEASE/zig-{s}-{s}-{s}.{s}", .{ arch, os_name, version, ending });
    defer allocator.free(url);

    var final_url = url;
    var max_redirects: u8 = 5;

    while (max_redirects > 0) : (max_redirects -= 1) {
        const uri = try std.Uri.parse(final_url);

        var client: std.http.Client = .{ .allocator = allocator };
        defer client.deinit();

        var request = try client.request(.GET, uri, .{});
        defer request.deinit();

        try request.sendBodiless();
        const head = try request.reader.receiveHead();

        if (std.mem.startsWith(u8, head, "HTTP/1.1 3") or std.mem.startsWith(u8, head, "HTTP/1.0 3")) {
            if (try parseLocation(allocator, head)) |location| {
                defer allocator.free(location);
                //std.debug.print("Following redirect to: {s}\n", .{location});

                if (final_url.ptr != url.ptr) {
                    allocator.free(final_url);
                }
                final_url = try allocator.dupe(u8, location);
                continue;
            } else {
                return error.RedirectWithoutLocation;
            }
        }

        const dest = std.fs.path.basename(url);
        const content_length = parseContentLength(head) catch |err| {
            std.debug.print("Failed to parse Content-Length: {}\n", .{err});
            std.debug.print("Will download with unknown size...\n", .{});

            const file = try std.fs.cwd().createFile(dest, .{});
            defer file.close();

            var transfer_buffer: [8192]u8 = undefined;
            var read_buffer: [8192]u8 = undefined;
            const reader = request.reader.bodyReader(&transfer_buffer, .none, null);

            var downloaded: usize = 0;
            while (true) {
                const size = reader.readSliceShort(&read_buffer) catch |read_err| {
                    if (read_err == error.EndOfStream) break;
                    return read_err;
                };
                if (size == 0) break;

                try file.writeAll(read_buffer[0..size]);
                downloaded += size;
                std.debug.print("\rDownloaded: {} bytes", .{downloaded});
            }
            std.debug.print("\nDownload complete! Total: {} bytes\n", .{downloaded});

            if (final_url.ptr != url.ptr) {
                allocator.free(final_url);
            }
            return;
        };

        std.debug.print("Downloading: {s}\n", .{dest});
        std.debug.print("Size: {} bytes\n", .{content_length});

        const file = try std.fs.cwd().createFile(dest, .{});
        defer file.close();

        var transfer_buffer: [8192]u8 = undefined;
        var read_buffer: [8192]u8 = undefined;
        const reader = request.reader.bodyReader(&transfer_buffer, .none, content_length);


        var downloaded: usize = 0;
        while (downloaded < content_length) {
            const size = try reader.readSliceShort(&read_buffer);
            if (size > 0) {
                try file.writeAll(read_buffer[0..size]);
                downloaded += size;
                const percent = (@as(f64, @floatFromInt(downloaded)) / @as(f64, @floatFromInt(content_length))) * 100.0;
                std.debug.print("\rProgress: {d:.1}% ({} / {} bytes)", .{ percent, downloaded, content_length });
            }
        }

        std.debug.print("\nDownload complete!\n", .{});

        if (final_url.ptr != url.ptr) {
            allocator.free(final_url);
        }
        return;
    }

    if (final_url.ptr != url.ptr) {
        allocator.free(final_url);
    }
    return error.TooManyRedirects;
}

fn getOsName(allocator: std.mem.Allocator) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => try allocator.dupe(u8, "windows"),
        .linux => try allocator.dupe(u8, "linux"),
        .macos => try allocator.dupe(u8, "macos"),
        else => try allocator.dupe(u8, "unknown"),
    };
}

fn getArch(allocator: std.mem.Allocator) ![]const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => try allocator.dupe(u8, "x86_64"),
        .aarch64 => try allocator.dupe(u8, "aarch64"),
        .arm => try allocator.dupe(u8, "arm"),
        else => try allocator.dupe(u8, "unknown"),
    };
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const prog_name = args.next() orelse "download_zig";
    const version = args.next() orelse {
        std.debug.print("ERROR: Usage: {s} <version> [os|native] [arch|native]\n", .{prog_name});
        return 1;
    };

    var os_name = if (args.next()) |arg|
        try allocator.dupe(u8, arg)
    else
        try getOsName(allocator);
    defer allocator.free(os_name);

    var arch = if (args.next()) |arg|
        try allocator.dupe(u8, arg)
    else
        try getArch(allocator);
    defer allocator.free(arch);

    if (std.mem.eql(u8, os_name, "native")) {
        allocator.free(os_name);
        os_name = try getOsName(allocator);
    }
    if (std.mem.eql(u8, arch, "native")) {
        allocator.free(arch);
        arch = try getArch(allocator);
    }

    std.debug.print("Downloading Zig {s} for:\n", .{version});
    std.debug.print("os: {s}\n", .{os_name});
    std.debug.print("arch: {s}\n", .{arch});

    try downloadZig(allocator, version, os_name, arch);
    return 0;
}