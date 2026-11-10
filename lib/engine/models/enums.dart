enum MessageType {
  sos('SOS', defaultTtl: 10, priorityRank: 0),
  ack('ACK', defaultTtl: 10, priorityRank: 1),
  shelter('SHELTER', defaultTtl: 10, priorityRank: 2),
  hazard('HAZARD', defaultTtl: 6, priorityRank: 3);

  const MessageType(
    this.wireName, {
    required this.defaultTtl,
    required this.priorityRank,
  });

  final String wireName;
  final int defaultTtl;
  final int priorityRank;

  static MessageType? fromWire(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return null;
  }
}

enum FrameType {
  hello(0x01),
  inv(0x02),
  req(0x03),
  msg(0x04),
  ping(0x05);

  const FrameType(this.byteValue);
  final int byteValue;

  static FrameType? fromByte(int byte) {
    for (final value in values) {
      if (value.byteValue == byte) return value;
    }
    return null;
  }
}

enum TrustTier {
  verifiedResponder('VERIFIED_RESPONDER'),
  signedPeer('SIGNED_PEER'),
  unverified('UNVERIFIED');

  const TrustTier(this.wireName);
  final String wireName;

  static TrustTier? fromWire(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return null;
  }
}

enum DropReason {
  badFrame('BAD_FRAME'),
  badSchema('BAD_SCHEMA'),
  badPayload('BAD_PAYLOAD'),
  badCoords('BAD_COORDS'),
  duplicate('DUPLICATE'),
  badOrigin('BAD_ORIGIN'),
  badSig('BAD_SIG'),
  rateLimited('RATE_LIMITED'),
  unauthorized('UNAUTHORIZED');

  const DropReason(this.code);
  final String code;
}

enum SosCategory {
  trapped('trapped'),
  medical('medical'),
  fire('fire'),
  flood('flood'),
  lost('lost'),
  other('other');

  const SosCategory(this.wireName);
  final String wireName;

  static SosCategory? fromWire(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return null;
  }
}

enum SosStatus {
  active('ACTIVE'),
  acknowledged('ACKNOWLEDGED'),
  resolved('RESOLVED'),
  expired('EXPIRED');

  const SosStatus(this.wireName);
  final String wireName;
}

enum AckStatus {
  received('RECEIVED'),
  dispatched('DISPATCHED'),
  resolved('RESOLVED'),
  cancelled('CANCELLED');

  const AckStatus(this.wireName);
  final String wireName;

  bool get isTerminal =>
      this == AckStatus.resolved || this == AckStatus.cancelled;

  static AckStatus? fromWire(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return null;
  }
}

enum HazardKind {
  flood('flood'),
  fire('fire'),
  collapse('collapse'),
  roadBlocked('road_blocked'),
  landslide('landslide'),
  other('other');

  const HazardKind(this.wireName);
  final String wireName;

  static HazardKind? fromWire(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return null;
  }
}

enum ShelterStatus {
  open('OPEN'),
  full('FULL'),
  closed('CLOSED');

  const ShelterStatus(this.wireName);
  final String wireName;

  static ShelterStatus? fromWire(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return null;
  }
}

