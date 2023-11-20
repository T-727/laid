const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");
const windows = @import("windows.zig");
const hooks = @import("hooks.zig");

var thread: u32 = undefined;
pub fn main() !void {
    thread = win.kernel32.GetCurrentThreadId();
    _ = win.ole32.CoInitialize(null);
    try win.SetConsoleCtrlHandler(ctrlHandler, true);
    windows.init();
    hooks.init();

    var msg: win32.MSG = undefined;
    while (win32.getMessage(&msg)) {}
    windows.deinit();
    hooks.deinit();
    _ = win.ole32.CoUninitialize();
    std.debug.print("\nEEEE\n", .{});
}

pub fn exit(code: u8) void {
    if (code != 0) std.log.err(
        \\Exited with error code: {d}\n
        \\Last error type: {s}
    , .{ code, @tagName(win.kernel32.GetLastError()) });
    std.debug.assert(win32.PostThreadMessageW(thread, win32.WM_QUIT, 0, 0));
}

pub fn ctrlHandler(fdwCtrlType: u32) callconv(win.WINAPI) win.BOOL {
    if (fdwCtrlType == win.CTRL_C_EVENT) exit(0);
    return win.TRUE;
}