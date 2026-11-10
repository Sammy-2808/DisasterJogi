import 'package:flutter/material.dart';

class SheltersScreen extends StatelessWidget {
  const SheltersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield, size: 56),
            SizedBox(height: 16),
            Text(
              'Shelters',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Verified responder shelters will live here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

