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

@available(gRPCSwiftNIOTransport 2.0, *)
extension MethodDescriptor {
  static var echoGet: Self {
    MethodDescriptor(fullyQualifiedService: "echo.Echo", method: "Get")
  }

  static var echoUpdate: Self {
    MethodDescriptor(fullyQualifiedService: "echo.Echo", method: "Update")
  }
}

@available(gRPCSwiftNIOTransport 2.0, *)
extension MethodConfig.Name {
  init(_ descriptor: MethodDescriptor) {
    self = MethodConfig.Name(
      service: descriptor.service.fullyQualifiedService,
      method: descriptor.method
    )
  }
}
