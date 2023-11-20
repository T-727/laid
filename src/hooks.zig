const win32 = @import("win32.zig");

const hooks = .{
    @import("hooks/foreground.zig").hook,
    @import("hooks/minimize.zig").hook,
};
var handles: [hooks.len]win32.HWINEVENTHOOK = undefined;

pub fn init() void {
    inline for (hooks, 0..) |hook, i| handles[i] = hook.init();
    hooks[1].callback(handles[1], 0, null, 0, 0, 0, 0);
}

pub fn deinit() void {
    inline for (handles) |handle| win32.WinEventHook.deinit(handle);
}
