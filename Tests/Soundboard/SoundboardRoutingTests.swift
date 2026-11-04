import Testing

@Suite("SoundboardRouting")
struct SoundboardRoutingTests {
    private func device(
        _ uid: String, _ name: String, input: Bool = true, output: Bool = true
    )
        -> SoundboardRouting.Device
    {
        .init(uid: uid, name: name, hasInput: input, hasOutput: output)
    }

    private func process(
        pid: Int32 = 100, input: Bool = true, reading: [String] = []
    ) -> AudioProcess {
        AudioProcess(
            objectID: 1, pid: pid, isRunningOutput: false, isRunningInput: input, outputDeviceUID: nil,
            inputDeviceUIDs: reading)
    }

    @Test("the virtual microphone is the BlackHole device, the 2ch one when there are several")
    func findsBlackHole() {
        let devices = [
            device("mic", "Microfone", output: false),
            device("BlackHole16ch_UID", "BlackHole 16ch"),
            device("BlackHole2ch_UID", "BlackHole 2ch"),
        ]
        #expect(SoundboardRouting.blackHole(in: devices)?.uid == "BlackHole2ch_UID")
        #expect(SoundboardRouting.blackHole(in: Array(devices.prefix(2)))?.uid == "BlackHole16ch_UID")
    }

    @Test("without BlackHole there is no virtual microphone, and a device that only half of it does not count")
    func noBlackHole() {
        #expect(SoundboardRouting.blackHole(in: [device("mic", "Microfone", output: false)]) == nil)
        #expect(SoundboardRouting.blackHole(in: [device("BlackHole2ch_UID", "BlackHole 2ch", output: false)]) == nil)
        #expect(SoundboardRouting.blackHole(in: []) == nil)
    }

    @Test("the real microphone is the default input")
    func defaultInput() {
        let devices = [
            device("builtin", "Microfone (MacBook Pro)", output: false),
            device("headset", "Headset"),
            device("BlackHole2ch_UID", "BlackHole 2ch"),
        ]
        #expect(SoundboardRouting.microphone(defaultInputUID: "headset", devices: devices)?.uid == "headset")
    }

    @Test("when the system microphone is BlackHole itself, the first real input is used instead")
    func defaultIsVirtual() {
        let devices = [
            device("speakers", "Alto-falantes", input: false),
            device("BlackHole2ch_UID", "BlackHole 2ch"),
            device("builtin", "Microfone (MacBook Pro)", output: false),
        ]
        #expect(SoundboardRouting.microphone(defaultInputUID: "BlackHole2ch_UID", devices: devices)?.uid == "builtin")
        #expect(SoundboardRouting.microphone(defaultInputUID: nil, devices: devices)?.uid == "builtin")
    }

    @Test("no input device, no microphone")
    func noMicrophone() {
        let devices = [device("speakers", "Alto-falantes", input: false), device("BlackHole2ch_UID", "BlackHole 2ch")]
        #expect(SoundboardRouting.microphone(defaultInputUID: "speakers", devices: devices) == nil)
    }

    @Test("the feed runs while an app reads the virtual microphone")
    func feedsWhenInUse() {
        #expect(SoundboardRouting.shouldFeed(blackHoleUID: "bh", processes: [process(reading: ["bh"])]))
        #expect(SoundboardRouting.shouldFeed(blackHoleUID: "bh", processes: [process(reading: ["mic", "bh"])]))
    }

    @Test("it does not run when nobody uses it, or the app is on another microphone, or is not recording")
    func idleWhen() {
        #expect(!SoundboardRouting.shouldFeed(blackHoleUID: "bh", processes: []))
        #expect(!SoundboardRouting.shouldFeed(blackHoleUID: "bh", processes: [process(reading: ["mic"])]))
        #expect(!SoundboardRouting.shouldFeed(blackHoleUID: "bh", processes: [process(input: false, reading: ["bh"])]))
        #expect(!SoundboardRouting.shouldFeed(blackHoleUID: nil, processes: [process(reading: ["bh"])]))
    }
}
