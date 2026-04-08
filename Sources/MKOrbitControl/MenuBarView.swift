import SwiftUI
import Combine
import ServiceManagement
import AppKit

// MARK: - Commander Environment Key

struct CommanderKey: EnvironmentKey {
    static let defaultValue: AntelopeCommander = AntelopeCommander()
}

extension EnvironmentValues {
    var commander: AntelopeCommander {
        get { self[CommanderKey.self] }
        set { self[CommanderKey.self] = newValue }
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var deviceState: DeviceState
    @EnvironmentObject var presetManager: PresetManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.commander) var commander
    @Environment(\.openURL) var openURL
    var onOpenSettings: (() -> Void)?

    private var t: AppTheme { themeManager.currentTheme }
    private var f: AppFont { themeManager.currentFont }

    @State private var sliderValue: Double = 0
    @State private var isUserDragging: Bool = false
    @State private var pendingSentValue: Int? = nil
    @State private var knobDragStart: Double = 0
    @State private var volumeDebounceTimer: Timer? = nil

    // Volume mapping
    private let maxSlider: Double = 96

    private func rawToDbString(_ raw: Int) -> String {
        if raw >= 96 { return "-∞" }
        if raw <= 0 { return "0" }
        return "-\(raw)"
    }

    private func sliderToRaw(_ slider: Double) -> Int {
        if slider <= 0 { return 96 }
        let raw = Int(maxSlider - slider)
        // Night mode: don't allow volume above the cap
        if deviceState.nightMode {
            return max(raw, deviceState.nightModeMax)
        }
        return raw
    }

    /// Maximum slider position allowed in night mode
    private var maxAllowedSlider: Double {
        if deviceState.nightMode {
            return maxSlider - Double(deviceState.nightModeMax)
        }
        return maxSlider
    }

    private func rawToSlider(_ raw: Int) -> Double {
        if raw >= 96 { return 0 }
        return max(0, min(maxSlider, maxSlider - Double(raw)))
    }

    private var isAtInfinity: Bool { sliderValue <= 0 }
    private var volumePercent: Double { sliderValue / maxSlider }

    var body: some View {
        if deviceState.miniMode {
            miniBody
        } else {
            fullBody
        }
    }

    // MARK: - Mini Mode

