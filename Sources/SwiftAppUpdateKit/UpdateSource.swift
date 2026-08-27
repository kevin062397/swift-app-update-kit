//
//  UpdateSource.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 8/26/26.
//

import Foundation

// MARK: - Lookup Request Error

/// A failure that occurred while fetching store metadata from the App Store Lookup API.
enum LookupRequestError: Error, Equatable {
    /// The request could not be sent or completed.
    case networkUnreachable
    /// The endpoint responded with an HTTP status code outside the success range.
    case serverError(statusCode: Int)
    /// The response body could not be decoded into the expected shape.
    case malformedResponse
    /// The lookup succeeded but returned no app for the queried storefront.
    case absentFromStorefront
    /// The response describes a different bundle identifier than the one requested.
    case identityMismatch

    /// Whether this error warrants one automatic retry.
    ///
    /// Transport failures and server-side errors (5xx) may succeed on a second attempt.
    /// Client-side errors and decoding failures cannot.
    var isRetryable: Bool {
        switch self {
        case .networkUnreachable:
            return true
        case .serverError(let statusCode):
            return statusCode >= 500
        case .malformedResponse, .absentFromStorefront, .identityMismatch:
            return false
        }
    }
}

// MARK: - Update Source Protocol

/// A source that fetches store metadata for a given bundle identifier.
///
/// This is the seam for a future app-hosted update source. The App Store lookup
/// is the only implementation shipping now, but additional sources can be added
/// without changing the pipeline that calls them.
protocol UpdateSource: Sendable {
    func fetchMetadata(
        bundleIdentifier: String,
        storefrontCountryCode: String?
    ) async throws(LookupRequestError) -> AppStoreMetadata
}

// MARK: - App Store Update Source

/// The production update source that queries the iTunes Lookup API.
struct AppStoreUpdateSource: UpdateSource {
    private static let requestTimeoutInterval: TimeInterval = 15
    private static let defaultRetryDelay: Duration = .seconds(2)

    private let retryDelay: Duration
    private let performDataRequest: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(session: URLSession = .shared) {
        let capturedSession = session
        self.retryDelay = Self.defaultRetryDelay
        self.performDataRequest = { request in
            try await capturedSession.data(for: request)
        }
    }

    // For testing: allows control over responses and retry timing.
    init(
        retryDelay: Duration = Self.defaultRetryDelay,
        performDataRequest: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.retryDelay = retryDelay
        self.performDataRequest = performDataRequest
    }

    func fetchMetadata(
        bundleIdentifier: String,
        storefrontCountryCode: String?
    ) async throws(LookupRequestError) -> AppStoreMetadata {
        let url = Self.buildLookupURL(
            bundleIdentifier: bundleIdentifier,
            storefrontCountryCode: storefrontCountryCode
        )
        let request = Self.buildRequest(for: url)

        do {
            return try await self.attemptFetch(
                request: request,
                expectedBundleIdentifier: bundleIdentifier
            )
        } catch {
            guard error.isRetryable else { throw error }
        }

        try? await Task.sleep(for: self.retryDelay)
        return try await self.attemptFetch(
            request: request,
            expectedBundleIdentifier: bundleIdentifier
        )
    }

    private func attemptFetch(
        request: URLRequest,
        expectedBundleIdentifier: String
    ) async throws(LookupRequestError) -> AppStoreMetadata {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.performDataRequest(request)
        } catch {
            throw .networkUnreachable
        }

        if let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
            throw .serverError(statusCode: httpResponse.statusCode)
        }

        do {
            return try LookupResponseDecoder.decode(
                data,
                expectedBundleIdentifier: expectedBundleIdentifier
            )
        } catch let decodeError as LookupDecodeError {
            switch decodeError {
            case .absentFromStorefront:
                throw .absentFromStorefront
            case .identityMismatch:
                throw .identityMismatch
            case .malformedResponse:
                throw .malformedResponse
            }
        } catch {
            throw .malformedResponse
        }
    }

    private static func buildLookupURL(
        bundleIdentifier: String,
        storefrontCountryCode: String?
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        var queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
        if let countryCode = storefrontCountryCode {
            queryItems.append(URLQueryItem(name: "country", value: countryCode))
        }
        components.queryItems = queryItems
        // Force-unwrap is safe: all components are known-valid string constants.
        return components.url!
    }

    private static func buildRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeoutInterval)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }
}
