const std = @import("std");
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
pub const WINEVENTPROC = *const fn (HWINEVENTHOOK, DWORD, ?HWND, LONG, LONG, DWORD, DWORD) callconv(WINAPI) void;

pub const WinEvent = enum(DWORD) {
    Foreground = 0x0003,

    Create = 0x8000,
    Destroy = 0x8001,

    Cloak = 0x8017,
    Uncloak = 0x8018,

    Minimize = 0x0016,
    Restore = 0x0017,
};

pub const WinEventHook = struct {
    const WINEVENT_OUTOFCONTEXT = 0x0;
    const WINEVENT_SKIPOWNPROCESS = 0x1;
    range: [2]WinEvent,
    callback: WINEVENTPROC,

    extern "user32" fn SetWinEventHook(eventMin: WinEvent, eventMax: WinEvent, hmodWinEventProc: ?win.HMODULE, pfnWinEventProc: WINEVENTPROC, idProcess: DWORD, idThread: DWORD, dwFlags: DWORD) callconv(WINAPI) HWINEVENTHOOK;
    pub fn init(comptime self: *const WinEventHook) HWINEVENTHOOK {
        const min = self.range[0];
        const max = self.range[1];
        if (@intFromEnum(min) > @intFromEnum(max))
            @compileError("Invalid WinEventHook range: " ++ @tagName(min) ++ " > " ++ @tagName(max));
        return SetWinEventHook(min, max, null, self.callback, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    }

    extern "user32" fn UnhookWinEvent(hWinEventHook: HWINEVENTHOOK) callconv(WINAPI) bool;
    pub fn deinit(handle: HWINEVENTHOOK) void {
        assert(UnhookWinEvent(handle));
    }
};

pub const PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
pub extern "kernel32" fn OpenProcess(dwDesiredAccess: DWORD, bInheritHandle: bool, dwProcessId: DWORD) callconv(WINAPI) ?win.HANDLE;

pub const WM_QUIT = 0x0012;
pub extern "user32" fn PostThreadMessageW(idThread: DWORD, Msg: DWORD, wParam: WPARAM, lParam: LPARAM) callconv(WINAPI) bool;

pub const MSG = extern struct { hwnd: ?HWND, message: DWORD, wParam: WPARAM, lParam: LPARAM, time: u32, pt: win.POINT };
extern "user32" fn GetMessageW(lpMsg: *MSG, hwnd: ?HWND, wMsgFilterMin: DWORD, wMsgFilterMax: DWORD) callconv(WINAPI) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(WINAPI) bool;
extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(WINAPI) win.LRESULT;
pub fn getMessage(msgPtr: *MSG) bool {
    return switch (GetMessageW(msgPtr, null, 0, 0)) {
        win.FALSE => false,
        win.TRUE => {
            assert(TranslateMessage(msgPtr));
            _ = DispatchMessageW(msgPtr);
            return true;
        },
        -1 => std.debug.panic("Failed to get next message in the message loop.", .{}),
        else => unreachable,
    };
}

pub const window = struct {
    pub extern "user32" fn EnumWindows(lpEnumFunc: *const fn (HWND, LPARAM) callconv(WINAPI) bool, lParam: LPARAM) callconv(WINAPI) bool;
    pub extern "user32" fn IsIconic(hwnd: HWND) callconv(WINAPI) bool;
    pub extern "user32" fn IsWindowVisible(hwnd: HWND) callconv(WINAPI) bool;
    pub extern "user32" fn GetWindowThreadProcessId(hwnd: HWND, lpdwProcessId: *DWORD) callconv(WINAPI) DWORD;

    const HMONITOR = *opaque {};
    const MONITORINFO = extern struct { cbSize: DWORD, rcMonitor: RECT, rcWork: RECT, dwFlags: enum(DWORD) { Primary = 1, _ } };
    extern "user32" fn GetDesktopWindow() callconv(WINAPI) HWND;
    extern "user32" fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(WINAPI) bool;
    extern "user32" fn MonitorFromWindow(hwnd: HWND, dwFlags: enum(DWORD) { Null, Primary, Nearest }) callconv(WINAPI) ?HMONITOR;
    pub fn monitorSize() RECT {
        var info = MONITORINFO{ .cbSize = @sizeOf(MONITORINFO), .rcWork = undefined, .dwFlags = undefined, .rcMonitor = undefined };
        assert(GetMonitorInfoW(MonitorFromWindow(GetDesktopWindow(), .Null).?, &info));
        return info.rcWork;
    }

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
        pub const CloakedReason = enum(DWORD) { App = 1, Shell = 2, Inherited = 4 };
        CornerPreference: *const CornerPreference = 33,
        BorderColor: *const BorderColor = 34,
        Cloaked: *BOOL = 14,
        // zig fmt: off
        extern "dwmapi" fn DwmSetWindowAttribute(hwnd: HWND, dwAttribute: DWORD, pvAttribute: win.LPCVOID, cbAttribute: DWORD) callconv(WINAPI) HRESULT;
        pub fn set(handle: HWND, attribute: Attribute) void {
            switch (attribute) {
                inline else => |ptr| assert(
                     DwmSetWindowAttribute(
                        handle,
                        @intFromEnum(attribute),
                        ptr,
                        @sizeOf(@typeInfo(@TypeOf(ptr)).Pointer.child)
                    ) == win.S_OK
                )
            }
        }
        extern "dwmapi" fn DwmGetWindowAttribute(hwnd: HWND, dwAttribute: DWORD, pvAttribute: win.PVOID, cbAttribute: DWORD) callconv(WINAPI) HRESULT;
        pub fn get(handle: HWND, attribute: Attribute) void {
            switch (attribute) {
                inline else => |ptr| assert(
                    DwmGetWindowAttribute(
                        handle,
                        @intFromEnum(attribute),
                        @constCast(ptr),
                        @sizeOf(@typeInfo(@TypeOf(ptr)).Pointer.child)
                    ) == win.S_OK
                )
            }
        }
        // zig fmt: on
    };
    pub const rect = struct {
        const Flags = enum(DWORD) {
            AsyncWindowPos = 0x4000,
            DeferErase = 0x2000,
            // DrawFrame = 0x0020,
            FrameChanged = 0x0020,
            HideWindow = 0x0080,
            NoActivate = 0x0010,
            NoCopyBits = 0x0100,
            NoMove = 0x0002,
            // NoOwnerZOrder = 0x0200,
            NoRedraw = 0x0008,
            NoReposition = 0x0200,
            NoSendChanging = 0x0400,
            NoSize = 0x0001,
            NoZorder = 0x0004,
            ShowWindow = 0x0040,
            _,
            pub fn init(comptime flags: []const Flags) Flags {
                comptime var acc: DWORD = 0;
                inline for (flags) |f| acc &= @intFromEnum(f);
                const flag = acc;
                return @enumFromInt(flag);
            }
        };
        extern "user32" fn SetWindowPos(hwnd: HWND, hWndInsertAfter: ?HWND, X: i32, Y: i32, cx: i32, cy: i32, uFlags: Flags) callconv(WINAPI) bool;
        pub fn set(handle: HWND, pos: RECT, comptime flags: []const Flags) void {
            assert(SetWindowPos(handle, null, pos.left, pos.top, pos.right, pos.bottom, Flags.init(flags)));
        }
        extern "user32" fn GetClientRect(hwnd: HWND, lpRect: *RECT) callconv(WINAPI) bool;
        pub fn get(handle: HWND, ptr: *RECT) void {
            assert(GetClientRect(handle, ptr));
        }
    };
};
