import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/engine/models/payloads.dart';

class EnvelopeSchemaException implements Exception {
  final DropReason reason;
  final String message;

  const EnvelopeSchemaException(this.reason, this.message);

  @override
  String toString() => 'EnvelopeSchemaException(${reason.code}): $message';
}

/// Wire message envelope matching docs/PROTOCOL.md section 2.
///
/// Mutable hop-by-hop fields ([ttl], [hops]) are NOT included in [signedMap].
class Envelope {
  static const int maxTtl = 10;

  final String id;
  final MessageType type;
  final String origin;
  final String originPub;
  final int ts;
  final double? lat;
  final double? lng;
  final String? refId;
  final Map<String, Object?> payload;
  final String sig;
  final int ttl;
  final int hops;

  const Envelope({
    required this.id,
    required this.type,
    required this.origin,
    required this.originPub,
    required this.ts,
    required this.lat,
    required this.lng,
    required this.refId,
    required this.payload,
    required this.sig,
    required this.ttl,
    required this.hops,
  });

  /// Exact map signed by Ed25519 (excludes mutable `ttl`, `hops`, and `sig`).
  Map<String, Object?> signedMap() => <String, Object?>{
        'id': id,
        'type': type.wireName,
        'origin': origin,
        'originPub': originPub,
        'ts': ts,
        'lat': lat,
        'lng': lng,
        'refId': refId,
        'payload': payload,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type.wireName,
        'origin': origin,
        'originPub': originPub,
        'ts': ts,
        'lat': lat,
        'lng': lng,
        'refId': refId,
        'payload': payload,
        'sig': sig,
        'ttl': ttl,
        'hops': hops,
      };

  Envelope copyWith({int? ttl, int? hops, String? sig}) => Envelope(
        id: id,
        type: type,
        origin: origin,
        originPub: originPub,
        ts: ts,
        lat: lat,
        lng: lng,
        refId: refId,
        payload: payload,
        sig: sig ?? this.sig,
        ttl: ttl ?? this.ttl,
        hops: hops ?? this.hops,
      );

