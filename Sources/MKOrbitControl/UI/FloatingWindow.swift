import AppKit
import SwiftUI

final class FloatingWindowController: NSObject, NSWindowDelegate {
    static let shared = FloatingWindowController()

    private var window: NSPanel?
    private var isVisible = false

    func toggle(deviceState: DeviceState, presetManager: PresetManager, themeManager: ThemeManager, commander: AntelopeCommander, onOpenSettings: @escaping () -> Void) {
        if isVisible {
            hide()
        } else {
            show(deviceState: deviceState, presetManager: presetManager, themeManager: themeManager, commander: commander, onOpenSettings: onOpenSettings)
        }
    }

    func show(deviceState: DeviceState, presetManager: PresetManager, themeManager: ThemeManager, commander: AntelopeCommander, onOpenSettings: @escaping () -> Void) {
        if let win = window {
            win.orderFrontRegardless()
            isVisible = true
            return
        }

        let view = MenuBarView(onOpenSettings: onOpenSettings)
            .environmentObject(deviceState)
            .environmentObject(presetManager)
            .environmentObject(themeManager)
            .environment(\.commander, commander)

        let hosting = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: OrbitControlLayout.fullSize),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "MK-OrbitControl"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = hosting
        panel.center()
        panel.orderFrontRegardless()

        window = panel
        isVisible = true
    }

    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    var visible: Bool { isVisible }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        isVisible = false
        window = nil
    }
}
