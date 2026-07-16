import 'package:flutter/material.dart';

/// Shimmer simple: un placeholder animado para estados de loading.
class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  Shimmer({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _ctrl.value, 0),
              end: Alignment(1 + 2 * _ctrl.value, 0),
              colors: [
                scheme.surfaceContainerHigh,
                scheme.surfaceContainerLow,
                scheme.surfaceContainerHigh,
              ],
            ),
          ),
        );
      },
    );
  }
}

class ShimmerMemberTile extends StatelessWidget {
  const ShimmerMemberTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Shimmer(
              width: 44,
              height: 44,
              borderRadius: BorderRadius.circular(22),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Shimmer(width: 160, height: 14),
                  SizedBox(height: 6),
                  Shimmer(width: 80, height: 12),
                ],
              ),
            ),
            SizedBox(width: 8),
            Shimmer(
              width: 44,
              height: 44,
              borderRadius: BorderRadius.circular(22),
            ),
          ],
        ),
      ),
    );
  }
}
