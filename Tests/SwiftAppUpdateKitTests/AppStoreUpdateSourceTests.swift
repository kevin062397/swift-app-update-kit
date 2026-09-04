//
//  AppStoreUpdateSourceTests.swift
//  SwiftAppUpdateKitTests
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation
import Testing

@testable import SwiftAppUpdateKit

struct AppStoreUpdateSourceTests {
    // MARK: - Test Helpers

    private actor MockSession {
        private(set) var capturedRequests: [URLRequest] = []
        private var responses: [Result<(Data, URLResponse), any Error>]

        init(_ responses: [Result<(Data, URLResponse), any Error>]) {
            self.responses = responses
        }

        func send(_ request: URLRequest) throws -> (Data, URLResponse) {
            self.capturedRequests.append(request)
            guard !self.responses.isEmpty else { throw URLError(.badServerResponse) }
            return try self.responses.removeFirst().get()
        }
    }

    private func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://itunes.apple.com/lookup")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    private var validResponseData: Data {
        Data(
            """
            {
                "resultCount": 1,
                "results": [{
                    "trackId": 1234567890,
                    "bundleId": "com.example.app",
                    "version": "1.5.0",
                    "minimumOsVersion": "17.0",
                    "currentVersionReleaseDate": "2026-08-14T07:00:00Z",
                    "trackViewUrl": "https://apps.apple.com/us/app/example-app/id1234567890",
                    "fileSizeBytes": "44039168"
                }]
            }
            """
            .utf8
        )
    }

    private func queryItems(from request: URLRequest) -> [URLQueryItem] {
        guard let url = request.url else { return [] }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    // MARK: - Response Body Preview

    @Test func responseBodyPreviewReportsEmptyResponse() {
        let preview = AppStoreUpdateSource.responseBodyPreview(from: Data())

        #expect(preview == "<empty response>")
    }

    @Test func responseBodyPreviewIsCapped() {
        let data = Data(String(repeating: "a", count: 2050).utf8)

        let preview = AppStoreUpdateSource.responseBodyPreview(from: data)

        #expect(preview.hasPrefix(String(repeating: "a", count: 2048)))
        #expect(preview.contains("truncated to 2048 bytes"))
    }

    // MARK: - URL Construction

    @Test func lookupURLAlwaysIncludesBundleIdentifier() async {
        let session = MockSession([.success((Data(), httpResponse(statusCode: 404)))])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        _ = try? await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: nil,
            languageCode: nil
        )

        let requests = await session.capturedRequests
        let items = requests.first.map { self.queryItems(from: $0) } ?? []
        #expect(items.contains(URLQueryItem(name: "bundleId", value: "com.example.app")))
    }

    @Test func lookupURLOmitsCountryWhenStorefrontIsNil() async {
        let session = MockSession([.success((Data(), httpResponse(statusCode: 404)))])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        _ = try? await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: nil,
            languageCode: nil
        )

        let requests = await session.capturedRequests
        let items = requests.first.map { self.queryItems(from: $0) } ?? []
        #expect(!items.contains(where: { $0.name == "country" }))
    }

    @Test func lookupURLIncludesCountryWhenStorefrontIsProvided() async {
        let session = MockSession([.success((Data(), httpResponse(statusCode: 404)))])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        _ = try? await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: "JP",
            languageCode: nil
        )

        let requests = await session.capturedRequests
        let items = requests.first.map { self.queryItems(from: $0) } ?? []
        // Country code is normalized to lowercase before URL construction.
        #expect(items.contains(URLQueryItem(name: "country", value: "jp")))
    }

    @Test func lookupURLIncludesLanguageWhenProvided() async {
        let session = MockSession([.success((Data(), httpResponse(statusCode: 404)))])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        _ = try? await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: nil,
            languageCode: "ZH_CN"
        )

        let requests = await session.capturedRequests
        let items = requests.first.map { self.queryItems(from: $0) } ?? []
        #expect(items.contains(URLQueryItem(name: "lang", value: "zh_cn")))
    }

    @Test func lookupURLKeepsStorefrontAndLanguageIndependent() async {
        let session = MockSession([.success((Data(), httpResponse(statusCode: 404)))])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        _ = try? await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: "CN",
            languageCode: "en_us"
        )

        let requests = await session.capturedRequests
        let items = requests.first.map { self.queryItems(from: $0) } ?? []
        #expect(items.contains(URLQueryItem(name: "country", value: "cn")))
        #expect(items.contains(URLQueryItem(name: "lang", value: "en_us")))
    }

    @Test func requestBypassesURLCache() async {
        let session = MockSession([.success((Data(), httpResponse(statusCode: 404)))])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        _ = try? await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: nil,
            languageCode: nil
        )

        let requests = await session.capturedRequests
        #expect(requests.first?.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    // MARK: - Retry Policy

    @Test func transportFailureIsRetried() async {
        let session = MockSession([
            .failure(URLError(.notConnectedToInternet)),
            .success((self.validResponseData, self.httpResponse(statusCode: 200))),
        ])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        _ = try? await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: nil,
            languageCode: nil
        )

        let requestCount = await session.capturedRequests.count
        #expect(requestCount == 2)
    }

    @Test func serverErrorAbove500IsRetried() async {
        let session = MockSession([
            .success((Data(), self.httpResponse(statusCode: 503))),
            .success((self.validResponseData, self.httpResponse(statusCode: 200))),
        ])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        _ = try? await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: nil,
            languageCode: nil
        )

        let requestCount = await session.capturedRequests.count
        #expect(requestCount == 2)
    }

    @Test func serverErrorBelow500IsNotRetried() async {
        let session = MockSession([
            .success((Data(), self.httpResponse(statusCode: 404)))
        ])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }

        var thrownError: LookupRequestError?
        do {
            _ = try await source.fetchMetadata(
                bundleIdentifier: "com.example.app",
                storefrontCountryCode: nil,
                languageCode: nil
            )
        } catch {
            thrownError = error
        }

        #expect(thrownError == .serverError(statusCode: 404))
        let requestCount = await session.capturedRequests.count
        #expect(requestCount == 1)
    }

    @Test func decodingFailureIsNotRetried() async {
        let truncatedPayload = Data("{}".utf8)
        let session = MockSession([
            .success((truncatedPayload, self.httpResponse(statusCode: 200)))
        ])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }

        var thrownError: LookupRequestError?
        do {
            _ = try await source.fetchMetadata(
                bundleIdentifier: "com.example.app",
                storefrontCountryCode: nil,
                languageCode: nil
            )
        } catch {
            thrownError = error
        }

        #expect(thrownError == .malformedResponse)
        let requestCount = await session.capturedRequests.count
        #expect(requestCount == 1)
    }

    @Test func secondAttemptFailureIsPropagated() async {
        let session = MockSession([
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet)),
        ])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }

        var thrownError: LookupRequestError?
        do {
            _ = try await source.fetchMetadata(
                bundleIdentifier: "com.example.app",
                storefrontCountryCode: nil,
                languageCode: nil
            )
        } catch {
            thrownError = error
        }

        #expect(thrownError == .networkUnreachable)
        let requestCount = await session.capturedRequests.count
        #expect(requestCount == 2)
    }

    @Test func successfulResponseDecodes() async throws {
        let session = MockSession([
            .success((self.validResponseData, self.httpResponse(statusCode: 200)))
        ])
        let source = AppStoreUpdateSource(retryDelay: .seconds(0)) { request in
            try await session.send(request)
        }
        let metadata = try await source.fetchMetadata(
            bundleIdentifier: "com.example.app",
            storefrontCountryCode: nil,
            languageCode: nil
        )
        #expect(metadata.version == AppVersion("1.5.0"))
        #expect(metadata.trackID == 1_234_567_890)
    }
}
