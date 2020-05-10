import Foundation
@_exported import SweetURLRequest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct EndpointExpectation {

    public static func successStatusCode(data : Data?, response: HTTPURLResponse) throws {
        let code = response.statusCode
        guard (200 ..< 300).contains(code) else {
            throw WrongStatusCodeError(statusCode: code, response: response, responseBody: data)
        }
    }
    
    public static func emptyResponse(_ data: Data?, _: HTTPURLResponse) throws {
        guard let data = data else { return }
        guard data.count == 0 else { throw EndpointError(description: "Expected an empty response") }
    }

    public static func ignoreResponse(_: Data?, _: HTTPURLResponse) throws {}
    
}


/// This describes an endpoint returning `A` values. It contains both a `URLRequest` and a way to parse the response.
public struct Endpoint<A> {
        
    /// The request for this endpoint
    public var request: URLRequest
    
    /// This is used to validate the response (like, check the status code).
    public typealias ValidateFunction = (_ data: Data?, _ response: HTTPURLResponse) throws -> Void
    var validate: ValidateFunction

    /// This is used to (try to) parse a response into an `A`.
    public typealias ParseFunction = (_ data : Data?, _ response: HTTPURLResponse) throws -> A?
    var parse: ParseFunction
    
    /// Transforms the result
    public func map<B>(_ f: @escaping (A) -> B) -> Endpoint<B> {
        return Endpoint<B>(request: request, validate: validate, parse: { value, response in
            try self.parse(value, response).map(f)
        })
    }

    /// Transforms the result
    public func compactMap<B>(_ transform: @escaping (A) throws -> B) -> Endpoint<B> {
        return Endpoint<B>(request: request, validate: validate, parse: { data, response in
            try self.parse(data, response).flatMap(transform)
        })
    }
    
    /// Creates a new Endpoint from a request
    ///
    /// - Parameters:
    ///   - request: the URL request
    ///   - validate: this validates the response, f.e. checks the status code.
    ///   - parse: this converts a response into an `A`.
    public init(request: URLRequest, validate: @escaping ValidateFunction = EndpointExpectation.successStatusCode, parse: @escaping ParseFunction) {
        self.request = request
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
    public init(jsonRequest: URLRequest, validate: @escaping ValidateFunction = EndpointExpectation.successStatusCode, jsonDecoder: JSONDecoder = JSONDecoder()) {
        var jsonRequest = jsonRequest
        jsonRequest.headers.accept = .json
        self.request = jsonRequest
        self.validate = validate
        self.parse = jsonDecoder.decodeResponse
    }

}

// MARK: - CustomStringConvertible
extension Endpoint: CustomStringConvertible {
    public var description: String {
        let data = request.httpBody ?? Data()
        return "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<no url>") \(String(data: data, encoding: .utf8) ?? "")"
    }
}

/// Signals that a response's data was unexpectedly nil.
public struct NoDataError: Error {
    public init() { }
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

extension URLSession {
    @discardableResult
    /// Loads an endpoint by creating (and directly resuming) a data task.
    ///
    /// - Parameters:
    ///   - e: The endpoint.
    ///   - onComplete: The completion handler.
    /// - Returns: The data task.
    public func load<A>(_ e: Endpoint<A>, onComplete: @escaping (Result<A, Error>) -> ()) -> URLSessionDataTask {
        let r = e.request
        let task = dataTask(with: r, completionHandler: { data, response, error in
            if let error = error {
                onComplete(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                onComplete(.failure(EndpointError(description: "Response was not a HTTPURLResponse")))
                return
            }
            
            do {
                try e.validate(data, httpResponse)
                if let result = try e.parse(data, httpResponse) {
                    onComplete(.success(result))
                } else {
                    onComplete(.failure(NoDataError()))
                }
            }
            catch let e {
                onComplete(.failure(e))
                return
            }
            
        })
        task.resume()
        return task
    }
}

#if canImport(Combine)
import Combine

@available(iOS 13, macOS 10.15, watchOS 6, tvOS 13, *)
extension URLSession {
    /// Returns a publisher that wraps a URL session data task for a given Endpoint.
    ///
    /// - Parameters:
    ///   - e: The endpoint.
    /// - Returns: The publisher of a dataTask.
    public func load<A>(_ e: Endpoint<A>) -> AnyPublisher<A, Error> {
        let r = e.request
        return dataTaskPublisher(for: r)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EndpointError(description: "Response was not a HTTPURLResponse")
                }

                try e.validate(data, httpResponse)
                if let result = try e.parse(data, httpResponse) {
                    return result
                } else {
                    throw NoDataError()
                }
        }
        .eraseToAnyPublisher()
    }
}
#endif
