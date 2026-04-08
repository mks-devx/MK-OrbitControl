import SwiftUI
import ServiceManagement

// MARK: - Settings Tab

private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case general    = "General"
    case hotkeys    = "Hotkeys"
    case midi       = "MIDI"
    case about      = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .general:    return "gearshape"
        case .hotkeys:    return "keyboard"
        case .midi:       return "pianokeys"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var hotkeyManager: HotkeyManagerObservable
    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var deviceState: DeviceState
    @ObservedObject var midiManager: MIDIManager

    @State private var selectedTab: SettingsTab = .appearance
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let bgDark = Color(red: 0.11, green: 0.11, blue: 0.13)
    private let bgSidebar = Color(red: 0.08, green: 0.08, blue: 0.10)
    private let bgCard = Color(red: 0.15, green: 0.15, blue: 0.17)
    private let borderColor = Color.white.opacity(0.06)
    private let textMain = Color.white.opacity(0.9)
    private let textSub = Color.white.opacity(0.5)

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 0.5)

            ZStack {
                bgDark
                contentForTab(selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 600, height: 450)
        .background(bgDark)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                sidebarItem(tab)
            }
            Spacer()
        }
        .padding(.top, 20)
        .padding(.horizontal, 10)
        .frame(width: 170)
        .background(bgSidebar)
    }

    private func sidebarItem(_ tab: SettingsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                    .foregroundColor(selectedTab == tab ? .white : .secondary)
                Text(tab.rawValue)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == tab
                          ? Color.accentColor
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Router

    @ViewBuilder
    private func contentForTab(_ tab: SettingsTab) -> some View {
        switch tab {
        case .appearance: appearanceContent
        case .general:    generalContent
        case .hotkeys:    hotkeysContent
        case .midi:       midiContent
        case .about:      aboutContent
        }
    }

    // MARK: - Appearance

    private var appearanceContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                tabHeader("Appearance")

                settingsGroup {
                    settingsRow {
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
                        .frame(width: 200)
                    }

                    Divider().padding(.leading, 12)

                    settingsRow {
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
                        .frame(width: 200)
                    }

                    Divider().padding(.leading, 12)

                    settingsRow {
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
                        .frame(width: 200)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - General

    private var generalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                tabHeader("General")

                settingsGroup {
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

                    Divider().padding(.leading, 12)

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
                        .frame(width: 120)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Hotkeys

    private var hotkeysContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                tabHeader("Hotkeys")

                if !hotkeyManager.hasAccessibility {
                    accessibilityWarning
                }

                settingsGroup {
                    hotkeyGroup(label: "MON A", actions: (.volumeUpMonA, .volumeDownMonA, .muteMonA))
                    Divider().padding(.vertical, 2)
                    hotkeyGroup(label: "MON B", actions: (.volumeUpMonB, .volumeDownMonB, .muteMonB))
                    Divider().padding(.vertical, 2)
                    hotkeyGroup(label: "HP 1",  actions: (.volumeUpHP1, .volumeDownHP1, .muteHP1))
                    Divider().padding(.vertical, 2)
                    hotkeyGroup(label: "HP 2",  actions: (.volumeUpHP2, .volumeDownHP2, .muteHP2))
                }
            }
            .padding(24)
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
        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
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

    // MARK: - MIDI

    private var midiContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    tabHeader("MIDI Learn")
                    Spacer()
                    if !midiManager.lastReceivedCC.isEmpty {
                        Text("Last: \(midiManager.lastReceivedCC)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                if midiManager.isLearning {
                    HStack {
                        Text("Move a MIDI knob/fader...")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Cancel") {
                            midiManager.cancelLearn()
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }

                settingsGroup {
                    ForEach(Array(MIDIAction.allCases.enumerated()), id: \.element.rawValue) { index, action in
                        if index > 0 {
                            Divider().padding(.leading, 12)
                        }
                        settingsRow {
                            Text(action.displayName)
                                .font(.system(size: 13))
                            Spacer()
                            if let mapping = midiManager.getMapping(for: action) {
                                Text("Ch\(mapping.channel + 1) CC\(mapping.cc)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                                    .cornerRadius(4)
                                Button {
                                    midiManager.removeMapping(for: action)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(midiManager.learningAction == action ? "Listening..." : "Learn") {
                                    midiManager.startLearn(for: action)
                                }
                                .controlSize(.small)
                                .disabled(midiManager.isLearning && midiManager.learningAction != action)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - About

    private var aboutContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                tabHeader("About")

                settingsGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("MK-OrbitControl")
                                .font(.system(size: 18, weight: .bold))
                            Text("Version 1.2")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        Text("Not affiliated with or endorsed by Antelope Audio. This is an independent utility for controlling Antelope Audio interfaces.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Divider()

                        HStack(spacing: 12) {
                            Button("Check for Updates") {
                                UpdateChecker.shared.checkManually()
                            }

                            Button {
                                if let url = URL(string: "https://buymeacoffee.com/mk_tools") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("☕")
                                    Text("Support")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Shared Helpers

    private func tabHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
                    .background(isRecording ? Color.accentColor.opacity(0.25) : Color(red: 0.18, green: 0.18, blue: 0.20))
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
