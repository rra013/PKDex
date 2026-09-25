//
//  LimitlessAPIErrorTests.swift
//  PKDexTests
//
//  Covers `LimitlessAPIError`: which HTTP responses throw, reading
//  Retry-After in both its forms, which errors are worth retrying, and the
//  messages the Tournaments tab shows.
//

import Testing
import Foundation
@testable import PKDex

@Suite("Limitless API Errors")
struct LimitlessAPIErrorTests {

    /// Noon UTC, Thursday 2026-09-24.
    private static let now = Date(timeIntervalSince1970: 1_790_251_200)
    private static let url = URL(string: "https://play.limitlesstcg.com/api/tournaments")!

    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: Self.url, statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: headers)!
    }

    private func error(from response: URLResponse) -> LimitlessAPIError? {
        do {
            try LimitlessAPIError.check(response, now: Self.now)
            return nil
        } catch {
            return error as? LimitlessAPIError
        }
    }

    @Test("Success statuses and non-HTTP responses pass")
    func successPasses() {
        #expect(error(from: response(200)) == nil)
        #expect(error(from: response(204)) == nil)
        #expect(error(from: URLResponse(url: Self.url, mimeType: nil, expectedContentLength: 0,
                                        textEncodingName: nil)) == nil)
    }

    @Test("A 429 is a rate limit, with Retry-After in seconds or as a date")
    func rateLimits() {
        #expect(error(from: response(429, headers: ["Retry-After": "30"]))
                == .rateLimited(retryAfter: 30))
        #expect(error(from: response(429, headers: ["Retry-After": "Thu, 24 Sep 2026 12:01:00 GMT"]))
                == .rateLimited(retryAfter: 60))
        #expect(error(from: response(429)) == .rateLimited(retryAfter: nil))
    }

    @Test("Other statuses are HTTP errors; only server errors are transient")
    func otherStatuses() {
        #expect(error(from: response(503)) == .http(status: 503))
        #expect(error(from: response(404)) == .http(status: 404))
        #expect(LimitlessAPIError.http(status: 503).isTransient)
        #expect(!LimitlessAPIError.http(status: 404).isTransient)
        #expect(LimitlessAPIError.rateLimited(retryAfter: nil).isTransient)
    }

    @Test("Retry-After parsing edge cases")
    func retryAfterParsing() {
        #expect(LimitlessAPIError.retryAfter(" 12 ", now: Self.now) == 12)
        #expect(LimitlessAPIError.retryAfter("-5", now: Self.now) == 0)
        #expect(LimitlessAPIError.retryAfter("Thu, 24 Sep 2026 11:00:00 GMT", now: Self.now) == 0)
        #expect(LimitlessAPIError.retryAfter("soon", now: Self.now) == nil)
        #expect(LimitlessAPIError.retryAfter(nil, now: Self.now) == nil)
    }

    @Test("Messages say what happened and when to try again")
    func messages() {
        #expect(LimitlessAPIError.rateLimited(retryAfter: 2.2).errorDescription
                == "Limitless is limiting requests right now. Try again in 3 seconds.")
        #expect(LimitlessAPIError.rateLimited(retryAfter: nil).errorDescription
                == "Limitless is limiting requests right now. Try again in a minute.")
        #expect(LimitlessAPIError.http(status: 500).errorDescription
                == "Limitless returned an error (HTTP 500).")
    }
}
