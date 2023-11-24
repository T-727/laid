const std = @import("std");
const meta = std.meta;
const assert = std.debug.assert;
const win = std.os.windows;
const WINAPI = win.WINAPI;
const DWORD = win.DWORD;
const LONG = win.LONG;
const HWND = win.HWND;
const BOOL = win.BOOL;
const HRESULT = win.HRESULT;
const COLORREF = win.DWORD;
const RECT = win.RECT;
const LPARAM = win.LPARAM;
const WPARAM = win.WPARAM;

pub const HWINEVENTHOOK = *opaque {};
pub const ObjectId = enum(LONG) { Window, _ };
pub const ChildId = enum(LONG) { Self, _ };
pub const WINEVENTPROC = *const fn (HWINEVENTHOOK, WinEvent, ?HWND, ObjectId, ChildId, DWORD, DWORD) callconv(WINAPI) void;

pub const WinEvent = enum(DWORD) {
    Foreground = 0x0003,

    Create = 0x8000,
    Destroy = 0x8001,

    Show = 0x8002,
    Hide = 0x8003,

    Cloak = 0x8017,
    UnCloak = 0x8018,

    Minimize = 0x0016,
    Restore = 0x0017,
};

pub const WinEventHook = struct {
    const SetWinEventHookFlags = packed struct(DWORD) {
        skip_own_thread: bool = false,
        skip_own_process: bool = false,
        in_context: bool = false,
        _: u29 = 0,
    };
    range: [2]WinEvent,
    callback: WINEVENTPROC,

    extern "user32" fn SetWinEventHook(eventMin: WinEvent, eventMax: WinEvent, hmodWinEventProc: ?win.HMODULE, pfnWinEventProc: WINEVENTPROC, idProcess: DWORD, idThread: DWORD, dwFlags: SetWinEventHookFlags) callconv(WINAPI) HWINEVENTHOOK;
    pub fn init(comptime self: *const WinEventHook) HWINEVENTHOOK {
        comptime assert(@intFromEnum(self.range[0]) <= @intFromEnum(self.range[1]));
        return SetWinEventHook(self.range[0], self.range[1], null, self.callback, 0, 0, .{ .skip_own_process = true });
    }

    extern "user32" fn UnhookWinEvent(hWinEventHook: HWINEVENTHOOK) callconv(WINAPI) bool;
    pub fn deinit(handle: HWINEVENTHOOK) void {
        assert(UnhookWinEvent(handle));
    }
};

// remove after zig 0.12
pub fn HRESULT_CODE(hr: HRESULT) win.Win32Error {
    return @enumFromInt(hr & 0xFFFF);
}

pub fn assertHResult(result: HRESULT, comptime message: []const u8, args: anytype) void {
    const code = HRESULT_CODE(result);
    if (code != .SUCCESS) std.debug.panic(message ++ "\nerror: {s}", .{@tagName(code)} ++ args);
}

pub extern "ole32" fn CoInitializeEx(pvReserved: ?win.LPVOID, dwCoInit: enum(DWORD) { ApartmentThreaded = 0x2 }) callconv(WINAPI) HRESULT;
pub extern "ole32" fn CoUninitialize() callconv(WINAPI) void;

pub extern "kernel32" fn OpenProcess(dwDesiredAccess: enum(DWORD) { ProcessQueryLimitedInformation = 0x1000 }, bInheritHandle: bool, dwProcessId: DWORD) callconv(WINAPI) ?win.HANDLE;

pub extern "user32" fn PostThreadMessageW(idThread: DWORD, Msg: enum(DWORD) { Quit = 0x0012 }, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) bool;

pub const MSG = extern struct { hwnd: ?HWND, message: DWORD, wParam: WPARAM, lParam: LPARAM, time: u32, pt: win.POINT };
extern "user32" fn GetMessageW(lpMsg: *MSG, hwnd: ?HWND, wMsgFilterMin: DWORD, wMsgFilterMax: DWORD) callconv(WINAPI) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(WINAPI) bool;
extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(WINAPI) win.LRESULT;
pub fn getMessage(msgPtr: *MSG) bool {
    switch (GetMessageW(msgPtr, null, 0, 0)) {
        win.FALSE => return false,
        win.TRUE => {
            assert(TranslateMessage(msgPtr));
            _ = DispatchMessageW(msgPtr);
            return true;
        },
        -1 => std.debug.panic("Failed to get next message in the message loop.", .{}),
        else => unreachable,
    }
}

