import AppKit
import SwiftUI

final class VolumeHUD {
    static let shared = VolumeHUD()

    private var window: NSWindow?
    private var hideTimer: Timer?

    func show(volume: Int, muted: Bool, channel: String) {
        DispatchQueue.main.async {
            self.hideTimer?.invalidate()
            self.createOrUpdate(volume: volume, muted: muted, channel: channel)
            self.hideTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
                self.hide()
            }
        }
    }

    private func createOrUpdate(volume: Int, muted: Bool, channel: String) {
        let hudView = HUDView(volume: volume, muted: muted, channel: channel)
        let hosting = NSHostingView(rootView: hudView)

        if let win = window {
            win.contentView = hosting
            win.orderFrontRegardless()
            win.alphaValue = 1
            return
        }

        let w: CGFloat = 200
        let h: CGFloat = 200

        guard let screen = NSScreen.main else { return }
        let x = (screen.frame.width - w) / 2
        let y = screen.frame.height * 0.25

        let win = NSPanel(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.contentView = hosting
        win.orderFrontRegardless()

        self.window = win
    }

    private func hide() {
        guard let win = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
            win.alphaValue = 1
        })
    }
}

// MARK: - HUD SwiftUI View

private struct HUDView: View {
    let volume: Int
    let muted: Bool
    let channel: String

    private var level: Double {
        if volume >= 96 { return 0 }
        return Double(96 - volume) / 96.0
    }

    private var dbText: String {
        if volume >= 96 { return "-∞" }
        if volume <= 0 { return "0" }
        return "-\(volume)"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Channel name
            Text(channel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            // Speaker icon
            Image(systemName: muted ? "speaker.slash.fill" : speakerIcon)
                .font(.system(size: 36))
                .foregroundColor(muted ? .red.opacity(0.8) : .white)

            // dB value
            Text("\(dbText) dB")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundColor(.white)

            // Volume bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * level)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 20)
        }
        .padding(20)
        .frame(width: 200, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var speakerIcon: String {
        if level > 0.66 { return "speaker.wave.3.fill" }
        if level > 0.33 { return "speaker.wave.2.fill" }
        if level > 0 { return "speaker.wave.1.fill" }
        return "speaker.slash.fill"
    }

    private var barColor: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.2, green: 0.8, blue: 0.4),
                Color(red: 0.9, green: 0.7, blue: 0.1),
                Color(red: 0.9, green: 0.2, blue: 0.2)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
