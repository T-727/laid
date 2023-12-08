const std = @import("std");
const meta = std.meta;
const win = std.os.windows;
const WINAPI = win.WINAPI;
const DWORD = win.DWORD;
const LONG = win.LONG;
const HWND = win.HWND;
const BOOL = win.BOOL;
const HRESULT = win.HRESULT;
const COLORREF = DWORD;
const RECT = win.RECT;
const LPARAM = win.LPARAM;
const WPARAM = win.WPARAM;
const HANDLE = win.HANDLE;
const GetLastError = win.kernel32.GetLastError;
const unexpectedError = win.unexpectedError;

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
    extern "user32" fn SetWinEventHook(eventMin: WinEvent, eventMax: WinEvent, hmodWinEventProc: ?win.HMODULE, pfnWinEventProc: WINEVENTPROC, idProcess: DWORD, idThread: DWORD, dwFlags: WinEventHookFlags) callconv(WINAPI) ?HWINEVENTHOOK;
    pub fn init(comptime range: struct { WinEvent, WinEvent }, callback: WINEVENTPROC, flags: WinEventHookFlags) !HWINEVENTHOOK {
        comptime std.debug.assert(@intFromEnum(range[0]) <= @intFromEnum(range[1]));
        const handle = SetWinEventHook(range[0], range[1], null, callback, 0, 0, flags);
        return handle orelse switch (GetLastError()) {
            .INVALID_HOOK_FILTER => unreachable,
            else => |err| unexpectedError(err),
        };
    }
    extern "user32" fn UnhookWinEvent(hWinEventHook: HWINEVENTHOOK) callconv(WINAPI) bool;
    pub fn deinit(handle: HWINEVENTHOOK) !void {
        if (!UnhookWinEvent(handle)) return switch (GetLastError()) {
            .INVALID_HANDLE => error.InvalidHandle,
            else => |err| unexpectedError(err),
        };
    }
};

// remove after zig 0.12
pub fn HRESULT_CODE(hr: HRESULT) win.Win32Error {
    return @enumFromInt(hr & 0xFFFF);
}

const CoInitFlags = packed struct(DWORD) {
    multi_threaded: bool = false,
    disable_ole1dde: bool = false,
    speed_over_memory: bool = false,
    _: u29 = 0,
};
extern "ole32" fn CoInitializeEx(pvReserved: ?win.LPVOID, dwCoInit: CoInitFlags) callconv(WINAPI) enum(HRESULT) {
    True = win.S_OK,
    False = win.S_FALSE,
    InvalidArgument = win.E_INVALIDARG,
    OutOfMemory = win.E_OUTOFMEMORY,
    RpcChangedMode = @truncate(0x80010106),
    UnexpectedError = win.E_UNEXPECTED,
};
extern "ole32" fn CoUninitialize() callconv(WINAPI) void;
pub fn init(flags: CoInitFlags) !bool {
    return switch (CoInitializeEx(null, flags)) {
        .True => true,
        .False => false,
        .InvalidArgument => error.InvalidArgument,
        .OutOfMemory => error.OutOfMemory,
        .RpcChangedMode => error.RpcChangedMode,
        .UnexpectedError => |err| unexpectedError(HRESULT_CODE(@intFromEnum(err))),
    };
}
pub fn deinit() void {
    CoUninitialize();
}

pub const process = struct {
    /// Only includes the subset useful for this application
    const ProcessAccessRights = enum(DWORD) { ProcessQueryLimitedInformation = 0x1000 };
    extern "kernel32" fn OpenProcess(dwDesiredAccess: ProcessAccessRights, bInheritHandle: bool, dwProcessId: DWORD) callconv(WINAPI) ?HANDLE;
    /// Caller must close the handle
    pub fn open(id: u32, rights: ProcessAccessRights) !HANDLE {
        return OpenProcess(rights, false, id) orelse unexpectedError(GetLastError());
    }
    pub fn path(handle: HANDLE, buf: [:0]u16) !u32 {
        const len = win.kernel32.K32GetProcessImageFileNameW(handle, buf.ptr, @truncate(buf.len));
        return if (len != 0) len else unexpectedError(GetLastError());
    }
    /// Only includes the subset useful for this application
    const TokenAccessRights = enum(DWORD) { Query = 0x0008 };
    extern "advapi32" fn OpenProcessToken(ProcessHandle: HANDLE, DesiredAccess: TokenAccessRights, TokenHandle: *HANDLE) callconv(WINAPI) bool;
    /// Caller must close the handle
    pub fn token(handle: HANDLE, access: TokenAccessRights) !HANDLE {
        var val: HANDLE = undefined;
        return if (OpenProcessToken(handle, access, &val)) val else unexpectedError(GetLastError());
    }
    /// Psuedo-handle. Does not need to be closed
    pub fn currentProcessToken() HANDLE {
        return @ptrFromInt(@as(usize, @truncate(-4)));
    }
    /// Only includes the subset useful for this application
    const TokenInformationClass = union(enum(DWORD)) {
        Elevation: extern struct { TokenIsElevated: DWORD } = 20,
    };
    extern "advapi32" fn GetTokenInformation(TokenHandle: HANDLE, TokenInformationClass: meta.Tag(TokenInformationClass), TokenInformation: win.LPVOID, TokenInformationLength: DWORD, ReturnLength: *DWORD) bool;
    pub fn tokenInfo(handle: HANDLE, comptime info: meta.Tag(TokenInformationClass)) !meta.TagPayload(TokenInformationClass, info) {
        var val: meta.TagPayload(TokenInformationClass, info) = undefined;
        var len: DWORD = undefined;
        if (!GetTokenInformation(handle, info, &val, @sizeOf(@TypeOf(val)), &len)) return unexpectedError(GetLastError());
        if (len != @sizeOf(@TypeOf(val))) return error.ReturnSizeDoesNotMatch;
        return val;
    }
};

