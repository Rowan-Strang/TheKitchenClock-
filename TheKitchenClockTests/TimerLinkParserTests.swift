import Foundation
import Testing
@testable import TheKitchenClock

struct TimerLinkParserTests {
    @Test func validTimerLinkParsesItsDuration() throws {
        let request = try TimerLinkParser.parse(try url("kitchenclock://timer?seconds=90"))

        #expect(request.duration == .seconds(90))
    }

    @Test func wrongSchemeIsRejected() throws {
        try expectParseFailure(
            "https://timer?seconds=30",
            expectedError: .invalidScheme
        )
    }

    @Test func wrongRouteIsRejected() throws {
        try expectParseFailure(
            "kitchenclock://preset?seconds=30",
            expectedError: .invalidRoute
        )
    }

    @Test func missingSecondsIsRejected() throws {
        try expectParseFailure(
            "kitchenclock://timer",
            expectedError: .invalidParameters
        )
    }

    @Test func malformedSecondsIsRejected() throws {
        try expectParseFailure(
            "kitchenclock://timer?seconds=thirty",
            expectedError: .invalidParameters
        )
    }

    @Test func duplicateSecondsIsRejected() throws {
        try expectParseFailure(
            "kitchenclock://timer?seconds=30&seconds=60",
            expectedError: .invalidParameters
        )
    }

    @Test func outOfRangeSecondsIsRejected() throws {
        try expectParseFailure(
            "kitchenclock://timer?seconds=0",
            expectedError: .invalidParameters
        )
    }

    @Test func extraParametersAreRejected() throws {
        try expectParseFailure(
            "kitchenclock://timer?seconds=30&repeat=true",
            expectedError: .invalidParameters
        )
    }

    private func expectParseFailure(
        _ link: String,
        expectedError: TimerLinkParser.Error
    ) throws {
        do {
            _ = try TimerLinkParser.parse(try url(link))
            Issue.record("Expected link parsing to fail.")
        } catch let error as TimerLinkParser.Error {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }
}
