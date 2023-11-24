const win = @import("std").os.windows;
const win32 = @import("../win32.zig");
const windows = @import("../windows.zig");

pub const hook = win32.WinEventHook{
    .range = .{ .Minimize, .Restore },
    .callback = minimize_hook,
};

fn minimize_hook(_: win32.HWINEVENTHOOK, _: win32.WinEvent, _: ?win.HWND, _: win32.ObjectId, _: win32.ChildId, _: u32, _: u32) callconv(win.WINAPI) void {
    var n: i32 = 0;
    for (windows.list.items) |w| {
        if (!w.minimized()) n += 1;
    }
    const ratio = @divTrunc(windows.desktop.right, n);

    var i: i32 = 0;
    for (windows.list.items) |w| if (!w.minimized()) {
        win32.window.Attribute.set(w.handle, .{ .CornerPreference = win32.window.CornerPreference.Round });
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
}
