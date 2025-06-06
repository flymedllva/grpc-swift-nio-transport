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

package import GRPCCore
package import NIOCore
internal import NIOHPACK
package import NIOHTTP2

@available(gRPCSwiftNIOTransport 2.0, *)
extension ChannelPipeline.SynchronousOperations {
  package typealias HTTP2ConnectionChannel = NIOAsyncChannel<HTTP2Frame, HTTP2Frame>
  package typealias HTTP2StreamMultiplexer = NIOHTTP2Handler.AsyncStreamMultiplexer<
    (
      NIOAsyncChannel<
        RPCRequestPart<GRPCNIOTransportBytes>,
        RPCResponsePart<GRPCNIOTransportBytes>
      >,
      EventLoopFuture<MethodDescriptor>
    )
  >

  package func configureGRPCServerPipeline(
    channel: any Channel,
    compressionConfig: HTTP2ServerTransport.Config.Compression,
    connectionConfig: HTTP2ServerTransport.Config.Connection,
    http2Config: HTTP2ServerTransport.Config.HTTP2,
    rpcConfig: HTTP2ServerTransport.Config.RPC,
    debugConfig: HTTP2ServerTransport.Config.ChannelDebuggingCallbacks,
    requireALPN: Bool,
    scheme: Scheme
  ) throws -> (HTTP2ConnectionChannel, HTTP2StreamMultiplexer) {
    let serverConnectionHandler = ServerConnectionManagementHandler(
      eventLoop: self.eventLoop,
      maxIdleTime: connectionConfig.maxIdleTime.map { TimeAmount($0) },
      maxAge: connectionConfig.maxAge.map { TimeAmount($0) },
      maxGraceTime: connectionConfig.maxGraceTime.map { TimeAmount($0) },
      keepaliveTime: TimeAmount(connectionConfig.keepalive.time),
      keepaliveTimeout: TimeAmount(connectionConfig.keepalive.timeout),
      allowKeepaliveWithoutCalls: connectionConfig.keepalive.clientBehavior.allowWithoutCalls,
      minPingIntervalWithoutCalls: TimeAmount(
        connectionConfig.keepalive.clientBehavior.minPingIntervalWithoutCalls
      ),
      requireALPN: requireALPN
    )
    let flushNotificationHandler = GRPCServerFlushNotificationHandler(
      serverConnectionManagementHandler: serverConnectionHandler
    )
    try self.addHandler(flushNotificationHandler)

    let clampedTargetWindowSize = self.clampTargetWindowSize(http2Config.targetWindowSize)
    let clampedMaxFrameSize = self.clampMaxFrameSize(http2Config.maxFrameSize)

    var http2HandlerConnectionConfiguration = NIOHTTP2Handler.ConnectionConfiguration()
    var http2HandlerHTTP2Settings = HTTP2Settings([
      HTTP2Setting(parameter: .initialWindowSize, value: clampedTargetWindowSize),
      HTTP2Setting(parameter: .maxFrameSize, value: clampedMaxFrameSize),
      HTTP2Setting(parameter: .maxHeaderListSize, value: HPACKDecoder.defaultMaxHeaderListSize),
    ])
    if let maxConcurrentStreams = http2Config.maxConcurrentStreams {
      http2HandlerHTTP2Settings.append(
        HTTP2Setting(parameter: .maxConcurrentStreams, value: maxConcurrentStreams)
      )
    }
    http2HandlerConnectionConfiguration.initialSettings = http2HandlerHTTP2Settings

    var http2HandlerStreamConfiguration = NIOHTTP2Handler.StreamConfiguration()
    http2HandlerStreamConfiguration.targetWindowSize = clampedTargetWindowSize

    let boundConnectionManagementHandler = NIOLoopBound(
      serverConnectionHandler.syncView,
      eventLoop: self.eventLoop
    )
    let streamMultiplexer = try self.configureAsyncHTTP2Pipeline(
      mode: .server,
      streamDelegate: serverConnectionHandler.http2StreamDelegate,
      configuration: NIOHTTP2Handler.Configuration(
        connection: http2HandlerConnectionConfiguration,
        stream: http2HandlerStreamConfiguration
      )
    ) { streamChannel in
      return streamChannel.eventLoop.makeCompletedFuture {
        let methodDescriptorPromise = streamChannel.eventLoop.makePromise(of: MethodDescriptor.self)
        let streamHandler = GRPCServerStreamHandler(
          scheme: scheme,
          acceptedEncodings: compressionConfig.enabledAlgorithms,
          maxPayloadSize: rpcConfig.maxRequestPayloadSize,
          methodDescriptorPromise: methodDescriptorPromise,
          eventLoop: streamChannel.eventLoop,
          connectionManagementHandler: boundConnectionManagementHandler.value
        )
        try streamChannel.pipeline.syncOperations.addHandler(streamHandler)

        let asyncStreamChannel = try NIOAsyncChannel(
          wrappingChannelSynchronously: streamChannel,
          configuration: NIOAsyncChannel.Configuration(
            inboundType: RPCRequestPart<GRPCNIOTransportBytes>.self,
            outboundType: RPCResponsePart<GRPCNIOTransportBytes>.self
          )
        )
        return (asyncStreamChannel, methodDescriptorPromise.futureResult)
      }.runInitializerIfSet(debugConfig.onAcceptHTTP2Stream, on: streamChannel)
    }

    try self.addHandler(serverConnectionHandler)

    let connectionChannel = try NIOAsyncChannel<HTTP2Frame, HTTP2Frame>(
      wrappingChannelSynchronously: channel
    )

    return (connectionChannel, streamMultiplexer)
  }
}