    private var miniBody: some View {
        VStack(spacing: 6) {
            // Channel + dB
            HStack {
                Text(deviceState.selectedOutput.label)
                    .font(f.dbFont(size: 13))
                    .foregroundColor(t.textPrimary)
                Spacer()
                Text("\(rawToDbString(sliderToRaw(sliderValue))) dB")
                    .font(f.dbFont(size: 18))
                    .foregroundColor(t.textPrimary)
                Spacer()
                // Mute button
                Button {
                    commander.setMute(channel: deviceState.selectedOutput, muted: !deviceState.currentChannel.mute)
                } label: {
                    Image(systemName: deviceState.currentChannel.mute ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13))
                        .foregroundColor(deviceState.currentChannel.mute ? .red : t.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)

            // Slider
            GeometryReader { geo in
                let trackH: CGFloat = 3
                let thumbW: CGFloat = 14
                let thumbH: CGFloat = 9
                let usable = geo.size.width - thumbW
                let thumbX = usable * (sliderValue / maxSlider) + thumbW / 2

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: trackH)
                        .padding(.horizontal, thumbW / 2)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(t.accent)
                        .frame(width: max(0, thumbX - thumbW / 2), height: trackH)
                        .padding(.leading, thumbW / 2)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: thumbW, height: thumbH)
                        .shadow(color: t.accent.opacity(0.4), radius: 3)
                        .offset(x: thumbX - thumbW / 2)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isUserDragging { isUserDragging = true }
                            let pct = max(0, min(1, (value.location.x - thumbW / 2) / usable))
                            sliderValue = min(pct * maxSlider, maxAllowedSlider)
                            scheduleVolumeCommand(value: sliderToRaw(sliderValue), delay: 0)
                        }
                        .onEnded { _ in
                            isUserDragging = false
                            scheduleVolumeCommand(value: sliderToRaw(sliderValue), delay: 0)
                        }
                )
            }
            .frame(height: 14)
            .padding(.horizontal, 14)

            // Output selector + expand
            HStack(spacing: 4) {
                ForEach(OutputChannel.displayOrder) { ch in
                    let isSelected = deviceState.selectedOutput == ch
                    Button {
                        deviceState.selectedOutput = ch
                    } label: {
                        Text(ch.label)
                            .font(f.font(size: 8, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? t.accent : t.textDim)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(isSelected ? t.accent.opacity(0.15) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    deviceState.miniMode = false
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9))
                        .foregroundColor(t.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .frame(width: 220, height: 90)
        .background {
            if t.useMaterial {
                Rectangle().fill(.ultraThinMaterial).opacity(0.85)
            }
        }
        .background(t.background.opacity(t.backgroundOpacity))
        .preferredColorScheme(.dark)
        .onReceive(deviceState.$channels) { _ in
            let deviceVol = deviceState.currentChannel.volume
            if isUserDragging { return }
            if let pending = pendingSentValue {
                if abs(deviceVol - pending) <= 2 { pendingSentValue = nil }
                return
            }
            let currentRaw = sliderToRaw(sliderValue)
            if abs(deviceVol - currentRaw) > 1 {
                sliderValue = rawToSlider(deviceVol)
            }
        }
        .onReceive(deviceState.$selectedOutput) { _ in
            pendingSentValue = nil
            sliderValue = rawToSlider(deviceState.currentChannel.volume)
        }
    }

    // MARK: - Full Mode

    private var fullBody: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 3) {
                // Top row: connection + app name + night mode
                HStack(spacing: 4) {
                    Circle()
                        .fill(deviceState.connected ? Color(red: 0.2, green: 0.8, blue: 0.3) : .red)
                        .frame(width: 5, height: 5)
                    Text(deviceState.connected ? "Connected" : "Offline")
                        .font(f.font(size: 9))
                        .foregroundColor(t.textDim)
                    Spacer()
                    Text("MK-OrbitControl")
                        .font(f.font(size: 9))
                        .foregroundColor(t.textDim)
                    if deviceState.nightMode {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.orange.opacity(0.5))
                    }
                }
                // Center: big output name
                Text(deviceState.selectedOutput.label)
                    .font(f.dbFont(size: 18))
                    .foregroundColor(t.textPrimary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)

            // Knob — centered
            ZStack {
                Circle()
                    .stroke(t.knobOuter, lineWidth: 5)
                    .frame(width: 140, height: 140)

                Circle()
                    .trim(from: 0, to: volumePercent * 0.75)
                    .stroke(
                        t.accent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(135))
                    .animation(.easeOut(duration: 0.08), value: volumePercent)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: t.knobInner,
                            center: .center,
                            startRadius: 0,
                            endRadius: 58
                        )
                    )
                    .frame(width: 118, height: 118)

                Circle()
                    .stroke(t.knobRing, lineWidth: 1)
                    .frame(width: 118, height: 118)

                VStack(spacing: 1) {
                    Text(rawToDbString(sliderToRaw(sliderValue)))
                        .font(f.dbFont(size: 30))
                        .foregroundColor(t.textPrimary)
                    Text("dB")
                        .font(f.font(size: 10, weight: .medium))
                        .foregroundColor(t.textDim)
                }

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 3, height: 14)
                    .offset(y: -52)
                    .rotationEffect(.degrees(225 + 270 * volumePercent))
                    .animation(.easeOut(duration: 0.08), value: volumePercent)
            }
            .padding(.top, 4)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isUserDragging {
                            isUserDragging = true
                            knobDragStart = sliderValue
                        }
                        let delta = (value.translation.width - value.translation.height) / 4.0
                        let newSlider = max(0, min(maxAllowedSlider, knobDragStart + delta))
                        sliderValue = newSlider
                        scheduleVolumeCommand(value: sliderToRaw(newSlider), delay: 0)
                    }
                    .onEnded { _ in
                        isUserDragging = false
                        scheduleVolumeCommand(value: sliderToRaw(sliderValue), delay: 0)
                    }
            )

            // Pro slider
            GeometryReader { geo in
                let trackH: CGFloat = 3
                let thumbW: CGFloat = 16
                let thumbH: CGFloat = 10
                let usable = geo.size.width - thumbW
                let thumbX = usable * (sliderValue / maxSlider) + thumbW / 2

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: trackH)
                        .padding(.horizontal, thumbW / 2)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(t.accent)
                        .frame(width: max(0, thumbX - thumbW / 2), height: trackH)
                        .padding(.leading, thumbW / 2)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: thumbW, height: thumbH)
                        .shadow(color: t.accent.opacity(0.4), radius: 3)
                        .offset(x: thumbX - thumbW / 2)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isUserDragging { isUserDragging = true }
                            let pct = max(0, min(1, (value.location.x - thumbW / 2) / usable))
                            sliderValue = min(pct * maxSlider, maxAllowedSlider)
                            scheduleVolumeCommand(value: sliderToRaw(sliderValue), delay: 0)
                        }
                        .onEnded { _ in
                            isUserDragging = false
                            scheduleVolumeCommand(value: sliderToRaw(sliderValue), delay: 0)
                        }
                )
            }
            .frame(height: 16)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            // Peak meters — horizontal L/R with smooth decay
            VStack(spacing: 2) {
                peakMeterRow(label: "L", level: deviceState.peaks.smoothL)
                peakMeterRow(label: "R", level: deviceState.peaks.smoothR)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            // Control buttons
            HStack(spacing: 8) {
                sideButton("DIM", active: deviceState.currentChannel.dim, color: Color.yellow) {
                    commander.setDim(channel: deviceState.selectedOutput, dimmed: !deviceState.currentChannel.dim)
                }
                sideButton("MUTE", active: deviceState.currentChannel.mute, color: Color.red) {
                    commander.setMute(channel: deviceState.selectedOutput, muted: !deviceState.currentChannel.mute)
                }
                sideButton("MONO", active: deviceState.currentChannel.mono, color: Color.blue) {
                    commander.setMono(channel: deviceState.selectedOutput, mono: !deviceState.currentChannel.mono)
                }
                sideButton("🌙", active: deviceState.nightMode, color: Color.orange) {
                    deviceState.nightMode.toggle()
                    // If turning on and current volume exceeds cap, lower it
                    if deviceState.nightMode {
                        let current = deviceState.currentChannel.volume
                        if current < deviceState.nightModeMax {
                            commander.setVolume(channel: deviceState.selectedOutput, value: deviceState.nightModeMax)
                        }
                    }
                }
                Spacer()
                Button {
                    let current = deviceState.selectedOutput
                    deviceState.selectedOutput = (current == .monA) ? .monB : .monA
                } label: {
                    Text("A/B")
                        .font(f.font(size: 9, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white.opacity(0.45))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Output selector + Presets combined
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    ForEach(OutputChannel.displayOrder) { ch in
                        outputDot(ch)
                    }
                }

                // Presets row with label
                HStack(spacing: 0) {
                    Text("PRESETS")
                        .font(f.font(size: 7))
                        .foregroundColor(t.textDim)
                        .frame(width: 42, alignment: .leading)
                    HStack(spacing: 5) {
                        ForEach(0..<4) { slot in
                            presetButton(slot: slot)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 6)

            // Footer — two rows for breathing room
            VStack(spacing: 8) {
                // Row 1: Mode buttons
                HStack(spacing: 6) {
                    footerButton(icon: "arrow.down.right.and.arrow.up.left", label: "Mini", action: {
                        deviceState.miniMode = true
                    })
                    footerButton(icon: "macwindow", label: "Float", action: {
                        FloatingWindowController.shared.toggle(
                            deviceState: deviceState,
                            presetManager: presetManager,
                            themeManager: themeManager,
                            commander: commander,
                            onOpenSettings: { onOpenSettings?() }
                        )
                    })
                    footerButton(icon: "gearshape", label: "Settings", action: {
                        onOpenSettings?()
                    })
                    footerButton(icon: "power", label: "Quit", action: {
                        NSApplication.shared.terminate(nil)
                    })
                }

                // Row 2: Support
                Button {
                    if let url = URL(string: "https://buymeacoffee.com/mk_tools") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("☕")
                            .font(f.font(size: 9))
                        Text("Buy me a coffee")
                            .font(f.font(size: 8))
                    }
                    .foregroundColor(t.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(width: 280, height: 480)
        .background {
            if t.useMaterial {
                Rectangle().fill(.ultraThinMaterial).opacity(0.85)
            }
        }
        .background(t.background.opacity(t.backgroundOpacity))
        .preferredColorScheme(.dark)
        .onReceive(deviceState.$channels) { _ in
            let deviceVol = deviceState.currentChannel.volume
            if isUserDragging { return }
            if let pending = pendingSentValue {
                // Accept if device is within 2 of what we sent
                if abs(deviceVol - pending) <= 2 {
                    pendingSentValue = nil
                }
                return
            }
            // Only update slider if the change is significant (prevents micro-jumps)
            let currentRaw = sliderToRaw(sliderValue)
            if abs(deviceVol - currentRaw) > 1 {
                sliderValue = rawToSlider(deviceVol)
            }
        }
        .onReceive(deviceState.$selectedOutput) { _ in
            pendingSentValue = nil
            sliderValue = rawToSlider(deviceState.currentChannel.volume)
        }
        .onAppear {
            sliderValue = rawToSlider(deviceState.currentChannel.volume)
        }
    }

    // MARK: - Components

    private func sideButton(_ label: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(f.font(size: 9, weight: .bold))
                .frame(width: 42, height: 24)
                .background(active ? color.opacity(0.3) : Color.white.opacity(0.05))
                .foregroundColor(active ? color : .white.opacity(0.35))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(active ? color.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func outputDot(_ channel: OutputChannel) -> some View {
        let isSelected = deviceState.selectedOutput == channel
        return Button {
            deviceState.selectedOutput = channel
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(isSelected ? Color(red: 0.9, green: 0.6, blue: 0.1) : Color.white.opacity(0.15))
                    .frame(width: 8, height: 8)
                Text(channel.label)
                    .font(f.font(size: 8, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .white.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
    }

    private func presetButton(slot: Int) -> some View {
        let preset = presetManager.get(slot: slot)
        let labels = ["A", "B", "C", "D"]
        let hasPreset = preset != nil

        return Button {
            if hasPreset {
                // Update UI immediately (optimistic)
                if let saved = preset?.channels[deviceState.selectedOutput.rawValue] {
                    sliderValue = rawToSlider(saved.volume)
                    pendingSentValue = saved.volume
                }
                presetManager.recall(slot: slot, to: commander, state: deviceState)
            }
        } label: {
            Text(hasPreset ? (preset?.name ?? labels[slot]) : labels[slot])
                .font(f.font(size: 10, weight: hasPreset ? .bold : .regular))
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(hasPreset ? Color.white.opacity(0.1) : Color.white.opacity(0.03))
                .foregroundColor(hasPreset ? .white.opacity(0.7) : .white.opacity(0.25))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(hasPreset ? 0.15 : 0.05), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Save current state") {
                presetManager.save(slot: slot, name: labels[slot], from: deviceState)
            }
            if hasPreset {
                Button("Recall") {
                    presetManager.recall(slot: slot, to: commander, state: deviceState)
                }
                Divider()
                Button("Clear", role: .destructive) {
                    presetManager.presets.removeAll { $0.id == slot }
                }
            }
        }
    }

    private func peakMeterRow(label: String, level: Double) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(f.font(size: 7, weight: .bold))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 4)
                    // Filled — themed gradient
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: t.meterGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * level, height: 4)
                        .animation(.linear(duration: 0.05), value: level)
                }
            }
            .frame(height: 4)
        }
    }

    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(f.font(size: 8))
            }
            .foregroundColor(t.textDim)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func scheduleVolumeCommand(value: Int, delay: TimeInterval) {
        volumeDebounceTimer?.invalidate()
        let channel = deviceState.selectedOutput
        pendingSentValue = value
        if delay == 0 {
            commander.setVolume(channel: channel, value: value)
        } else {
            volumeDebounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                commander.setVolume(channel: channel, value: value)
            }
        }
    }
}