  /// Validates wire JSON in the exact order specified by docs/PROTOCOL.md section 5:
  /// schema -> type/payload -> coords -> ttl clamp.
  factory Envelope.fromWireJson(Map<String, Object?> json) {
    final id = json['id'];
    final typeRaw = json['type'];
    final origin = json['origin'];
    final originPub = json['originPub'];
    final ts = json['ts'];
    final refIdRaw = json['refId'];
    final payloadRaw = json['payload'];
    final sig = json['sig'];
    final ttlRaw = json['ttl'];
    final hopsRaw = json['hops'];

    if (id is! String || id.isEmpty || id.length > 64) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'Invalid or missing id',
      );
    }
    if (typeRaw is! String) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'Invalid or missing type',
      );
    }
    if (origin is! String || origin.isEmpty || origin.length > 32) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'Invalid or missing origin',
      );
    }
    if (originPub is! String || originPub.isEmpty) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'Invalid or missing originPub',
      );
    }
    if (ts is! int) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'ts must be an integer epoch seconds value',
      );
    }
    if (refIdRaw != null && (refIdRaw is! String || refIdRaw.isEmpty)) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'refId must be null or a non-empty string',
      );
    }
    if (payloadRaw is! Map) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'payload must be a JSON object',
      );
    }
    if (sig is! String || sig.isEmpty) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'Invalid or missing sig',
      );
    }
    if (ttlRaw is! int) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'ttl must be an int',
      );
    }
    if (hopsRaw is! int || hopsRaw < 0) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'hops must be a non-negative int',
      );
    }

    // Validate coordinate types as part of schema before payload/coord range check.
    final latRaw = json['lat'];
    final lngRaw = json['lng'];
    if (latRaw != null && latRaw is! num) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'lat must be null or numeric',
      );
    }
    if (lngRaw != null && lngRaw is! num) {
      throw const EnvelopeSchemaException(
        DropReason.badSchema,
        'lng must be null or numeric',
      );
    }

    // Step 3: type known, payload matches schema.
    final type = MessageType.fromWire(typeRaw);
    if (type == null) {
      throw EnvelopeSchemaException(
        DropReason.badPayload,
        'Unknown message type: $typeRaw',
      );
    }
    final payloadMap = _coerceStringKeyMap(payloadRaw);
    if (payloadMap == null) {
      throw const EnvelopeSchemaException(
        DropReason.badPayload,
        'payload contains non-string keys',
      );
    }

    try {
      switch (type) {
        case MessageType.sos:
          SosPayload.fromJson(payloadMap);
        case MessageType.hazard:
          HazardPayload.fromJson(payloadMap);
        case MessageType.shelter:
          ShelterPayload.fromJson(payloadMap);
        case MessageType.ack:
          AckPayload.fromJson(payloadMap);
          if (refIdRaw == null) {
            throw const PayloadValidationException('ACK requires refId');
          }
      }
    } on PayloadValidationException catch (e) {
      throw EnvelopeSchemaException(DropReason.badPayload, e.message);
    }

    // Step 4: coordinate validation.
    final double? lat = latRaw == null ? null : (latRaw as num).toDouble();
    final double? lng = lngRaw == null ? null : (lngRaw as num).toDouble();
    if ((lat == null) != (lng == null)) {
      throw const EnvelopeSchemaException(
        DropReason.badCoords,
        'lat and lng must both be present or both be null',
      );
    }
    if (lat == null || lng == null) {
      // Hazards and shelters must carry a position to be plotted/clustered.
      if (type == MessageType.hazard || type == MessageType.shelter) {
        throw EnvelopeSchemaException(
          DropReason.badCoords,
          '${type.wireName} requires coordinates',
        );
      }
    } else {
      if (!lat.isFinite ||
          !lng.isFinite ||
          lat < -90.0 ||
          lat > 90.0 ||
          lng < -180.0 ||
          lng > 180.0) {
        throw EnvelopeSchemaException(
          DropReason.badCoords,
          'Coordinates out of range: ($lat, $lng)',
        );
      }
    }

    // Step 5: clamp TTL to [0, 10] without dropping.
    final clampedTtl = ttlRaw.clamp(0, maxTtl);

    return Envelope(
      id: id,
      type: type,
      origin: origin,
      originPub: originPub,
      ts: ts,
      lat: lat,
      lng: lng,
      refId: refIdRaw as String?,
      payload: payloadMap,
      sig: sig,
      ttl: clampedTtl,
      hops: hopsRaw,
    );
  }

  SosPayload parseSosPayload() {
    if (type != MessageType.sos) {
      throw StateError('Expected SOS envelope, got ${type.wireName}');
    }
    return SosPayload.fromJson(payload);
  }

  HazardPayload parseHazardPayload() {
    if (type != MessageType.hazard) {
      throw StateError('Expected HAZARD envelope, got ${type.wireName}');
    }
    return HazardPayload.fromJson(payload);
  }

  ShelterPayload parseShelterPayload() {
    if (type != MessageType.shelter) {
      throw StateError('Expected SHELTER envelope, got ${type.wireName}');
    }
    return ShelterPayload.fromJson(payload);
  }

  AckPayload parseAckPayload() {
    if (type != MessageType.ack) {
      throw StateError('Expected ACK envelope, got ${type.wireName}');
    }
    return AckPayload.fromJson(payload);
  }
}

Map<String, Object?>? _coerceStringKeyMap(Map<dynamic, dynamic> raw) {
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final k = entry.key;
    if (k is! String) return null;
    final v = entry.value;
    if (v is Map) {
      final nested = _coerceStringKeyMap(v);
      if (nested == null) return null;
      result[k] = nested;
    } else if (v is List) {
      result[k] = _coerceList(v);
    } else {
      result[k] = v;
    }
  }
  return result;
}

List<Object?> _coerceList(List<dynamic> raw) {
  return raw.map((item) {
    if (item is Map) {
      return _coerceStringKeyMap(item);
    }
    if (item is List) {
      return _coerceList(item);
    }
    return item;
  }).toList();
}

