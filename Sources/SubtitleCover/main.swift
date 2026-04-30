import AppKit

private enum Constants {
    static let defaultSize = NSSize(width: 800, height: 30)
    static let minSize = NSSize(width: 100, height: 30)
    static let alphaRange: ClosedRange<CGFloat> = 0.1...1.0
}

private struct OverlaySettings: Codable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let defaults = OverlaySettings(
        x: 120,
        y: 120,
        width: Constants.defaultSize.width,
        height: Constants.defaultSize.height,
        red: 0.0,
        green: 0.0,
        blue: 0.0,
        alpha: 0.8
    )
}

private final class SettingsStore {
    private let defaultsKey = "subtitle_cover.overlay_settings"
    private let defaults = UserDefaults.standard

    func load() -> OverlaySettings {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let settings = try? JSONDecoder().decode(OverlaySettings.self, from: data)
        else {
            return OverlaySettings.defaults
        }
        return settings
    }

    func save(_ settings: OverlaySettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

private protocol OverlayViewDelegate: AnyObject {
    func overlayViewDidRequestMenu(_ view: OverlayView, event: NSEvent)
    func overlayViewDidRequestSettings(_ view: OverlayView)
    func overlayViewDidChangeFrame(_ view: OverlayView)
    func overlayViewDidRequestBecomeKey(_ view: OverlayView)
}

private final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?

    private let resizeHandleSize: CGFloat = 14
    private var isResizing = false
    private var isSelecting = false
    private var dragStartScreenPoint: NSPoint = .zero
    private var dragStartWindowFrame: NSRect = .zero
    private var selectionAnchorScreen: NSPoint = .zero
    private var fillColor = NSColor.black.withAlphaComponent(0.8)

    override var acceptsFirstResponder: Bool { true }

    var overlayColor: NSColor {
        get { fillColor }
        set {
            fillColor = newValue
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fillColor.setFill()
        dirtyRect.fill()

        let handleRect = NSRect(
            x: bounds.maxX - resizeHandleSize - 2,
            y: 2,
            width: resizeHandleSize,
            height: resizeHandleSize
        )
        NSColor.gray.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()

        NSColor.white.withAlphaComponent(0.7).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: handleRect.minX + 3, y: handleRect.minY + 3))
        path.line(to: NSPoint(x: handleRect.maxX - 3, y: handleRect.maxY - 3))
        path.move(to: NSPoint(x: handleRect.minX + 6, y: handleRect.minY + 3))
        path.line(to: NSPoint(x: handleRect.maxX - 3, y: handleRect.maxY - 6))
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.overlayViewDidRequestBecomeKey(self)
        guard let window else { return }

        let location = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, isInResizeHandle(location) {
            delegate?.overlayViewDidRequestSettings(self)
            return
        }

        dragStartWindowFrame = window.frame
        dragStartScreenPoint = event.locationInWindowInScreen(window: window)
        selectionAnchorScreen = dragStartScreenPoint

        if event.modifierFlags.contains(.control) {
            isSelecting = true
            isResizing = false
            return
        }

        isResizing = isInResizeHandle(location)
        isSelecting = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let now = event.locationInWindowInScreen(window: window)
        if isSelecting {
            let frame = NSRect(
                x: min(selectionAnchorScreen.x, now.x),
                y: min(selectionAnchorScreen.y, now.y),
                width: abs(now.x - selectionAnchorScreen.x),
                height: abs(now.y - selectionAnchorScreen.y)
            )
            if frame.width >= Constants.minSize.width, frame.height >= Constants.minSize.height {
                window.setFrame(frame, display: true)
                delegate?.overlayViewDidChangeFrame(self)
            }
            return
        }

        let deltaX = now.x - dragStartScreenPoint.x
        let deltaY = now.y - dragStartScreenPoint.y

        if isResizing {
            var newFrame = dragStartWindowFrame
            newFrame.size.width = max(Constants.minSize.width, dragStartWindowFrame.size.width + deltaX)
            newFrame.size.height = max(Constants.minSize.height, dragStartWindowFrame.size.height + deltaY)
            window.setFrame(newFrame, display: true)
            delegate?.overlayViewDidChangeFrame(self)
            return
        }

        var newFrame = dragStartWindowFrame
        newFrame.origin.x += deltaX
        newFrame.origin.y += deltaY
        window.setFrame(newFrame, display: true)
        delegate?.overlayViewDidChangeFrame(self)
    }

    override func mouseUp(with event: NSEvent) {
        isResizing = false
        isSelecting = false
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayViewDidRequestMenu(self, event: event)
    }

    private func isInResizeHandle(_ point: NSPoint) -> Bool {
        let rect = NSRect(
            x: bounds.maxX - resizeHandleSize - 4,
            y: 0,
            width: resizeHandleSize + 4,
            height: resizeHandleSize + 4
        )
        return rect.contains(point)
    }
}

