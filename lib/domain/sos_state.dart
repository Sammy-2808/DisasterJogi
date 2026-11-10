import 'package:mesh_rescue/crypto/trust_service.dart';
import 'package:mesh_rescue/data/message_store.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';

class SosDerivation {
  final StoredMessage sos;
  final SosPayload payload;
  final SosStatus status;
  final AckStatus? ackStatus;
  final StoredMessage? latestAck;

  const SosDerivation({
    required this.sos,
    required this.payload,
    required this.status,
    this.ackStatus,
    this.latestAck,
  });
}

/// Pure function deriving SOS lifecycle state from the SOS message and all
/// candidate ACK messages referencing its id (`refId == sos.id`).
SosDerivation deriveSosState({
  required StoredMessage sos,
  required Iterable<StoredMessage> candidateAcks,
  required TrustService trustService,
  required int nowSeconds,
}) {
  final sosPayload = sos.envelope.parseSosPayload();

  final validAcks = <({StoredMessage msg, AckPayload payload})>[];
  for (final ackMsg in candidateAcks) {
    if (ackMsg.type != MessageType.ack) continue;
    if (ackMsg.envelope.refId != sos.id) continue;

    final ackPayload = ackMsg.envelope.parseAckPayload();
    final isResponder = trustService.isTrustedResponderPub(
      ackMsg.envelope.originPub,
    );
    final isSameOrigin = ackMsg.envelope.originPub == sos.envelope.originPub;

    final authorized =
        isResponder || (isSameOrigin && ackPayload.status.isTerminal);
    if (!authorized) continue;

    validAcks.add((msg: ackMsg, payload: ackPayload));
  }

  validAcks.sort((a, b) {
    final rankCmp = _ackRank(b.payload.status).compareTo(_ackRank(a.payload.status));
    if (rankCmp != 0) return rankCmp;
    return b.msg.receivedAt.compareTo(a.msg.receivedAt);
  });

  if (validAcks.isNotEmpty) {
    final top = validAcks.first;
    if (top.payload.status.isTerminal) {
      return SosDerivation(
        sos: sos,
        payload: sosPayload,
        status: SosStatus.resolved,
        ackStatus: top.payload.status,
        latestAck: top.msg,
      );
    }
    if (nowSeconds - sos.receivedAt >= ExpiryDurations.sosSeconds) {
      return SosDerivation(
        sos: sos,
        payload: sosPayload,
        status: SosStatus.expired,
        ackStatus: top.payload.status,
        latestAck: top.msg,
      );
    }
    return SosDerivation(
      sos: sos,
      payload: sosPayload,
      status: SosStatus.acknowledged,
      ackStatus: top.payload.status,
      latestAck: top.msg,
    );
  }

  final isExpired = nowSeconds - sos.receivedAt >= ExpiryDurations.sosSeconds;
  return SosDerivation(
    sos: sos,
    payload: sosPayload,
    status: isExpired ? SosStatus.expired : SosStatus.active,
  );
}

int _ackRank(AckStatus status) {
  switch (status) {
    case AckStatus.received:
      return 1;
    case AckStatus.dispatched:
      return 2;
    case AckStatus.resolved:
      return 3;
    case AckStatus.cancelled:
      return 4;
  }
}

