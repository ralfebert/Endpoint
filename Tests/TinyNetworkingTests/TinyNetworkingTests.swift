import SweetURLRequest
@testable import TinyNetworking
import XCTest

final class TinyNetworkingTests: XCTestCase {

    func testUrlWithoutParams() {
        let url = URL(string: "http://www.example.com/example.json")!
        let endpoint = Endpoint<[String]>(jsonRequest: URLRequest(url: url))
        XCTAssertEqual(url, endpoint.request.url)
    }

    func testUrlWithParams() {
        let url = URL(string: "http://www.example.com/example.json")!
        let urlRequest = URLRequest(method: .get, url: url, parameters: ["foo": "bar bar"])
        let endpoint = Endpoint<[String]>(jsonRequest: urlRequest)
        XCTAssertEqual(URL(string: "http://www.example.com/example.json?foo=bar%20bar")!, endpoint.request.url)
    }

    func testUrlAdditionalParams() {
        let url = URL(string: "http://www.example.com/example.json?abc=def")!
        let urlRequest = URLRequest(method: .get, url: url, parameters: ["foo": "bar bar"])
        let endpoint = Endpoint<[String]>(jsonRequest: urlRequest)
        XCTAssertEqual(URL(string: "http://www.example.com/example.json?abc=def&foo=bar%20bar")!, endpoint.request.url)
    }

}
