import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mesh_rescue/crypto/signer.dart';
import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/domain/geo.dart';
import 'package:mesh_rescue/engine/canonical_json.dart';
import 'package:mesh_rescue/engine/clock.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/frame.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';
import 'package:mesh_rescue/engine/outbox.dart';
import 'package:mesh_rescue/engine/rate_limiter.dart';
import 'package:mesh_rescue/engine/sync.dart';
import 'package:mesh_rescue/transport/mesh_transport.dart';
import 'package:uuid/uuid.dart';

final class DropEvent {
  final String peerId;
  final DropReason reason;
  final String? messageId;
  final String detail;

  const DropEvent({
    required this.peerId,
    required this.reason,
    this.messageId,
    required this.detail,
  });
}

/// Pure-Dart mesh protocol engine implementing docs/PROTOCOL.md.
class MeshEngine {
  static const Uuid _uuid = Uuid();

  final MeshTransport transport;
  final MessageStore store;
  final Signer signer;
  final IdentityKeyPair identity;
  final TrustService trustService;
  final Clock clock;
  final RateLimiter rateLimiter;
  final PeerAbuseTracker abuseTracker;
  late final OutboxScheduler outbox;
  late final SyncManager syncManager;

  bool batterySaver;

  final Set<String> _connectedPeers = <String>{};
  final Map<DropReason, int> _dropCounts = <DropReason, int>{};

  final StreamController<StoredMessage> _acceptedController =
      StreamController<StoredMessage>.broadcast();
  final StreamController<DropEvent> _dropController =
      StreamController<DropEvent>.broadcast();

  StreamSubscription<PeerConnectedEvent>? _connSub;
  StreamSubscription<PeerDisconnectedEvent>? _discSub;
  StreamSubscription<IncomingFrameEvent>? _frameSub;
  bool _running = false;
  int _relayedCount = 0;

  MeshEngine({
    required this.transport,
    required this.store,
    required this.signer,
    required this.identity,
    required this.trustService,
    required this.clock,
    RateLimiter? rateLimiter,
    PeerAbuseTracker? abuseTracker,
    this.batterySaver = false,
    int minSendSpacingMillis = 0,
  })  : rateLimiter = rateLimiter ?? RateLimiter(clock: clock),
        abuseTracker = abuseTracker ?? PeerAbuseTracker(clock: clock) {
    outbox = OutboxScheduler(
      store: store,
      transport: transport,
      clock: clock,
      minSendSpacingMillis: minSendSpacingMillis,
    );
    syncManager = SyncManager(
      store: store,
      transport: transport,
      identity: identity,
      outbox: outbox,
      clock: clock,
    );
  }

