@testable import PixelCompanionCore
import XCTest

final class PaperclipPrivateTransportTests: XCTestCase {
    func testLocalSSHForwardCanRemainUnencryptedOverLoopbackOnly() {
        for url in [
            "http://localhost:3100",
            "http://127.0.0.1:3100/",
            "http://[::1]:3100"
        ] {
            XCTAssertNotNil(PaperclipConfiguration(baseURLString: url).baseURL, url)
        }
    }

    func testRemoteTransportAlwaysRequiresHTTPS() {
        for url in [
            "http://paperclip.example",
            "http://10.1.2.3:3000",
            "http://192.168.1.12:3000",
            "http://172.16.0.1",
            "http://paperclip.internal",
            "http://0.0.0.0:3100"
        ] {
            let config = PaperclipConfiguration(baseURLString: url)
            XCTAssertNil(config.baseURL, url)
            XCTAssertNotNil(config.validationError, url)
        }
        for url in [
            "https://paperclip.example",
            "https://paperclip.internal:8443",
            "https://10.1.2.3:3100"
        ] {
            XCTAssertNotNil(PaperclipConfiguration(baseURLString: url).baseURL, url)
        }
    }

    func testCredentialedUrlsAndUnsafeSchemesStayRejected() {
        for url in [
            "https://person:secret@paperclip.example",
            "http://person@localhost:3100",
            "https://paperclip.example?auth=x",
            "https://paperclip.example#token",
            "file:///tmp/paperclip"
        ] {
            XCTAssertNil(PaperclipConfiguration(baseURLString: url).baseURL, url)
        }
    }
}
