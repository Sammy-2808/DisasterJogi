import 'package:flutter/material.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';
import 'package:mesh_rescue/services/location_service.dart';

class SosDetailsResult {
  final SosCategory category;
  final int people;
  final String note;
  final String contact;

  const SosDetailsResult({
    required this.category,
    required this.people,
    required this.note,
    required this.contact,
  });
}

Future<SosDetailsResult?> showSosDetailsSheet(
  BuildContext context, {
  SosCategory initialCategory = SosCategory.trapped,
  int initialPeople = 1,
  GeoFix? locationFix,
}) {
  return showModalBottomSheet<SosDetailsResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _SosDetailsSheet(
      initialCategory: initialCategory,
      initialPeople: initialPeople,
      locationFix: locationFix,
    ),
  );
}

class _SosDetailsSheet extends StatefulWidget {
  final SosCategory initialCategory;
  final int initialPeople;
  final GeoFix? locationFix;

  const _SosDetailsSheet({
    required this.initialCategory,
    required this.initialPeople,
    required this.locationFix,
  });

  @override
  State<_SosDetailsSheet> createState() => _SosDetailsSheetState();
}

class _SosDetailsSheetState extends State<_SosDetailsSheet> {
  late SosCategory _category = widget.initialCategory;
  late int _people = widget.initialPeople;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fix = widget.locationFix;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.sos, color: MeshColors.sosRed, size: 28),
                const SizedBox(width: 8),
                Text(
                  'SOS Details',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              fix == null
                  ? 'GPS unavailable: describe your landmark in the note below.'
                  : 'GPS: ${fix.lat.toStringAsFixed(5)}, ${fix.lng.toStringAsFixed(5)}${fix.isStale ? " (stale)" : ""}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SosCategory.values
                  .map(
                    (c) => ChoiceChip(
                      label: Text(c.wireName.toUpperCase()),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('People needing help:', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton.outlined(
                  onPressed: _people > 1 ? () => setState(() => _people--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('$_people', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                IconButton.outlined(
                  onPressed: () => setState(() => _people++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Situation / location note',
                hintText: 'e.g. 2nd floor, stairs blocked',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contactController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Optional contact / name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: MeshColors.sosRed),
              onPressed: () {
                Navigator.of(context).pop(
                  SosDetailsResult(
                    category: _category,
                    people: _people,
                    note: _noteController.text,
                    contact: _contactController.text,
                  ),
                );
              },
              icon: const Icon(Icons.sos),
              label: const Text('Broadcast SOS Now'),
            ),
          ],
        ),
      ),
    );
  }
}

