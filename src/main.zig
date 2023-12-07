const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");
const windows = @import("windows.zig");
const events = @import("events.zig");

var thread: u32 = undefined;
pub fn main() !void {
    thread = win.kernel32.GetCurrentThreadId();
    if (!try win32.init(.{})) std.log.debug("COM was already initialized for this thread.", .{});
    defer win32.deinit();

    try win.SetConsoleCtrlHandler(ctrlHandler, true);

    try windows.init();
    defer windows.deinit();

    try events.init();
    defer events.deinit();

    var msg: win32.message.MSG = undefined;
    while (try win32.message.get(&msg)) {
        try win32.message.translate(&msg);
        win32.message.dispatch(&msg);
    }
    std.debug.print("\nEEEE\n", .{});
}

pub fn exit(code: u8) void {
    if (code != 0) std.log.err(
        \\Exited with error code: {d}\n
        \\Last error type: {s}
    , .{ code, @tagName(win.kernel32.GetLastError()) });
    win32.message.post(thread, .Quit) catch std.os.exit(code);
}

fn ctrlHandler(fdwCtrlType: u32) callconv(win.WINAPI) win.BOOL {
    if (fdwCtrlType == win.CTRL_C_EVENT) exit(0);
    return win.TRUE;
}
