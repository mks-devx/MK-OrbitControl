import SwiftUI
import WidgetKit
import AppIntents

struct OrbitWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: OrbitWidgetSnapshot
}

struct OrbitWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> OrbitWidgetEntry {
        OrbitWidgetEntry(
            date: Date(),
            snapshot: OrbitWidgetSnapshot(
                outputRawValue: 0,
                volume: 44,
                muted: false,
                dimmed: false,
                connected: true,
                updatedAt: Date(),
                lastCommandFailed: false
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (OrbitWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OrbitWidgetEntry>) -> Void) {
        let entry = currentEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60))))
    }

    private func currentEntry() -> OrbitWidgetEntry {
        var snapshot = OrbitWidgetStateStore.load()
        if Date().timeIntervalSince(snapshot.updatedAt) > 90 {
            snapshot.connected = false
        }
        return OrbitWidgetEntry(date: Date(), snapshot: snapshot)
    }
}

private enum OrbitWidgetPalette {
    static let accent = Color(red: 0.94, green: 0.16, blue: 0.18)
    static let primary = Color(red: 0.98, green: 0.94, blue: 0.94)
    static let secondary = Color(red: 0.74, green: 0.60, blue: 0.61)
    static let surface = Color(red: 0.15, green: 0.055, blue: 0.06)
    static let raised = Color(red: 0.22, green: 0.075, blue: 0.08)
}

struct MKOrbitControlWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OrbitWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            default:
                mediumLayout
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                OrbitWidgetPalette.surface
                RadialGradient(
                    colors: [OrbitWidgetPalette.accent.opacity(0.13), .clear],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 220
                )
            }
        }
        .widgetAccentable(false)
    }

    private var mediumLayout: some View {
        VStack(spacing: 12) {
            header

            HStack(alignment: .center, spacing: 16) {
                volumeReadout
                Spacer(minLength: 0)
                volumeButtons
            }

            HStack(spacing: 6) {
                stateButton(
                    title: "DIM",
                    icon: "speaker.minus.fill",
                    active: entry.snapshot.dimmed,
                    intent: ToggleOrbitDimIntent()
                )
                stateButton(
                    title: "MUTE",
                    icon: "speaker.slash.fill",
                    active: entry.snapshot.muted,
                    intent: ToggleOrbitMuteIntent()
                )
                outputButton("A", output: .monA, icon: "speaker.wave.2.fill")
                outputButton("B", output: .monB, icon: "speaker.wave.2.fill")
                outputButton("H1", output: .hp1, icon: "headphones")
                outputButton("H2", output: .hp2, icon: "headphones")
            }
        }
        .padding(16)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            volumeReadout
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                compactVolumeButton(icon: "minus", direction: .quieter)
                compactVolumeButton(icon: "plus", direction: .louder)
                stateButton(
                    title: "MUTE",
                    icon: "speaker.slash.fill",
                    active: entry.snapshot.muted,
                    intent: ToggleOrbitMuteIntent()
                )
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.snapshot.outputRawValue < 3 && entry.snapshot.outputRawValue > 0
                  ? "headphones" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OrbitWidgetPalette.accent)
            Text(entry.snapshot.outputLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(OrbitWidgetPalette.primary)
            Spacer(minLength: 0)
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusLabel)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(statusColor)
        }
    }

    private var volumeReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(entry.snapshot.displayVolume)
                .font(.system(size: family == .systemSmall ? 36 : 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OrbitWidgetPalette.primary)
                .invalidatableContent()
            Text("dB")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(OrbitWidgetPalette.secondary)
        }
    }

    private var volumeButtons: some View {
        HStack(spacing: 8) {
            volumeButton(label: "−3", direction: .quieter)
            volumeButton(label: "+3", direction: .louder)
        }
    }

    private func volumeButton(label: String, direction: OrbitWidgetVolumeDirection) -> some View {
        Button(intent: AdjustOrbitVolumeIntent(direction: direction)) {
            Text(label)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(OrbitWidgetPalette.primary)
                .frame(width: 54, height: 42)
                .background(OrbitWidgetPalette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!entry.snapshot.connected)
        .accessibilityLabel(direction == .louder ? "Raise volume 3 decibels" : "Lower volume 3 decibels")
    }

    private func compactVolumeButton(icon: String, direction: OrbitWidgetVolumeDirection) -> some View {
        Button(intent: AdjustOrbitVolumeIntent(direction: direction)) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OrbitWidgetPalette.primary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(OrbitWidgetPalette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!entry.snapshot.connected)
    }

    private func stateButton<I: AppIntent>(
        title: String,
        icon: String,
        active: Bool,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.4)
            }
            .foregroundStyle(active ? OrbitWidgetPalette.primary : OrbitWidgetPalette.secondary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                active ? OrbitWidgetPalette.accent.opacity(0.72) : OrbitWidgetPalette.raised,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!entry.snapshot.connected)
        .accessibilityLabel(title)
        .accessibilityValue(active ? "On" : "Off")
    }

    private func outputButton(_ title: String, output: OrbitWidgetOutput, icon: String) -> some View {
        let selected = entry.snapshot.outputRawValue == output.rawValue
        return Button(intent: SelectOrbitOutputIntent(output: output)) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
            }
            .foregroundStyle(selected ? OrbitWidgetPalette.primary : OrbitWidgetPalette.secondary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                selected ? OrbitWidgetPalette.accent.opacity(0.72) : OrbitWidgetPalette.raised,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(output.accessibilityLabel)")
    }

    private var statusColor: Color {
        if entry.snapshot.lastCommandFailed { return .orange }
        return entry.snapshot.connected ? Color(red: 0.30, green: 0.88, blue: 0.48) : OrbitWidgetPalette.secondary
    }

    private var statusLabel: String {
        if entry.snapshot.lastCommandFailed { return "RETRY" }
        return entry.snapshot.connected ? "ONLINE" : "OFFLINE"
    }
}

private extension OrbitWidgetOutput {
    var accessibilityLabel: String {
        switch self {
        case .monA: return "monitor A"
        case .monB: return "monitor B"
        case .hp1: return "headphones 1"
        case .hp2: return "headphones 2"
        }
    }
}

struct MKOrbitControlWidget: Widget {
    let kind = OrbitWidgetConfiguration.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OrbitWidgetProvider()) { entry in
            MKOrbitControlWidgetView(entry: entry)
        }
        .configurationDisplayName("MK-OrbitControl")
        .description("Fast Antelope monitor and headphone control from the desktop.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct MKOrbitControlWidgetBundle: WidgetBundle {
    var body: some Widget {
        MKOrbitControlWidget()
    }
}

#Preview(as: .systemMedium) {
    MKOrbitControlWidget()
} timeline: {
    OrbitWidgetEntry(
        date: Date(),
        snapshot: OrbitWidgetSnapshot(
            outputRawValue: 0,
            volume: 44,
            muted: false,
            dimmed: false,
            connected: true,
            updatedAt: Date(),
            lastCommandFailed: false
        )
    )
}