  Stream<StoredMessage> get onMessageAccepted => _acceptedController.stream;
  Stream<DropEvent> get onDrop => _dropController.stream;
  Set<String> get connectedPeers => Set<String>.unmodifiable(_connectedPeers);
  Map<DropReason, int> get dropCounts => Map<DropReason, int>.unmodifiable(_dropCounts);
  int get relayedCount => _relayedCount;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _connSub = transport.onPeerConnected.listen(_handlePeerConnected);
    _discSub = transport.onPeerDisconnected.listen(_handlePeerDisconnected);
    _frameSub = transport.onFrameReceived.listen(_handleIncomingFrame);
    await transport.start();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _connSub?.cancel();
    await _discSub?.cancel();
    await _frameSub?.cancel();
    _connSub = null;
    _discSub = null;
    _frameSub = null;
    await transport.stop();
    _connectedPeers.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _acceptedController.close();
    await _dropController.close();
  }

  Future<void> _handlePeerConnected(PeerConnectedEvent event) async {
    if (abuseTracker.isBlocked(event.peerId)) {
      await transport.disconnectPeer(event.peerId);
      return;
    }
    _connectedPeers.add(event.peerId);
    await syncManager.onPeerConnected(event.peerId);
    await outbox.flush(<String>[event.peerId]);
  }

  void _handlePeerDisconnected(PeerDisconnectedEvent event) {
    _connectedPeers.remove(event.peerId);
    syncManager.onPeerDisconnected(event.peerId);
    outbox.clearPeer(event.peerId);
  }

  Future<void> _handleIncomingFrame(IncomingFrameEvent event) async {
    await receiveFrame(event.peerId, event.bytes);
    await outbox.flush(_connectedPeers);
  }

  /// Drives one engine maintenance step: outbox flush, periodic INV sync,
  /// local SOS rebroadcast check, and expiry purge.
  Future<void> tick() async {
    await outbox.flush(_connectedPeers);
    await syncManager.tickPeriodicInv(_connectedPeers);
    await outbox.tickLocalSosRebroadcast(
      _connectedPeers,
      batterySaver: batterySaver,
    );
    await store.purgeExpired(clock.nowSeconds());
  }

  /// Processes one raw frame from [peerId] synchronously through decode and the
  /// 10-step receive pipeline. Exposed publicly for deterministic unit tests.
  Future<StoredMessage?> receiveFrame(String peerId, Uint8List bytes) async {
    if (abuseTracker.isBlocked(peerId)) {
      return null;
    }

    final MeshFrame frame;
    try {
      frame = FrameCodec.decode(bytes);
    } on FrameDecodeException catch (e) {
      await _recordDrop(
        peerId,
        e.reason,
        detail: e.message,
        penalizePeer: true,
      );
      return null;
    }

    switch (frame) {
      case HelloFrame():
        await syncManager.handleHello(peerId, frame);
        return null;
      case InvFrame():
        await syncManager.handleInv(peerId, frame);
        return null;
      case ReqFrame():
        await syncManager.handleReq(peerId, frame);
        return null;
      case PingFrame():
      case UnknownFrame():
        return null;
      case MsgFrame():
        return _processIncomingEnvelope(peerId, frame.envelope);
    }
  }

  Future<StoredMessage?> _processIncomingEnvelope(
    String peerId,
    Envelope env,
  ) async {
    final nowSec = clock.nowSeconds();

    // Step 6: dedup by id.
    if (await store.hasMessage(env.id)) {
      await store.markSentTo(env.id, peerId, nowSec);
      await _recordDrop(
        peerId,
        DropReason.duplicate,
        messageId: env.id,
        detail: 'Duplicate message id',
      );
      return null;
    }

    // Step 7: origin == first 8 hex of SHA-256(originPub).
    if (!await signer.matchesOrigin(env.origin, env.originPub)) {
      await _recordDrop(
        peerId,
        DropReason.badOrigin,
        messageId: env.id,
        detail: 'origin does not match SHA-256(originPub)',
        penalizePeer: true,
      );
      return null;
    }

    // Step 8: Ed25519 signature check over canonical signed bytes.
    final signedBytes = canonicalJsonBytes(env.signedMap());
    final sigValid = await signer.verifyBytes(
      signedBytes,
      signatureBase64: env.sig,
      publicKeyBase64: env.originPub,
    );
    if (!sigValid) {
      await _recordDrop(
        peerId,
        DropReason.badSig,
        messageId: env.id,
        detail: 'Invalid Ed25519 signature',
        penalizePeer: true,
      );
      return null;
    }

    // Step 9: per-origin rate limit.
    if (!rateLimiter.allow(env.origin)) {
      await _recordDrop(
        peerId,
        DropReason.rateLimited,
        messageId: env.id,
        detail: 'Origin ${env.origin} exceeded rate limit',
      );
      return null;
    }

    // Step 10: type-specific authority & trust tier assignment.
    if (env.type == MessageType.ack) {
      final ack = env.parseAckPayload();
      final isResponder = trustService.isTrustedResponderPub(env.originPub);
      if (!isResponder) {
        if (!ack.status.isTerminal) {
          await _recordDrop(
            peerId,
            DropReason.unauthorized,
            messageId: env.id,
            detail: 'Non-responder ACK status ${ack.status.wireName} rejected',
          );
          return null;
        }
        final refSos = await store.getMessage(env.refId!);
        if (refSos == null ||
            refSos.type != MessageType.sos ||
            refSos.envelope.originPub != env.originPub) {
          await _recordDrop(
            peerId,
            DropReason.unauthorized,
            messageId: env.id,
            detail: 'Origin cancel/resolve key mismatch or missing SOS',
          );
          return null;
        }
      }
    }

    final trust = trustService.evaluateTrust(
      type: env.type,
      originPub: env.originPub,
      signatureValid: true,
    );

    // Forwarding adjustment: store updated hop count and remaining TTL.
    final canForward = env.ttl - 1 > 0;
    final storedEnv = env.copyWith(
      ttl: math.max(0, env.ttl - 1),
      hops: env.hops + 1,
    );

    final geohash = (storedEnv.lat != null && storedEnv.lng != null)
        ? encodeGeohash7(storedEnv.lat!, storedEnv.lng!)
        : null;

    final stored = StoredMessage(
      envelope: storedEnv,
      receivedAt: nowSec,
      geohash: geohash,
      trust: trust,
      isLocal: false,
    );

    await store.saveMessage(stored, nowSeconds: nowSec);
    // Mark sender so we never forward back to the peer it came from, and if
    // ttl - 1 <= 0 mark all peers so it will not be forwarded.
    await store.markSentTo(stored.id, peerId, nowSec);
    if (!canForward) {
      for (final p in _connectedPeers) {
        await store.markSentTo(stored.id, p, nowSec);
      }
    } else if (_connectedPeers.length > 1) {
      _relayedCount++;
    }

    _acceptedController.add(stored);
    return stored;
  }

  /// Creates, signs, stores, and queues a new locally originated SOS.
  Future<StoredMessage> publishSos({
    required SosPayload payload,
    double? lat,
    double? lng,
    IdentityKeyPair? signingIdentity,
  }) =>
      _publishLocal(
        type: MessageType.sos,
        payload: payload.toJson(),
        lat: lat,
        lng: lng,
        signingIdentity: signingIdentity,
      );

  /// Creates, signs, stores, and queues a new locally originated HAZARD.
  Future<StoredMessage> publishHazard({
    required HazardPayload payload,
    required double lat,
    required double lng,
    String? refId,
    IdentityKeyPair? signingIdentity,
  }) =>
      _publishLocal(
        type: MessageType.hazard,
        payload: payload.toJson(),
        lat: lat,
        lng: lng,
        refId: refId,
        signingIdentity: signingIdentity,
      );

  /// Creates, signs, stores, and queues a new SHELTER announcement/update.
  Future<StoredMessage> publishShelter({
    required ShelterPayload payload,
    required double lat,
    required double lng,
    IdentityKeyPair? signingIdentity,
  }) =>
      _publishLocal(
        type: MessageType.shelter,
        payload: payload.toJson(),
        lat: lat,
        lng: lng,
        signingIdentity: signingIdentity,
      );

  /// Creates, signs, stores, and queues an ACK for an SOS.
  Future<StoredMessage> publishAck({
    required String sosId,
    required AckPayload payload,
    double? lat,
    double? lng,
    IdentityKeyPair? signingIdentity,
  }) =>
      _publishLocal(
        type: MessageType.ack,
        payload: payload.toJson(),
        lat: lat,
        lng: lng,
        refId: sosId,
        signingIdentity: signingIdentity,
      );

  Future<StoredMessage> _publishLocal({
    required MessageType type,
    required Map<String, Object?> payload,
    required double? lat,
    required double? lng,
    String? refId,
    IdentityKeyPair? signingIdentity,
  }) async {
    final signerId = signingIdentity ?? identity;
    final nowSec = clock.nowSeconds();
    final unsigned = Envelope(
      id: _uuid.v4(),
      type: type,
      origin: signerId.origin,
      originPub: signerId.publicKeyBase64,
      ts: nowSec,
      lat: lat == null ? null : double.parse(lat.toStringAsFixed(5)),
      lng: lng == null ? null : double.parse(lng.toStringAsFixed(5)),
      refId: refId,
      payload: payload,
      sig: '',
      ttl: type.defaultTtl,
      hops: 0,
    );

    final bytes = canonicalJsonBytes(unsigned.signedMap());
    final sig = await signer.signBytes(bytes, signerId);
    final signed = unsigned.copyWith(sig: sig);

    final trust = trustService.evaluateTrust(
      type: type,
      originPub: signed.originPub,
      signatureValid: true,
    );
    final geohash = (signed.lat != null && signed.lng != null)
        ? encodeGeohash7(signed.lat!, signed.lng!)
        : null;

    final stored = StoredMessage(
      envelope: signed,
      receivedAt: nowSec,
      geohash: geohash,
      trust: trust,
      isLocal: true,
    );

    await store.saveMessage(stored, nowSeconds: nowSec);
    _acceptedController.add(stored);
    await outbox.flush(_connectedPeers);
    return stored;
  }

  Future<void> _recordDrop(
    String peerId,
    DropReason reason, {
    String? messageId,
    required String detail,
    bool penalizePeer = false,
  }) async {
    _dropCounts[reason] = (_dropCounts[reason] ?? 0) + 1;
    _dropController.add(
      DropEvent(
        peerId: peerId,
        reason: reason,
        messageId: messageId,
        detail: detail,
      ),
    );
    if (penalizePeer && abuseTracker.recordOffense(peerId)) {
      await transport.disconnectPeer(peerId);
      _connectedPeers.remove(peerId);
    }
  }
}

