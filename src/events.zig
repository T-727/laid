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
pub fn init() void {
    inline for (ranges, 0..) |range, i| handles[i] = win32.WinEvent.init(range, hook);
}
fn hook(_: win32.HWINEVENTHOOK, event: win32.WinEvent, handle: ?win.HWND, object: win32.ObjectId, child: win32.ChildId, _: u32, _: u32) callconv(win.WINAPI) void {
    if (object == .Window and child == .Self and handle != null) process(event, handle.?);
}

pub fn deinit() void {
    for (handles) |handle| win32.WinEvent.deinit(handle);
}

// temp
const color = win32.window.BorderColor.Custom("FF0000".*) catch unreachable;

var foreground_window: ?*windows.Window = null;

pub fn process(event: win32.WinEvent, handle: win.HWND) void {
    switch (event) {
        .Foreground => {
            if (foreground_window) |last| for (windows.list.items) |w| //
                if (w == last) break win32.window.Attribute.set(last.handle, .{ .BorderColor = .Default });

            foreground_window = if (windows.indexFromHandle(handle)) |i| windows.list.items[i] else null;
            if (foreground_window) |current| win32.window.Attribute.set(current.handle, .{ .BorderColor = color });
        },

        .Show, .UnCloak => if (windows.Window.init(handle)) |w| {
            windows.list.append(w) catch unreachable;
            win32.window.Attribute.set(w.handle, .{ .CornerPreference = .Round });
            std.log.debug("[{s}] {s}: {any}", .{ @tagName(event), w.name, w.rect.* });
            process(.Foreground, handle);
        } else |_| return,

        .Hide, .Cloak => if (windows.indexFromHandle(handle)) |i| {
            const w = windows.list.orderedRemove(i);
            std.log.debug("[{s}] {s}: {any}", .{ @tagName(event), w.name, w.rect.* });
            w.deinit();
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
        win32.window.rect.set(w.handle, .{
            .left = ratio * i + i,
            .top = windows.desktop.top,
            .right = ratio,
            .bottom = windows.desktop.bottom,
        }, .{
            .frame_changed = true,
            .no_activate = true,
            .no_copy_bits = true,
            .async_window_pos = true,
        });
        i += 1;
    };
}