pub const window = struct {
    pub extern "user32" fn EnumWindows(lpEnumFunc: *const fn (HWND, LPARAM) callconv(WINAPI) bool, lParam: LPARAM) callconv(WINAPI) bool;
    pub extern "user32" fn IsIconic(hwnd: HWND) callconv(WINAPI) bool;
    pub extern "user32" fn IsWindowVisible(hwnd: HWND) callconv(WINAPI) bool;
    pub extern "user32" fn GetWindowThreadProcessId(hwnd: HWND, lpdwProcessId: *DWORD) callconv(WINAPI) DWORD;
    pub extern "user32" fn IsWindow(hwnd: HWND) callconv(WINAPI) bool;
    pub extern "user32" fn GetAncestor(hwnd: HWND, gaFlags: enum(DWORD) { Parent = 1, Root = 2, RootOwner = 3 }) callconv(WINAPI) ?HWND;

    const HMONITOR = *opaque {};
    const MONITORINFO = extern struct { cbSize: DWORD, rcMonitor: RECT, rcWork: RECT, dwFlags: enum(DWORD) { Primary = 1, _ } };
    extern "user32" fn GetDesktopWindow() callconv(WINAPI) HWND;
    extern "user32" fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(WINAPI) bool;
    extern "user32" fn MonitorFromWindow(hwnd: HWND, dwFlags: enum(DWORD) { Null, Primary, Nearest }) callconv(WINAPI) ?HMONITOR;
    pub fn monitorInfo() MONITORINFO {
        var info = MONITORINFO{ .cbSize = @sizeOf(MONITORINFO), .rcWork = undefined, .dwFlags = undefined, .rcMonitor = undefined };
        assert(GetMonitorInfoW(MonitorFromWindow(GetDesktopWindow(), .Null).?, &info));
        return info;
    }

    extern "user32" fn GetWindowLongPtrW(hwnd: HWND, nIndex: enum(i32) { Style = -16, ExStyle = -20 }) callconv(WINAPI) win.LONG_PTR;
    pub fn exStyle(handle: HWND) ExStyle {
        return @bitCast(GetWindowLongPtrW(handle, .ExStyle));
    }
    pub fn style(handle: HWND) Style {
        return @bitCast(GetWindowLongPtrW(handle, .Style));
    }
    pub const ExStyle = packed struct(win.LONG_PTR) {
        _: u7 = 0,
        tool_window: bool = false,
        __: u19 = 0,
        no_activate: bool = false,
        ___: u36 = 0,
    };
    pub const Style = packed struct(win.LONG_PTR) {
        _: u12,
        tabstop: bool = false,
        group: bool = false,
        sizebox: bool = false,
        sysmenu: bool = false,
        hscroll: bool = false,
        vscroll: bool = false,
        // caption = border | dlg_frame
        dlg_frame: bool = false,
        border: bool = false,
        maximize: bool = false,
        clip_children: bool = false,
        clip_siblings: bool = false,
        disabled: bool = false,
        visible: bool = false,
        minimize: bool = false,
        child: bool = false,
        popup: bool = false,
    };

    pub const CornerPreference = enum(DWORD) { Default, DoNotRound, Round, RoundSmall };
    pub const BorderColor = enum(COLORREF) {
        Default = 0xFFFFFFFF,
        None = 0xFFFFFFFE,
        _,
        pub fn Custom(fmt: [6]u8) std.fmt.ParseIntError!BorderColor {
            const r = try std.fmt.parseInt(u8, fmt[0..2], 16);
            const g = try std.fmt.parseInt(u16, fmt[2..4], 16);
            const b = try std.fmt.parseInt(u32, fmt[4..6], 16);
            return @enumFromInt(b * 0x10000 + g * 0x100 + r);
        }
    };

    pub const Attribute = union(enum(DWORD)) {
        CornerPreference: CornerPreference = 33,
        BorderColor: BorderColor = 34,
        Cloaked: BOOL = 14,
        // zig fmt: off
        extern "dwmapi" fn DwmSetWindowAttribute(hwnd: HWND, dwAttribute: meta.Tag(Attribute), pvAttribute: win.LPCVOID, cbAttribute: DWORD) callconv(WINAPI) HRESULT;
        pub fn set(handle: HWND, attribute: Attribute) void {
            switch (attribute) {
                inline else => |val| assertHResult(
                     DwmSetWindowAttribute(handle, attribute, &val, @sizeOf(@TypeOf(val))),
                    "DwmSetWindowAttribute({s})", .{@tagName(attribute)}
                )
            }
        }
        extern "dwmapi" fn DwmGetWindowAttribute(hwnd: HWND, dwAttribute: meta.Tag(Attribute), pvAttribute: win.PVOID, cbAttribute: DWORD) callconv(WINAPI) HRESULT;
        pub fn get(handle: HWND, comptime attribute: meta.Tag(Attribute)) meta.TagPayload(Attribute, attribute) {
            var val: meta.TagPayload(Attribute, attribute) = undefined;
            assertHResult(
                DwmGetWindowAttribute(handle, attribute, &val, @sizeOf(@TypeOf(val))),
                "DwmGetWindowAttribute({s})", .{@tagName(attribute)}
            );
            return val;
        }
        // zig fmt: on
    };
    pub const rect = struct {
        const SetWindowPosFlags = packed struct(DWORD) {
            no_size: bool = false,
            no_move: bool = false,
            no_zorder: bool = false,
            no_redraw: bool = false,
            no_activate: bool = false,
            frame_changed: bool = false,
            show_window: bool = false,
            hide_window: bool = false,
            no_copy_bits: bool = false,
            no_reposition: bool = false,
            no_send_changing: bool = false,
            _: u2 = 0,
            defer_erase: bool = false,
            async_window_pos: bool = false,
            __: u17 = 0,
        };
        extern "user32" fn SetWindowPos(hwnd: HWND, hWndInsertAfter: ?HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: SetWindowPosFlags) callconv(WINAPI) bool;
        pub fn set(handle: HWND, pos: RECT, flags: SetWindowPosFlags) void {
            assert(SetWindowPos(handle, null, pos.left, pos.top, pos.right, pos.bottom, flags));
        }
        extern "user32" fn GetClientRect(hwnd: HWND, lpRect: *RECT) callconv(WINAPI) bool;
        pub fn get(handle: HWND) RECT {
            var val: RECT = undefined;
            assert(GetClientRect(handle, &val));
            return val;
        }
        extern "user32" fn GetWindowRect(hwnd: HWND, lpRect: *RECT) callconv(WINAPI) bool;
        pub fn getNonClient(handle: HWND) RECT {
            var val: RECT = undefined;
            assert(GetWindowRect(handle, &val));
            return val;
        }
    };
};