private extension NSEvent {
    func locationInWindowInScreen(window: NSWindow) -> NSPoint {
        let localPoint = locationInWindow
        return window.convertPoint(toScreen: localPoint)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, OverlayViewDelegate {
    private let settingsStore = SettingsStore()
    private var settings = OverlaySettings.defaults
    private var window: NSPanel!
    private var overlayView: OverlayView!
    private var colorPanelTarget: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = settingsStore.load()
        createWindow()
        applySettings()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistCurrentSettings()
    }

    private func createWindow() {
        let contentRect = NSRect(
            x: settings.x,
            y: settings.y,
            width: max(Constants.minSize.width, settings.width),
            height: max(Constants.minSize.height, settings.height)
        )

        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let view = OverlayView(frame: panel.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        view.delegate = self
        panel.contentView = view

        window = panel
        overlayView = view
    }

    private func applySettings() {
        let color = NSColor(
            calibratedRed: settings.red,
            green: settings.green,
            blue: settings.blue,
            alpha: settings.alpha.clamped(to: Constants.alphaRange)
        )
        overlayView.overlayColor = color
    }

    private func updateColor(_ color: NSColor) {
        let converted = color.usingColorSpace(.deviceRGB) ?? NSColor.black
        settings.red = converted.redComponent
        settings.green = converted.greenComponent
        settings.blue = converted.blueComponent
        settings.alpha = converted.alphaComponent.clamped(to: Constants.alphaRange)
        overlayView.overlayColor = converted.withAlphaComponent(settings.alpha)
    }

    private func persistCurrentSettings() {
        settings.x = window.frame.origin.x
        settings.y = window.frame.origin.y
        settings.width = window.frame.size.width
        settings.height = window.frame.size.height
        settingsStore.save(settings)
    }

    private func setAlpha(_ alpha: CGFloat) {
        settings.alpha = alpha.clamped(to: Constants.alphaRange)
        let color = NSColor(
            calibratedRed: settings.red,
            green: settings.green,
            blue: settings.blue,
            alpha: settings.alpha
        )
        overlayView.overlayColor = color
    }

    @objc private func menuOpenSettings() {
        let alert = NSAlert()
        alert.messageText = "遮挡设置"
        alert.informativeText = "可在此调整透明度与颜色。"

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 96))
        let valueLabel = NSTextField(labelWithString: "透明度：\(Int(settings.alpha * 100))%")
        valueLabel.frame = NSRect(x: 0, y: 70, width: 280, height: 18)

        let slider = NSSlider(value: settings.alpha * 100, minValue: 10, maxValue: 100, target: nil, action: nil)
        slider.frame = NSRect(x: 0, y: 44, width: 280, height: 24)
        slider.numberOfTickMarks = 10
        slider.allowsTickMarkValuesOnly = false

        let colorLabel = NSTextField(labelWithString: "颜色：")
        colorLabel.frame = NSRect(x: 0, y: 20, width: 80, height: 18)

        let colorSegment = NSSegmentedControl(labels: ["黑色", "白色"], trackingMode: .selectOne, target: nil, action: nil)
        colorSegment.frame = NSRect(x: 58, y: 16, width: 160, height: 24)
        let isWhite = settings.red > 0.5 && settings.green > 0.5 && settings.blue > 0.5
        colorSegment.selectedSegment = isWhite ? 1 : 0

        container.addSubview(valueLabel)
        container.addSubview(slider)
        container.addSubview(colorLabel)
        container.addSubview(colorSegment)
        alert.accessoryView = container

        alert.addButton(withTitle: "应用并保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "退出程序")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if colorSegment.selectedSegment == 1 {
                settings.red = 1.0
                settings.green = 1.0
                settings.blue = 1.0
            } else {
                settings.red = 0.0
                settings.green = 0.0
                settings.blue = 0.0
            }
            let newAlpha = CGFloat(slider.doubleValue / 100.0)
            setAlpha(newAlpha)
            persistCurrentSettings()
        } else if response == .alertThirdButtonReturn {
            persistCurrentSettings()
            NSApp.terminate(nil)
        }
    }

    @objc private func menuPickColor() {
        let panel = NSColorPanel.shared
        panel.color = NSColor(
            calibratedRed: settings.red,
            green: settings.green,
            blue: settings.blue,
            alpha: settings.alpha
        )

        if let observer = colorPanelTarget {
            NotificationCenter.default.removeObserver(observer)
        }
        colorPanelTarget = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.updateColor(panel.color)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func menuResetSize() {
        var frame = window.frame
        frame.size = Constants.defaultSize
        window.setFrame(frame, display: true, animate: true)
        overlayView.needsDisplay = true
        persistCurrentSettings()
    }

    @objc private func menuCenterHorizontally() {
        guard let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        var frame = window.frame
        frame.origin.x = screenFrame.midX - (frame.size.width / 2)
        window.setFrameOrigin(frame.origin)
        persistCurrentSettings()
    }

    @objc private func menuSaveSettings() {
        persistCurrentSettings()
    }

    @objc private func menuHelp() {
        let alert = NSAlert()
        alert.messageText = "Subtitle Cover 快捷说明"
        alert.informativeText = """
        双击右下角灰色手柄 : 打开设置（透明度）
        Control + 拖拽 : 框选新的遮盖区域
        右键菜单 : 颜色、重置、居中、保存、退出
        """
        alert.runModal()
    }

    @objc private func menuExit() {
        persistCurrentSettings()
        NSApp.terminate(nil)
    }

    // MARK: OverlayViewDelegate

    func overlayViewDidRequestMenu(_ view: OverlayView, event: NSEvent) {
        let menu = NSMenu()

        menu.addItem(withTitle: "设置", action: #selector(menuOpenSettings), keyEquivalent: "")
        menu.addItem(withTitle: "更改颜色", action: #selector(menuPickColor), keyEquivalent: "")
        menu.addItem(withTitle: "重置大小", action: #selector(menuResetSize), keyEquivalent: "")
        menu.addItem(withTitle: "窗口居中", action: #selector(menuCenterHorizontally), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "保存设置", action: #selector(menuSaveSettings), keyEquivalent: "")
        menu.addItem(withTitle: "帮助", action: #selector(menuHelp), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(menuExit), keyEquivalent: "")

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func overlayViewDidRequestSettings(_ view: OverlayView) {
        menuOpenSettings()
    }

    func overlayViewDidChangeFrame(_ view: OverlayView) {
        persistCurrentSettings()
    }

    func overlayViewDidRequestBecomeKey(_ view: OverlayView) {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
