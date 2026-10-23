import Foundation
import Testing
@testable import GrailsKit

@Suite struct ExtensionNudgeTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func show(_ record: ExtensionNudgeRecord, safari: Bool, browser: ExtensionNudgeBrowser = .other, enabled: Bool = false, now: Date? = nil) -> ExtensionNudgeOffer? {
        record.offer(safariAvailable: safari, browser: browser, safariEnabled: enabled, now: now ?? start)
    }

    @Test func aFreshRecordOffersOnlyChromeWhileSafariIsOff() {
        let record = ExtensionNudgeRecord()
        for browser in [ExtensionNudgeBrowser.chromium, .safari, .other] {
            let offer = show(record, safari: false, browser: browser)
            #expect(offer == ExtensionNudgeOffer(primary: .addToChrome, secondary: nil, compact: false))
        }
    }

    @Test func theDefaultBrowserActionComesFirstWhenSafariIsOn() {
        let record = ExtensionNudgeRecord()
        #expect(show(record, safari: true, browser: .chromium) == ExtensionNudgeOffer(primary: .addToChrome, secondary: .enableInSafari, compact: false))
        #expect(show(record, safari: true, browser: .safari) == ExtensionNudgeOffer(primary: .enableInSafari, secondary: .addToChrome, compact: false))
        #expect(show(record, safari: true, browser: .other) == ExtensionNudgeOffer(primary: .addToChrome, secondary: .enableInSafari, compact: true))
    }

    @Test func aChromePairHidesItForGood() {
        var record = ExtensionNudgeRecord()
        record.note(.chromeStore)
        record.note(.chromeStore)
        #expect(record.chromePaired)
        #expect(show(record, safari: false) == nil)
        #expect(show(record, safari: true, browser: .safari, enabled: false) == nil)
        record.snooze(now: start)
        #expect(show(record, safari: false, now: start.addingTimeInterval(ExtensionNudgeRecord.snoozeInterval)) == nil)
    }

    @Test func aSafariPairCountsOnlyWhileSafariIsAvailable() {
        var record = ExtensionNudgeRecord()
        record.note(.safari(UUID()))
        #expect(record.safariPaired)
        #expect(show(record, safari: false) == ExtensionNudgeOffer(primary: .addToChrome, secondary: nil, compact: false))
        #expect(show(record, safari: true, enabled: false) == nil)
    }

    @Test func safariEnabledHidesItOnlyWhileTheSwitchIsOn() {
        let record = ExtensionNudgeRecord()
        #expect(show(record, safari: false, enabled: true) == ExtensionNudgeOffer(primary: .addToChrome, secondary: nil, compact: false))
        #expect(show(record, safari: true, enabled: true) == nil)
    }

    @Test func snoozeHidesItUntilThreeDaysPass() {
        var record = ExtensionNudgeRecord()
        record.snooze(now: start)
        let interval = ExtensionNudgeRecord.snoozeInterval
        #expect(interval == 3 * 24 * 60 * 60)
        #expect(show(record, safari: false, now: start.addingTimeInterval(interval - 1)) == nil)
        #expect(show(record, safari: false, now: start.addingTimeInterval(interval)) == ExtensionNudgeOffer(primary: .addToChrome, secondary: nil, compact: false))
        let later = start.addingTimeInterval(86_400)
        record.snooze(now: later)
        #expect(show(record, safari: true, browser: .chromium, now: later.addingTimeInterval(interval - 1)) == nil)
        #expect(show(record, safari: true, browser: .chromium, now: later.addingTimeInterval(interval)) == ExtensionNudgeOffer(primary: .addToChrome, secondary: .enableInSafari, compact: false))
    }

    @Test func theRecordRoundTripsAndIgnoresGarbage() throws {
        let name = "extension-nudge-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ExtensionNudgeRecord.load(defaults) == ExtensionNudgeRecord())
        var record = ExtensionNudgeRecord()
        record.note(.chromeStore)
        record.snooze(now: start)
        record.save(defaults)
        #expect(ExtensionNudgeRecord.load(defaults) == record)
        defaults.set(Data("nope".utf8), forKey: ExtensionNudgeRecord.defaultsKey)
        #expect(ExtensionNudgeRecord.load(defaults) == ExtensionNudgeRecord())
    }
}
