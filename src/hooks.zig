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
    if (object == .Window and child == .Self and handle != null) processEvent(event, handle.?);
}

pub fn deinit() void {
    for (handles) |handle| win32.WinEvent.deinit(handle);
}

// temp
const color = win32.window.BorderColor.Custom("FF0000".*) catch unreachable;

var index: ?usize = null;

pub fn processEvent(event: win32.WinEvent, handle: win.HWND) void {
    switch (event) {
        .Foreground => {
            if (index) |last| win32.window.Attribute.set(windows.list.items[last].handle, .{ .BorderColor = .Default });

            if (index != null and index.? < windows.list.items.len) //
                win32.window.Attribute.set(windows.list.items[index.?].handle, .{ .BorderColor = .Default });

            index = windows.indexFromHandle(handle);
            if (index != null) win32.window.Attribute.set(handle, .{ .BorderColor = color });
        },

        .Show, .UnCloak => if (windows.Window.init(handle)) |w| {
            windows.list.append(w) catch unreachable;
            win32.window.Attribute.set(w.handle, .{ .CornerPreference = .Round });
            std.log.debug("[{s}] {s}: {any}", .{ @tagName(event), w.name, w.rect.* });
            processEvent(.Foreground, handle);
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
