import Foundation
import os
@_exported import SweetURLRequest

public typealias ValidateFunction = (_ data: Data?, _ response: HTTPURLResponse) throws -> Void

public struct EndpointExpectation {

    public static func validateStatusCode(_ validate: @escaping (_ statusCode: Int) -> Bool) -> ValidateFunction {
        return { (data: Data?, response: HTTPURLResponse) throws in
            let code = response.statusCode
            guard validate(code) else {
                throw WrongStatusCodeError(statusCode: code, response: response, responseBody: data)
            }
        }
    }

    public static func expectStatus(_ responseType: HTTPStatusCode.ResponseType) -> ValidateFunction {
        self.validateStatusCode { HTTPStatusCode.ResponseType(httpStatusCode: $0) == responseType }
    }

    public static func expectStatus(_ values: [HTTPStatusCode]) -> ValidateFunction {
        self.validateStatusCode {
            guard let statusCode = HTTPStatusCode(rawValue: $0) else { return false }
            return values.contains(statusCode)
        }
    }

    public static func expectStatus(_ value: HTTPStatusCode) -> ValidateFunction {
        self.validateStatusCode { HTTPStatusCode(rawValue: $0) == value }
    }

    public static let expectSuccess = expectStatus(.success)

    public static func emptyResponse(_ data: Data?, _: HTTPURLResponse) throws {
        guard let data = data else { return }
        guard data.count == 0 else { throw EndpointError(description: "Expected an empty response") }
    }

    public static func ignoreResponse(_: Data?, _: HTTPURLResponse) throws {}

}

public struct EndpointLogging {

    public static let log = OSLog(subsystem: "TinyNetworking", category: "Endpoint")

}

/// This describes an endpoint returning `A` values. It contains both a `URLRequest` and a way to parse the response.
public struct Endpoint<A> {

    /// The request for this endpoint
    let request: URLRequest

    /// The URLSession to use for this endpoint
    let urlSession: URLSession

    /// This is used to validate the response (like, check the status code).
    let validate: ValidateFunction

    /// This is used to (try to) parse a response into an `A`.
    public typealias ParseFunction = (_ data: Data?, _ response: HTTPURLResponse) throws -> A?
    let parse: ParseFunction

    /// Transforms the result
    public func map<B>(_ f: @escaping (A) -> B) -> Endpoint<B> {
        return Endpoint<B>(request: self.request, validate: self.validate, parse: { value, response in
            try self.parse(value, response).map(f)
        })
    }

    /// Transforms the result
    public func compactMap<B>(_ transform: @escaping (A) throws -> B) -> Endpoint<B> {
        return Endpoint<B>(request: self.request, validate: self.validate, parse: { data, response in
            try self.parse(data, response).flatMap(transform)
        })
    }

    /// Creates a new Endpoint from a request
    ///
    /// - Parameters:
    ///   - request: the URL request
    ///   - validate: this validates the response, f.e. checks the status code.
    ///   - parse: this converts a response into an `A`.
    public init(request: URLRequest, urlSession: URLSession = .shared, validate: @escaping ValidateFunction = EndpointExpectation.expectSuccess, parse: @escaping ParseFunction) {
        self.request = request
        self.urlSession = urlSession
        self.validate = validate
        self.parse = parse
    }

}

extension Endpoint where A: Decodable {

    /// Creates a new Endpoint from a request that returns JSON
    ///
    /// - Parameters:
    ///   - request: the URL request
    ///   - validate: this validates the response, f.e. checks the status code.
    ///   - parse: this converts a response into an `A`.
    public init(jsonRequest: URLRequest, urlSession: URLSession = .shared, validate: @escaping ValidateFunction = EndpointExpectation.expectSuccess, jsonDecoder: JSONDecoder = JSONDecoder()) {
        var jsonRequest = jsonRequest
        jsonRequest.headers.accept = .json
        self.urlSession = urlSession
        self.request = jsonRequest
        self.validate = validate
        self.parse = jsonDecoder.decodeResponse
    }

}

// MARK: - CustomStringConvertible

extension Endpoint: CustomStringConvertible {
    public var description: String {
        "[\(self.request.httpMethod ?? "") \(self.request.url?.absoluteString ?? "")]"
    }
}

/// Signals that a response's data was unexpectedly nil.
public struct NoDataError: Error {
    public init() {}
}

/// An unknown error
public struct EndpointError: Error {
    public var description: String
    public init(description: String) {
        self.description = description
    }
}

/// Signals that a response's status code was wrong.
public struct WrongStatusCodeError: Error {
    public let statusCode: Int
    public let response: HTTPURLResponse?
    public let responseBody: Data?
    public init(statusCode: Int, response: HTTPURLResponse?, responseBody: Data?) {
        self.statusCode = statusCode
        self.response = response
        self.responseBody = responseBody
    }
}

extension JSONDecoder {

    public func decodeResponse<T: Decodable>(_ data: Data?, _: HTTPURLResponse) throws -> T {
        guard let data = data else {
            throw NoDataError()
        }
        return try self.decode(T.self, from: data)
    }

}
