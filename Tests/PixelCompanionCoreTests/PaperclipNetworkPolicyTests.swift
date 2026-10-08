import Foundation
@testable import PixelCompanionCore
import XCTest

final class PaperclipNetworkPolicyTests: XCTestCase {
    func testDefaultSessionHasNoSharedCookiesCredentialsOrDiskCache() {
        let session = PaperclipNetworkPolicy.makeSession()
        defer { session.invalidateAndCancel() }
        let config = session.configuration
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.httpCookieAcceptPolicy, .never)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertNil(config.urlCache)
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertTrue(session.delegate is PaperclipNoRedirectDelegate)
    }

    func testRedirectDelegateRefusesCrossHostDestination() throws {
        let session = PaperclipNetworkPolicy.makeSession()
        defer { session.invalidateAndCancel() }
        let source = try XCTUnwrap(URL(string: "http://localhost:3100/api/health"))
        let destination = try XCTUnwrap(URL(string: "https://unrelated.example/private"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: source, statusCode: 302, httpVersion: "HTTP/1.1",
            headerFields: ["Location": destination.absoluteString]
        ))
        let task = session.dataTask(with: source)
        let redirectDelegate = try XCTUnwrap(
            session.delegate as? PaperclipNoRedirectDelegate
        )
        var invoked = false
        redirectDelegate.urlSession(
            session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: destination)
        ) { allowedRequest in
            invoked = true
            XCTAssertNil(allowedRequest)
        }
        XCTAssertTrue(invoked)
        task.cancel()
    }

    func testRequestDisablesCookiesEvenWithInjectedSession() throws {
        let session = URLSession(configuration: .default)
        defer { session.invalidateAndCancel() }
        let client = PaperclipHTTPClient(session: session)
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:3100"))
        switch client.request(baseURL: baseURL, path: "api/health", queryItems: []) {
        case let .success(request):
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            XCTAssertEqual(request.url?.path, "/api/health")
        case .failure:
            XCTFail("Valid fixed endpoint unexpectedly refused")
        }
    }

    func testValidCompanyIDPathsStaySupported() {
        for path in [
            "api/health",
            "api/companies",
            "api/companies/abc-123/approvals",
            "api/companies/uuid_ABC.123/heartbeat-runs",
            "api/companies/a~b/live-runs"
        ] {
            XCTAssertTrue(PaperclipNetworkPolicy.validRelativePath(path), path)
        }
    }

    func testUnsafePathSegmentsAreNeverPermitted() {
        for path in [
            "", "/api/health", "api/companies/", "api//companies",
            "api/./companies", "api/../settings",
            "api/companies/%2F/agents",
            "api/companies/id?token=x/agents",
            "api/companies/id#fragment/agents",
            "api/companies/id\\extra/agents",
            "api/companies/evil@host/agents",
            "api/companies/space here/agents"
        ] {
            XCTAssertFalse(PaperclipNetworkPolicy.validRelativePath(path), path)
        }
    }

    func testUnsafeCompanyIdentifiersFailBeforeNetwork() throws {
        let client = PaperclipHTTPClient(
            session: PaperclipNetworkPolicy.makeSession()
        )
        let baseURL = try XCTUnwrap(URL(string: "http://localhost:3100"))
        for identifier in ["..", "a/../../admin", "id?query=1", "id%2Fpath"] {
            let path = "api/companies/\(identifier)/approvals"
            switch client.request(baseURL: baseURL, path: path, queryItems: []) {
            case .success:
                XCTFail("Unsafe company identifier accepted")
            case let .failure(error):
                XCTAssertTrue(error is PaperclipServiceError)
            }
        }
    }

    func testSafeSubpathRetainsConfiguredOrigin() throws {
        let client = PaperclipHTTPClient(
            session: PaperclipNetworkPolicy.makeSession()
        )
        let origin = try XCTUnwrap(URL(string: "https://paperclip.example/subpath"))
        switch client.request(
            baseURL: origin,
            path: "api/companies/valid-uuid/agents", queryItems: []
        ) {
        case let .success(request):
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "paperclip.example")
            XCTAssertEqual(request.url?.path, "/subpath/api/companies/valid-uuid/agents")
        case .failure:
            XCTFail("Valid Paperclip endpoint unexpectedly refused")
        }
    }

    func testCompanyPathRejectsUnsafeIDBeforeInterpolation() {
        XCTAssertEqual(
            PaperclipNetworkPolicy.companyPath("company-123", resource: "agents"),
            "api/companies/company-123/agents"
        )
        for id in [
            "a/b", "a//b", "../admin", "x/agents", ".", "..", "",
            "id?token=test", "id#fragment", "a%2Fb", "bad\\id"
        ] {
            XCTAssertNil(
                PaperclipNetworkPolicy.companyPath(id, resource: "agents"),
                "ID must be a single safe segment"
            )
        }
        XCTAssertNil(
            PaperclipNetworkPolicy.companyPath("valid-id", resource: "issues/extra")
        )
    }
}
