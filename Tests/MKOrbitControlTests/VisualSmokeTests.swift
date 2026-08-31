import AppKit
import SwiftUI
import XCTest
@testable import MKOrbitControl

final class VisualSmokeTests: XCTestCase {
    @MainActor
    func testFullMenuRendersAtProductionSize() throws {
        let fixture = try makeFixture(miniMode: false)
        try render(
            fixture,
            size: OrbitControlLayout.fullSize,
            captureEnvironmentKey: "MK_CAPTURE_UI_FULL"
        )
    }

    @MainActor
    func testMiniMenuRendersAtProductionSize() throws {
        let fixture = try makeFixture(miniMode: true)
        try render(
            fixture,
            size: OrbitControlLayout.miniSize,
            captureEnvironmentKey: "MK_CAPTURE_UI_MINI"
        )
    }

    @MainActor
    private func makeFixture(miniMode: Bool) throws -> AnyView {
        let suiteName = "VisualSmokeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let deviceState = DeviceState(defaults: defaults)
        deviceState.selectedOutput = .monA
        deviceState.channels[.monA] = ChannelState(volume: 55)
        deviceState.miniMode = miniMode
        deviceState.markDataReceived()

        let themeManager = ThemeManager(defaults: defaults)
        themeManager.setTheme(try XCTUnwrap(allThemes.first { $0.id == "crimson" }))
        themeManager.setSurfaceStyle(.solid)

        let content = MenuBarView()
            .environmentObject(deviceState)
            .environmentObject(PresetManager(defaults: defaults))
            .environmentObject(themeManager)
            .environment(\.commander, AntelopeCommander())
        return AnyView(content)
    }

    @MainActor
    private func render<Content: View>(
        _ content: Content,
        size: CGSize,
        captureEnvironmentKey: String
    ) throws {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(
            width: size.width,
            height: size.height
        )
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)

        let environment = ProcessInfo.processInfo.environment
        guard let capturePath = environment[captureEnvironmentKey] ?? environment["MK_CAPTURE_UI"] else {
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
    }
}
