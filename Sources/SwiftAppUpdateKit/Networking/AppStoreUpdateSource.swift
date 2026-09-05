//
//  AppStoreUpdateSource.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 9/3/26.
//

import Foundation
import OSLog

/// The production update source that queries the iTunes Lookup API.
struct AppStoreUpdateSource: UpdateSource {
    private static let requestTimeoutInterval: TimeInterval = 15
    private static let defaultRetryDelay: Duration = .seconds(2)
    private static let responseBodyPreviewLimit = 2048

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
        storefrontCountryCode: String?,
        languageCodes: [String]
    ) async throws(LookupRequestError) -> AppStoreMetadata {
        Logger.appStoreUpdateSource.debug(
            "[\(Self.self)] \(#function): Fetching metadata for bundle=\(bundleIdentifier, privacy: .public), storefront=\(storefrontCountryCode ?? "<default>", privacy: .public), languageCandidates=\(languageCodes.joined(separator: ","), privacy: .public)"
        )
        for languageCode in languageCodes {
            let request = Self.buildRequest(
                bundleIdentifier: bundleIdentifier,
                storefrontCountryCode: storefrontCountryCode,
                languageCode: languageCode
            )

            do {
                return try await self.fetchMetadata(
                    request: request,
                    expectedBundleIdentifier: bundleIdentifier
                )
            } catch .unsupportedLanguageCode {
                Logger.appStoreUpdateSource.info(
                    "[\(Self.self)] \(#function): Continuing lookup with the next language candidate"
                )
            }
        }

        if !languageCodes.isEmpty {
            Logger.appStoreUpdateSource.info(
                "[\(Self.self)] \(#function): Retrying lookup without a language code after unsupported language responses"
            )
        }

        let fallbackRequest = Self.buildRequest(
            bundleIdentifier: bundleIdentifier,
            storefrontCountryCode: storefrontCountryCode,
            languageCode: nil
        )
        return try await self.fetchMetadata(
            request: fallbackRequest,
            expectedBundleIdentifier: bundleIdentifier
        )
    }

    private func fetchMetadata(
        request: URLRequest,
        expectedBundleIdentifier: String
    ) async throws(LookupRequestError) -> AppStoreMetadata {
        do {
            return try await self.attemptFetch(
                request: request,
                expectedBundleIdentifier: expectedBundleIdentifier
            )
        } catch {
            guard error.isRetryable else { throw error }
            Logger.appStoreUpdateSource.info(
                "[\(Self.self)] \(#function): Retrying lookup after retryable failure: \(String(describing: error), privacy: .public)"
            )
        }

        try? await Task.sleep(for: self.retryDelay)
        return try await self.attemptFetch(
            request: request,
            expectedBundleIdentifier: expectedBundleIdentifier
        )
    }

    private func attemptFetch(
        request: URLRequest,
        expectedBundleIdentifier: String
    ) async throws(LookupRequestError) -> AppStoreMetadata {
        Logger.appStoreUpdateSource.debug(
            "[\(Self.self)] \(#function): Sending lookup request: url=\(request.url?.absoluteString ?? "<missing>", privacy: .private), timeout=\(request.timeoutInterval, privacy: .public), cachePolicy=\(String(describing: request.cachePolicy), privacy: .public)"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.performDataRequest(request)
        } catch {
            Logger.appStoreUpdateSource.error(
                "[\(Self.self)] \(#function): Lookup request failed before receiving a response: \(String(describing: error), privacy: .public)"
            )
            throw .networkUnreachable
        }

        Self.logResponseMetadata(response, byteCount: data.count)
        guard !Self.isUnsupportedLanguageResponse(data) else {
            Logger.appStoreUpdateSource.info(
                "[\(Self.self)] \(#function): Lookup request received unsupported language response"
            )
            throw .unsupportedLanguageCode
        }

        if let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
            Logger.appStoreUpdateSource.error(
                "[\(Self.self)] \(#function): Lookup request received server error: status=\(httpResponse.statusCode, privacy: .public)"
            )
            throw .serverError(statusCode: httpResponse.statusCode)
        }

        do {
            let metadata = try LookupResponseDecoder.decode(
                data,
                expectedBundleIdentifier: expectedBundleIdentifier
            )
            Logger.appStoreUpdateSource.debug(
                "[\(Self.self)] \(#function): Lookup decoded metadata for version \(metadata.versionString, privacy: .public)"
            )
            return metadata
        } catch let decodeError as LookupDecodeError {
            Self.logDecodeFailure(decodeError, data: data)
            switch decodeError {
            case .absentFromStorefront:
                throw .absentFromStorefront
            case .identityMismatch:
                throw .identityMismatch
            case .malformedResponse:
                throw .malformedResponse
            }
        } catch {
            Self.logDecodeFailure(.malformedResponse, data: data)
            throw .malformedResponse
        }
    }

    private static func logResponseMetadata(_ response: URLResponse, byteCount: Int) {
        let finalURL = response.url?.absoluteString ?? "<missing>"
        if let httpResponse = response as? HTTPURLResponse {
            Logger.appStoreUpdateSource.debug(
                "[\(Self.self)] \(#function): Received lookup response: status=\(httpResponse.statusCode, privacy: .public), bytes=\(byteCount, privacy: .public), url=\(finalURL, privacy: .private)"
            )
        } else {
            Logger.appStoreUpdateSource.debug(
                "[\(Self.self)] \(#function): Received non-HTTP lookup response: bytes=\(byteCount, privacy: .public), url=\(finalURL, privacy: .private)"
            )
        }
    }

    private static func logDecodeFailure(_ error: LookupDecodeError, data: Data) {
        Logger.appStoreUpdateSource.error(
            "[\(Self.self)] \(#function): Lookup response decode failed: error=\(String(describing: error), privacy: .public), bodyPreview=\(Self.responseBodyPreview(from: data), privacy: .private)"
        )
    }

    static func responseBodyPreview(from data: Data) -> String {
        guard !data.isEmpty else {
            return "<empty response>"
        }
        let prefix = data.prefix(Self.responseBodyPreviewLimit)
        let preview = String(decoding: prefix, as: UTF8.self)
        if data.count > Self.responseBodyPreviewLimit {
            return "\(preview)… <truncated to \(Self.responseBodyPreviewLimit) bytes>"
        }
        return preview
    }

    private static func isUnsupportedLanguageResponse(_ data: Data) -> Bool {
        guard
            let errorResponse = try? JSONDecoder().decode(LookupErrorResponse.self, from: data),
            errorResponse.errorMessage?.contains("Invalid value") == true,
            errorResponse.queryParameters.keys.contains("lang")
        else {
            return false
        }
        return true
    }

    private static func buildLookupURL(
        bundleIdentifier: String,
        storefrontCountryCode: String?,
        languageCode: String?
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        var queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
        if let countryCode = storefrontCountryCode {
            queryItems.append(URLQueryItem(name: "country", value: countryCode.lowercased()))
        }
        if let languageCode = languageCode {
            queryItems.append(URLQueryItem(name: "lang", value: languageCode.lowercased()))
        }
        components.queryItems = queryItems
        // Force-unwrap is safe: all components are known-valid string constants.
        return components.url!
    }

    private static func buildRequest(
        bundleIdentifier: String,
        storefrontCountryCode: String?,
        languageCode: String?
    ) -> URLRequest {
        let url = Self.buildLookupURL(
            bundleIdentifier: bundleIdentifier,
            storefrontCountryCode: storefrontCountryCode,
            languageCode: languageCode
        )
        return Self.buildRequest(for: url)
    }

    private static func buildRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeoutInterval)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }
}

private struct LookupErrorResponse: Decodable {
    let errorMessage: String?
    let queryParameters: [String: String]
}
