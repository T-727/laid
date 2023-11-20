const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");

pub var list = std.ArrayList(Window).init(_gpa.allocator());
var _gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const Window = struct {
    handle: win.HWND,
    name: []const u8,
    rect: *win.RECT,

    // TODO get more useful names for apps that run in ApplicationFrameHost.exe
    const WindowInitError = error{ HandleInvisible, BlacklistedProcess };
    pub fn init(handle: win.HWND, allocator: std.mem.Allocator) !Window {
        if (!visible(handle)) return WindowInitError.HandleInvisible;

        var rect = try allocator.create(win.RECT);
        win32.window.rect.get(handle, rect);

        var name = try processName(handle, allocator);
        errdefer allocator.free(name);

        // TODO un-blacklist
        if (std.mem.eql(u8, name, "explorer.exe")) return WindowInitError.BlacklistedProcess;

        return .{
            .handle = handle,
            .name = name,
            .rect = rect,
        };
    }

    pub fn deinit(self: *Window, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.destroy(self.rect);
        allocator.destroy(self);
        self.* = undefined;
    }

    fn processName(handle: win.HWND, allocator: std.mem.Allocator) ![]const u8 {
        var process_id: u32 = undefined;
        _ = win32.window.GetWindowThreadProcessId(handle, &process_id);

        const process = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, false, process_id).?;
        defer win.CloseHandle(process);

        var buf16: [win.PATH_MAX_WIDE:0]u16 = undefined;
        _ = win.kernel32.K32GetProcessImageFileNameW(process, &buf16, buf16.len);

        var buf8: [std.fs.MAX_PATH_BYTES:0]u8 = undefined;
        return try allocator.dupe(u8, std.fs.path.basename(buf8[0..try std.unicode.utf16leToUtf8(&buf8, std.mem.span(@as([*:0]u16, &buf16)))]));
    }

    fn visible(handle: win.HWND) bool {
        var cloaked: win.BOOL = win.FALSE;
        win32.window.Attribute.get(handle, .{ .Cloaked = &cloaked });
        return win32.window.IsWindowVisible(handle) and cloaked == win.FALSE;
    }

    pub fn minimized(self: *const Window) bool {
        return win32.window.IsIconic(self.handle);
    }
};

pub var monitor: win.RECT = undefined;
pub fn init() void {
    monitor = win32.window.monitorSize();
    std.debug.assert(win32.window.EnumWindows(enumerator, 0));
    std.debug.print("[0] Desktop: {any}\n", .{monitor});
    for (list.items, 1..) |w, i| std.debug.print("[{d}] {s}: {any}\n", .{ i, w.name, w.rect.* });
}

pub fn deinit() void {
    for (list.items) |w| {
        win32.window.Attribute.set(w.handle, .{ .BorderColor = &win32.window.BorderColor.Default });
        win32.window.Attribute.set(w.handle, .{ .CornerPreference = &win32.window.CornerPreference.Default });
    }
}

fn enumerator(handle: win.HWND, _: win.LPARAM) callconv(win.WINAPI) bool {
    const window = Window.init(handle, _gpa.allocator()) catch |err| {
        switch (err) {
            error.HandleInvisible, error.BlacklistedProcess => {},
            else => std.debug.print("initWindow error: {s}\n", .{@errorName(err)}),
        }
        return true;
    };
    list.append(window) catch unreachable;
    return true;
}
