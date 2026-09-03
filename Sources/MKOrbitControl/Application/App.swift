import AppKit
import SwiftUI
import Combine

// MARK: - Entry Point

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

    private let deviceState = DeviceState()
    private let commander = AntelopeCommander()
    private let presetManager = PresetManager()
    private let themeManager = ThemeManager()
    private var midiManager: MIDIManager?
    private var stateReader: AntelopeStateReader?

    private var hotkeyManager: HotkeyManager?
    private var hotkeyManagerObservable: HotkeyManagerObservable?
    private var settingsWindow: NSWindow?
    private var settingsCloseObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        commander.onStatusChange = { [weak deviceState] status in
            deviceState?.updateControlAvailability(status)
        }
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupConnectionRecovery()

        let reader = AntelopeStateReader(deviceState: deviceState)
        stateReader = reader
        deviceState.stateReader = reader
        reader.start()
        midiManager = MIDIManager(commander: commander, deviceState: deviceState)
        UpdateChecker.shared.checkOnLaunch()

        // Watch for mini mode changes to resize popover
        miniModeObserver = deviceState.$miniMode.sink { [weak self] mini in
            DispatchQueue.main.async {
                self?.popover?.contentSize = mini
                    ? OrbitControlLayout.miniSize
                    : OrbitControlLayout.fullSize
            }
        }

        // Set up HotkeyManager
        let hm = HotkeyManager(commander: commander, deviceState: deviceState)
        hotkeyManager = hm
        hotkeyManagerObservable = HotkeyManagerObservable(manager: hm)
        hm.registerAll()
    }

    // MARK: - Status Item

    private var iconObserver: AnyCancellable?
    private var miniModeObserver: AnyCancellable?

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        updateMenuBarIcon()

        // Watch for icon changes
        iconObserver = themeManager.$currentIcon.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuBarIcon() }
        }
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(
            systemSymbolName: themeManager.currentIcon.rawValue,
            accessibilityDescription: "MK-OrbitControl"
        )
        image?.isTemplate = true
        button.image = image
    }

    // MARK: - Popover

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = OrbitControlLayout.fullSize
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let menuBarView = MenuBarView(onOpenSettings: { [weak self] in
            self?.openSettings()
        })

        let contentView = NSHostingView(
            rootView: menuBarView
                .environmentObject(deviceState)
                .environmentObject(presetManager)
                .environmentObject(themeManager)
                .environment(\.commander, commander)
        )
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = contentView

        self.popover = popover
    }

    // MARK: - Event Monitor (dismiss on outside click)

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, let popover = self.popover, popover.isShown else { return }
            popover.performClose(nil)
        }
    }

    private func setupConnectionRecovery() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.recoverConnections()
            }
            workspaceObservers.append(observer)
        }
    }

    private func recoverConnections() {
        stateReader?.reconnect()
        commander.resetConnection()
    }

    // MARK: - Toggle Popover

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Settings Window

    func openSettings() {
        popover?.performClose(nil)

        // Switch to regular app so we can receive keyboard events in Settings
        NSApplication.shared.setActivationPolicy(.regular)

        if let win = settingsWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        guard let observable = hotkeyManagerObservable, let midiManager else { return }
        observable.refresh()

        let settingsView = SettingsView(
            hotkeyManager: observable,
            themeManager: themeManager,
            deviceState: deviceState,
            midiManager: midiManager
        )
        let hostingView = NSHostingView(rootView: settingsView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "MK-OrbitControl Settings"
        win.minSize = NSSize(width: 560, height: 420)
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // When Settings closes, go back to accessory mode (no dock icon)
        if let observer = settingsCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            NSApplication.shared.setActivationPolicy(.accessory)
            self?.settingsWindow = nil
            if let observer = self?.settingsCloseObserver {
                NotificationCenter.default.removeObserver(observer)
                self?.settingsCloseObserver = nil
            }
        }

        settingsWindow = win
    }

    // MARK: - Terminate

    func applicationWillTerminate(_ notification: Notification) {
        stateReader?.stop()
        hotkeyManager?.unregisterAll()
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = settingsCloseObserver { NotificationCenter.default.removeObserver(observer) }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        workspaceObservers.removeAll()
    }
}

// MARK: - Main

@main
final class AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
