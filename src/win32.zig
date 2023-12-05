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
const HANDLE = win.HANDLE;

pub const HWINEVENTHOOK = *opaque {};
/// Only includes the subset useful for this application
pub const ObjectId = enum(LONG) { Window, _ };
pub const ChildId = enum(LONG) { Self, _ };
pub const WINEVENTPROC = *const fn (HWINEVENTHOOK, WinEvent, ?HWND, ObjectId, ChildId, DWORD, DWORD) callconv(WINAPI) void;

/// Only includes the subset useful for this application
pub const WinEvent = enum(DWORD) {
    Foreground = 0x0003,
    Minimize = 0x0016,
    Restore,
    Create = 0x8000,
    Destroy,
    Show = 0x8002,
    Hide,
    Cloak = 0x8017,
    UnCloak,
    const WinEventHookFlags = packed struct(DWORD) {
        skip_own_thread: bool = false,
        skip_own_process: bool = false,
        in_context: bool = false,
        _: u29 = 0,
    };
    extern "user32" fn SetWinEventHook(eventMin: WinEvent, eventMax: WinEvent, hmodWinEventProc: ?win.HMODULE, pfnWinEventProc: WINEVENTPROC, idProcess: DWORD, idThread: DWORD, dwFlags: WinEventHookFlags) callconv(WINAPI) HWINEVENTHOOK;
    pub fn init(comptime range: struct { WinEvent, WinEvent }, callback: WINEVENTPROC, flags: WinEventHookFlags) HWINEVENTHOOK {
        comptime assert(@intFromEnum(range[0]) <= @intFromEnum(range[1]));
        return SetWinEventHook(range[0], range[1], null, callback, 0, 0, flags);
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
pub fn assertHResult(result: HRESULT, comptime msg: []const u8, args: anytype) void {
    const code = HRESULT_CODE(result);
    if (code != .SUCCESS) {
        @setEvalBranchQuota(@typeInfo(win.Win32Error).Enum.fields.len);
        std.debug.panic(msg ++ "\nerror: {s}", args ++ .{std.enums.tagName(win.Win32Error, code) orelse "UNKNOWN"});
    }
}

const CoInitFlags = packed struct(DWORD) {
    multi_threaded: bool = false,
    disable_ole1dde: bool = false,
    speed_over_memory: bool = false,
    _: u29 = 0,
};
extern "ole32" fn CoInitializeEx(pvReserved: ?win.LPVOID, dwCoInit: CoInitFlags) callconv(WINAPI) HRESULT;
extern "ole32" fn CoUninitialize() callconv(WINAPI) void;
pub fn init(flags: CoInitFlags) HRESULT {
    return CoInitializeEx(null, flags);
}
pub fn deinit() void {
    CoUninitialize();
}

pub const process = struct {
    /// Only includes the subset useful for this application
    const AccessRights = enum(DWORD) { ProcessQueryLimitedInformation = 0x1000 };
    extern "kernel32" fn OpenProcess(dwDesiredAccess: AccessRights, bInheritHandle: bool, dwProcessId: DWORD) callconv(WINAPI) ?HANDLE;
    pub fn open(id: u32, rights: AccessRights) ?HANDLE {
        return OpenProcess(rights, false, id);
    }
    pub fn path(handle: HANDLE, buf: [:0]u16) u32 {
        return win.kernel32.K32GetProcessImageFileNameW(handle, buf.ptr, @truncate(buf.len));
    }
};

pub const message = struct {
    /// Only includes the subset useful for this application
    const MessageId = enum(DWORD) { Quit = 0x0012, _ };
    pub const MSG = extern struct { hwnd: ?HWND, message: message.MessageId, wParam: WPARAM, lParam: LPARAM, time: u32, pt: win.POINT };

    extern "user32" fn GetMessageW(lpMsg: *MSG, hwnd: ?HWND, wMsgFilterMin: DWORD, wMsgFilterMax: DWORD) callconv(WINAPI) BOOL;
    pub fn get(buf: *MSG) bool {
        const ok = GetMessageW(buf, null, 0, 0);
        if (ok == -1) std.debug.panic("Failed to get next message in the message loop.", .{}) else return ok == win.TRUE;
    }
    extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(WINAPI) bool;
    pub fn translate(msg: *const MSG) bool {
        return TranslateMessage(msg);
    }
    extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(WINAPI) win.LRESULT;
    pub fn dispatch(msg: *const MSG) void {
        _ = DispatchMessageW(msg);
    }
    extern "user32" fn PostThreadMessageW(idThread: DWORD, Msg: MessageId, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) bool;
    pub fn post(thread: u32, msg: MessageId) bool {
        return PostThreadMessageW(thread, msg, 0, 0);
    }
};

pub const window = struct {
    extern "user32" fn EnumWindows(lpEnumFunc: *const fn (HWND, LPARAM) callconv(WINAPI) bool, lParam: LPARAM) callconv(WINAPI) bool;
    pub fn enumerate(callback: *const fn (HWND, LPARAM) callconv(WINAPI) bool) bool {
        return EnumWindows(callback, 0);
    }
    extern "user32" fn IsIconic(hwnd: HWND) callconv(WINAPI) bool;
    pub fn minimized(handle: HWND) bool {
        return IsIconic(handle);
    }
    extern "user32" fn IsWindowVisible(hwnd: HWND) callconv(WINAPI) bool;
    pub fn visible(handle: HWND) bool {
        return IsWindowVisible(handle);
    }
    extern "user32" fn IsWindow(hwnd: HWND) callconv(WINAPI) bool;
    pub fn isWindow(handle: HWND) bool {
        return IsWindow(handle);
    }
    const Ancestor = enum(DWORD) { Parent = 1, Root, RootOwner };
    extern "user32" fn GetAncestor(hwnd: HWND, gaFlags: Ancestor) callconv(WINAPI) ?HWND;
    pub fn ancestor(handle: HWND, which: Ancestor) ?HWND {
        return GetAncestor(handle, which);
    }
    extern "user32" fn GetForegroundWindow() callconv(WINAPI) ?HWND;
    pub fn foreground() ?HWND {
        return GetForegroundWindow();
    }

    extern "user32" fn GetWindowThreadProcessId(hwnd: HWND, lpdwProcessId: *DWORD) callconv(WINAPI) DWORD;
    pub fn processId(handle: HWND) u32 {
        var val: u32 = undefined;
        _ = GetWindowThreadProcessId(handle, &val);
        return val;
    }

    const HMONITOR = *opaque {};
    const MONITORINFO = extern struct { cbSize: DWORD = @sizeOf(MONITORINFO), rcMonitor: RECT, rcWork: RECT, dwFlags: enum(DWORD) { Primary = 1, _ } };
    extern "user32" fn GetDesktopWindow() callconv(WINAPI) HWND;
    pub fn desktop() HWND {
        return GetDesktopWindow();
    }
    const MonitorFallback = enum(DWORD) { Null, Primary, Nearest };
    extern "user32" fn MonitorFromWindow(hwnd: HWND, dwFlags: MonitorFallback) callconv(WINAPI) ?HMONITOR;
    pub fn monitor(handle: HWND, comptime fallback: MonitorFallback) if (fallback == .Null) ?HMONITOR else HMONITOR {
        return MonitorFromWindow(handle, fallback);
    }
    extern "user32" fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(WINAPI) bool;
    pub fn monitorInfo(handle: HMONITOR) MONITORINFO {
        var info = MONITORINFO{ .rcWork = undefined, .dwFlags = undefined, .rcMonitor = undefined };
        assert(GetMonitorInfoW(handle, &info));
        return info;
    }

    /// Only includes the subset useful for this application
    const WindowLongPtr = union(enum(i32)) {
        Style: packed struct(win.LONG_PTR) {
            _: u16 = 0,
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
            __: u32 = 0,
        } = -16,
        /// Only includes the subset useful for this application
        ExStyle: packed struct(win.LONG_PTR) {
            _: u7 = 0,
            tool_window: bool = false,
            __: u19 = 0,
            no_activate: bool = false,
            ___: u36 = 0,
        } = -20
    };
    extern "user32" fn GetWindowLongPtrW(hwnd: HWND, nIndex: meta.Tag(WindowLongPtr)) callconv(WINAPI) win.LONG_PTR;
    pub fn longPtr(handle: HWND, comptime offset: meta.Tag(WindowLongPtr)) meta.TagPayload(WindowLongPtr, offset) {
        return @bitCast(GetWindowLongPtrW(handle, offset));
    }

    pub const CornerPreference = enum(DWORD) { Default, DoNotRound, Round, RoundSmall };
    pub const BorderColor = enum(COLORREF) {
        None = 0xFFFFFFFE,
        Default,
        _,
        pub fn Custom(fmt: [6]u8) std.fmt.ParseIntError!BorderColor {
            const r = fmt[0..2];
            const g = fmt[2..4];
            const b = fmt[4..6];
            return @enumFromInt(try std.fmt.parseInt(COLORREF, b ++ g ++ r, 16));
        }
    };

    /// Only includes the subset useful for this application
    pub const Attribute = union(enum(DWORD)) {
        Cloaked: BOOL = 14,
        CornerPreference: CornerPreference = 33,
        BorderColor: BorderColor,
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
        extern "user32" fn GetWindowRect(hwnd: HWND, lpRect: *RECT) callconv(WINAPI) bool;
        pub fn get(handle: HWND, client: bool) RECT {
            var val: RECT = undefined;
            assert(if (client) GetClientRect(handle, &val) else GetWindowRect(handle, &val));
            return val;
        }
    };
};
