import Foundation
import Testing
@testable import GrailsKit

/// 20k-item budgets from PLAN.md §6. Gated because they take ~20 s: `GRAILS_PERF=1 swift test --filter PerformanceTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GRAILS_PERF"] != nil))
struct PerformanceTests {
    @Test func twentyThousandItemLibraryMeetsBudgets() async throws {
        let root = TestSupport.tempDir("fixture").appendingPathComponent("Big.grails")
        let t0 = Date()
        let layout = try FixtureLibrary.generate(at: root, count: 20_000)
        print("fixture generated in \(Date().timeIntervalSince(t0))s")

        let index = try LibraryIndex(path: TestSupport.tempDir().appendingPathComponent("perf.sqlite"))
        let t1 = Date()
        let failures = try await index.rebuild(from: layout)
        let rebuild = Date().timeIntervalSince(t1)
        print("rebuild 20k: \(rebuild)s")
        #expect(failures.isEmpty)
        #expect(try await index.count(ItemQuery()) == 20_000)
        #expect(rebuild < 10)

        var worst = 0.0
        for text in ["biryani", "warm night", "item 0123", "typo", "cha"] {
            let t = Date()
            _ = try await index.query(ItemQuery(text: text))
            worst = max(worst, Date().timeIntervalSince(t))
        }
        print("worst FTS query: \(worst * 1000)ms")
        #expect(worst < 0.05)

        let store = try await LibraryStore.open(at: root, index: index)
        let t2 = Date()
        let r = try await store.rescan()
        print("no-op rescan 20k: \(Date().timeIntervalSince(t2))s")
        #expect(r == RescanResult())
    }
}
