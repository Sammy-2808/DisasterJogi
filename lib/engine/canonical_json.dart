import 'dart:convert';
import 'dart:typed_data';

/// Produces deterministic canonical JSON per docs/PROTOCOL.md section 4:
/// - Object keys sorted lexicographically at every depth
/// - No whitespace
/// - Numbers in shortest finite JSON form (negative zero normalized to 0.0)
/// - `null` kept explicitly
/// - Strings encoded with standard JSON escaping
String canonicalJson(Object? value) {
  final buffer = StringBuffer();
  _writeCanonical(value, buffer);
  return buffer.toString();
}

Uint8List canonicalJsonBytes(Object? value) =>
    Uint8List.fromList(utf8.encode(canonicalJson(value)));

void _writeCanonical(Object? value, StringBuffer buffer) {
  if (value == null) {
    buffer.write('null');
    return;
  }
  if (value is bool || value is String) {
    buffer.write(jsonEncode(value));
    return;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Non-finite number in JSON');
    }
    final normalized = (value is double && value == 0 && value.isNegative)
        ? 0.0
        : value;
    buffer.write(jsonEncode(normalized));
    return;
  }
  if (value is List) {
    buffer.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) buffer.write(',');
      _writeCanonical(value[i], buffer);
    }
    buffer.write(']');
    return;
  }
  if (value is Map) {
    final entries = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(key, 'key', 'JSON object keys must be strings');
      }
      entries[key] = entry.value;
    }
    final sortedKeys = entries.keys.toList()..sort();
    buffer.write('{');
    for (var i = 0; i < sortedKeys.length; i++) {
      if (i > 0) buffer.write(',');
      final key = sortedKeys[i];
      buffer.write(jsonEncode(key));
      buffer.write(':');
      _writeCanonical(entries[key], buffer);
    }
    buffer.write('}');
    return;
  }
  throw ArgumentError.value(
    value,
    'value',
    'Unsupported type for canonical JSON: ${value.runtimeType}',
  );
}

