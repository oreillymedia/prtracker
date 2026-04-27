import Testing
@testable import PRTracker

@Suite struct KeychainTests {
    @Test func saveLoadDelete() {
        let kc = Keychain(service: "com.prtracker.github.test", account: "pat")
        kc.delete()
        #expect(kc.load() == nil)
        kc.save("ghp_test_token")
        #expect(kc.load() == "ghp_test_token")
        kc.save("ghp_replaced")
        #expect(kc.load() == "ghp_replaced")
        kc.delete()
        #expect(kc.load() == nil)
    }
}
