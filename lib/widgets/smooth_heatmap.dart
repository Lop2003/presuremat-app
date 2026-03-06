import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math';

/// Smooth gradient-based heatmap for pressure sensor display.
/// Uses bilinear interpolation to create smooth gradients between 5x5 sensor cells.
class SmoothHeatmap extends StatelessWidget {
  final List<List<double>> pressureData; // 5x5 grid, values 0-100 (normalized)
  final bool isLeftFoot;
  final VoidCallback? onTap;
  /// CoP trace: list of normalized positions (0.0-1.0 for both x and y)
  final List<Offset>? copTrace;
  /// Current index in the trace (for highlighting current position)
  final int? currentTraceIndex;

  const SmoothHeatmap({
    super.key,
    required this.pressureData,
    this.isLeftFoot = true,
    this.onTap,
    this.copTrace,
    this.currentTraceIndex,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isLeftFoot
                ? Colors.cyanAccent.withOpacity(0.3)
                : Colors.pinkAccent.withOpacity(0.3),
            width: 1.5,
          ),
          color: Colors.grey[900],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLeftFoot
                      ? [Colors.cyan.withOpacity(0.3), Colors.cyan.withOpacity(0.1)]
                      : [Colors.pink.withOpacity(0.3), Colors.pink.withOpacity(0.1)],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Center(
                child: Text(
                  isLeftFoot ? 'LEFT FOOT' : 'RIGHT FOOT',
                  style: TextStyle(
                    color: isLeftFoot ? Colors.cyanAccent : Colors.pinkAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            // Smooth heatmap
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: CustomPaint(
                  painter: _SmoothHeatmapPainter(
                    pressureData: pressureData,
                    isLeftFoot: isLeftFoot,
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

class _SmoothHeatmapPainter extends CustomPainter {
  final List<List<double>> pressureData;
  final bool isLeftFoot;
  final List<Offset>? copTrace;
  final int? currentTraceIndex;

  _SmoothHeatmapPainter({
    required this.pressureData,
    required this.isLeftFoot,
    this.copTrace,
    this.currentTraceIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pressureData.isEmpty) return;

    final rows = pressureData.length;
    final cols = rows > 0 ? pressureData[0].length : 5;

    // Render resolution (higher = smoother but slower)
    final int renderCols = (size.width / 4).round().clamp(20, 60);
    final int renderRows = (size.height / 4).round().clamp(30, 80);

    final cellW = size.width / renderCols;
    final cellH = size.height / renderRows;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int ry = 0; ry < renderRows; ry++) {
      for (int rx = 0; rx < renderCols; rx++) {
        final dataX = (rx / (renderCols - 1)) * (cols - 1);
        final dataY = (ry / (renderRows - 1)) * (rows - 1);
        final pressure = _bilinearInterpolate(dataY, dataX, rows, cols);
        paint.color = _getHeatColor(pressure);
        canvas.drawRect(
          Rect.fromLTWH(rx * cellW, ry * cellH, cellW + 0.5, cellH + 0.5),
          paint,
        );
      }
    }

    // Draw CoP trace
    _drawCoPTrace(canvas, size);
  }

  void _drawCoPTrace(Canvas canvas, Size size) {
    if (copTrace == null || copTrace!.isEmpty) return;
    final idx = currentTraceIndex ?? copTrace!.length - 1;
    final endIdx = idx.clamp(0, copTrace!.length - 1);
    if (endIdx < 1) return;

    // Convert normalized coords (0-1) to canvas pixels
    // copTrace Offset: dx = column (left-right), dy = row (top=toe, bottom=heel)
    Offset toCanvas(Offset o) =>
        Offset(o.dx.clamp(0.0, 1.0) * size.width, o.dy.clamp(0.0, 1.0) * size.height);

    // Draw full trace path up to current index (grey line)
    final tracePaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..strokeWidth = 2.0
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

    // Draw current CoP position (white dot with glow)
    final currentPt = toCanvas(copTrace![endIdx]);
    // Glow
    canvas.drawCircle(
      currentPt,
      8,
      Paint()
        ..color = Colors.white.withOpacity(0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Solid dot
    canvas.drawCircle(
      currentPt,
      4,
      Paint()..color = Colors.white,
    );
    // Border
    canvas.drawCircle(
      currentPt,
      4,
      Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  double _bilinearInterpolate(double row, double col, int rows, int cols) {
    final r0 = row.floor().clamp(0, rows - 1);
    final r1 = (r0 + 1).clamp(0, rows - 1);
    final c0 = col.floor().clamp(0, cols - 1);
    final c1 = (c0 + 1).clamp(0, cols - 1);

    final rFrac = row - r0;
    final cFrac = col - c0;

    final v00 = pressureData[r0][c0];
    final v01 = pressureData[r0][c1];
    final v10 = pressureData[r1][c0];
    final v11 = pressureData[r1][c1];

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
  bool shouldRepaint(covariant _SmoothHeatmapPainter old) {
    return old.pressureData != pressureData ||
        old.currentTraceIndex != currentTraceIndex ||
        old.copTrace != copTrace;
  }
}
