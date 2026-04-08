import SwiftUI
import ServiceManagement

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var hotkeyManager: HotkeyManagerObservable
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var deviceState: DeviceState

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar area
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    appearanceSection
                    generalSection
                    hotkeysSection
                    aboutSection
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APPEARANCE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                // Theme picker
                HStack {
                    Text("Theme")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { themeManager.currentTheme.id },
                        set: { id in
                            if let theme = allThemes.first(where: { $0.id == id }) {
                                themeManager.setTheme(theme)
                            }
                        }
                    )) {
                        ForEach(allThemes) { theme in
                            HStack(spacing: 6) {
                                Circle().fill(theme.accent).frame(width: 8, height: 8)
                                Text(theme.name)
                            }.tag(theme.id)
                        }
                    }
                    .frame(width: 160)
                }

                // Icon picker
                HStack {
                    Text("Menu Bar Icon")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { themeManager.currentIcon.rawValue },
                        set: { id in
                            if let icon = MenuBarIcon(rawValue: id) {
                                themeManager.setIcon(icon)
                            }
                        }
                    )) {
                        ForEach(MenuBarIcon.allCases) { icon in
                            HStack(spacing: 6) {
                                Image(systemName: icon.rawValue)
                                    .frame(width: 16)
                                Text(icon.displayName)
                            }.tag(icon.rawValue)
                        }
                    }
                    .frame(width: 160)
                }

                // Font picker
                HStack {
                    Text("Font")
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { themeManager.currentFont.rawValue },
                        set: { id in
                            if let font = AppFont(rawValue: id) {
                                themeManager.setFont(font)
                            }
                        }
                    )) {
                        ForEach(AppFont.allCases) { font in
                            Text(font.displayName).tag(font.rawValue)
                        }
                    }
                    .frame(width: 160)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("General")

            settingsRow {
                Text("Launch at Login")
                    .font(.system(size: 13))
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            settingsRow {
                Text("Night Mode Volume Cap")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $deviceState.nightModeMax) {
                    Text("-20 dB").tag(20)
                    Text("-30 dB").tag(30)
                    Text("-40 dB").tag(40)
                    Text("-50 dB").tag(50)
                    Text("-60 dB").tag(60)
                }
                .frame(width: 100)
            }
        }
    }

    // MARK: - Hotkeys

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Hotkeys")

            if !hotkeyManager.hasAccessibility {
                accessibilityWarning
            }

            VStack(spacing: 1) {
                hotkeyGroup(label: "MON A", actions: (.volumeUpMonA, .volumeDownMonA, .muteMonA))
                Divider().padding(.vertical, 2)
                hotkeyGroup(label: "MON B", actions: (.volumeUpMonB, .volumeDownMonB, .muteMonB))
                Divider().padding(.vertical, 2)
                hotkeyGroup(label: "HP 1",  actions: (.volumeUpHP1, .volumeDownHP1, .muteHP1))
                Divider().padding(.vertical, 2)
                hotkeyGroup(label: "HP 2",  actions: (.volumeUpHP2, .volumeDownHP2, .muteHP2))
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
    }

    private func hotkeyGroup(
        label: String,
        actions: (up: HotkeyAction, down: HotkeyAction, mute: HotkeyAction)
    ) -> some View {
        VStack(spacing: 0) {
            hotkeyRow(channelLabel: label, actionLabel: "Volume Up", action: actions.up)
            Divider().padding(.leading, 100)
            hotkeyRow(channelLabel: nil, actionLabel: "Volume Down", action: actions.down)
            Divider().padding(.leading, 100)
            hotkeyRow(channelLabel: nil, actionLabel: "Mute", action: actions.mute)
        }
    }

    private func hotkeyRow(channelLabel: String?, actionLabel: String, action: HotkeyAction) -> some View {
        HStack(spacing: 8) {
            if let label = channelLabel {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 52, alignment: .leading)
            } else {
                Spacer().frame(width: 52)
            }
            Text(actionLabel)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            HotkeyRecorderButton(
                action: action,
                currentBinding: hotkeyManager.getBinding(for: action),
                onRecord: { binding in
                    if let b = binding {
                        hotkeyManager.save(b)
                    } else {
                        hotkeyManager.remove(action: action)
                    }
                }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var accessibilityWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Permission Required")
                    .font(.system(size: 12, weight: .semibold))
                Text("Global hotkeys need Accessibility access. Grant it in System Settings.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 11))
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("About")

            settingsRow {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MK-OrbitControl")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Version 1.1")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Not affiliated with Antelope Audio")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button("Check for Updates") {
                            UpdateChecker.shared.check()
                        }
                        .controlSize(.small)

                        Button {
                            if let url = URL(string: "https://buymeacoffee.com/mk_tools") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("☕")
                                    .font(.system(size: 12))
                                Text("Support")
                                    .font(.system(size: 12))
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .tracking(0.5)
    }

    @ViewBuilder
    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Hotkey Recorder (click to record)

struct HotkeyRecorderButton: View {
    let action: HotkeyAction
    let currentBinding: HotkeyBinding?
    let onRecord: (HotkeyBinding?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(displayText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .frame(width: 110, height: 24)
                    .background(isRecording ? Color.accentColor.opacity(0.25) : Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            if currentBinding != nil && !isRecording {
                Button {
                    onRecord(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var displayText: String {
        if isRecording { return "Type shortcut..." }
        guard let b = currentBinding else { return "Click to record" }
        return modifierString(b.modifiers) + keyCodeString(b.keyCode)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

            // Escape cancels
            if keyCode == 53 {
                stopRecording()
                return nil
            }

            // Require at least one modifier
            guard !flags.isEmpty else { return nil }

            let binding = HotkeyBinding(
                keyCode: UInt32(keyCode),
                modifiers: UInt(flags.rawValue),
                action: action
            )
            onRecord(binding)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func modifierString(_ raw: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: raw)
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    private func keyCodeString(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            0:"A", 11:"B", 8:"C", 2:"D", 14:"E", 3:"F", 5:"G", 4:"H",
            34:"I", 38:"J", 40:"K", 37:"L", 46:"M", 45:"N", 31:"O", 35:"P",
            12:"Q", 15:"R", 1:"S", 17:"T", 32:"U", 9:"V", 13:"W", 7:"X",
            16:"Y", 6:"Z",
            29:"0", 18:"1", 19:"2", 20:"3", 21:"4", 23:"5",
            22:"6", 26:"7", 28:"8", 25:"9",
            122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6",
            98:"F7", 100:"F8", 101:"F9", 109:"F10", 103:"F11", 111:"F12",
            123:"←", 124:"→", 125:"↓", 126:"↑",
            49:"Space", 36:"↩", 48:"⇥", 51:"⌫",
        ]
        return map[keyCode] ?? "(\(keyCode))"
    }
}

// MARK: - HotkeyManagerObservable (bridge for SwiftUI)

final class HotkeyManagerObservable: ObservableObject {
    private let manager: HotkeyManager
    @Published var bindings: [HotkeyAction: HotkeyBinding] = [:]
    @Published var hasAccessibility: Bool = false

    init(manager: HotkeyManager) {
        self.manager = manager
        refresh()
    }

    func refresh() {
        var map = [HotkeyAction: HotkeyBinding]()
        for action in HotkeyAction.allCases {
            if let b = manager.getBinding(for: action) {
                map[action] = b
            }
        }
        bindings = map
        hasAccessibility = manager.hasAccessibilityPermission()
    }

    func save(_ binding: HotkeyBinding) {
        manager.save(binding)
        refresh()
    }

    func remove(action: HotkeyAction) {
        manager.remove(action: action)
        refresh()
    }

    func getBinding(for action: HotkeyAction) -> HotkeyBinding? {
        bindings[action]
    }
}
