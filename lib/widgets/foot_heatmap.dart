import 'package:flutter/material.dart';
import 'dart:math';

class FootHeatmap extends StatefulWidget {
  final List<List<double>> pressureData;
  final bool isLeftFoot;
  final VoidCallback? onTap;

  const FootHeatmap({
    super.key,
    required this.pressureData,
    this.isLeftFoot = true,
    this.onTap,
  });

  @override
  State<FootHeatmap> createState() => _FootHeatmapState();
}

class _FootHeatmapState extends State<FootHeatmap> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 120,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CustomPaint(
            painter: FootHeatmapPainter(
              pressureData: widget.pressureData,
              isLeftFoot: widget.isLeftFoot,
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.1),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.isLeftFoot ? Icons.directions_walk : Icons.directions_walk,
                      color: Colors.white.withOpacity(0.7),
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.isLeftFoot ? 'LEFT' : 'RIGHT',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FootHeatmapPainter extends CustomPainter {
  final List<List<double>> pressureData;
  final bool isLeftFoot;

  FootHeatmapPainter({
    required this.pressureData,
    required this.isLeftFoot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final path = Path();

    // สร้างรูปเท้า
    _createFootShape(path, size);
    
    // วาดพื้นหลัง
    paint.color = Colors.grey[200]!;
    canvas.drawPath(path, paint);

    // วาด heatmap
    _drawHeatmap(canvas, size);
  }

  void _createFootShape(Path path, Size size) {
    final width = size.width;
    final height = size.height;
    
    // สร้างรูปเท้าแบบง่าย
    path.moveTo(width * 0.2, height * 0.1); // เริ่มจากนิ้วเท้า
    path.quadraticBezierTo(width * 0.1, height * 0.2, width * 0.15, height * 0.4); // ด้านซ้าย
    path.quadraticBezierTo(width * 0.1, height * 0.6, width * 0.2, height * 0.8); // ด้านซ้าย
    path.quadraticBezierTo(width * 0.3, height * 0.9, width * 0.5, height * 0.95); // ส้นเท้า
    path.quadraticBezierTo(width * 0.7, height * 0.9, width * 0.8, height * 0.8); // ด้านขวา
    path.quadraticBezierTo(width * 0.9, height * 0.6, width * 0.85, height * 0.4); // ด้านขวา
    path.quadraticBezierTo(width * 0.9, height * 0.2, width * 0.8, height * 0.1); // ด้านขวา
    path.quadraticBezierTo(width * 0.6, height * 0.05, width * 0.4, height * 0.05); // กลับไปจุดเริ่มต้น
    path.close();
  }

  void _drawHeatmap(Canvas canvas, Size size) {
    if (pressureData.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final rows = pressureData.length;
    final cols = pressureData[0].length;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final pressure = pressureData[row][col];
        if (pressure > 0) {
          final x = (col / (cols - 1)) * width;
          final y = (row / (rows - 1)) * height;
          final cellWidth = width / cols;
          final cellHeight = height / rows;

          final paint = Paint()
            ..color = _getHeatmapColor(pressure)
            ..style = PaintingStyle.fill;

          canvas.drawRect(
            Rect.fromLTWH(x, y, cellWidth, cellHeight),
            paint,
          );
        }
      }
    }
  }

  Color _getHeatmapColor(double pressure) {
    // แปลงค่า pressure (0-100) เป็นสี heatmap
    final normalizedPressure = pressure / 100.0;
    
    if (normalizedPressure < 0.1) {
      return Colors.blue.withOpacity(0.3);
    } else if (normalizedPressure < 0.3) {
      return Colors.green.withOpacity(0.5);
    } else if (normalizedPressure < 0.5) {
      return Colors.yellow.withOpacity(0.7);
    } else if (normalizedPressure < 0.7) {
      return Colors.orange.withOpacity(0.8);
    } else {
      return Colors.red.withOpacity(0.9);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class HeatmapDataGenerator {
  static List<List<double>> generateRandomFootPressure({
    required bool isLeftFoot,
    int rows = 10,
    int cols = 6,
  }) {
    final random = Random();
    final data = List.generate(rows, (i) => List.generate(cols, (j) => 0.0));

    // สร้างจุดที่มีแรงกดสูง (เช่น ส้นเท้า, นิ้วเท้า)
    final heelRow = (rows * 0.8).round();
    final toeRow = (rows * 0.2).round();
    final centerCol = (cols * 0.5).round();

    // ส้นเท้า
    for (int i = heelRow; i < rows; i++) {
      for (int j = centerCol - 1; j <= centerCol + 1; j++) {
        if (j >= 0 && j < cols) {
          data[i][j] = 60 + random.nextDouble() * 30;
        }
      }
    }

    // นิ้วเท้า
    for (int i = 0; i < toeRow; i++) {
      for (int j = 0; j < cols; j++) {
        data[i][j] = 40 + random.nextDouble() * 40;
      }
    }

    // กลางเท้า (arch)
    for (int i = toeRow; i < heelRow; i++) {
      for (int j = 0; j < cols; j++) {
        if (j < centerCol - 1 || j > centerCol + 1) {
          data[i][j] = 20 + random.nextDouble() * 20;
        }
      }
    }

    return data;
  }

  static List<List<double>> generateSwingPhasePressure({
    required String phase,
    required bool isLeftFoot,
    int rows = 10,
    int cols = 6,
  }) {
    final random = Random();
    final data = List.generate(rows, (i) => List.generate(cols, (j) => 0.0));

    switch (phase) {
      case 'Address':
        // น้ำหนักเท่ากันทั้งสองข้าง
        for (int i = 0; i < rows; i++) {
          for (int j = 0; j < cols; j++) {
            data[i][j] = 50 + random.nextDouble() * 20;
          }
        }
        break;
      
      case 'Backswing':
        if (isLeftFoot) {
          // เท้าซ้ายรับน้ำหนักมากขึ้น
          for (int i = 0; i < rows; i++) {
            for (int j = 0; j < cols; j++) {
              data[i][j] = 70 + random.nextDouble() * 25;
            }
          }
        } else {
          // เท้าขวาน้ำหนักลดลง
          for (int i = 0; i < rows; i++) {
            for (int j = 0; j < cols; j++) {
              data[i][j] = 20 + random.nextDouble() * 15;
            }
          }
        }
        break;
      
      case 'Downswing':
        if (isLeftFoot) {
          // เท้าซ้ายน้ำหนักลดลง
          for (int i = 0; i < rows; i++) {
            for (int j = 0; j < cols; j++) {
              data[i][j] = 20 + random.nextDouble() * 15;
            }
          }
        } else {
          // เท้าขวารับน้ำหนักมากขึ้น
          for (int i = 0; i < rows; i++) {
            for (int j = 0; j < cols; j++) {
              data[i][j] = 70 + random.nextDouble() * 25;
            }
          }
        }
        break;
      
      case 'Follow Through':
        if (isLeftFoot) {
          // เท้าซ้ายน้ำหนักน้อย
          for (int i = 0; i < rows; i++) {
            for (int j = 0; j < cols; j++) {
              data[i][j] = 10 + random.nextDouble() * 10;
            }
          }
        } else {
          // เท้าขวารับน้ำหนักเต็มที่
          for (int i = 0; i < rows; i++) {
            for (int j = 0; j < cols; j++) {
              data[i][j] = 80 + random.nextDouble() * 20;
            }
          }
        }
        break;
      
      default:
        // Default: น้ำหนักเท่ากัน
        for (int i = 0; i < rows; i++) {
          for (int j = 0; j < cols; j++) {
            data[i][j] = 50 + random.nextDouble() * 20;
          }
        }
    }

    return data;
  }
}
