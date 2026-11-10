import 'dart:typed_data';

import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/transport/nearby_transport.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:test/test.dart';

class _FakeNearbyApi implements NearbyApi {
  OnConnectionInitiated? advertInit;
  OnConnectionResult? advertResult;
  OnDisconnected? advertDisconnected;

  OnEndpointFound? endpointFound;
  OnEndpointLost? endpointLost;

  OnConnectionInitiated? discoverInit;
  OnConnectionResult? discoverResult;
  OnDisconnected? discoverDisconnected;

  final Map<String, OnPayloadReceived> acceptedPayloadCallbacks = {};
  final List<String> requestedEndpoints = [];
  final List<String> acceptedEndpoints = [];
  final List<String> rejectedEndpoints = [];
  final List<({String endpointId, Uint8List bytes})> sentPayloads = [];
  bool advertising = false;
  bool discovering = false;

  @override
  Future<bool> startAdvertising(
    String userNickName,
    Strategy strategy, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
    required String serviceId,
  }) async {
    advertising = true;
    advertInit = onConnectionInitiated;
    advertResult = onConnectionResult;
    advertDisconnected = onDisconnected;
    return true;
  }

  @override
  Future<void> stopAdvertising() async {
    advertising = false;
  }

  @override
  Future<bool> startDiscovery(
    String userNickName,
    Strategy strategy, {
    required OnEndpointFound onEndpointFound,
    required OnEndpointLost onEndpointLost,
    required String serviceId,
  }) async {
    discovering = true;
    endpointFound = onEndpointFound;
    endpointLost = onEndpointLost;
    return true;
  }

  @override
  Future<void> stopDiscovery() async {
    discovering = false;
  }

  @override
  Future<bool> requestConnection(
    String userNickName,
    String endpointId, {
    required OnConnectionInitiated onConnectionInitiated,
    required OnConnectionResult onConnectionResult,
    required OnDisconnected onDisconnected,
  }) async {
    requestedEndpoints.add(endpointId);
    discoverInit = onConnectionInitiated;
    discoverResult = onConnectionResult;
    discoverDisconnected = onDisconnected;
    return true;
  }

  @override
  Future<bool> acceptConnection(
    String endpointId, {
    required OnPayloadReceived onPayloadReceived,
    OnPayloadTransferUpdate? onPayloadTransferUpdate,
  }) async {
    acceptedEndpoints.add(endpointId);
    acceptedPayloadCallbacks[endpointId] = onPayloadReceived;
    return true;
  }

  @override
  Future<bool> rejectConnection(String endpointId) async {
    rejectedEndpoints.add(endpointId);
    return true;
  }

  @override
  Future<void> disconnectFromEndpoint(String endpointId) async {}

  @override
  Future<void> stopAllEndpoints() async {}

  @override
  Future<void> sendBytesPayload(String endpointId, Uint8List bytes) async {
    sentPayloads.add((endpointId: endpointId, bytes: bytes));
  }
}

void main() {
  group('NearbyTransport connection rules', () {
    late _FakeNearbyApi api;
    late FakeClock clock;
    late NearbyTransport transport;

    setUp(() async {
      api = _FakeNearbyApi();
      clock = FakeClock.fromSeconds(1000);
      transport = NearbyTransport(
        deviceId: 'bbbb0000',
        api: api,
        clock: clock,
        maxPeers: 4,
      );
      await transport.start();
    });

    tearDown(() async {
      await transport.dispose();
    });

    test('deterministic tie-break: smaller deviceId initiates, larger waits', () async {
      // Peer 'aaaa0000' < 'bbbb0000' -> we must NOT initiate.
      api.endpointFound?.call('ep-a', 'aaaa0000', NearbyTransport.serviceId);
      await Future<void>.delayed(Duration.zero);
      expect(api.requestedEndpoints, isEmpty);

      // Peer 'cccc0000' > 'bbbb0000' -> we ARE smaller, so we initiate.
      api.endpointFound?.call('ep-c', 'cccc0000', NearbyTransport.serviceId);
      await Future<void>.delayed(Duration.zero);
      expect(api.requestedEndpoints, ['ep-c']);

      // Incoming connection from 'aaaa0000' is auto-accepted and maps peerId stably.
      final connectedPeers = <String>[];
      final sub = transport.onPeerConnected.listen((e) => connectedPeers.add(e.peerId));
      api.advertInit?.call('ep-a', ConnectionInfo('aaaa0000', 'tok', true));
      await Future<void>.delayed(Duration.zero);
      expect(api.acceptedEndpoints, contains('ep-a'));

      api.advertResult?.call('ep-a', Status.CONNECTED);
      await Future<void>.delayed(Duration.zero);
      expect(connectedPeers, ['aaaa0000']);
      await sub.cancel();
    });

    test('degree cap of 4 ignores 5th discovery and rejects 5th incoming', () async {
      for (var i = 0; i < 4; i++) {
        final ep = 'ep-$i';
        final name = 'peer000$i';
        api.advertInit?.call(ep, ConnectionInfo(name, 'tok', true));
        await Future<void>.delayed(Duration.zero);
        api.advertResult?.call(ep, Status.CONNECTED);
      }
      expect(transport.peerTelemetry.length, 4);

      // 5th discovery ('zzzz0000' > 'bbbb0000') ignored because cap reached.
      api.endpointFound?.call('ep-5', 'zzzz0000', NearbyTransport.serviceId);
      await Future<void>.delayed(Duration.zero);
      expect(api.requestedEndpoints, isEmpty);

      // 5th incoming connection rejected.
      api.advertInit?.call('ep-5', ConnectionInfo('peer0005', 'tok', true));
      await Future<void>.delayed(Duration.zero);
      expect(api.rejectedEndpoints, ['ep-5']);
    });

    test('exponential backoff prevents immediate reconnect storm after disconnect', () async {
      api.endpointFound?.call('ep-1', 'dddd0000', NearbyTransport.serviceId);
      await Future<void>.delayed(Duration.zero);
      expect(api.requestedEndpoints.length, 1);

      // Connection fails -> backoff 2s.
      api.discoverResult?.call('ep-1', Status.ERROR);
      await Future<void>.delayed(Duration.zero);

      // Rediscover at +1s -> blocked by backoff.
      clock.advanceSeconds(1);
      api.endpointFound?.call('ep-2', 'dddd0000', NearbyTransport.serviceId);
      await Future<void>.delayed(Duration.zero);
      expect(api.requestedEndpoints.length, 1);

      // At +2s -> allowed again.
      clock.advanceSeconds(1);
      api.endpointFound?.call('ep-2', 'dddd0000', NearbyTransport.serviceId);
      await Future<void>.delayed(Duration.zero);
      expect(api.requestedEndpoints.length, 2);
    });

    test('blocks oversized outbound frames over 4096 bytes', () async {
      api.advertInit?.call('ep-1', ConnectionInfo('aaaa0000', 'tok', true));
      await Future<void>.delayed(Duration.zero);
      api.advertResult?.call('ep-1', Status.CONNECTED);

      await transport.send('aaaa0000', Uint8List(FrameCodec.maxFrameBytes + 1));
      expect(api.sentPayloads, isEmpty);

      await transport.send('aaaa0000', Uint8List.fromList([0x05, 0x7B, 0x7D]));
      expect(api.sentPayloads.length, 1);
      expect(api.sentPayloads.first.endpointId, 'ep-1');
    });
  });
}

