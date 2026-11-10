import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mesh_rescue/app/theme.dart';

/// Emergency SOS button requiring a 2-second continuous hold to prevent
/// accidental triggers while remaining large and high-contrast under stress.
class HoldSosButton extends StatefulWidget {
  final VoidCallback onTriggered;
  final bool enabled;

  const HoldSosButton({
    super.key,
    required this.onTriggered,
    this.enabled = true,
  });

  @override
  State<HoldSosButton> createState() => _HoldSosButtonState();
}

class _HoldSosButtonState extends State<HoldSosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_fired) {
          _fired = true;
          HapticFeedback.heavyImpact();
          widget.onTriggered();
          Future<void>.delayed(const Duration(milliseconds: 250), () {
            if (mounted) {
              _controller.reset();
              _fired = false;
            }
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startHold() {
    if (!widget.enabled || _fired) return;
    HapticFeedback.selectionClick();
    _controller.forward(from: 0);
  }

  void _cancelHold() {
    if (_controller.isAnimating && !_fired) {
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value;
          final remaining = ((1.0 - progress) * 2.0).clamp(0.0, 2.0);

          return Semantics(
            button: true,
            label: 'Hold for 2 seconds to broadcast SOS',
            child: Container(
              height: 156,
              decoration: BoxDecoration(
                color: widget.enabled ? MeshColors.sosRed : Colors.grey.shade500,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 112,
                    height: 112,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sos, color: Colors.white, size: 44),
                      const SizedBox(height: 6),
                      Text(
                        progress > 0
                            ? 'HOLD ${remaining.toStringAsFixed(1)}s'
                            : 'HOLD 2s FOR SOS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

