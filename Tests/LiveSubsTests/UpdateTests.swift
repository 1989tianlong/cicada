import Foundation
import Testing
@testable import LiveSubs

@Suite struct UpdateTests {
    @Test func versionsCompareNumerically() {
        #expect(UpdateChecker.isNewer("2.10.0", than: "2.9.1"))
        #expect(UpdateChecker.isNewer("2.0.1", than: "2.0"))
        #expect(!UpdateChecker.isNewer("2.0", than: "2.0.0"))
        #expect(!UpdateChecker.isNewer("1.9.9", than: "2.0.0"))
        #expect(!UpdateChecker.isNewer("2.0.0", than: "2.0.0"))
    }

    @Test func checksumIsFoundByName() {
        let file = Data("""
            AAA111  Cicada-2.1.0-macOS-AppleSilicon.dmg
            BBB222 *Cicada-2.1.0-macOS-AppleSilicon.zip
            """.utf8)
        #expect(Updater.expectedHash(of: "Cicada-2.1.0-macOS-AppleSilicon.zip", in: file) == "bbb222")
        #expect(Updater.expectedHash(of: "Cicada-2.1.0-macOS-AppleSilicon.dmg", in: file) == "aaa111")
        #expect(Updater.expectedHash(of: "Cicada-2.0.0-macOS-AppleSilicon.zip", in: file) == nil)
    }
}
