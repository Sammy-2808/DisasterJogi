import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

class RadarBlip {
  final String id;
  final String label;
  final MessageType type;
  final TrustTier trust;
  final double distanceMeters;
  final double bearingDegrees;
  final String detail;

  const RadarBlip({
    required this.id,
    required this.label,
    required this.type,
    required this.trust,
    required this.distanceMeters,
    required this.bearingDegrees,
    required this.detail,
  });
}

/// Offline zero-tile Radar view plotting SOS, hazards, and shelters around the
/// user by distance and initial great-circle bearing.
class RadarView extends StatelessWidget {
  final List<RadarBlip> blips;
  final bool hasUserLocation;
  final void Function(RadarBlip blip)? onTapBlip;

  const RadarView({
    super.key,
    required this.blips,
    required this.hasUserLocation,
    this.onTapBlip,
  });

  @override
  Widget build(BuildContext context) {
    final maxMeters = blips.isEmpty
        ? 1000.0
        : math.max(
            500.0,
            blips.map((b) => b.distanceMeters).reduce(math.max) * 1.15,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final radarSize = math.min(
          constraints.maxWidth - 32,
          math.max(180.0, constraints.maxHeight * 0.56),
        );

        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            if (!hasUserLocation)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF3E0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: const Row(
                  children: [
                    Icon(Icons.gps_off, color: MeshColors.hazardAmber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Waiting for GPS fix — distances/bearings use fallback reference until GPS locks.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Center(
                child: SizedBox(
                  width: radarSize,
                  height: radarSize,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: MeshColors.inkPrimary, width: 2),
                    ),
                    child: CustomPaint(
                      painter: _RadarPainter(
                        blips: blips,
                        maxRadiusMeters: maxMeters,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  const _LegendChip(
                    color: Color(0xFFFF5252),
                    icon: Icons.circle,
                    label: 'SOS',
                  ),
                  const _LegendChip(
                    color: Color(0xFFFFB300),
                    icon: Icons.change_history,
                    label: 'Hazard',
                  ),
                  const _LegendChip(
                    color: Color(0xFF66BB6A),
                    icon: Icons.square,
                    label: 'Verified Shelter',
                  ),
                  Text(
                    'Outer ring: ${_formatDistance(maxMeters)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (blips.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No geolocated SOS, hazards, or shelters received yet.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final b in blips)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: ListTile(
                      leading:
                          Icon(_iconForType(b.type), color: _colorForBlip(b)),
                      title: Text(
                        b.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${_formatDistance(b.distanceMeters)} • '
                        '${b.bearingDegrees.round()}° ${_cardinal(b.bearingDegrees)} • ${b.detail}',
                      ),
                      onTap: onTapBlip == null ? null : () => onTapBlip!(b),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }

  static IconData _iconForType(MessageType t) => switch (t) {
        MessageType.sos => Icons.sos,
        MessageType.hazard => Icons.warning_amber_rounded,
        MessageType.shelter => Icons.shield,
        MessageType.ack => Icons.check_circle,
      };

  static Color _colorForBlip(RadarBlip b) => switch (b.type) {
        MessageType.sos => MeshColors.sosRed,
        MessageType.hazard => MeshColors.hazardAmber,
        MessageType.shelter => b.trust == TrustTier.verifiedResponder
            ? MeshColors.verifiedGreen
            : MeshColors.hazardAmber,
        MessageType.ack => MeshColors.primaryBlue,
      };
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _LegendChip({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<RadarBlip> blips;
  final double maxRadiusMeters;

  const _RadarPainter({
    required this.blips,
    required this.maxRadiusMeters,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.42;

    final gridPaint = Paint()
      ..color = const Color(0xFF415A77)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final frac in [0.33, 0.66, 1.0]) {
      canvas.drawCircle(center, radius * frac, gridPaint);
    }
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    _drawLabel(
        canvas, 'N', Offset(center.dx, center.dy - radius - 14), Colors.white70);
    _drawLabel(
        canvas, 'S', Offset(center.dx, center.dy + radius + 14), Colors.white70);
    _drawLabel(
        canvas, 'E', Offset(center.dx + radius + 14, center.dy), Colors.white70);
    _drawLabel(
        canvas, 'W', Offset(center.dx - radius - 14, center.dy), Colors.white70);

    canvas.drawCircle(center, 6, Paint()..color = const Color(0xFF4FC3F7));

    for (final blip in blips) {
      final normDist = (blip.distanceMeters / maxRadiusMeters).clamp(0.05, 1.0);
      final r = normDist * radius;
      final rad = (blip.bearingDegrees - 90.0) * (math.pi / 180.0);
      final pos = Offset(
        center.dx + r * math.cos(rad),
        center.dy + r * math.sin(rad),
      );

      switch (blip.type) {
        case MessageType.sos:
          canvas.drawCircle(pos, 9, Paint()..color = const Color(0xFFFF5252));
          canvas.drawCircle(
            pos,
            9,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        case MessageType.hazard:
          final path = Path()
            ..moveTo(pos.dx, pos.dy - 9)
            ..lineTo(pos.dx + 8, pos.dy + 7)
            ..lineTo(pos.dx - 8, pos.dy + 7)
            ..close();
          canvas.drawPath(path, Paint()..color = const Color(0xFFFFB300));
        case MessageType.shelter:
          final color = blip.trust == TrustTier.verifiedResponder
              ? const Color(0xFF66BB6A)
              : const Color(0xFFFFB300);
          canvas.drawRect(
            Rect.fromCenter(center: pos, width: 14, height: 14),
            Paint()..color = color,
          );
        case MessageType.ack:
          break;
      }
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.blips != blips ||
      oldDelegate.maxRadiusMeters != maxRadiusMeters;
}

String _formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String _cardinal(double deg) {
  const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return dirs[((deg + 22.5) ~/ 45) % 8];
}
