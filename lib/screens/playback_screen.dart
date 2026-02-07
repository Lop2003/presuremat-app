import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:golf_force_plate/widgets/foot_heatmap.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

class PlaybackScreen extends StatefulWidget {
  final String swingId; // รับ ID ของ document เข้ามา

  const PlaybackScreen({super.key, required this.swingId});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  Future<Map<String, dynamic>?>? _swingDataFuture;
  double _currentTime = 0.0;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  List<Map<String, dynamic>> _dataPoints = [];
  List<List<double>> _leftFootPressure = [];
  List<List<double>> _rightFootPressure = [];
  String _currentSwingPhase = 'Ready';
  
  VideoPlayerController? _videoController;
  Future<void>? _initializeVideoPlayerFuture;
  bool _hasVideo = false;

  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchSwingData();
  }

  void _fetchSwingData() {
    _swingDataFuture = _supabase
        .from('swings')
        .select()
        .eq('id', widget.swingId)
        .single();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swing Playback'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _swingDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text("Swing session not found."));
          }
          if (snapshot.hasError) {
            return const Center(child: Text("Error loading data."));
          }

          // เมื่อมีข้อมูลแล้ว
          final swingData = snapshot.data!;
          final timestamp = DateTime.parse(swingData['timestamp']);
          final dataPoints = List<Map<String, dynamic>>.from(
             (swingData['data_points'] ?? swingData['dataPoints']) as List
          );
          
          // เก็บข้อมูลไว้ใน state
          if (_dataPoints.isEmpty) {
            _dataPoints = dataPoints;
            _loadHeatmapData(swingData);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _initializeVideo(swingData);
            });
          }

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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(timestamp, dataPoints.length),
                const SizedBox(height: 20),
                if (_hasVideo) ...[
                   _buildVideoSection(),
                   const SizedBox(height: 20),
                ],
                _buildHeatmapSection(),
                const SizedBox(height: 20),
                _buildChartSection(leftDataPoints, rightDataPoints),
                const SizedBox(height: 20),
                _buildTimelineControl(dataPoints.length),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  void _loadHeatmapData(Map<String, dynamic> swingData) {
    final heatmapData = (swingData['heatmap_data'] ?? swingData['heatmapData']) as Map<String, dynamic>?;

    if (heatmapData != null) {
      // Check if data is stored as Map (legacy) or List (Supabase JSONB array)
      _leftFootPressure = _parsePressureData(heatmapData['leftFoot']);
      _rightFootPressure = _parsePressureData(heatmapData['rightFoot']);
      _currentSwingPhase = heatmapData['swingPhase'] ?? heatmapData['swing_phase'] ?? 'Ready';
    } else {
      // สร้างข้อมูล heatmap เริ่มต้น
      _leftFootPressure = HeatmapDataGenerator.generateRandomFootPressure(isLeftFoot: true);
      _rightFootPressure = HeatmapDataGenerator.generateRandomFootPressure(isLeftFoot: false);
    }
  }

  // Parse pressure data from either List<List> or Map (legacy)
  List<List<double>> _parsePressureData(dynamic data) {
      if (data == null) return HeatmapDataGenerator.generateRandomFootPressure(isLeftFoot: true); // fallback

      if (data is List) {
          // It's a list of lists
          return (data).map<List<double>>((row) => (row as List).map<double>((e) => (e as num).toDouble()).toList()).toList();
      } else if (data is Map) {
          // Legacy map format
          return _convertMapTo2DArray(data as Map<String, dynamic>);
      }
      return HeatmapDataGenerator.generateRandomFootPressure(isLeftFoot: true);
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

  void _initializeVideo(Map<String, dynamic> swingData) {
    final videoPath = swingData['video_path'] ?? swingData['videoPath'];
    if (videoPath != null && videoPath.toString().isNotEmpty) {
       VideoPlayerController? controller;
       if (videoPath.startsWith('http')) {
          controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
       } else {
          final file = File(videoPath);
          if (file.existsSync()) {
             controller = VideoPlayerController.file(file);
          }
       }

       if (controller != null) {
          _videoController = controller;
          _initializeVideoPlayerFuture = _videoController!.initialize().then((_) {
             if (mounted) setState(() => _hasVideo = true);
          });
       }
    }
  }

  Widget _buildVideoSection() {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Swing Video',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder(
            future: _initializeVideoPlayerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return Container(
                  height: 400,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            VideoPlayer(_videoController!),
                            VideoProgressIndicator(_videoController!, allowScrubbing: true),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
          const SizedBox(height: 8),
          Center(
             child: IconButton(
                onPressed: () {
                  setState(() {
                    if (_videoController!.value.isPlaying) {
                      _videoController!.pause();
                    } else {
                      _videoController!.play();
                    }
                  });
                },
                icon: Icon(
                  _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
             )
          )
        ],
      ),
    );
  }

  Widget _buildHeader(DateTime timestamp, int dataPointCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, MMM d, yyyy - hh:mm a').format(timestamp),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$dataPointCount data points recorded',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Swing Phase: $_currentSwingPhase',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapSection() {
    return Container(
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
                'Time: ${_currentTime.toStringAsFixed(1)}s',
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
        ],
      ),
    );
  }

  Widget _buildChartSection(List<FlSpot> leftDataPoints, List<FlSpot> rightDataPoints) {
    return Container(
      height: 300,
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
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _buildLegendItem('Left', const Color(0xFF3B82F6)),
              const SizedBox(width: 12),
              _buildLegendItem('Right', const Color(0xFFEC4899)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              _buildPlaybackChartData(leftDataPoints, rightDataPoints),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildTimelineControl(int totalDataPoints) {
    final maxTime = _dataPoints.isNotEmpty ? (_dataPoints.last['t'] as num).toDouble() : 0.0;
    
    return Container(
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
              Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Timeline Control',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${_currentTime.toStringAsFixed(1)}s / ${maxTime.toStringAsFixed(1)}s',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Slider(
            value: _currentTime.clamp(0.0, maxTime),
            min: 0.0,
            max: maxTime <= 0 ? 0.0 : maxTime,
            onChanged: (value) {
              final clamped = value.clamp(0.0, maxTime);
              setState(() {
                _currentTime = clamped;
                _updateHeatmapForTime(_currentTime);
              });
            },
            activeColor: Colors.blue,
            inactiveColor: Colors.grey,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _isPlaying ? _pausePlayback : _startPlayback,
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(_isPlaying ? 'Pause' : 'Play'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _resetPlayback,
                icon: const Icon(Icons.replay),
                label: const Text('Reset'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _startPlayback() {
    setState(() => _isPlaying = true);
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final maxTime = _dataPoints.isNotEmpty ? (_dataPoints.last['t'] as num).toDouble() : 0.0;
      if (_currentTime >= maxTime) {
        setState(() {
          _currentTime = maxTime;
          _updateHeatmapForTime(_currentTime);
        });
        _pausePlayback();
        return;
      }
      setState(() {
        _currentTime = (_currentTime + 0.1).clamp(0.0, maxTime);
        _updateHeatmapForTime(_currentTime);
      });
    });
  }

  void _pausePlayback() {
    setState(() => _isPlaying = false);
    _playbackTimer?.cancel();
  }

  void _resetPlayback() {
    _pausePlayback();
    setState(() {
      _currentTime = 0.0;
      _updateHeatmapForTime(0.0);
    });
  }

  void _updateHeatmapForTime(double time) {
    // หาข้อมูลที่ใกล้เคียงกับเวลาปัจจุบัน
    if (_dataPoints.isEmpty) return;
    
    int closestIndex = 0;
    double minDiff = double.infinity;
    
    for (int i = 0; i < _dataPoints.length; i++) {
      final pointTime = _dataPoints[i]['t'] as double;
      final diff = (pointTime - time).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }
    
    // อัปเดต heatmap ตามข้อมูลที่เลือก
    final leftWeight = _dataPoints[closestIndex]['l'] as double;
    final rightWeight = _dataPoints[closestIndex]['r'] as double;
    
    // สร้าง heatmap ตามน้ำหนัก
    _leftFootPressure = _generateHeatmapFromWeight(leftWeight, true);
    _rightFootPressure = _generateHeatmapFromWeight(rightWeight, false);
  }

  List<List<double>> _generateHeatmapFromWeight(double weight, bool isLeftFoot) {
    final List<List<double>> result = List.generate(10, (i) => List.generate(6, (j) => 0.0));
    
    // สร้าง heatmap ตามน้ำหนัก
    final basePressure = weight / 100.0 * 80.0; // แปลงเป็น 0-80
    
    for (int i = 0; i < 10; i++) {
      for (int j = 0; j < 6; j++) {
        // สร้างรูปแบบการกระจายน้ำหนัก
        double pressure = basePressure;
        
        // ส้นเท้า (แถวล่าง)
        if (i >= 7) {
          pressure *= 1.2;
        }
        // นิ้วเท้า (แถวบน)
        else if (i <= 2) {
          pressure *= 0.8;
        }
        // กลางเท้า
        else {
          pressure *= 0.6;
        }
        
        // เพิ่มความแปรปรวน
        pressure += (DateTime.now().millisecondsSinceEpoch % 20 - 10) * 0.1;
        pressure = pressure.clamp(0.0, 100.0);
        
        result[i][j] = pressure;
      }
    }
    
    return result;
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
