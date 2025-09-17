import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class PlaybackScreen extends StatefulWidget {
  final String swingId; // รับ ID ของ document เข้ามา

  const PlaybackScreen({super.key, required this.swingId});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  Future<DocumentSnapshot>? _swingDataFuture;

  @override
  void initState() {
    super.initState();
    // ดึงข้อมูลแค่ครั้งเดียวเมื่อเปิดหน้าจอ
    _swingDataFuture = FirebaseFirestore.instance
        .collection('swings')
        .doc(widget.swingId)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swing Playback'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _swingDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Swing session not found."));
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Error loading data."));
          }

          // เมื่อมีข้อมูลแล้ว
          final swingData = snapshot.data!.data() as Map<String, dynamic>;
          final timestamp = (swingData['timestamp'] as Timestamp).toDate();
          final dataPoints = swingData['dataPoints'] as List;

          // แปลงข้อมูลให้อยู่ในรูปแบบ FlSpot สำหรับกราฟ
          final List<FlSpot> leftDataPoints = [];
          final List<FlSpot> rightDataPoints = [];
          for (var point in dataPoints) {
            leftDataPoints.add(
              FlSpot(
                (point['t'] as num).toDouble(),
                (point['l'] as num).toDouble(),
              ),
            );
            rightDataPoints.add(
              FlSpot(
                (point['t'] as num).toDouble(),
                (point['r'] as num).toDouble(),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, MMM d, yyyy - hh:mm a').format(timestamp),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text('${dataPoints.length} data points recorded.'),
                const SizedBox(height: 24),
                AspectRatio(
                  aspectRatio: 1.5,
                  child: LineChart(
                    _buildPlaybackChartData(leftDataPoints, rightDataPoints),
                  ),
                ),
                // TODO: เพิ่ม Slider สำหรับเลื่อนดูข้อมูลบนกราฟ
              ],
            ),
          );
        },
      ),
    );
  }

  // ฟังก์ชันวาดกราฟ (คล้ายกับของ Dashboard แต่แสดงข้อมูลทั้งหมด)
  LineChartData _buildPlaybackChartData(
    List<FlSpot> leftSpots,
    List<FlSpot> rightSpots,
  ) {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.white.withOpacity(0.1), strokeWidth: 1),
        getDrawingVerticalLine: (value) =>
            FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 25,
            getTitlesWidget: (value, meta) => Text(
              '${value.toInt()}%',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            reservedSize: 40,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (value, meta) => Text(
              value.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            reservedSize: 30,
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.white24),
      ),
      minY: 0,
      maxY: 100,
      lineBarsData: [
        LineChartBarData(
          spots: leftSpots,
          isCurved: true,
          gradient: const LinearGradient(
            colors: [Colors.cyanAccent, Colors.blueAccent],
          ),
          barWidth: 4,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: rightSpots,
          isCurved: true,
          gradient: const LinearGradient(
            colors: [Colors.pinkAccent, Colors.redAccent],
          ),
          barWidth: 4,
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }
}
