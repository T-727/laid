const std = @import("std");
const win = std.os.windows;
const win32 = @import("../win32.zig");
const windows = @import("../windows.zig");

pub const hook = win32.WinEventHook{
    .range = .{ .Foreground, .Foreground },
    .callback = foreground_hook,
};

// temp
const color = win32.window.BorderColor.Custom("FF0000".*) catch unreachable;

var index: ?usize = null;

fn foreground_hook(_: win32.HWINEVENTHOOK, _: win32.WinEvent, handle: ?win.HWND, _: win32.ObjectId, _: win32.ChildId, _: u32, _: u32) callconv(win.WINAPI) void {
    if (index) |last| win32.window.Attribute.set(windows.list.items[last].handle, .{ .BorderColor = win32.window.BorderColor.Default });

    index = for (windows.list.items, 0..) |w, i| {
        if (w.handle == handle) {
            win32.window.Attribute.set(w.handle, .{ .BorderColor = color });
            break i;
        }
    } else null;
}