pub const message = struct {
    /// Only includes the subset useful for this application
    const MessageId = enum(DWORD) { Null, Quit = 0x0012, _ };
    pub const MSG = extern struct { hwnd: ?HWND, message: message.MessageId, wParam: WPARAM, lParam: LPARAM, time: u32, pt: win.POINT };

    extern "user32" fn GetMessageW(lpMsg: *MSG, hwnd: ?HWND, wMsgFilterMin: MessageId, wMsgFilterMax: MessageId) callconv(WINAPI) enum(BOOL) { Error = -1, False, True };
    pub fn get(buf: *MSG) !bool {
        return switch (GetMessageW(buf, null, .Null, .Null)) {
            .True => true,
            .False => false,
            .Error => unexpectedError(GetLastError()),
        };
    }
    extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(WINAPI) bool;
    pub fn translate(msg: *const MSG) !void {
        if (!TranslateMessage(msg)) return error.UnexpectedError;
    }
    extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(WINAPI) win.LRESULT;
    pub fn dispatch(msg: *const MSG) void {
        _ = DispatchMessageW(msg);
    }
    extern "user32" fn PostThreadMessageW(idThread: DWORD, Msg: MessageId, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) bool;
    pub fn post(thread: u32, msg: MessageId) !void {
        if (!PostThreadMessageW(thread, msg, 0, 0)) return unexpectedError(GetLastError());
    }
};

pub const window = struct {
    extern "user32" fn EnumWindows(lpEnumFunc: *const fn (HWND, LPARAM) callconv(WINAPI) bool, lParam: LPARAM) callconv(WINAPI) bool;
    pub fn enumerate(callback: *const fn (HWND, LPARAM) callconv(WINAPI) bool) !void {
        if (!EnumWindows(callback, 0)) return unexpectedError(GetLastError());
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
    pub fn processId(handle: HWND) !u32 {
        var val: u32 = undefined;
        _ = GetWindowThreadProcessId(handle, &val);
        return if (val != 0) val else unexpectedError(GetLastError());
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
    pub fn monitorInfo(handle: HMONITOR) !MONITORINFO {
        var info = MONITORINFO{ .rcWork = undefined, .dwFlags = undefined, .rcMonitor = undefined };
        return if (GetMonitorInfoW(handle, &info)) info else error.UnexpectedError;
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
    pub fn longPtr(handle: HWND, comptime offset: meta.Tag(WindowLongPtr)) !meta.TagPayload(WindowLongPtr, offset) {
        const long = GetWindowLongPtrW(handle, offset);
        return if (long != 0) @bitCast(long) else unexpectedError(GetLastError());
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
        extern "dwmapi" fn DwmSetWindowAttribute(hwnd: HWND, dwAttribute: meta.Tag(Attribute), pvAttribute: win.LPCVOID, cbAttribute: DWORD) callconv(WINAPI) HRESULT;
        pub fn set(handle: HWND, attribute: Attribute) !void {
            return switch (attribute) {
                inline else => |val| switch (HRESULT_CODE(DwmSetWindowAttribute(handle, attribute, &val, @sizeOf(@TypeOf(val))))) {
                    .SUCCESS => {},
                    .INVALID_HANDLE => error.InvalidHandle,
                    else => |err| unexpectedError(err),
                }
            };
        }
        extern "dwmapi" fn DwmGetWindowAttribute(hwnd: HWND, dwAttribute: meta.Tag(Attribute), pvAttribute: win.PVOID, cbAttribute: DWORD) callconv(WINAPI) HRESULT;
        pub fn get(handle: HWND, comptime attribute: meta.Tag(Attribute)) !meta.TagPayload(Attribute, attribute) {
            var val: meta.TagPayload(Attribute, attribute) = undefined;
            return switch (HRESULT_CODE(DwmGetWindowAttribute(handle, attribute, &val, @sizeOf(@TypeOf(val))))) {
                .SUCCESS => val,
                .INVALID_HANDLE => error.InvalidHandle,
                else => |err| unexpectedError(err),
            };
        }
    };
    pub const rect = struct {
        pub const SetWindowPosFlags = packed struct(DWORD) {
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
        pub fn set(handle: HWND, pos: RECT, flags: SetWindowPosFlags) !void {
            if (!SetWindowPos(handle, null, pos.left, pos.top, pos.right, pos.bottom, flags)) return switch (GetLastError()) {
                .ACCESS_DENIED => error.AccessDenied,
                else => |err| unexpectedError(err),
            };
        }
        extern "user32" fn GetClientRect(hwnd: HWND, lpRect: *RECT) callconv(WINAPI) bool;
        extern "user32" fn GetWindowRect(hwnd: HWND, lpRect: *RECT) callconv(WINAPI) bool;
        pub fn get(handle: HWND, comptime client: bool) !RECT {
            var val: RECT = undefined;
            return if (if (client) GetClientRect(handle, &val) else GetWindowRect(handle, &val)) val else unexpectedError(GetLastError());
        }
    };
};
