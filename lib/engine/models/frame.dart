import 'dart:convert';
import 'dart:typed_data';

import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

class FrameDecodeException implements Exception {
  final DropReason reason;
  final String message;

  const FrameDecodeException(this.reason, this.message);

  @override
  String toString() => 'FrameDecodeException(${reason.code}): $message';
}

sealed class MeshFrame {
  const MeshFrame();
}

final class HelloFrame extends MeshFrame {
  static const int currentVersion = 1;

  final int v;
  final String deviceId;
  final String pub;
  final List<String> caps;

  const HelloFrame({
    this.v = currentVersion,
    required this.deviceId,
    required this.pub,
    this.caps = const <String>['sos', 'hazard', 'shelter'],
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'v': v,
        'deviceId': deviceId,
        'pub': pub,
        'caps': caps,
      };
}

final class InvItem {
  final String id;
  final MessageType type;
  final int ts;

  const InvItem({
    required this.id,
    required this.type,
    required this.ts,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type.wireName,
        'ts': ts,
      };
}

final class InvFrame extends MeshFrame {
  /// Kept at 50 items per frame so every encoded INV frame remains < 4096 B.
  static const int maxItemsPerFrame = 50;
  static const int maxItemsPerSyncRound = 200;

  final List<InvItem> items;

  const InvFrame({required this.items});

  Map<String, Object?> toJson() => <String, Object?>{
        'items': items.map((e) => e.toJson()).toList(growable: false),
      };
}

final class ReqFrame extends MeshFrame {
  static const int maxIdsPerFrame = 50;

  final List<String> ids;

  const ReqFrame({required this.ids});

  Map<String, Object?> toJson() => <String, Object?>{
        'ids': ids,
      };
}

final class MsgFrame extends MeshFrame {
  final Envelope envelope;

  const MsgFrame({required this.envelope});
}

final class PingFrame extends MeshFrame {
  const PingFrame();
}

final class UnknownFrame extends MeshFrame {
  final int rawType;

  const UnknownFrame(this.rawType);
}

abstract final class FrameCodec {
  static const int maxFrameBytes = 4096;

  static Uint8List encode(MeshFrame frame) {
    final int typeByte;
    final Map<String, Object?> body;
    switch (frame) {
      case HelloFrame():
        typeByte = FrameType.hello.byteValue;
        body = frame.toJson();
      case InvFrame():
        if (frame.items.length > InvFrame.maxItemsPerFrame) {
          throw ArgumentError.value(
            frame.items.length,
            'items',
            'INV frame exceeds ${InvFrame.maxItemsPerFrame} items',
          );
        }
        typeByte = FrameType.inv.byteValue;
        body = frame.toJson();
      case ReqFrame():
        if (frame.ids.length > ReqFrame.maxIdsPerFrame) {
          throw ArgumentError.value(
            frame.ids.length,
            'ids',
            'REQ frame exceeds ${ReqFrame.maxIdsPerFrame} ids',
          );
        }
        typeByte = FrameType.req.byteValue;
        body = frame.toJson();
      case MsgFrame():
        typeByte = FrameType.msg.byteValue;
        body = frame.envelope.toJson();
      case PingFrame():
        typeByte = FrameType.ping.byteValue;
        body = const <String, Object?>{};
      case UnknownFrame():
        throw ArgumentError('Cannot encode UnknownFrame');
    }

    final jsonBytes = utf8.encode(jsonEncode(body));
    final totalLength = 1 + jsonBytes.length;
    if (totalLength > maxFrameBytes) {
      throw StateError(
        'Encoded frame exceeds $maxFrameBytes bytes ($totalLength bytes)',
      );
    }
    final out = Uint8List(totalLength);
    out[0] = typeByte;
    out.setRange(1, totalLength, jsonBytes);
    return out;
  }

  static MeshFrame decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxFrameBytes) {
      throw FrameDecodeException(
        DropReason.badFrame,
        'Frame length ${bytes.length} outside 1..$maxFrameBytes bytes',
      );
    }

