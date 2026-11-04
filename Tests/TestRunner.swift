import Testing

/// The entry point of the test executable built by scripts/test.sh: Swift Testing runs every `@Test` it finds.
/// (`swift test` would do this, but the Swift Package Manager is not usable with every Command Line Tools release.)
@main
struct TestRunner {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
