// --- COPY & PASTE ไฟล์นี้ทับของเดิมได้เลย ---
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:golf_force_plate/widgets/foot_heatmap.dart';

class PresentationDashboard extends StatefulWidget {
  const PresentationDashboard({super.key});

  @override
  State<PresentationDashboard> createState() => _PresentationDashboardState();
}

class _PresentationDashboardState extends State<PresentationDashboard> {
  Timer? _simulationTimer;
  double _leftWeightPercent = 50.0;
  double _rightWeightPercent = 50.0;
  bool _isSwinging = false;
  String _swingPhase = "Ready";

  List<FlSpot> _leftDataPoints = [];
  List<FlSpot> _rightDataPoints = [];
  double _graphXValue = 0;
  final Random _random = Random();

  // Heatmap data
  List<List<double>> _leftFootPressure = [];
  List<List<double>> _rightFootPressure = [];
  bool _showHeatmap = true;

  @override
  void initState() {
    super.initState();
    _initializeGraphWithBaseline();
    _initializeHeatmapData();
  }

  void _initializeHeatmapData() {
    _leftFootPressure = HeatmapDataGenerator.generateRandomFootPressure(
      isLeftFoot: true,
    );
    _rightFootPressure = HeatmapDataGenerator.generateRandomFootPressure(
      isLeftFoot: false,
    );
  }

  void _initializeGraphWithBaseline() {
    _leftDataPoints.clear();
    _rightDataPoints.clear();
    _graphXValue = 0;

    // สร้างจุดเริ่มต้นมากขึ้นเพื่อให้เห็นเส้นฐานชัดเจน
    for (int i = 0; i < 20; i++) {
      double x = i * 0.1;
      _leftDataPoints.add(FlSpot(x, 50.0));
      _rightDataPoints.add(FlSpot(x, 50.0));
      _graphXValue = x;
    }

    setState(() {});
  }

