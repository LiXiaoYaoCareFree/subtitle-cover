#if os(Windows)
import WinSDK

private let className = Array("SubtitleCoverWindow".utf16) + [0]
private let windowTitle = Array("Subtitle Cover (Windows)".utf16) + [0]
private let menuTitleOpacityUp = Array("透明度 +10%".utf16) + [0]
private let menuTitleOpacityDown = Array("透明度 -10%".utf16) + [0]
private let menuTitleExit = Array("退出".utf16) + [0]
private let menuTitleSettings = Array("打开设置".utf16) + [0]
private let helpTitle = Array("设置".utf16) + [0]
private let helpText = Array("双击右下角灰色手柄可打开设置菜单。".utf16) + [0]

private let defaultWidth: Int32 = 800
private let defaultHeight: Int32 = 30
private let minWidth: Int32 = 100
private let minHeight: Int32 = 30
private let resizeHandleSize: Int32 = 14

private let menuOpacityUpId: UINT_PTR = 1001
private let menuOpacityDownId: UINT_PTR = 1002
private let menuOpenSettingsId: UINT_PTR = 1003
private let menuExitId: UINT_PTR = 1099

private var currentOpacity: BYTE = 204 // 80%

@inline(__always)
private func lowWord(_ value: LPARAM) -> Int32 {
    Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: value & 0xFFFF)))
}

@inline(__always)
private func highWord(_ value: LPARAM) -> Int32 {
    Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: (value >> 16) & 0xFFFF)))
}

private func clientPoint(from lParam: LPARAM) -> POINT {
    POINT(x: lowWord(lParam), y: highWord(lParam))
}

private func isInResizeHandle(hwnd: HWND?, point: POINT) -> Bool {
    var rect = RECT()
    _ = GetClientRect(hwnd, &rect)
    let left = rect.right - resizeHandleSize - 2
    let top = rect.bottom - resizeHandleSize - 2
    return point.x >= left && point.y >= top
}

private func applyOpacity(hwnd: HWND?) {
    _ = SetLayeredWindowAttributes(hwnd, 0, currentOpacity, DWORD(LWA_ALPHA))
}

private func changeOpacity(hwnd: HWND?, deltaPercent: Int32) {
    let current = Int32(currentOpacity) * 100 / 255
    let nextPercent = max(10, min(100, current + deltaPercent))
    currentOpacity = BYTE(nextPercent * 255 / 100)
    applyOpacity(hwnd: hwnd)
}

private func showSettingsMenu(hwnd: HWND?, atScreenX x: Int32, screenY y: Int32) {
    let menu = CreatePopupMenu()
    _ = AppendMenuW(menu, UINT(MF_STRING), menuOpacityUpId, menuTitleOpacityUp)
    _ = AppendMenuW(menu, UINT(MF_STRING), menuOpacityDownId, menuTitleOpacityDown)
    _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
    _ = AppendMenuW(menu, UINT(MF_STRING), menuExitId, menuTitleExit)

    let command = TrackPopupMenu(
        menu,
        UINT(TPM_RETURNCMD | TPM_RIGHTBUTTON),
        x,
        y,
        0,
        hwnd,
        nil
    )
    _ = DestroyMenu(menu)

    switch UINT_PTR(command) {
    case menuOpacityUpId:
        changeOpacity(hwnd: hwnd, deltaPercent: 10)
    case menuOpacityDownId:
        changeOpacity(hwnd: hwnd, deltaPercent: -10)
    case menuExitId:
        _ = PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
    default:
        break
    }
}

