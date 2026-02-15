import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math';

/// Combined heatmap showing both feet as a single pressure mat
/// with a unified Center of Pressure (CoP) trace.
class CombinedHeatmap extends StatelessWidget {
  final List<List<double>> leftPressureData;  // 5x5 grid
  final List<List<double>> rightPressureData; // 5x5 grid
  /// CoP trace: normalized positions (0.0-1.0) across the combined mat
  final List<Offset>? copTrace;
  /// Current index in the trace
  final int? currentTraceIndex;
  final VoidCallback? onTap;

  const CombinedHeatmap({
    super.key,
    required this.leftPressureData,
    required this.rightPressureData,
    this.copTrace,
    this.currentTraceIndex,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
            width: 1.5,
          ),
          color: Colors.grey[900],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.cyan.withOpacity(0.2),
                    Colors.transparent,
                    Colors.pink.withOpacity(0.2),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'LEFT',
                    style: TextStyle(
                      color: Colors.cyanAccent.withOpacity(0.8),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Text(
                    'PRESSURE MAP',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'RIGHT',
                    style: TextStyle(
                      color: Colors.pinkAccent.withOpacity(0.8),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            // Combined heatmap canvas
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: CustomPaint(
                  painter: _CombinedHeatmapPainter(
                    leftData: leftPressureData,
                    rightData: rightPressureData,
                    copTrace: copTrace,
                    currentTraceIndex: currentTraceIndex,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CombinedHeatmapPainter extends CustomPainter {
  final List<List<double>> leftData;
  final List<List<double>> rightData;
  final List<Offset>? copTrace;
  final int? currentTraceIndex;

  _CombinedHeatmapPainter({
    required this.leftData,
    required this.rightData,
    this.copTrace,
    this.currentTraceIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (leftData.isEmpty && rightData.isEmpty) return;

    final halfW = size.width / 2;
    final gap = 4.0; // gap between left and right

    // Draw left foot heatmap
    _drawHeatmap(canvas, Rect.fromLTWH(0, 0, halfW - gap / 2, size.height), leftData);
    // Draw right foot heatmap
    _drawHeatmap(canvas, Rect.fromLTWH(halfW + gap / 2, 0, halfW - gap / 2, size.height), rightData);

    // Draw center divider line
    final dividerPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(halfW, 0),
      Offset(halfW, size.height),
      dividerPaint,
    );

    // Draw CoP trace
    _drawCoPTrace(canvas, size);
  }

  void _drawHeatmap(Canvas canvas, Rect area, List<List<double>> data) {
    if (data.isEmpty) return;

    final rows = data.length;
    final cols = data[0].length;

    final int renderCols = (area.width / 4).round().clamp(10, 40);
    final int renderRows = (area.height / 4).round().clamp(15, 60);

    final cellW = area.width / renderCols;
    final cellH = area.height / renderRows;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int ry = 0; ry < renderRows; ry++) {
      for (int rx = 0; rx < renderCols; rx++) {
        final dataX = (rx / (renderCols - 1)) * (cols - 1);
        final dataY = ((renderRows - 1 - ry) / (renderRows - 1)) * (rows - 1);
        final pressure = _bilinearInterpolate(data, dataY, dataX, rows, cols);
        paint.color = _getHeatColor(pressure);
        canvas.drawRect(
          Rect.fromLTWH(area.left + rx * cellW, area.top + ry * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }
  }

  void _drawCoPTrace(Canvas canvas, Size size) {
    if (copTrace == null || copTrace!.isEmpty) return;
    final idx = currentTraceIndex ?? copTrace!.length - 1;
    final endIdx = idx.clamp(0, copTrace!.length - 1);

    Offset toCanvas(Offset o) =>
        Offset(o.dx.clamp(0.0, 1.0) * size.width, o.dy.clamp(0.0, 1.0) * size.height);

    // Draw trace path if there are 2+ points
    if (endIdx >= 1) {
      final tracePaint = Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      path.moveTo(toCanvas(copTrace![0]).dx, toCanvas(copTrace![0]).dy);
      for (int i = 1; i <= endIdx; i++) {
        final pt = toCanvas(copTrace![i]);
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, tracePaint);
    }

    // Current CoP position — dot with glow (always draw)
    final currentPt = toCanvas(copTrace![endIdx]);

    // Glow effect
    canvas.drawCircle(
      currentPt,
      12,
      Paint()
        ..color = Colors.white.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Solid dot
    canvas.drawCircle(
      currentPt,
      5,
      Paint()..color = Colors.white,
    );
    // Outer ring
    canvas.drawCircle(
      currentPt,
      7,
      Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Draw "L/R" indicator based on CoP X position
    final copX = copTrace![endIdx].dx;
    final bias = copX < 0.5 ? 'L' : copX > 0.5 ? 'R' : '=';
    final biasPercent = ((copX - 0.5).abs() * 200).round();
    if (biasPercent > 2) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$bias $biasPercent%',
          style: TextStyle(
            color: copX < 0.5 ? Colors.cyanAccent : Colors.pinkAccent,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 4),
              Shadow(color: Colors.black, blurRadius: 8),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(currentPt.dx - textPainter.width / 2, currentPt.dy - 20),
      );
    }
  }

  double _bilinearInterpolate(List<List<double>> data, double row, double col, int rows, int cols) {
    final r0 = row.floor().clamp(0, rows - 1);
    final r1 = (r0 + 1).clamp(0, rows - 1);
    final c0 = col.floor().clamp(0, cols - 1);
    final c1 = (c0 + 1).clamp(0, cols - 1);

    final rFrac = row - r0;
    final cFrac = col - c0;

    final v00 = data[r0][c0];
    final v01 = data[r0][c1];
    final v10 = data[r1][c0];
    final v11 = data[r1][c1];

    final top = v00 + (v01 - v00) * cFrac;
    final bottom = v10 + (v11 - v10) * cFrac;

    return top + (bottom - top) * rFrac;
  }

  Color _getHeatColor(double pressure) {
    final t = (pressure / 100.0).clamp(0.0, 1.0);

    if (t < 0.01) return const Color(0xFF1a1a2e);
    if (t < 0.15) {
      final p = (t - 0.01) / 0.14;
      return Color.lerp(const Color(0xFF1a1a2e), const Color(0xFF0d47a1), p)!;
    }
    if (t < 0.30) {
      final p = (t - 0.15) / 0.15;
      return Color.lerp(const Color(0xFF0d47a1), const Color(0xFF00bcd4), p)!;
    }
    if (t < 0.50) {
      final p = (t - 0.30) / 0.20;
      return Color.lerp(const Color(0xFF00bcd4), const Color(0xFF4caf50), p)!;
    }
    if (t < 0.70) {
      final p = (t - 0.50) / 0.20;
      return Color.lerp(const Color(0xFF4caf50), const Color(0xFFffeb3b), p)!;
    }
    if (t < 0.85) {
      final p = (t - 0.70) / 0.15;
      return Color.lerp(const Color(0xFFffeb3b), const Color(0xFFff9800), p)!;
    }
    final p = (t - 0.85) / 0.15;
    return Color.lerp(const Color(0xFFff9800), const Color(0xFFf44336), p)!;
  }

  @override
  bool shouldRepaint(covariant _CombinedHeatmapPainter old) {
    return old.leftData != leftData ||
        old.rightData != rightData ||
        old.currentTraceIndex != currentTraceIndex ||
        old.copTrace != copTrace;
  }
}
