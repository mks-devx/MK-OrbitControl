import AppKit
import SwiftUI

class FloatingWindowController {
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
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 434),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
}
