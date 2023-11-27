const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");
const windows = @import("windows.zig");

const ranges = .{
    .{ .Foreground, .Foreground },
    .{ .Minimize, .Restore },
};
var handles: [ranges.len]win32.HWINEVENTHOOK = undefined;
pub fn init() void {
    inline for (ranges, 0..) |range, i| handles[i] = win32.WinEvent.init(range, handler);
}

pub fn deinit() void {
    for (handles) |handle| win32.WinEvent.deinit(handle);
}

// temp
const color = win32.window.BorderColor.Custom("FF0000".*) catch unreachable;

var index: ?usize = null;

fn handler(_: win32.HWINEVENTHOOK, event: win32.WinEvent, handle: ?win.HWND, object: win32.ObjectId, child: win32.ChildId, _: u32, _: u32) callconv(win.WINAPI) void {
    if (object != .Window or child != .Self) return;
    switch (event) {
        .Foreground => {
            if (index) |last| win32.window.Attribute.set(windows.list.items[last].handle, .{ .BorderColor = .Default });

            index = for (windows.list.items, 0..) |w, i| {
                if (w.handle == handle) {
                    win32.window.Attribute.set(w.handle, .{ .BorderColor = color });
                    break i;
                }
            } else null;
        },
        .Minimize, .Restore => {
            var n: i32 = 0;
            for (windows.list.items) |w| {
                if (!w.minimized()) n += 1;
            }
            const ratio = @divTrunc(windows.desktop.right, n);

            var i: i32 = 0;
            for (windows.list.items) |w| if (!w.minimized()) {
                win32.window.Attribute.set(w.handle, .{ .CornerPreference = .Round });
                win32.window.rect.set(w.handle, .{
                    .left = ratio * i + i,
                    .top = windows.desktop.top,
                    .right = ratio,
                    .bottom = windows.desktop.bottom,
                }, .{
                    .frame_changed = true,
                });
                i += 1;
            };
        },
        else => unreachable,
    }
}
