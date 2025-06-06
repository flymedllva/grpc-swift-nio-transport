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

// Equatable conformance for these types is 'best effort', this is sufficient for testing but not
// for general use.
@available(gRPCSwiftNIOTransport 2.0, *)
extension Connection.Event: Equatable {}
@available(gRPCSwiftNIOTransport 2.0, *)
extension Connection.CloseReason: Equatable {}

@available(gRPCSwiftNIOTransport 2.0, *)
extension ClientConnectionEvent: Equatable {}
@available(gRPCSwiftNIOTransport 2.0, *)
extension ClientConnectionEvent.CloseReason: Equatable {}

@available(gRPCSwiftNIOTransport 2.0, *)
extension Connection.Event {
  static func == (lhs: Connection.Event, rhs: Connection.Event) -> Bool {
    switch (lhs, rhs) {
    case (.connectSucceeded, .connectSucceeded),
      (.connectFailed, .connectFailed):
      return true

    case (.goingAway(let lhsCode, let lhsReason), .goingAway(let rhsCode, let rhsReason)):
      return lhsCode == rhsCode && lhsReason == rhsReason

    case (.closed(let lhsReason), .closed(let rhsReason)):
      return lhsReason == rhsReason

    default:
      return false
    }
  }
}

@available(gRPCSwiftNIOTransport 2.0, *)
extension Connection.CloseReason {
  static func == (lhs: Connection.CloseReason, rhs: Connection.CloseReason) -> Bool {
    switch (lhs, rhs) {
    case (.idleTimeout, .idleTimeout),
      (.keepaliveTimeout, .keepaliveTimeout),
      (.initiatedLocally, .initiatedLocally),
      (.remote, .remote):
      return true

    case (.error(let lhsError, let lhsStreams), .error(let rhsError, let rhsStreams)):
      return lhsError == rhsError && lhsStreams == rhsStreams

    default:
      return false
    }
  }
}

@available(gRPCSwiftNIOTransport 2.0, *)
extension ClientConnectionEvent {
  static func == (lhs: ClientConnectionEvent, rhs: ClientConnectionEvent) -> Bool {
    switch (lhs, rhs) {
    case (.ready, .ready):
      return true
    case (.closing(let lhsReason), .closing(let rhsReason)):
      return lhsReason == rhsReason
    default:
      return false
    }
  }
}

@available(gRPCSwiftNIOTransport 2.0, *)
extension ClientConnectionEvent.CloseReason {
  static func == (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.goAway(let lhsCode, let lhsMessage), .goAway(let rhsCode, let rhsMessage)):
      return lhsCode == rhsCode && lhsMessage == rhsMessage
    case (.unexpected(let lhsError, let lhsIsIdle), .unexpected(let rhsError, let rhsIsIdle)):
      if let lhs = lhsError as? RPCError, let rhs = rhsError as? RPCError {
        return lhs == rhs && lhsIsIdle == rhsIsIdle
      } else {
        return lhsIsIdle == rhsIsIdle
      }
    case (.keepaliveExpired, .keepaliveExpired),
      (.idle, .idle),
      (.initiatedLocally, .initiatedLocally):
      return true
    default:
      return false
    }
  }
}
