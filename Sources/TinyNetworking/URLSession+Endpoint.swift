import Foundation
import os
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension URLSession {
    @discardableResult
    /// Loads an endpoint by creating (and directly resuming) a data task.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint.
    ///   - onComplete: The completion handler.
    /// - Returns: The data task.
    public func load<A>(_ endpoint: Endpoint<A>, onComplete: @escaping (Result<A, Error>) -> Void) -> URLSessionDataTask {
        os_log("Loading %s", log: EndpointLogging.log, type: .debug, endpoint.description)

        let task = dataTask(with: endpoint.request, completionHandler: { data, response, error in

            os_log("Got response for %s - %i bytes", log: EndpointLogging.log, type: .debug, endpoint.description, data?.count ?? 0)

            if let error = error {
                onComplete(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                onComplete(.failure(EndpointError(description: "Response was not a HTTPURLResponse")))
                return
            }

            do {
                try endpoint.validate(data, httpResponse)
                if let result = try endpoint.parse(data, httpResponse) {
                    onComplete(.success(result))
                } else {
                    onComplete(.failure(NoDataError()))
                }
            } catch let e {
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
        ///   - endpoint: The endpoint.
        /// - Returns: The publisher of a dataTask.
        public func load<A>(_ endpoint: Endpoint<A>) -> AnyPublisher<A, Error> {
            os_log("Loading %s", log: EndpointLogging.log, type: .debug, endpoint.description)
            return dataTaskPublisher(for: endpoint.request)
                .tryMap { data, response in
                    os_log("Got response for %s - %i bytes", log: EndpointLogging.log, type: .debug, endpoint.description, data.count)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw EndpointError(description: "Response was not a HTTPURLResponse")
                    }

                    try endpoint.validate(data, httpResponse)
                    if let result = try endpoint.parse(data, httpResponse) {
                        return result
                    } else {
                        throw NoDataError()
                    }
                }
                .eraseToAnyPublisher()
        }
    }
#endif