  Future<void> _saveSwingSession(
    List<FlSpot> leftData,
    List<FlSpot> rightData,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final List<Map<String, double>> dataPoints = [];
    for (int i = 0; i < leftData.length; i++) {
      dataPoints.add({
        't': leftData[i].x,
        'l': leftData[i].y,
        'r': rightData[i].y,
      });
    }

    // เตรียมข้อมูล heatmap แบบที่ Firestore รองรับ
    final Map<String, dynamic> heatmapData = {
      'leftFoot': _convert2DArrayToMap(_leftFootPressure),
      'rightFoot': _convert2DArrayToMap(_rightFootPressure),
      'swingPhase': _swingPhase,
    };

    try {
      await FirebaseFirestore.instance.collection('swings').add({
        'userId': user.uid,
        'timestamp': Timestamp.now(),
        'dataPoints': dataPoints,
        'heatmapData': heatmapData,
        'swingPhase': _swingPhase,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Swing session with heatmap saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save session: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _simulateSwing() {
    if (_isSwinging) return;

    // --- จุดแก้ไขสำคัญ ---
    setState(() {
      _leftDataPoints = [];
      _rightDataPoints = [];
      _graphXValue = 0;
      _isSwinging = true;
      _swingPhase = "Backswing";
    });
    // --------------------

    final List<FlSpot> currentSwingL = [];
    final List<FlSpot> currentSwingR = [];
    double swingTime = 0.0;

    final backswingPeak = 30 + _random.nextDouble() * 10;
    final transitionPeak = 70 + _random.nextDouble() * 10;
    final finishPeak = 85 + _random.nextDouble() * 10;

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 40), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      swingTime += 0.04;
      double left;

      if (swingTime < 1.5) {
        if (mounted) setState(() => _swingPhase = "Backswing");
        left = 50 - backswingPeak * (swingTime / 1.5);
      } else if (swingTime < 2.0) {
        if (mounted) setState(() => _swingPhase = "Transition");
        left =
            (50 - backswingPeak) + transitionPeak * ((swingTime - 1.5) / 0.5);
      } else if (swingTime < 3.5) {
        if (mounted) setState(() => _swingPhase = "Finish");
        left =
            (50 - backswingPeak + transitionPeak) +
            (finishPeak - (50 - backswingPeak + transitionPeak)) *
                ((swingTime - 2.0) / 1.5);
      } else {
        _isSwinging = false;
        if (mounted) setState(() => _swingPhase = "Saving...");
        timer.cancel();

        _saveSwingSession(currentSwingL, currentSwingR);
        _returnToBaseline();
        return;
      }

      left = left.clamp(5, 95);
      final right = 100 - left;

      _updateData(left, right);
      currentSwingL.add(FlSpot(swingTime, left));
      currentSwingR.add(FlSpot(swingTime, right));
    });
  }

  void _returnToBaseline() {
    Timer.periodic(const Duration(milliseconds: 50), (backTimer) {
      if (!mounted || (_leftWeightPercent - 50.0).abs() < 1.0) {
        if (mounted) {
          setState(() => _swingPhase = "Ready");
          _initializeGraphWithBaseline(); // รีเซ็ตกราฟกลับเป็นเส้นฐาน
        }
        backTimer.cancel();
      } else {
        final newLeft = _leftWeightPercent - (_leftWeightPercent - 50.0) * 0.1;
        _updateData(newLeft, 100 - newLeft);
      }
    });
  }

  void _updateData(double left, double right) {
    if (!mounted) return;

    setState(() {
      _leftWeightPercent = left;
      _rightWeightPercent = right;

      _graphXValue += 0.04;

      // เก็บข้อมูลเฉพาะ 50 จุดล่าสุด
      if (_leftDataPoints.length > 50) {
        _leftDataPoints.removeAt(0);
        _rightDataPoints.removeAt(0);
      }

      _leftDataPoints.add(FlSpot(_graphXValue, left));
      _rightDataPoints.add(FlSpot(_graphXValue, right));

      // อัปเดต heatmap ตาม swing phase
      _leftFootPressure = HeatmapDataGenerator.generateSwingPhasePressure(
        phase: _swingPhase,
        isLeftFoot: true,
      );
      _rightFootPressure = HeatmapDataGenerator.generateSwingPhasePressure(
        phase: _swingPhase,
        isLeftFoot: false,
      );
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _leftDataPoints.clear();
    _rightDataPoints.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              _buildAppBar(context),
              const SizedBox(height: 20),
              _buildWeightCards(),
              const SizedBox(height: 20),
              if (_showHeatmap) ...[
                _buildHeatmapSection(),
                const SizedBox(height: 20),
              ],
              _buildChartCard(),
              const SizedBox(height: 20),
              _buildRecordButton(),
              const SizedBox(height: 20), // เพิ่มระยะห่างด้านล่าง
            ],
          ),
        ),
      ),
    );
  }

  // โค้ด UI Widgets ที่เหลือเหมือนเดิมทั้งหมด
  Widget _buildAppBar(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          const Color(0xFF1E293B).withOpacity(0.8),
          const Color(0xFF0F172A).withOpacity(0.6),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.sports_golf, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Force Plate',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              _buildStatusBadge(),
            ],
          ),
        ),
        _buildActionButtons(context),
      ],
    ),
  );

  Widget _buildStatusBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: _swingPhase == 'Ready'
          ? Colors.green.withOpacity(0.2)
          : Colors.orange.withOpacity(0.2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(
          Icons.circle,
          color: _swingPhase == 'Ready' ? Colors.green : Colors.orange,
          size: 10,
        ),
        const SizedBox(width: 8),
        Text(
          _swingPhase,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );

  Widget _buildActionButtons(BuildContext context) => Row(
    children: [
      IconButton(
        icon: Icon(
          _showHeatmap ? Icons.visibility : Icons.visibility_off,
          color: Colors.white70,
        ),
        tooltip: _showHeatmap ? 'Hide Heatmap' : 'Show Heatmap',
        onPressed: () => setState(() => _showHeatmap = !_showHeatmap),
      ),
      IconButton(
        icon: const Icon(Icons.logout, color: Colors.white70),
        tooltip: 'Logout',
        onPressed: () => FirebaseAuth.instance.signOut(),
      ),
    ],
  );

  Widget _buildWeightCards() => Row(
    children: [
      Expanded(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) => Transform.scale(
            scale: value,
            child: _WeightCard(
              label: "Left",
              percentage: _leftWeightPercent,
              color: const Color(0xFF3B82F6),
            ),
          ),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Transform.scale(
            scale: value,
            child: _WeightCard(
              label: "Right",
              percentage: _rightWeightPercent,
              color: const Color(0xFFEC4899),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildChartCard() => Container(
    height: 300, // กำหนดความสูงคงที่
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      color: const Color(0xFF1F2937),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF1F2937),
          const Color(0xFF1F2937).withOpacity(0.8),
        ],
      ),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.show_chart, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Balance Analysis',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _LegendItem(label: 'Left', color: const Color(0xFF3B82F6)),
            const SizedBox(width: 12),
            _LegendItem(label: 'Right', color: const Color(0xFFEC4899)),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: LineChart(
            _buildChartData(),
            duration: const Duration(milliseconds: 0),
          ),
        ),
      ],
    ),
  );

  Widget _buildHeatmapSection() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: const Color(0xFF1F2937),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.thermostat, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Foot Pressure Heatmap',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              _swingPhase,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Column(
                children: [
                  FootHeatmap(
                    pressureData: _leftFootPressure,
                    isLeftFoot: true,
                    onTap: () => _updateHeatmapData(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Left Foot',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  FootHeatmap(
                    pressureData: _rightFootPressure,
                    isLeftFoot: false,
                    onTap: () => _updateHeatmapData(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Right Foot',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildHeatmapLegendItem('Low', Colors.blue),
              _buildHeatmapLegendItem('Medium', Colors.yellow),
              _buildHeatmapLegendItem('High', Colors.orange),
              _buildHeatmapLegendItem('Very High', Colors.red),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildHeatmapLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  void _updateHeatmapData() {
    setState(() {
      _leftFootPressure = HeatmapDataGenerator.generateSwingPhasePressure(
        phase: _swingPhase,
        isLeftFoot: true,
      );
      _rightFootPressure = HeatmapDataGenerator.generateSwingPhasePressure(
        phase: _swingPhase,
        isLeftFoot: false,
      );
    });
  }

  // แปลง 2D array เป็น Map เพื่อให้ Firestore รองรับ
  Map<String, dynamic> _convert2DArrayToMap(List<List<double>> array2D) {
    final Map<String, dynamic> result = {};
    for (int i = 0; i < array2D.length; i++) {
      final Map<String, dynamic> row = {};
      for (int j = 0; j < array2D[i].length; j++) {
        row['col$j'] = array2D[i][j];
      }
      result['row$i'] = row;
    }
    return result;
  }

  // แปลง Map กลับเป็น 2D array (สำหรับการอ่านข้อมูล)
  List<List<double>> _convertMapTo2DArray(Map<String, dynamic> map) {
    final List<List<double>> result = [];
    final rowKeys = map.keys.toList()..sort();
    
    for (final rowKey in rowKeys) {
      final rowMap = map[rowKey] as Map<String, dynamic>;
      final List<double> row = [];
      final colKeys = rowMap.keys.toList()..sort();
      
      for (final colKey in colKeys) {
        row.add((rowMap[colKey] as num).toDouble());
      }
      result.add(row);
    }
    return result;
  }

  Widget _buildRecordButton() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: Colors.blue.withOpacity(0.2),
          blurRadius: 10,
          spreadRadius: 2,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _isSwinging ? null : _simulateSwing,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Icon(
            _isSwinging ? Icons.sports_golf : Icons.golf_course_outlined,
            size: 24,
            key: ValueKey(_isSwinging),
          ),
        ),
        label: Text(
          _isSwinging ? 'Swinging...' : 'Start Record',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isSwinging ? Colors.grey[800] : Colors.blue,
          foregroundColor: Colors.white,
          elevation: _isSwinging ? 0 : 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),
    ),
  );

  LineChartData _buildChartData() {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.white24, strokeWidth: 0.5),
        getDrawingVerticalLine: (value) =>
            FlLine(color: Colors.white12, strokeWidth: 0.5),
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 25,
            getTitlesWidget: (value, meta) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${value.toInt()}%',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            reservedSize: 40,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: _graphXValue - 2, // แสดงช่วง 2 วินาทีล่าสุด
      maxX: _graphXValue,
      minY: 0,
      maxY: 100,
      lineBarsData: [
        _createLineChartBarData(_leftDataPoints, const Color(0xFF3B82F6)),
        _createLineChartBarData(_rightDataPoints, const Color(0xFFEC4899)),
      ],
    );
  }

  LineChartBarData _createLineChartBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: true, color: color.withOpacity(0.1)),
    );
  }
}

// ... Custom Widgets (_WeightCard, _LegendItem) ...
class _WeightCard extends StatelessWidget {
  final String label;
  final double percentage;
  final Color color;

  const _WeightCard({
    required this.label,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF1F2937),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Center(
            child: Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendItem({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
      ],
    );
  }
}
