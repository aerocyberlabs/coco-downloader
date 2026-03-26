/// SquareProgressBar — custom painter port of the Python SquareProgressBar.
///
/// Draws 24 small rectangles (squares) in a row:
///   - Filled squares use the theme's primary colour (green in light mode).
///   - Unfilled squares use [ColorScheme.surfaceContainerHighest].
///   - All squares are outlined with [ColorScheme.outlineVariant].
///
/// Usage:
/// ```dart
/// SquareProgressBar(value: 42)  // 42 % filled
/// ```
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// SquareProgressBar widget
// ---------------------------------------------------------------------------

class SquareProgressBar extends StatelessWidget {
  const SquareProgressBar({
    super.key,
    required this.value,
    this.squareCount = 24,
    this.height = 22.0,
  });

  /// Progress value, clamped to [0, 100].
  final int value;

  /// Number of squares to draw.
  final int squareCount;

  /// Height of the widget in logical pixels.
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SquarePainter(
          value: value.clamp(0, 100),
          squareCount: math.max(5, squareCount),
          filledColor: cs.primary,
          unfilledColor: cs.surfaceContainerHighest,
          borderColor: cs.outlineVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SquarePainter
// ---------------------------------------------------------------------------

class _SquarePainter extends CustomPainter {
  const _SquarePainter({
    required this.value,
    required this.squareCount,
    required this.filledColor,
    required this.unfilledColor,
    required this.borderColor,
  });

  final int value;
  final int squareCount;
  final Color filledColor;
  final Color unfilledColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final boxWidth =
        (size.width - gap * (squareCount - 1)) / squareCount;
    final boxHeight = size.height;

    final filled = (value / 100 * squareCount).round();

    final filledPaint = Paint()..color = filledColor;
    final unfilledPaint = Paint()..color = unfilledColor;
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    double x = 0;
    for (int i = 0; i < squareCount; i++) {
      final rect = Rect.fromLTWH(x, 0, boxWidth, boxHeight);
      canvas.drawRect(rect, i < filled ? filledPaint : unfilledPaint);
      canvas.drawRect(rect, borderPaint);
      x += boxWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_SquarePainter old) {
    return old.value != value ||
        old.squareCount != squareCount ||
        old.filledColor != filledColor ||
        old.unfilledColor != unfilledColor ||
        old.borderColor != borderColor;
  }
}
