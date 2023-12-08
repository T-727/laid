const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");
const windows = @import("windows.zig");

const ranges = .{
    .{ .Foreground, .Foreground },
    .{ .Minimize, .Restore },
    .{ .Show, .Hide },
    .{ .Cloak, .UnCloak },
};
var handles: [ranges.len]win32.HWINEVENTHOOK = undefined;
pub fn init() !void {
    inline for (ranges, 0..) |range, i| handles[i] = try win32.WinEvent.init(range, hook, .{ .skip_own_process = true });
}
fn hook(_: win32.HWINEVENTHOOK, event: win32.WinEvent, handle: ?win.HWND, object: win32.ObjectId, child: win32.ChildId, _: u32, _: u32) callconv(win.WINAPI) void {
    if (object == .Window and child == .Self and handle != null) process(event, handle.?);
}

pub fn deinit() void {
    inline for (handles, 0..) |handle, i| win32.WinEvent.deinit(handle) catch |err| {
        std.log.warn("Failed to Unhook event handler for WinEvent range: {{ .{s}, .{s} }}. Error code: {s}", .{
            @tagName(ranges[i][0]), @tagName(ranges[i][1]), @errorName(err),
        });
    };
}

// temp
const color = win32.window.BorderColor.Custom("FF0000".*) catch unreachable;

var foreground_window: ?*windows.Window = null;

pub fn process(event: win32.WinEvent, handle: win.HWND) void {
    switch (event) {
        .Foreground => {
            if (foreground_window) |last| if (std.mem.indexOfScalar(*windows.Window, windows.list.items, last)) |_| {
                last.attribute(.{ .BorderColor = .Default }) catch |err| std.log.warn(
                    "Failed to reset foreground border color for previous window. Name: {s}, Error code: {s}",
                    .{ last.name, @errorName(err) },
                );
            };
            foreground_window = windows.findByHandle(handle);
            if (foreground_window) |current| {
                current.attribute(.{ .BorderColor = color }) catch |err| std.log.warn(
                    "Failed to set foreground border color for current window. Name: {s}, Error code: {s}",
                    .{ current.name, @errorName(err) },
                );
            }
        },

        .Show, .UnCloak => if (windows.Window.init(handle)) |new| {
            windows.list.append(new) catch unreachable;
            new.attribute(.{ .CornerPreference = .Round }) catch |err| std.log.warn(
                "Failed to set corner preference for new window. Name: {s}, Error code: {s}",
                .{ new.name, @errorName(err) },
            );
            std.log.debug("[{s}] {s}: {any}", .{ @tagName(event), new.name, new.rect.* });
            process(.Foreground, handle);
        } else |_| return,

        .Hide, .Cloak => if (windows.findByHandle(handle)) |w| {
            const removed = windows.list.orderedRemove(std.mem.indexOfScalar(*windows.Window, windows.list.items, w).?);
            std.log.debug("[{s}] {s}: {any}", .{ @tagName(event), removed.name, removed.rect.* });
            removed.deinit();
        } else return,

        // trigger window arrangement
        .Minimize, .Restore => {},

        else => unreachable,
    }
    var n: i32 = 0;
    for (windows.list.items) |w| {
        if (!w.minimized()) n += 1;
    }
    if (n == 0) return;
    const ratio = @divTrunc(windows.desktop.right, n);

    var i: i32 = 0;
    for (windows.list.items) |w| if (!w.minimized()) {
        w.position(.{
            .left = ratio * i + i,
            .top = windows.desktop.top,
            .right = ratio,
            .bottom = windows.desktop.bottom,
        }, .{
            .frame_changed = true,
            .no_activate = true,
            .no_copy_bits = true,
            .async_window_pos = true,
        }) catch unreachable;
        i += 1;
    };
}
