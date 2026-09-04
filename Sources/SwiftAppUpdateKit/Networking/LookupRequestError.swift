//
//  LookupRequestError.swift
//  SwiftAppUpdateKit
//
//  Created by Haoyuan Xia on 9/3/26.
//

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
