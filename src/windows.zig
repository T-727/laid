const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");

pub var list = std.ArrayList(*Window).init(allocator);
var _gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = _gpa.allocator();

pub const Window = struct {
    handle: win.HWND,
    name: []const u8,
    rect: *win.RECT,

    pub fn init(handle: win.HWND) InvalidWindowError!*Window {
        if (indexFromHandle(handle) != null) return error.WindowAlreadyAdded;

        const rect = allocator.create(win.RECT) catch unreachable;
        rect.* = win32.window.rect.get(handle, true);
        errdefer allocator.destroy(rect);

        const name = processName(handle) catch unreachable;
        for (system_apps.items) |sysapp| if (std.mem.eql(u8, sysapp, name)) return error.IsSystemApp;
        errdefer allocator.free(name);

        const ptr = allocator.create(Window) catch unreachable;
        ptr.* = .{
            .handle = handle,
            .name = name,
            .rect = rect,
        };
        return ptr;
    }

    pub fn deinit(self: *Window) void {
        allocator.free(self.name);
        allocator.destroy(self.rect);
        allocator.destroy(self);
        self.* = undefined;
    }

    fn processName(handle: win.HWND) ![]const u8 {
        var process_id: u32 = undefined;
        _ = win32.window.GetWindowThreadProcessId(handle, &process_id);

        const process = win32.OpenProcess(.ProcessQueryLimitedInformation, false, process_id).?;
        defer win.CloseHandle(process);

        var buf16: [win.PATH_MAX_WIDE:0]u16 = undefined;
        _ = win.kernel32.K32GetProcessImageFileNameW(process, &buf16, buf16.len);

        var buf8: [std.fs.MAX_PATH_BYTES:0]u8 = undefined;
        return try allocator.dupe(u8, std.fs.path.basename(buf8[0..try std.unicode.utf16leToUtf8(&buf8, std.mem.span(@as([*:0]u16, &buf16)))]));
    }

    const InvalidWindowError = error{
        WindowNonExistent,
        WindowInvisible,
        WindowUnControlable,
        WindowCloaked,
        WindowIsNotRoot,
        WindowAlreadyAdded,
        WindowIsTaskbar,
        WindowIsChild,
        IsSystemApp,
        NullProcess,
    };

    pub fn validate(handle: win.HWND) InvalidWindowError!void {
        if (!win32.window.IsWindow(handle)) return error.WindowNonExistent;

        if (!win32.window.IsWindowVisible(handle)) return error.WindowInvisible;

        const style = win32.window.style(handle);
        if (style.child) return error.WindowIsChild;

        if (handle != win32.window.GetAncestor(handle, .RootOwner).?) return error.WindowIsNotRoot;

        if (win32.window.Attribute.get(handle, .Cloaked) != win.FALSE) return error.WindowCloaked;

        const exstyle = win32.window.exStyle(handle);
        if (exstyle.no_activate or exstyle.tool_window) return error.WindowUnControlable;

        const rect = win32.window.rect.get(handle, true);
        const rect_nc = win32.window.rect.get(handle, false);
        // zig fmt: off
        if (
            rect_nc.bottom == monitor.bottom
            and rect_nc.right == monitor.right
            and rect_nc.top == (monitor.bottom - rect.bottom)
        ) return error.WindowIsTaskbar;
        // zig fmt: on
    }

    pub fn minimized(self: *const Window) bool {
        return win32.window.IsIconic(self.handle);
    }
};

pub var desktop: win.RECT = undefined;
pub var monitor: win.RECT = undefined;
pub fn init() !void {
    try initSystemApps();
    const info = win32.window.monitorInfo();
    desktop = info.rcWork;
    monitor = info.rcMonitor;
    std.debug.assert(win32.window.EnumWindows(enumerator, 0));
    std.debug.print("[-] Monitor: {any}\n", .{monitor});
    std.debug.print("[0] Desktop: {any}\n", .{desktop});
    for (list.items, 1..) |w, i| std.debug.print("[{d}] {s}: {any}\n", .{ i, w.name, w.rect.* });
}

pub fn deinit() void {
    for (list.items) |w| {
        win32.window.Attribute.set(w.handle, .{ .BorderColor = .Default });
        win32.window.Attribute.set(w.handle, .{ .CornerPreference = .Default });
    }
}

pub fn indexFromHandle(handle: win.HWND) ?usize {
    for (list.items, 0..) |w, i| if (w.handle == handle) return i;
    return null;
}

fn enumerator(handle: win.HWND, _: win.LPARAM) callconv(win.WINAPI) bool {
    Window.validate(handle) catch return true;
    if (Window.init(handle)) |window| list.append(window) catch unreachable //
    else |err| std.log.debug("window init error: {s}", .{@errorName(err)});
    return true;
}

var _sys = std.heap.ArenaAllocator.init(allocator);
// maybe BoundedArray instead?
var system_apps = std.ArrayList([]const u8).init(_sys.allocator());

/// `$SystemRoot/SystemApps/*/*.exe`
fn initSystemApps() !void {
    // would SHGetKnownFolderPath() be better here?
    const sysroot = try std.process.getEnvVarOwned(allocator, "SystemRoot");
    defer allocator.free(sysroot);

    const sysapps_path = try std.fs.path.join(allocator, &.{ sysroot, "SystemApps" });
    defer allocator.free(sysapps_path);

    // TODO 0.12 https://github.com/ziglang/zig/pull/18076
    var sysapps_dir = try std.fs.openIterableDirAbsolute(sysapps_path, .{});
    defer sysapps_dir.close();

    var sysapps_iter = sysapps_dir.iterate();
    while (try sysapps_iter.next()) |dir| {
        var appdir = try sysapps_dir.dir.openIterableDir(dir.name, .{});
        defer appdir.close();
        var appiter = appdir.iterate();
        while (try appiter.next()) |item|
            if (item.kind == .file and std.mem.endsWith(u8, item.name, ".exe")) {
                try system_apps.append(try _sys.allocator().dupe(u8, item.name));
            };
    }
}