    final rawType = bytes[0];
    final frameType = FrameType.fromByte(rawType);
    if (frameType == null) {
      // Forward compatibility: unknown frame types are ignored.
      return UnknownFrame(rawType);
    }

    final Object? decoded;
    try {
      final jsonStr = utf8.decode(bytes.sublist(1));
      decoded = jsonDecode(jsonStr);
    } on FormatException catch (e) {
      throw FrameDecodeException(
        DropReason.badFrame,
        'Invalid UTF-8 or JSON body: ${e.message}',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FrameDecodeException(
        DropReason.badFrame,
        'Frame JSON body must be an object',
      );
    }
    final body = Map<String, Object?>.from(decoded);

    switch (frameType) {
      case FrameType.hello:
        return _decodeHello(body);
      case FrameType.inv:
        return _decodeInv(body);
      case FrameType.req:
        return _decodeReq(body);
      case FrameType.msg:
        return _decodeMsg(body);
      case FrameType.ping:
        return const PingFrame();
    }
  }

  static HelloFrame _decodeHello(Map<String, Object?> body) {
    final v = body['v'];
    final deviceId = body['deviceId'];
    final pub = body['pub'];
    final capsRaw = body['caps'];
    if (v is! int ||
        deviceId is! String ||
        deviceId.isEmpty ||
        pub is! String ||
        pub.isEmpty ||
        capsRaw is! List) {
      throw const FrameDecodeException(
        DropReason.badSchema,
        'Invalid HELLO frame fields',
      );
    }
    final caps = <String>[];
    for (final c in capsRaw) {
      if (c is! String) {
        throw const FrameDecodeException(
          DropReason.badSchema,
          'HELLO caps must be strings',
        );
      }
      caps.add(c);
    }
    return HelloFrame(v: v, deviceId: deviceId, pub: pub, caps: caps);
  }

  static InvFrame _decodeInv(Map<String, Object?> body) {
    final itemsRaw = body['items'];
    if (itemsRaw is! List || itemsRaw.length > InvFrame.maxItemsPerFrame) {
      throw const FrameDecodeException(
        DropReason.badSchema,
        'INV items must be a list of <= ${InvFrame.maxItemsPerFrame} items',
      );
    }
    final items = <InvItem>[];
    for (final entry in itemsRaw) {
      if (entry is! Map) {
        throw const FrameDecodeException(
          DropReason.badSchema,
          'INV entry must be an object',
        );
      }
      final id = entry['id'];
      final typeRaw = entry['type'];
      final ts = entry['ts'];
      if (id is! String || id.isEmpty || typeRaw is! String || ts is! int) {
        throw const FrameDecodeException(
          DropReason.badSchema,
          'INV entry missing id/type/ts',
        );
      }
      final type = MessageType.fromWire(typeRaw);
      if (type == null) {
        throw FrameDecodeException(
          DropReason.badSchema,
          'Unknown message type in INV: $typeRaw',
        );
      }
      items.add(InvItem(id: id, type: type, ts: ts));
    }
    return InvFrame(items: items);
  }

  static ReqFrame _decodeReq(Map<String, Object?> body) {
    final idsRaw = body['ids'];
    if (idsRaw is! List || idsRaw.length > ReqFrame.maxIdsPerFrame) {
      throw const FrameDecodeException(
        DropReason.badSchema,
        'REQ ids must be a list of <= ${ReqFrame.maxIdsPerFrame} ids',
      );
    }
    final ids = <String>[];
    for (final entry in idsRaw) {
      if (entry is! String || entry.isEmpty) {
        throw const FrameDecodeException(
          DropReason.badSchema,
          'REQ ids must be non-empty strings',
        );
      }
      ids.add(entry);
    }
    return ReqFrame(ids: ids);
  }

  static MsgFrame _decodeMsg(Map<String, Object?> body) {
    try {
      return MsgFrame(envelope: Envelope.fromWireJson(body));
    } on EnvelopeSchemaException catch (e) {
      throw FrameDecodeException(e.reason, e.message);
    }
  }
}

