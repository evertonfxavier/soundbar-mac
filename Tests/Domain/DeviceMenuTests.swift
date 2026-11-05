import Testing

@Suite("DeviceMenu")
struct DeviceMenuTests {
    private func device(
        _ uid: String, _ name: String, input: Bool = true, output: Bool = true
    )
        -> SoundboardRouting.Device
    {
        .init(uid: uid, name: name, hasInput: input, hasOutput: output)
    }

    private var devices: [SoundboardRouting.Device] {
        [
            device("speakers", "Alto-falantes (MacBook Pro)", input: false),
            device("headset", "Studio Pro WHG03P"),
            device("BlackHole2ch_UID", "BlackHole 2ch"),
            device("builtin", "Microfone (MacBook Pro)", output: false),
        ]
    }

    @Test("the speakers offered are the devices with outputs, by name, without BlackHole")
    func outputs() {
        #expect(DeviceMenu.outputs(from: devices).map(\.uid) == ["speakers", "headset"])
    }

    @Test("the microphones offered are the devices with inputs, by name, BlackHole included")
    func inputs() {
        #expect(DeviceMenu.inputs(from: devices).map(\.uid) == ["BlackHole2ch_UID", "builtin", "headset"])
    }

    @Test("the names are sorted without regard to case")
    func sortedIgnoringCase() {
        let list = [device("b", "beta"), device("a", "Alfa"), device("c", "Charlie")]
        #expect(DeviceMenu.inputs(from: list).map(\.uid) == ["a", "b", "c"])
    }

    @Test("nothing in, nothing out")
    func empty() {
        #expect(DeviceMenu.outputs(from: []).isEmpty)
        #expect(DeviceMenu.inputs(from: []).isEmpty)
    }
}
