import 'package:flutter/material.dart';

/// Simple 5x5 Grid Heatmap for pressure sensor display
/// This matches the sensor layout from the Processing visualization code
class SimpleGridHeatmap extends StatelessWidget {
  final List<List<double>> pressureData; // 5x5 grid, values 0-100 (normalized)
  final bool isLeftFoot;
  final VoidCallback? onTap;

  const SimpleGridHeatmap({
    super.key,
    required this.pressureData,
    this.isLeftFoot = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[700]!, width: 1),
          color: Colors.grey[900],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isLeftFoot ? Colors.cyan.withOpacity(0.2) : Colors.pink.withOpacity(0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(11),
                  topRight: Radius.circular(11),
                ),
              ),
              child: Center(
                child: Text(
                  isLeftFoot ? 'LEFT (0-24)' : 'RIGHT (32-56)',
                  style: TextStyle(
                    color: isLeftFoot ? Colors.cyanAccent : Colors.pinkAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            // Grid - drawn from bottom to top to match Processing code layout
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: _buildGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    // Get the number of rows and cols from data, default to 5x5
    final rows = pressureData.length;
    final cols = rows > 0 ? pressureData[0].length : 5;
    
    return Column(
      children: List.generate(rows, (row) {
        // Reverse row order so row 0 (sensors 0-4) is at the bottom
        final displayRow = rows - 1 - row;
        return Expanded(
          child: Row(
            children: List.generate(cols, (col) {
              final pressure = displayRow < pressureData.length && col < pressureData[displayRow].length
                  ? pressureData[displayRow][col]
                  : 0.0;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: _getHeatmapColor(pressure),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Center(
                    child: Text(
                      pressure.toInt().toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Color _getHeatmapColor(double pressure) {
    // Similar to Processing HSB heatmap:
    // Low values = dark/grey, high values = red through yellow to blue
    if (pressure < 1) {
      return Colors.grey[800]!;
    }
    
    // Map 0-100 to hue 240 (blue) to 0 (red)
    final hue = (1 - (pressure / 100.0).clamp(0.0, 1.0)) * 240;
    return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
  }
}
