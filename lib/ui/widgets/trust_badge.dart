import 'package:flutter/material.dart';
import 'package:mesh_rescue/app/theme.dart';
import 'package:mesh_rescue/engine/models/enums.dart';

/// Displays the message's cryptographic trust tier using both icon and text.
/// Never uses the words "safe" or "verified" outside [TrustTier.verifiedResponder].
class TrustBadge extends StatelessWidget {
  final TrustTier tier;
  final String? responderName;

  const TrustBadge({
    super.key,
    required this.tier,
    this.responderName,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label, Color fg, Color bg) = switch (tier) {
      TrustTier.verifiedResponder => (
          Icons.verified_user,
          responderName == null ? 'Verified Responder' : 'Verified • $responderName',
          MeshColors.verifiedGreen,
          const Color(0xFFE8F5E9),
        ),
      TrustTier.signedPeer => (
          Icons.badge_outlined,
          'Signed Peer',
          MeshColors.inkSecondary,
          const Color(0xFFECEFF1),
        ),
      TrustTier.unverified => (
          Icons.warning_amber_rounded,
          'Unverified',
          MeshColors.hazardAmber,
          const Color(0xFFFFF3E0),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats local relative age and hop count per UI contract.
String formatAge(int receivedAtSec, int nowSec) {
  final delta = (nowSec - receivedAtSec).clamp(0, 9999999);
  if (delta < 60) return '${delta}s ago';
  if (delta < 3600) return '${delta ~/ 60}m ago';
  return '${delta ~/ 3600}h ago';
}

String formatHopsLabel(int hops) {
  if (hops <= 0) return 'Origin (this phone)';
  if (hops == 1) return 'Direct (1 hop)';
  final relays = hops - 1;
  return 'Relayed through $relays ${relays == 1 ? "phone" : "phones"} ($hops hops)';
}

