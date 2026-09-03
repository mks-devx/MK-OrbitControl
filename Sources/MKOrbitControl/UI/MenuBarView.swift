import SwiftUI
import AppKit

enum OrbitControlLayout {
    static let fullSize = CGSize(width: 300, height: 500)
    static let miniSize = CGSize(width: 240, height: 126)
}

// MARK: - Commander Environment Key

struct CommanderKey: EnvironmentKey {
    static let defaultValue: AntelopeCommander = AntelopeCommander()
}

private extension View {
    @ViewBuilder
    func orbitTranslucentSurface<S: Shape>(in shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.75))
    }

    @ViewBuilder
    func orbitLiquidGlassSurface<S: Shape>(
        in shape: S,
        tint: Color?,
        interactive: Bool
    ) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(
                Glass.regular.tint(tint).interactive(interactive),
                in: shape
            )
        } else {
            self.orbitTranslucentSurface(in: shape)
        }
#else
        self.orbitTranslucentSurface(in: shape)
#endif
    }

    @ViewBuilder
    func suppressDefaultFocusEffect() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }

    @ViewBuilder
    func orbitSurface<S: Shape>(
        style: InterfaceSurfaceStyle,
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        switch style {
        case .solid:
            self
                .background(tint ?? Color.primary.opacity(0.055), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 0.75))
        case .translucent:
            self.orbitTranslucentSurface(in: shape)
        case .liquidGlass:
            if ProcessInfo.processInfo.environment["MK_CAPTURE_UI"] != nil {
                self.orbitTranslucentSurface(in: shape)
            } else {
                self.orbitLiquidGlassSurface(
                    in: shape,
                    tint: tint,
                    interactive: interactive
                )
            }
        }
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpenSettings: (() -> Void)?

    private var t: AppTheme { themeManager.currentTheme }
    private var f: AppFont { themeManager.currentFont }

    @State private var sliderValue: Double = 0
    @State private var isUserDragging: Bool = false
    @State private var pendingSentValue: Int? = nil
    @State private var knobDragStart: Double = 0
    @FocusState private var volumeControlFocused: Bool

    // Volume mapping
    private let maxSlider = Double(VolumeScale.maximumRaw)

    private func rawToDbString(_ raw: Int) -> String {
        VolumeScale.rawToDisplay(raw)
    }

    private func sliderToRaw(_ slider: Double) -> Int {
        let raw = VolumeScale.sliderToRaw(slider)
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
        VolumeScale.rawToSlider(raw)
    }

    private var isAtInfinity: Bool { sliderValue <= 0 }
    private var volumePercent: Double { sliderValue / maxSlider }

    @ViewBuilder
    private var menuBackground: some View {
        switch themeManager.surfaceStyle {
        case .solid:
            Rectangle().fill(t.background)
        case .translucent, .liquidGlass:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(t.background.opacity(1 - themeManager.backgroundTransparency))
            }
        }
    }

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
                .accessibilityLabel(deviceState.currentChannel.mute ? "Unmute \(deviceState.selectedOutput.label)" : "Mute \(deviceState.selectedOutput.label)")
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
                            sendVolumeCommand(value: sliderToRaw(sliderValue))
                        }
                        .onEnded { _ in
                            isUserDragging = false
                            sendVolumeCommand(value: sliderToRaw(sliderValue))
                        }
                )
            }
            .frame(height: 28)
            .padding(.horizontal, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(deviceState.selectedOutput.label) volume")
            .accessibilityValue("\(rawToDbString(sliderToRaw(sliderValue))) decibels")
            .accessibilityAdjustableAction(adjustAccessibilityVolume)
            .focusable()
            .onMoveCommand(perform: adjustKeyboardVolume)

            // Output selector + expand
            HStack(spacing: 4) {
                ForEach(OutputChannel.displayOrder) { ch in
                    let isSelected = deviceState.selectedOutput == ch
                    Button {
                        deviceState.selectedOutput = ch
                    } label: {
                        Text(ch.label)
                            .font(f.font(size: 10, weight: isSelected ? .bold : .regular))
                            .foregroundColor(isSelected ? t.accent : t.textDim)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 6)
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
                        .font(.system(size: 12))
                        .foregroundColor(t.textDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand controls")
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .frame(
            width: OrbitControlLayout.miniSize.width,
            height: OrbitControlLayout.miniSize.height
        )
        .background { menuBackground }
        .preferredColorScheme(t.isDark ? .dark : .light)
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
            // Output identity and device health share one glass navigation plane.
            HStack(spacing: 10) {
                Image(systemName: deviceState.selectedOutput.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text("ACTIVE OUTPUT")
                        .font(f.font(size: 8, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(t.textDim)
                    Text(deviceState.selectedOutput.label)
                        .font(f.dbFont(size: 17))
                        .foregroundStyle(t.textPrimary)
                }

                Spacer(minLength: 6)

                Button {
                    deviceState.reconnect()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(deviceState.connected ? Color(red: 0.30, green: 0.88, blue: 0.48) : .red)
                            .frame(width: 6, height: 6)
                        Text(deviceState.connected ? "ONLINE" : "OFFLINE")
                            .font(f.font(size: 8, weight: .semibold))
                            .tracking(0.7)
                    }
                    .foregroundStyle(deviceState.connected ? t.textSecondary : Color.red)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                }
                .buttonStyle(.plain)
                .help("Reconnect to device")
                .accessibilityLabel("Reconnect to Antelope device")

                if !deviceState.connected {
                    Button {
                        deviceState.restartServer()
                    } label: {
                        if deviceState.isRestartingServer {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(deviceState.isRestartingServer)
                    .help("Restart Antelope Server (admin)")
                    .accessibilityLabel("Restart Antelope server")
                }

                if deviceState.nightMode {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .orbitSurface(
                style: themeManager.surfaceStyle,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous),
                tint: t.accent.opacity(0.035)
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if deviceState.controlAvailability.isBlocking {
                runtimeWarning
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }

            // Monitor-controller dial
            ZStack {
                // Restrained calibration marks make the interaction range legible
                // without turning the control into a decorative gauge.
                ForEach(0..<19, id: \.self) { tick in
                    Capsule()
                        .fill(
                            tick % 3 == 0
                                ? t.textSecondary.opacity(0.56)
                                : t.textDim.opacity(0.24)
                        )
                        .frame(width: tick % 3 == 0 ? 1.5 : 1, height: tick % 3 == 0 ? 7 : 4)
                        .offset(y: -70)
                        .rotationEffect(.degrees(135 + Double(tick) * 15))
                }

                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(t.knobOuter, lineWidth: 5)
                    .frame(width: 136, height: 136)
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: volumePercent * 0.75)
                    .stroke(
                        t.accent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 136, height: 136)
                    .rotationEffect(.degrees(135))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: volumePercent)

                Circle()
                    .fill(t.background.opacity(0.34))
                    .frame(width: 114, height: 114)

                Circle()
                    .fill(Color.clear)
                    .frame(width: 114, height: 114)
                    .orbitSurface(
                        style: themeManager.surfaceStyle,
                        in: Circle(),
                        tint: t.accent.opacity(0.035),
                        interactive: true
                    )

                Circle()
                    .stroke(t.knobRing, lineWidth: 1)
                    .frame(width: 114, height: 114)

                Circle()
                    .stroke(t.textPrimary.opacity(0.035), lineWidth: 1)
                    .frame(width: 104, height: 104)

                VStack(spacing: 0) {
                    Text(rawToDbString(sliderToRaw(sliderValue)))
                        .font(f.dbFont(size: 32))
                        .foregroundColor(t.textPrimary)
                    Text("dB")
                        .font(f.font(size: 9, weight: .semibold))
                        .foregroundColor(t.textDim)
                        .tracking(1.2)
                }

                Capsule()
                    .fill(t.textSecondary)
                    .frame(width: 3, height: 13)
                    .offset(y: -50)
                    .rotationEffect(.degrees(225 + 270 * volumePercent))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: volumePercent)

                // A circular keyboard focus treatment replaces macOS's default square.
                Circle()
                    .stroke(t.accent.opacity(volumeControlFocused ? 0.62 : 0), lineWidth: 2)
                    .frame(width: 150, height: 150)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: volumeControlFocused)
            }
            .frame(width: 154, height: 154)
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
                        sendVolumeCommand(value: sliderToRaw(newSlider))
                    }
                    .onEnded { _ in
                        isUserDragging = false
                        sendVolumeCommand(value: sliderToRaw(sliderValue))
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(deviceState.selectedOutput.label) volume")
            .accessibilityValue("\(rawToDbString(sliderToRaw(sliderValue))) decibels")
            .accessibilityAdjustableAction(adjustAccessibilityVolume)
            .focusable()
            .focused($volumeControlFocused)
            .suppressDefaultFocusEffect()
            .onMoveCommand(perform: adjustKeyboardVolume)
            .overlay {
                HStack {
                    volumeStepButton(direction: .quieter)
                    Spacer()
                    volumeStepButton(direction: .louder)
                }
                .frame(width: 244)
            }

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
                            sendVolumeCommand(value: sliderToRaw(sliderValue))
                        }
                        .onEnded { _ in
                            isUserDragging = false
                            sendVolumeCommand(value: sliderToRaw(sliderValue))
                        }
                )
            }
            .frame(height: 32)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .accessibilityHidden(true)

            // Peak meters — horizontal L/R with smooth decay
            VStack(spacing: 2) {
                peakMeterRow(label: "L", level: deviceState.peaks.smoothL, peakHold: deviceState.peaks.peakHoldL)
                peakMeterRow(label: "R", level: deviceState.peaks.smoothR, peakHold: deviceState.peaks.peakHoldR)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            // Fast monitoring controls — the primary tactile layer.
            HStack(spacing: 6) {
                monitorButton("DIM", icon: "speaker.minus.fill", active: deviceState.currentChannel.dim, color: .yellow) {
                    commander.setDim(channel: deviceState.selectedOutput, dimmed: !deviceState.currentChannel.dim)
                }
                monitorButton("MUTE", icon: "speaker.slash.fill", active: deviceState.currentChannel.mute, color: .red) {
                    commander.setMute(channel: deviceState.selectedOutput, muted: !deviceState.currentChannel.mute)
                }
                monitorButton("MONO", icon: "circle.lefthalf.filled", active: deviceState.currentChannel.mono, color: .blue) {
                    commander.setMono(channel: deviceState.selectedOutput, mono: !deviceState.currentChannel.mono)
                }
                monitorButton("NIGHT", icon: "moon.fill", active: deviceState.nightMode, color: .orange) {
                    deviceState.nightMode.toggle()
                    if deviceState.nightMode {
                        let current = deviceState.currentChannel.volume
                        if current < deviceState.nightModeMax {
                            commander.setVolume(channel: deviceState.selectedOutput, value: deviceState.nightModeMax)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Output routing and snapshots are grouped, but not nested in glass.
            VStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(OutputChannel.displayOrder) { ch in
                        outputDot(ch)
                    }
                }
                .padding(4)
                .orbitSurface(
                    style: themeManager.surfaceStyle,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

                HStack(spacing: 8) {
                    Text("PRESETS")
                        .font(f.font(size: 8, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(t.textDim)
                        .frame(width: 48, alignment: .leading)
                    HStack(spacing: 5) {
                        ForEach(0..<4) { slot in
                            presetButton(slot: slot)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(
                    t.textPrimary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(t.textPrimary.opacity(0.07), lineWidth: 0.75)
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Navigation toolbar. Support solicitation intentionally removed.
            HStack(spacing: 2) {
                footerButton(icon: "arrow.down.right.and.arrow.up.left", label: "Mini") {
                    deviceState.miniMode = true
                }
                footerButton(icon: "macwindow", label: "Float") {
                    FloatingWindowController.shared.toggle(
                        deviceState: deviceState,
                        presetManager: presetManager,
                        themeManager: themeManager,
                        commander: commander,
                        onOpenSettings: { onOpenSettings?() }
                    )
                }
                footerButton(icon: "gearshape", label: "Settings") {
                    onOpenSettings?()
                }
                footerButton(icon: "power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(4)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(t.textPrimary.opacity(0.08))
                    .frame(height: 0.75)
                    .padding(.horizontal, 20)
            }
        }
        .frame(
            width: OrbitControlLayout.fullSize.width,
            height: OrbitControlLayout.fullSize.height,
            alignment: .top
        )
        .background { menuBackground }
        .preferredColorScheme(t.isDark ? .dark : .light)
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

    private var runtimeWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(deviceState.controlAvailability.title)
                    .font(f.font(size: 11, weight: .bold))
                    .foregroundColor(t.textPrimary)
                Text(deviceState.controlAvailability.recovery)
                    .font(f.font(size: 10))
                    .foregroundColor(t.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(t.textPrimary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.orange.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func monitorButton(
        _ label: String,
        icon: String,
        active: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                Text(label)
                    .font(f.font(size: 8, weight: .semibold))
                    .tracking(0.45)
            }
            .foregroundStyle(active ? color : t.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .orbitSurface(
                style: themeManager.surfaceStyle,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                tint: active ? color.opacity(0.22) : nil,
                interactive: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "NIGHT" ? "Night mode" : label)
        .accessibilityValue(active ? "On" : "Off")
    }

    private func outputDot(_ channel: OutputChannel) -> some View {
        let isSelected = deviceState.selectedOutput == channel
        return Button {
            deviceState.selectedOutput = channel
        } label: {
            HStack(spacing: 5) {
                Image(systemName: channel.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(channel.label)
                    .font(f.font(size: 9, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? t.textPrimary : t.textDim)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background {
                if isSelected {
                    Capsule()
                        .fill(t.accent.opacity(t.isDark ? 0.18 : 0.12))
                        .overlay(Capsule().stroke(t.accent.opacity(0.32), lineWidth: 0.75))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(channel.label)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
                .font(f.font(size: 9, weight: hasPreset ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    hasPreset ? t.accent.opacity(0.14) : t.textPrimary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .foregroundStyle(hasPreset ? t.textPrimary : t.textDim)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(hasPreset ? t.accent.opacity(0.26) : t.textPrimary.opacity(0.08), lineWidth: 0.75)
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
                    presetManager.clear(slot: slot)
                }
            }
        }
    }

    private func peakMeterRow(label: String, level: Double, peakHold: Double = 0) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(f.font(size: 10, weight: .bold))
                .foregroundColor(t.textSecondary)
                .frame(width: 10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(t.textPrimary.opacity(0.08))
                        .frame(height: 6)
                    // Filled bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: t.meterGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * level, height: 6)
                        .animation(reduceMotion ? nil : .linear(duration: 0.05), value: level)
                    // Peak hold indicator
                    if peakHold > 0.01 {
                        Rectangle()
                            .fill(t.textPrimary)
                            .frame(width: 2, height: 6)
                            .offset(x: geo.size.width * peakHold - 1)
                            .animation(reduceMotion ? nil : .linear(duration: 0.05), value: peakHold)
                    }
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) channel peak")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private func footerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(f.font(size: 8, weight: .medium))
            }
            .foregroundStyle(label == "Quit" ? t.textDim : t.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private enum VolumeStepDirection: Equatable {
        case quieter
        case louder
    }

    private func volumeStepButton(direction: VolumeStepDirection) -> some View {
        let isLouder = direction == .louder
        let signedStep = isLouder ? deviceState.volumeStep : -deviceState.volumeStep
        let label = isLouder ? "Louder" : "Quieter"
        let isDisabled = isLouder ? sliderValue >= maxAllowedSlider : isAtInfinity

        return Button {
            adjustVolumeSlider(by: Double(signedStep))
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isLouder ? "plus" : "minus")
                    .font(.system(size: 12, weight: .bold))
                Text("\(isLouder ? "+" : "−")\(deviceState.volumeStep)")
                    .font(f.font(size: 8, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isDisabled ? t.textDim.opacity(0.45) : t.textSecondary)
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .orbitSurface(
                style: themeManager.surfaceStyle,
                in: Circle(),
                tint: t.accent.opacity(0.08),
                interactive: true
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("\(label) by \(deviceState.volumeStep) decibels")
        .help("\(label) by \(deviceState.volumeStep) dB")
    }

    private func sendVolumeCommand(value: Int) {
        let channel = deviceState.selectedOutput
        pendingSentValue = value
        commander.setVolume(channel: channel, value: value, completion: handleVolumeCompletion)
    }

    private func handleVolumeCompletion(_ succeeded: Bool) {
        guard !succeeded else { return }
        pendingSentValue = nil
        sliderValue = rawToSlider(deviceState.currentChannel.volume)
    }

    private func adjustAccessibilityVolume(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: adjustVolumeSlider(by: Double(deviceState.volumeStep))
        case .decrement: adjustVolumeSlider(by: -Double(deviceState.volumeStep))
        @unknown default: break
        }
    }

    private func adjustKeyboardVolume(_ direction: MoveCommandDirection) {
        switch direction {
        case .up, .right: adjustVolumeSlider(by: Double(deviceState.volumeStep))
        case .down, .left: adjustVolumeSlider(by: -Double(deviceState.volumeStep))
        default: break
        }
    }

    private func adjustVolumeSlider(by delta: Double) {
        sliderValue = max(0, min(maxAllowedSlider, sliderValue + delta))
        sendVolumeCommand(value: sliderToRaw(sliderValue))
    }
}
