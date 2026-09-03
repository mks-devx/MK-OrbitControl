import XCTest
@testable import MKOrbitControl

final class HardwareIntegrationTests: XCTestCase {
    func testNativeCommandsAgainstConnectedHardwareAtSaferLevel() throws {
        guard ProcessInfo.processInfo.environment["MK_ORBIT_HARDWARE_TEST"] == "1" else {
            throw XCTSkip("Set MK_ORBIT_HARDWARE_TEST=1 for the controlled hardware test.")
        }

        let state = DeviceState(defaults: isolatedDefaults())
        let reader = AntelopeStateReader(deviceState: state)
        state.stateReader = reader
        reader.start()
        defer { reader.stop() }

        XCTAssertTrue(
            waitUntil(timeout: 12) { state.connected },
            "The local Antelope service did not provide device state."
        )

        let channel = OutputChannel.monA
        guard let original = state.channels[channel] else {
            XCTFail("MON A state is unavailable.")
            return
        }
        guard original.volume < VolumeScale.maximumRaw else {
            throw XCTSkip("MON A is already silent; no quieter mutation is available.")
        }

        let commander = AntelopeCommander()
        defer {
            XCTAssertTrue(
                waitForCommand {
                    commander.setVolume(
                        channel: channel,
                        value: original.volume,
                        completion: $0
                    )
                },
                "Could not restore the original MON A volume."
            )
            XCTAssertTrue(
                waitUntil(timeout: 5) { state.channels[channel]?.volume == original.volume },
                "The restored MON A volume was not observed."
            )
        }

        let saferVolume = original.volume + 1
        XCTAssertTrue(waitForCommand { commander.setVolume(channel: channel, value: saferVolume, completion: $0) })
        XCTAssertTrue(
            waitUntil(timeout: 5) { state.channels[channel]?.volume == saferVolume },
            "The 1 dB quieter MON A value was not observed."
        )
        XCTAssertTrue(waitForCommand { commander.setMute(channel: channel, muted: original.mute, completion: $0) })
        XCTAssertTrue(waitForCommand { commander.setDim(channel: channel, dimmed: original.dim, completion: $0) })
        XCTAssertTrue(waitForCommand { commander.setMono(channel: channel, mono: original.mono, completion: $0) })
    }

    private func waitForCommand(
        timeout: TimeInterval = 8,
        _ start: (@escaping (Bool) -> Void) -> Void
    ) -> Bool {
        var result: Bool?
        start { result = $0 }
        _ = waitUntil(timeout: timeout) { result != nil }
        return result ?? false
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "HardwareIntegrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
