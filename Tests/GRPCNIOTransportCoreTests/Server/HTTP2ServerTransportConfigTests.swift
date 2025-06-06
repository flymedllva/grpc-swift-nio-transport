/*
 * Copyright 2024, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import GRPCCore
import GRPCNIOTransportCore
import XCTest

@available(gRPCSwiftNIOTransport 2.0, *)
final class HTTP2ServerTransportConfigTests: XCTestCase {
  func testCompressionDefaults() {
    let config = HTTP2ServerTransport.Config.Compression.defaults
    XCTAssertEqual(config.enabledAlgorithms, .none)
  }

  func testKeepaliveDefaults() {
    let config = HTTP2ServerTransport.Config.Keepalive.defaults
    XCTAssertEqual(config.time, .seconds(7200))
    XCTAssertEqual(config.timeout, .seconds(20))
    XCTAssertEqual(config.clientBehavior.allowWithoutCalls, false)
    XCTAssertEqual(config.clientBehavior.minPingIntervalWithoutCalls, .seconds(300))
  }

  func testConnectionDefaults() {
    let config = HTTP2ServerTransport.Config.Connection.defaults
    XCTAssertNil(config.maxAge)
    XCTAssertNil(config.maxGraceTime)
    XCTAssertNil(config.maxIdleTime)
  }

  func testHTTP2Defaults() {
    let config = HTTP2ServerTransport.Config.HTTP2.defaults
    XCTAssertEqual(config.maxFrameSize, 16_384)
    XCTAssertEqual(config.targetWindowSize, 65_535)
    XCTAssertNil(config.maxConcurrentStreams)
  }

  func testRPCDefaults() {
    let config = HTTP2ServerTransport.Config.RPC.defaults
    XCTAssertEqual(config.maxRequestPayloadSize, 4_194_304)
  }
}
