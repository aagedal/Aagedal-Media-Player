// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testSuccessfulManualAndAutomaticChecksRecordLastChecked() async throws {
        let defaults = try makeDefaults()
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let checker = makeChecker(defaults: defaults, clock: clock) { _ in
            UpdateHTTPResponse(data: Self.releaseJSON(tag: "v1.6.1"), statusCode: 200)
        }

        let manualResult = await checker.checkNow(isUserInitiated: true)

        XCTAssertEqual(manualResult, .upToDate(Self.release(version: "1.6.1")))
        XCTAssertEqual(checker.lastChecked, Date(timeIntervalSince1970: 1_000))

        clock.date = Date(timeIntervalSince1970: 2_000)
        let automaticResult = await checker.checkNow(isUserInitiated: false)

        XCTAssertEqual(automaticResult, .upToDate(Self.release(version: "1.6.1")))
        XCTAssertEqual(checker.lastChecked, Date(timeIntervalSince1970: 2_000))
    }

    func testSuccessfulCheckPublishesTypedAvailableRelease() async throws {
        let defaults = try makeDefaults()
        let checker = makeChecker(defaults: defaults) { _ in
            UpdateHTTPResponse(data: Self.releaseJSON(tag: "v2.0.0"), statusCode: 200)
        }

        let result = await checker.checkNow()

        XCTAssertEqual(result, .updateAvailable(Self.release(version: "2.0.0")))
        XCTAssertTrue(checker.updateAvailable)
        XCTAssertEqual(checker.latestVersion, "2.0.0")
        XCTAssertEqual(checker.releaseNotesURL, URL(string: "https://example.com/release"))
        XCTAssertEqual(checker.downloadAssetURL, URL(string: "https://example.com/player.zip"))
    }

    func testFailedRefreshCannotPresentStaleUpToDateState() async throws {
        let defaults = try makeDefaults()
        let source = SequencedUpdateSource()
        let checker = makeChecker(defaults: defaults) { request in
            try await source.fetch(request)
        }

        let firstResult = await checker.checkNow()
        let successfulCheckDate = checker.lastChecked
        let secondResult = await checker.checkNow()

        XCTAssertEqual(firstResult, .upToDate(Self.release(version: "1.6.1")))
        guard case .failed(let failure) = secondResult else {
            return XCTFail("Expected a typed failure, got \(secondResult)")
        }
        XCTAssertTrue(failure.isRetryable)
        XCTAssertNil(checker.result.release)
        XCTAssertFalse(checker.updateAvailable)
        XCTAssertEqual(checker.lastChecked, successfulCheckDate)
    }

    func testHTTPFailuresDescribeWhetherRetryIsAppropriate() async throws {
        let defaults = try makeDefaults()
        let unavailable = makeChecker(defaults: defaults) { _ in
            UpdateHTTPResponse(data: Data(), statusCode: 503)
        }
        let missing = makeChecker(defaults: defaults) { _ in
            UpdateHTTPResponse(data: Data(), statusCode: 404)
        }

        let unavailableResult = await unavailable.checkNow()
        let missingResult = await missing.checkNow()

        guard case .failed(let unavailableFailure) = unavailableResult,
              case .failed(let missingFailure) = missingResult else {
            return XCTFail("Expected typed HTTP failures")
        }
        XCTAssertTrue(unavailableFailure.isRetryable)
        XCTAssertFalse(missingFailure.isRetryable)
    }

    func testInvalidResponseDoesNotAdvanceLastChecked() async throws {
        let defaults = try makeDefaults()
        let previousDate = Date(timeIntervalSince1970: 500)
        defaults.set(previousDate, forKey: AppSettings.updateLastChecked.key)
        let checker = makeChecker(defaults: defaults) { _ in
            UpdateHTTPResponse(data: Data("{}".utf8), statusCode: 200)
        }

        let result = await checker.checkNow()

        XCTAssertEqual(result, .failed(.invalidResponse))
        XCTAssertEqual(checker.lastChecked, previousDate)
    }

    func testAutomaticCheckUsesInjectedTimeForIntervalDecision() async throws {
        let defaults = try makeDefaults()
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let requests = RequestCounter()
        defaults.set(Date(timeIntervalSince1970: 900), forKey: AppSettings.updateLastChecked.key)
        let checker = makeChecker(defaults: defaults, clock: clock) { _ in
            requests.increment()
            return UpdateHTTPResponse(data: Self.releaseJSON(tag: "v1.6.1"), statusCode: 200)
        }

        XCTAssertNil(checker.checkIfNeeded())
        XCTAssertEqual(requests.count, 0)

        clock.date = Date(timeIntervalSince1970: 700_000)
        let task = try XCTUnwrap(checker.checkIfNeeded())
        _ = await task.value

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(checker.lastChecked, clock.date)
    }

    private func makeChecker(
        defaults: UserDefaults,
        clock: TestClock = TestClock(Date(timeIntervalSince1970: 1_000)),
        fetch: @escaping UpdateChecker.Fetch
    ) -> UpdateChecker {
        UpdateChecker(
            defaults: defaults,
            now: { clock.date },
            currentVersion: "1.6.1",
            isHomebrewInstall: true,
            sparkleIsActive: false,
            fetch: fetch
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "UpdateCheckerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    nonisolated private static func release(version: String) -> UpdateRelease {
        UpdateRelease(
            version: version,
            releaseNotesURL: URL(string: "https://example.com/release"),
            downloadAssetURL: URL(string: "https://example.com/player.zip")
        )
    }

    nonisolated fileprivate static func releaseJSON(tag: String) -> Data {
        Data("""
        {
          "tag_name": "\(tag)",
          "html_url": "https://example.com/release",
          "assets": [
            {
              "name": "Aagedal-Media-Player.zip",
              "browser_download_url": "https://example.com/player.zip"
            }
          ]
        }
        """.utf8)
    }
}

private final class TestClock: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var storedDate: Date

    nonisolated init(_ date: Date) {
        storedDate = date
    }

    nonisolated var date: Date {
        get { lock.withLock { storedDate } }
        set { lock.withLock { storedDate = newValue } }
    }
}

private actor SequencedUpdateSource {
    private var requestCount = 0

    func fetch(_: URLRequest) throws -> UpdateHTTPResponse {
        requestCount += 1
        if requestCount == 1 {
            return UpdateHTTPResponse(
                data: UpdateCheckerTests.releaseJSON(tag: "v1.6.1"),
                statusCode: 200
            )
        }
        throw URLError(.notConnectedToInternet)
    }
}

private final class RequestCounter: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var value = 0

    nonisolated var count: Int {
        lock.withLock { value }
    }

    nonisolated func increment() {
        lock.withLock { value += 1 }
    }
}