@available(gRPCSwiftNIOTransport 2.0, *)
extension ChannelPipeline.SynchronousOperations {
  package func configureGRPCClientPipeline(
    channel: any Channel,
    config: GRPCChannel.Config
  ) throws -> (
    NIOAsyncChannel<ClientConnectionEvent, Void>,
    NIOHTTP2Handler.AsyncStreamMultiplexer<Void>
  ) {
    let clampedTargetWindowSize = self.clampTargetWindowSize(config.http2.targetWindowSize)
    let clampedMaxFrameSize = self.clampMaxFrameSize(config.http2.maxFrameSize)

    // Use NIOs defaults as a starting point.
    var http2 = NIOHTTP2Handler.Configuration()
    http2.stream.targetWindowSize = clampedTargetWindowSize
    http2.connection.initialSettings = [
      // Disallow servers from creating push streams.
      HTTP2Setting(parameter: .enablePush, value: 0),
      // Set the initial window size and max frame size to the clamped configured values.
      HTTP2Setting(parameter: .initialWindowSize, value: clampedTargetWindowSize),
      HTTP2Setting(parameter: .maxFrameSize, value: clampedMaxFrameSize),
      // Use NIOs default max header list size (16kB)
      HTTP2Setting(parameter: .maxHeaderListSize, value: HPACKDecoder.defaultMaxHeaderListSize),
    ]

    // These rates inform NIO's DoS detection heuristics which typically apply to a server. The
    // rate at which RST_STREAM frames are permitted is increased for the client as clients are
    // likely to receive 'RST_STREAM' frames if the server rejects RPCs (i.e. the server sends a
    // trailers-only response).
    //
    // The default values are 200 in a 30 second period. Allow the same number of failures in a
    // shorter period.
    http2.stream.streamResetFrameRateLimit.maximumCount = 200
    http2.stream.streamResetFrameRateLimit.windowLength = .seconds(10)

    let connectionHandler = ClientConnectionHandler(
      eventLoop: self.eventLoop,
      maxIdleTime: config.connection.maxIdleTime.map { TimeAmount($0) },
      keepaliveTime: config.connection.keepalive.map { TimeAmount($0.time) },
      keepaliveTimeout: config.connection.keepalive.map { TimeAmount($0.timeout) },
      keepaliveWithoutCalls: config.connection.keepalive?.allowWithoutCalls ?? false
    )

    let multiplexer = try self.configureAsyncHTTP2Pipeline(
      mode: .client,
      streamDelegate: connectionHandler.http2StreamDelegate,
      configuration: http2
    ) { stream in
      // Shouldn't happen, push-promises are disabled so the server shouldn't be able to
      // open streams.
      stream.close()
    }

    try self.addHandler(connectionHandler)

    let connection = try NIOAsyncChannel(
      wrappingChannelSynchronously: channel,
      configuration: NIOAsyncChannel.Configuration(
        inboundType: ClientConnectionEvent.self,
        outboundType: Void.self
      )
    )

    return (connection, multiplexer)
  }
}

extension ChannelPipeline.SynchronousOperations {
  /// Max frame size must be in the range `2^14 ..< 2^24` (RFC 9113 § 4.2).
  fileprivate func clampMaxFrameSize(_ maxFrameSize: Int) -> Int {
    let clampedMaxFrameSize: Int
    if maxFrameSize >= (1 << 24) {
      clampedMaxFrameSize = (1 << 24) - 1
    } else if maxFrameSize < (1 << 14) {
      clampedMaxFrameSize = (1 << 14)
    } else {
      clampedMaxFrameSize = maxFrameSize
    }
    return clampedMaxFrameSize
  }

  /// Window size which mustn't exceed `2^31 - 1` (RFC 9113 § 6.5.2).
  internal func clampTargetWindowSize(_ targetWindowSize: Int) -> Int {
    min(targetWindowSize, Int(Int32.max))
  }
}