private let wndProc: WNDPROC = { hwnd, msg, wParam, lParam in
    switch msg {
    case UINT(WM_CREATE):
        applyOpacity(hwnd: hwnd)
        return 0

    case UINT(WM_GETMINMAXINFO):
        if let raw = UnsafeMutableRawPointer(bitPattern: UInt(lParam)) {
            let info = raw.assumingMemoryBound(to: MINMAXINFO.self)
            info.pointee.ptMinTrackSize.x = minWidth
            info.pointee.ptMinTrackSize.y = minHeight
        }
        return 0

    case UINT(WM_NCHITTEST):
        var screenPoint = POINT(x: lowWord(lParam), y: highWord(lParam))
        _ = ScreenToClient(hwnd, &screenPoint)
        if isInResizeHandle(hwnd: hwnd, point: screenPoint) {
            return LRESULT(HTBOTTOMRIGHT)
        }
        return LRESULT(HTCLIENT)

    case UINT(WM_LBUTTONDOWN):
        let point = clientPoint(from: lParam)
        if !isInResizeHandle(hwnd: hwnd, point: point) {
            _ = ReleaseCapture()
            _ = SendMessageW(hwnd, UINT(WM_NCLBUTTONDOWN), WPARAM(HTCAPTION), 0)
        }
        return 0

    case UINT(WM_LBUTTONDBLCLK):
        let point = clientPoint(from: lParam)
        if isInResizeHandle(hwnd: hwnd, point: point) {
            var screenPoint = point
            _ = ClientToScreen(hwnd, &screenPoint)
            showSettingsMenu(hwnd: hwnd, atScreenX: screenPoint.x, screenY: screenPoint.y)
        }
        return 0

    case UINT(WM_RBUTTONUP):
        var point = clientPoint(from: lParam)
        _ = ClientToScreen(hwnd, &point)
        showSettingsMenu(hwnd: hwnd, atScreenX: point.x, screenY: point.y)
        return 0

    case UINT(WM_COMMAND):
        let cmd = UINT_PTR(wParam & 0xFFFF)
        if cmd == menuOpenSettingsId {
            _ = MessageBoxW(hwnd, helpText, helpTitle, UINT(MB_OK))
            return 0
        }
        return DefWindowProcW(hwnd, msg, wParam, lParam)

    case UINT(WM_PAINT):
        var ps = PAINTSTRUCT()
        let hdc = BeginPaint(hwnd, &ps)

        var rect = RECT()
        _ = GetClientRect(hwnd, &rect)
        _ = FillRect(hdc, &rect, HBRUSH(GetStockObject(BLACK_BRUSH)))

        var handleRect = RECT(
            left: rect.right - resizeHandleSize - 2,
            top: rect.bottom - resizeHandleSize - 2,
            right: rect.right - 2,
            bottom: rect.bottom - 2
        )
        _ = FillRect(hdc, &handleRect, HBRUSH(GetStockObject(GRAY_BRUSH)))

        _ = EndPaint(hwnd, &ps)
        return 0

    case UINT(WM_DESTROY):
        PostQuitMessage(0)
        return 0

    default:
        return DefWindowProcW(hwnd, msg, wParam, lParam)
    }
}

private func run() {
    let instance = GetModuleHandleW(nil)
    var wc = WNDCLASSW()
    wc.style = UINT(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS)
    wc.lpfnWndProc = wndProc
    wc.hInstance = instance
    wc.hCursor = LoadCursorW(nil, IDC_ARROW)
    wc.hbrBackground = HBRUSH(GetStockObject(BLACK_BRUSH))
    wc.lpszClassName = className
    _ = RegisterClassW(&wc)

    let exStyle = DWORD(WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW)
    let style = DWORD(WS_POPUP | WS_VISIBLE)
    let hwnd = CreateWindowExW(
        exStyle,
        className,
        windowTitle,
        style,
        120,
        120,
        defaultWidth,
        defaultHeight,
        nil,
        nil,
        instance,
        nil
    )

    guard hwnd != nil else { return }

    applyOpacity(hwnd: hwnd)
    _ = ShowWindow(hwnd, INT32(SW_SHOW))
    _ = UpdateWindow(hwnd)

    var msg = MSG()
    while GetMessageW(&msg, nil, 0, 0) > 0 {
        _ = TranslateMessage(&msg)
        _ = DispatchMessageW(&msg)
    }
}

run()
#else
print("SubtitleCoverWindows 仅在 Windows 平台可运行。")
#endif
