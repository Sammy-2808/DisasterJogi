import 'dart:convert';

import 'package:mesh_rescue/engine/canonical_json.dart';
import 'package:mesh_rescue/engine/models/envelope.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:test/test.dart';

void main() {
  group('canonicalJson', () {
    test('matches fixed deterministic test vector with sorted nested keys', () {
      final input = <String, Object?>{
        'z': 1,
        'a': null,
        'm': <String, Object?>{
          'b': true,
          'a': 'hello\n"world"',
          'c': <Object?>[3, false, null, <String, Object?>{'y': 2, 'x': 1}],
        },
        'f': -0.0,
      };

      expect(
        canonicalJson(input),
        '{"a":null,"f":0.0,"m":{"a":"hello\\n\\"world\\"","b":true,"c":[3,false,null,{"x":1,"y":2}]},"z":1}',
      );
    });

    test('two differently ordered maps produce identical bytes', () {
      final mapA = <String, Object?>{
        'payload': <String, Object?>{'people': 3, 'category': 'trapped', 'note': '2nd floor'},
        'ts': 1731200000,
        'id': '3f2b8c1e-0000-4000-8000-000000000001',
        'lat': 21.4669,
        'lng': 83.9812,
        'refId': null,
        'originPub': 'AAAA',
        'origin': 'a1b2c3d4',
        'type': 'SOS',
      };
      final mapB = <String, Object?>{
        'id': '3f2b8c1e-0000-4000-8000-000000000001',
        'type': 'SOS',
        'origin': 'a1b2c3d4',
        'originPub': 'AAAA',
        'ts': 1731200000,
        'lat': 21.4669,
        'lng': 83.9812,
        'refId': null,
        'payload': <String, Object?>{'note': '2nd floor', 'category': 'trapped', 'people': 3},
      };

      expect(canonicalJson(mapA), equals(canonicalJson(mapB)));
      expect(canonicalJsonBytes(mapA), equals(canonicalJsonBytes(mapB)));
      expect(utf8.decode(canonicalJsonBytes(mapA)), equals(canonicalJson(mapA)));
    });

    test('Envelope.signedMap excludes mutable ttl, hops, and sig', () {
      const env1 = Envelope(
        id: 'id-1',
        type: MessageType.sos,
        origin: 'a1b2c3d4',
        originPub: 'pub',
        ts: 1731200000,
        lat: 21.4669,
        lng: 83.9812,
        refId: null,
        payload: {'category': 'flood', 'people': 2, 'note': ''},
        sig: 'sig-1',
        ttl: 10,
        hops: 0,
      );
      final env2 = env1.copyWith(ttl: 4, hops: 6, sig: 'different');

      expect(
        canonicalJsonBytes(env1.signedMap()),
        equals(canonicalJsonBytes(env2.signedMap())),
      );
      expect(env1.signedMap().containsKey('ttl'), isFalse);
      expect(env1.signedMap().containsKey('hops'), isFalse);
      expect(env1.signedMap().containsKey('sig'), isFalse);
      expect(env1.signedMap().containsKey('refId'), isTrue);
    });
  });
}

