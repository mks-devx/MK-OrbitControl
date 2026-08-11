import AppKit
import SwiftUI
import XCTest
@testable import MKOrbitControl

final class VisualSmokeTests: XCTestCase {
    @MainActor
    func testFullMenuRendersAtProductionSize() throws {
        let deviceState = DeviceState()
        deviceState.selectedOutput = .monA
        deviceState.channels[.monA] = ChannelState(volume: 55)

        let content = MenuBarView()
            .environmentObject(deviceState)
            .environmentObject(PresetManager())
            .environmentObject(ThemeManager())
            .environment(\.commander, AntelopeCommander())

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(
            width: OrbitControlLayout.fullSize.width,
            height: OrbitControlLayout.fullSize.height
        )
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, OrbitControlLayout.fullSize.width, accuracy: 0.5)
        XCTAssertEqual(image.size.height, OrbitControlLayout.fullSize.height, accuracy: 0.5)

        guard let capturePath = ProcessInfo.processInfo.environment["MK_CAPTURE_UI"] else {
            return
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: capturePath), options: .atomic)
    }
}
