import 'package:flutter/material.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.list_alt, size: 56),
            SizedBox(height: 16),
            Text(
              'Alerts & Hazards Feed',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Priority-sorted SOS and hazard reports will live here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

