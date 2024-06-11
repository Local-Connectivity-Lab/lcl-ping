//
// This source file is part of the LCL open source project
//
// Copyright (c) 2021-2024 Local Connectivity Lab and the project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of project authors
//
// SPDX-License-Identifier: Apache-2.0
//

import XCTest
import NIOCore
@testable import LCLPing

final class HTTPConfigurationTest: XCTest {
    func testInvalidIPURL() throws {
        let urlString = "ww.invalid-url.^&*:8080"
        let expectedError = PingError.invalidURL(urlString)
        do {
            _ = try HTTPPingClient.Configuration(url: urlString)
            XCTFail("Expect throwing PingError.invalidURL")
        } catch {
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
    }

    func testMissingHTTPSchemaInURL() throws {
        let expectedError = PingError.httpMissingSchema
        do {
            _ = try HTTPPingClient.Configuration(url: "someOtherSchema://127.0.0.1:8080")
            XCTFail("Expect throwing PingError.httpMissingSchema")
        } catch {
            XCTAssertEqual(expectedError.localizedDescription, error.localizedDescription)
        }
    }
}
