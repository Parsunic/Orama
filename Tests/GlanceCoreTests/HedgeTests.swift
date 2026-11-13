import XCTest
@testable import GlanceCore

private struct Boom: Error {}

private func after(_ seconds: Double, _ value: String) -> Job<String> {
    { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); return value }
}

private func failAfter(_ seconds: Double) -> Job<String> {
    { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); throw Boom() }
}

/// Counts whether the backup was ever started.
private actor Flag {
    var raised = false
    func raise() { raised = true }
}

final class HedgeTests: XCTestCase {
    let policy = HedgePolicy(cloudTimeout: 0.5, hedgeDelay: 0.1, localTimeout: 1)

    func testFastCloudWinsAndBackupNeverStarts() async throws {
        let flag = Flag()
        let local: Job<String> = { await flag.raise(); return "local" }
        let (value, source) = try await runHedged(cloud: after(0.02, "cloud"), local: local, policy: policy)
        XCTAssertEqual(value, "cloud")
        XCTAssertEqual(source, .cloud)
        let started = await flag.raised
        XCTAssertFalse(started, "a fast cloud must not pay for the backup")
    }

    func testCloudOnlyTimesOut() async {
        do {
            _ = try await runHedged(cloud: after(2, "late"), local: nil, policy: policy)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertTrue(error is TimeoutError)
        }
    }

    func testSlowCloudLetsTheBackupAnswer() async throws {
        let (value, source) = try await runHedged(cloud: after(2, "late"), local: after(0.05, "local"), policy: policy)
        XCTAssertEqual(value, "local")
        XCTAssertEqual(source, .local)
    }

    func testCloudFailureStartsTheBackupImmediately() async throws {
        let started = Date()
        let (value, source) = try await runHedged(cloud: failAfter(0.01), local: after(0.01, "local"), policy: HedgePolicy(cloudTimeout: 5, hedgeDelay: 3, localTimeout: 1))
        XCTAssertEqual(value, "local")
        XCTAssertEqual(source, .local)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "should not wait for the hedge delay after a failure")
    }

    func testBothFailingReportsTheCloudError() async {
        do {
            _ = try await runHedged(cloud: failAfter(0.01), local: failAfter(0.01), policy: policy)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    func testNoServiceAtAll() async {
        do {
            _ = try await runHedged(cloud: nil as Job<String>?, local: nil, policy: policy)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is NoServiceError)
        }
    }

    func testCancellingTheCallerStopsTheRace() async {
        let task = Task { try await runHedged(cloud: after(5, "late"), local: nil, policy: HedgePolicy(cloudTimeout: 10, hedgeDelay: 1, localTimeout: 1)) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let result = await task.result
        if case .success = result { XCTFail("a cancelled race must not succeed") }
    }
}
