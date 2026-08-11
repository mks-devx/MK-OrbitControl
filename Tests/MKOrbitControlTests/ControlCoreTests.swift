import Combine
import XCTest
@testable import MKOrbitControl

final class ControlCoreTests: XCTestCase {
    func testDynamicPortCandidatesIncludeShiftedDeviceEndpoint() {
        XCTAssertEqual(Array(AntelopeProtocol.candidatePorts.prefix(6)), [2024, 2021, 2023, 2022, 2025, 2020])
        XCTAssertTrue(AntelopeProtocol.candidatePorts.contains(2027))
        XCTAssertEqual(Set(AntelopeProtocol.candidatePorts).count, AntelopeProtocol.candidatePorts.count)
    }

    func testVolumeScaleClampsAndRoundTrips() {
        XCTAssertEqual(VolumeScale.clamp(raw: -1), 0)
        XCTAssertEqual(VolumeScale.clamp(raw: 120), 96)
        XCTAssertEqual(VolumeScale.rawToSlider(0), 96)
        XCTAssertEqual(VolumeScale.rawToSlider(96), 0)

        for raw in 0...96 {
            XCTAssertEqual(VolumeScale.sliderToRaw(VolumeScale.rawToSlider(raw)), raw)
        }
    }

    func testVolumeScaleDisplayAndMIDIEndpoints() {
        XCTAssertEqual(VolumeScale.rawToDisplay(0), "0")
        XCTAssertEqual(VolumeScale.rawToDisplay(40), "-40")
        XCTAssertEqual(VolumeScale.rawToDisplay(96), "-∞")
        XCTAssertEqual(VolumeScale.midiToRaw(0), 96)
        XCTAssertEqual(VolumeScale.midiToRaw(127), 0)
    }

    func testVersionComparisonHandlesDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewerVersion("1.4.1", than: "1.4"))
        XCTAssertTrue(UpdateChecker.isNewerVersion("2.0", than: "1.99.99"))
        XCTAssertFalse(UpdateChecker.isNewerVersion("1.4", than: "1.4.0"))
        XCTAssertFalse(UpdateChecker.isNewerVersion("1.3.9", than: "1.4"))
    }

    func testClearingPresetIsPersisted() throws {
        let suiteName = "ControlCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = DeviceState()
        state.channels[.monA] = ChannelState(volume: 40, mute: true)

        let manager = PresetManager(defaults: defaults)
        manager.save(slot: 0, name: "A", from: state)
        XCTAssertNotNil(PresetManager(defaults: defaults).get(slot: 0))

        manager.clear(slot: 0)
        XCTAssertNil(PresetManager(defaults: defaults).get(slot: 0))
    }

    func testCompactCyclicGreetingIsAccepted() {
        let greeting = Array(#"{"type": "cyclic", "protocol_version": 1, "contents": {}}"#.utf8)
        XCTAssertLessThan(greeting.count, 500)
        XCTAssertTrue(AntelopeProtocol.isCyclicPayload(greeting))
        XCTAssertFalse(AntelopeProtocol.isCyclicPayload(Array(#"{"type": "notification"}"#.utf8)))
    }

    func testAntelopeFrameLengthIncludesHeader() {
        XCTAssertEqual(AntelopeProtocol.payloadLength(totalFrameLength: 118), 114)
        XCTAssertEqual(AntelopeProtocol.totalFrameLength(payloadLength: 114), 118)
        XCTAssertNil(AntelopeProtocol.payloadLength(totalFrameLength: 4))
        XCTAssertNil(AntelopeProtocol.totalFrameLength(payloadLength: 0))
    }

    func testAppearanceSurfaceAndTransparencyPersistSafely() throws {
        let suiteName = "ControlCoreTests.Theme.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ThemeManager(defaults: defaults)
        manager.setSurfaceStyle(.translucent)
        manager.setBackgroundTransparency(0.9)

        let restored = ThemeManager(defaults: defaults)
        XCTAssertEqual(restored.surfaceStyle, .translucent)
        XCTAssertEqual(restored.backgroundTransparency, 0.75, accuracy: 0.001)

        restored.setBackgroundTransparency(-0.5)
        XCTAssertEqual(restored.backgroundTransparency, 0, accuracy: 0.001)
    }

    func testDeviceSnapshotDoesNotRepublishUnchangedChannels() {
        let state = DeviceState()
        var channelPublicationCount = 0
        let cancellable = state.$channels
            .dropFirst()
            .sink { _ in channelPublicationCount += 1 }
        defer { cancellable.cancel() }

        let first = ChannelState(volume: 55, mute: false, dim: false, mono: false)
        state.applySnapshot(channelUpdates: [.monA: first], peakLevels: [])
        XCTAssertEqual(channelPublicationCount, 1)

        state.applySnapshot(channelUpdates: [.monA: first], peakLevels: [])
        XCTAssertEqual(channelPublicationCount, 1)

        var changed = first
        changed.mute = true
        state.applySnapshot(channelUpdates: [.monA: changed], peakLevels: [])
        XCTAssertEqual(channelPublicationCount, 2)
    }
}
