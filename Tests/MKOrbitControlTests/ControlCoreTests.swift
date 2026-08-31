import AppKit
import Combine
import XCTest
@testable import MKOrbitControl

final class ControlCoreTests: XCTestCase {
    func testDeclaredInterfaceSymbolsResolve() {
        let symbols = Set(
            OutputChannel.allCases.map(\.icon)
                + MenuBarIcon.allCases.map(\.rawValue)
                + [
                    "speaker.minus.fill", "speaker.slash.fill",
                    "circle.lefthalf.filled", "moon.fill", "macwindow", "gearshape", "power",
                    "paintbrush", "keyboard", "pianokeys", "info.circle",
                ]
        )

        for symbol in symbols {
            XCTAssertNotNil(
                NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
                "Missing SF Symbol: \(symbol)"
            )
        }
    }

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

    func testMissingVolumeStateFailsQuietForHotkeyAdjustments() {
        XCTAssertEqual(VolumeScale.adjustedRaw(nil, by: -1), 95)
        XCTAssertEqual(VolumeScale.adjustedRaw(nil, by: 1), 96)
        XCTAssertEqual(VolumeScale.adjustedRaw(0, by: -1), 0)
        XCTAssertEqual(VolumeScale.adjustedRaw(96, by: 1), 96)
    }

    func testControlPreferencesPersistAndRejectInvalidValues() throws {
        let suiteName = "ControlCoreTests.DevicePreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = DeviceState(defaults: defaults)
        XCTAssertEqual(state.selectedOutput, .monA)
        XCTAssertEqual(state.nightModeMax, 40)
        XCTAssertEqual(state.volumeStep, 3)
        XCTAssertFalse(state.miniMode)

        state.selectedOutput = .hp2
        state.nightModeMax = 50
        state.volumeStep = 6
        state.miniMode = true

        let restored = DeviceState(defaults: defaults)
        XCTAssertEqual(restored.selectedOutput, .hp2)
        XCTAssertEqual(restored.nightModeMax, 50)
        XCTAssertEqual(restored.volumeStep, 6)
        XCTAssertTrue(restored.miniMode)

        restored.nightModeMax = 7
        restored.volumeStep = 99
        XCTAssertEqual(restored.nightModeMax, 40)
        XCTAssertEqual(restored.volumeStep, 3)
    }

    func testDuplicatePhysicalBindingsResolveToTheNewestAction() {
        let firstHotkey = HotkeyBinding(keyCode: 12, modifiers: 1, action: .volumeUpMonA)
        let conflictingHotkey = HotkeyBinding(keyCode: 12, modifiers: 1, action: .muteHP1)
        let replacedAction = HotkeyBinding(keyCode: 13, modifiers: 1, action: .volumeUpMonA)
        XCTAssertEqual(
            HotkeyBinding.reconciled([firstHotkey, conflictingHotkey, replacedAction]),
            [conflictingHotkey, replacedAction]
        )

        let firstMIDI = MIDIMapping(channel: 0, cc: 7, action: .volumeMonA)
        let conflictingMIDI = MIDIMapping(channel: 0, cc: 7, action: .muteHP1)
        let invalidMIDI = MIDIMapping(channel: 16, cc: 7, action: .volumeHP2)
        XCTAssertEqual(
            MIDIMapping.reconciled([firstMIDI, conflictingMIDI, invalidMIDI]),
            [conflictingMIDI]
        )
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
