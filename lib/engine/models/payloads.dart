import 'package:mesh_rescue/engine/models/enums.dart';

class PayloadValidationException implements Exception {
  final String message;
  const PayloadValidationException(this.message);

  @override
  String toString() => 'PayloadValidationException: $message';
}

abstract final class PayloadConstraints {
  static const int maxNoteLength = 500;
  static const int maxContactLength = 120;
  static const int maxKeyLength = 80;
  static const int maxNameLength = 120;
  static const int maxServicesCount = 16;
  static const int maxPeopleCount = 10000;
}

class SosPayload {
  final SosCategory category;
  final int people;
  final String note;
  final String? contact;

  const SosPayload({
    required this.category,
    required this.people,
    this.note = '',
    this.contact,
  });

  factory SosPayload.fromJson(Map<String, Object?> json) {
    final categoryRaw = json['category'];
    if (categoryRaw is! String) {
      throw const PayloadValidationException('SOS category must be a string');
    }
    final category = SosCategory.fromWire(categoryRaw);
    if (category == null) {
      throw PayloadValidationException('Unknown SOS category: $categoryRaw');
    }

    final peopleRaw = json['people'];
    if (peopleRaw is! int ||
        peopleRaw < 1 ||
        peopleRaw > PayloadConstraints.maxPeopleCount) {
      throw const PayloadValidationException(
        'SOS people must be an int in 1..10000',
      );
    }

    final noteRaw = json['note'];
    if (noteRaw != null && noteRaw is! String) {
      throw const PayloadValidationException('SOS note must be a string');
    }
    final note = (noteRaw as String?) ?? '';
    if (note.length > PayloadConstraints.maxNoteLength) {
      throw const PayloadValidationException('SOS note too long');
    }

    final contactRaw = json['contact'];
    if (contactRaw != null && contactRaw is! String) {
      throw const PayloadValidationException('SOS contact must be a string');
    }
    final contact = contactRaw as String?;
    if (contact != null && contact.length > PayloadConstraints.maxContactLength) {
      throw const PayloadValidationException('SOS contact too long');
    }

    return SosPayload(
      category: category,
      people: peopleRaw,
      note: note,
      contact: contact,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'category': category.wireName,
        'people': people,
        'note': note,
        if (contact != null) 'contact': contact,
      };
}

class HazardPayload {
  final HazardKind kind;
  final int severity;
  final String note;

  const HazardPayload({
    required this.kind,
    required this.severity,
    this.note = '',
  });

  factory HazardPayload.fromJson(Map<String, Object?> json) {
    final kindRaw = json['kind'];
    if (kindRaw is! String) {
      throw const PayloadValidationException('HAZARD kind must be a string');
    }
    final kind = HazardKind.fromWire(kindRaw);
    if (kind == null) {
      throw PayloadValidationException('Unknown HAZARD kind: $kindRaw');
    }

    final severityRaw = json['severity'];
    if (severityRaw is! int || severityRaw < 1 || severityRaw > 5) {
      throw const PayloadValidationException(
        'HAZARD severity must be an int in 1..5',
      );
    }

    final noteRaw = json['note'];
    if (noteRaw != null && noteRaw is! String) {
      throw const PayloadValidationException('HAZARD note must be a string');
    }
    final note = (noteRaw as String?) ?? '';
    if (note.length > PayloadConstraints.maxNoteLength) {
      throw const PayloadValidationException('HAZARD note too long');
    }

    return HazardPayload(kind: kind, severity: severityRaw, note: note);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.wireName,
        'severity': severity,
        'note': note,
      };
}

class ShelterPayload {
  final String key;
  final String name;
  final ShelterStatus status;
  final int capacity;
  final List<String> services;
  final String note;
  final int seq;

  const ShelterPayload({
    required this.key,
    required this.name,
    required this.status,
    required this.capacity,
    required this.services,
    this.note = '',
    required this.seq,
  });

  factory ShelterPayload.fromJson(Map<String, Object?> json) {
    final key = json['key'];
    if (key is! String ||
        key.trim().isEmpty ||
        key.length > PayloadConstraints.maxKeyLength) {
      throw const PayloadValidationException(
        'SHELTER key must be a non-empty string',
      );
    }

    final name = json['name'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > PayloadConstraints.maxNameLength) {
      throw const PayloadValidationException(
        'SHELTER name must be a non-empty string',
      );
    }

    final statusRaw = json['status'];
    if (statusRaw is! String) {
      throw const PayloadValidationException(
        'SHELTER status must be a string',
      );
    }
    final status = ShelterStatus.fromWire(statusRaw);
    if (status == null) {
      throw PayloadValidationException('Unknown SHELTER status: $statusRaw');
    }

    final capacity = json['capacity'];
    if (capacity is! int || capacity < 0 || capacity > 1000000) {
      throw const PayloadValidationException(
        'SHELTER capacity must be a non-negative int',
      );
    }

    final servicesRaw = json['services'];
    if (servicesRaw is! List ||
        servicesRaw.length > PayloadConstraints.maxServicesCount) {
      throw const PayloadValidationException(
        'SHELTER services must be a list of strings',
      );
    }
    final services = <String>[];
    for (final item in servicesRaw) {
      if (item is! String || item.length > 40) {
        throw const PayloadValidationException(
          'SHELTER service entries must be short strings',
        );
      }
      services.add(item);
    }

    final noteRaw = json['note'];
    if (noteRaw != null && noteRaw is! String) {
      throw const PayloadValidationException('SHELTER note must be a string');
    }
    final note = (noteRaw as String?) ?? '';
    if (note.length > PayloadConstraints.maxNoteLength) {
      throw const PayloadValidationException('SHELTER note too long');
    }

    final seq = json['seq'];
    if (seq is! int || seq < 0) {
      throw const PayloadValidationException(
        'SHELTER seq must be a non-negative int',
      );
    }

    return ShelterPayload(
      key: key,
      name: name,
      status: status,
      capacity: capacity,
      services: List<String>.unmodifiable(services),
      note: note,
      seq: seq,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'name': name,
        'status': status.wireName,
        'capacity': capacity,
        'services': services,
        'note': note,
        'seq': seq,
      };
}

class AckPayload {
  final AckStatus status;
  final String note;

  const AckPayload({required this.status, this.note = ''});

  factory AckPayload.fromJson(Map<String, Object?> json) {
    final statusRaw = json['status'];
    if (statusRaw is! String) {
      throw const PayloadValidationException('ACK status must be a string');
    }
    final status = AckStatus.fromWire(statusRaw);
    if (status == null) {
      throw PayloadValidationException('Unknown ACK status: $statusRaw');
    }

    final noteRaw = json['note'];
    if (noteRaw != null && noteRaw is! String) {
      throw const PayloadValidationException('ACK note must be a string');
    }
    final note = (noteRaw as String?) ?? '';
    if (note.length > PayloadConstraints.maxNoteLength) {
      throw const PayloadValidationException('ACK note too long');
    }

    return AckPayload(status: status, note: note);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.wireName,
        'note': note,
      };
}

