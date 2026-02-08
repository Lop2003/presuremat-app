import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:golf_force_plate/widgets/simple_grid_heatmap.dart';
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
          
          // Detect if timestamps are absolute (milliseconds since epoch) or relative
          final firstTime = dataPoints.isNotEmpty ? (dataPoints.first['t'] as num).toDouble() : 0.0;
          final isAbsoluteTimestamp = firstTime > 1000000; // Likely epoch milliseconds
          final baseTime = isAbsoluteTimestamp ? firstTime : 0.0;
          
          for (var point in dataPoints) {
            final rawTime = (point['t'] as num).toDouble();
            // Convert to relative seconds from start
            final relativeTime = isAbsoluteTimestamp 
                ? (rawTime - baseTime) / 1000.0 // Convert ms to seconds
                : rawTime;
            
            leftDataPoints.add(
              FlSpot(
                relativeTime,
                (point['l'] as num).toDouble(),
              ),
            );
            rightDataPoints.add(
              FlSpot(
                relativeTime,
                (point['r'] as num).toDouble(),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(timestamp, dataPoints.length),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Video & Heatmap
                      Expanded(
                        flex: 1, // 50% width
                        child: Column(
                          children: [
                            if (_hasVideo) ...[
                              Expanded(child: _buildVideoSection()),
                              const SizedBox(height: 16),
                            ],
                            // Heatmap takes remaining space or fixed space if video is present
                            _hasVideo 
                                ? SizedBox(height: 250, child: _buildHeatmapSection()) 
                                : Expanded(child: _buildHeatmapSection()),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Right Column: Chart & Controls
                      Expanded(
                        flex: 1, // 50% width
                        child: Column(
                          children: [
                            Expanded(child: _buildChartSection(leftDataPoints, rightDataPoints)),
                            const SizedBox(height: 16),
                            _buildTimelineControl(dataPoints.length),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
      // สร้างข้อมูล heatmap เริ่มต้น (5x5 grid)
      _leftFootPressure = List.generate(5, (_) => List.filled(5, 0.0));
      _rightFootPressure = List.generate(5, (_) => List.filled(5, 0.0));
    }
  }

  // Parse pressure data from either List<List> or Map (legacy)
  List<List<double>> _parsePressureData(dynamic data) {
      if (data == null) return List.generate(5, (_) => List.filled(5, 0.0)); // fallback to 5x5 grid

      if (data is List) {
          // It's a list of lists
          return (data).map<List<double>>((row) => (row as List).map<double>((e) => (e as num).toDouble()).toList()).toList();
      } else if (data is Map) {
          // Legacy map format
          return _convertMapTo2DArray(data as Map<String, dynamic>);
      }
      return List.generate(5, (_) => List.filled(5, 0.0));
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
             if (mounted) {
               setState(() => _hasVideo = true);
               _videoController!.addListener(_videoListener);
             }
          });
       }
    }
  }

  void _videoListener() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      final position = _videoController!.value.position;
      final duration = _videoController!.value.duration;
      final isPlaying = _videoController!.value.isPlaying;

      if (isPlaying != _isPlaying) {
        if (mounted) setState(() => _isPlaying = isPlaying);
      }

      if (position <= duration) {
        final double seconds = position.inMilliseconds / 1000.0;
        if (mounted) {
          setState(() {
            _currentTime = seconds;
            _updateHeatmapForTime(_currentTime);
          });
        }
      }
      
      if (position >= duration && !isPlaying) {
         if (mounted) setState(() => _isPlaying = false);
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
          Expanded(
            child: FutureBuilder(
              future: _initializeVideoPlayerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return Container(
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
        mainAxisSize: MainAxisSize.min, // Prevent overflow
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
          const SizedBox(height: 8),
          // Using SimpleGridHeatmap - simple 5x5 grids
          SizedBox(
            height: 140,
            child: Row(
              children: [
                Expanded(
                  child: SimpleGridHeatmap(
                    pressureData: _leftFootPressure,
                    isLeftFoot: true,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SimpleGridHeatmap(
                    pressureData: _rightFootPressure,
                    isLeftFoot: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection(List<FlSpot> leftDataPoints, List<FlSpot> rightDataPoints) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          // Header with explanation
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.show_chart, color: Colors.cyanAccent, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weight Distribution',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '50% = Balanced | >50% = Left | <50% = Right',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_upward, color: Colors.cyanAccent, size: 14),
                    SizedBox(width: 4),
                    Text('Left %', style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_downward, color: Colors.redAccent, size: 14),
                    SizedBox(width: 4),
                    Text('Right %', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              _buildPlaybackChartData(leftDataPoints, rightDataPoints, _currentTime),
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
              if (_hasVideo && _videoController != null) {
                _videoController!.seekTo(Duration(milliseconds: (clamped * 1000).toInt()));
              }
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

  // Replace manual _startPlayback with unified logic
  void _startPlayback() {
    if (_hasVideo && _videoController != null) {
      _videoController!.play();
    } else {
      // Fallback for no video (existing timer logic)
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
  }

  void _pausePlayback() {
    if (_hasVideo && _videoController != null) {
      _videoController!.pause();
    } else {
      setState(() => _isPlaying = false);
      _playbackTimer?.cancel();
    }
  }

  void _resetPlayback() {
    _pausePlayback();
    if (_hasVideo && _videoController != null) {
      _videoController!.seekTo(Duration.zero);
    }
    setState(() {
      _currentTime = 0.0;
      _updateHeatmapForTime(0.0);
    });
  }

  void _updateHeatmapForTime(double time) {
    // Find closest data point
    if (_dataPoints.isEmpty) return;
    
    int closestIndex = 0;
    
    // Check if time values are relative (small numbers like 0.1, 0.2) or absolute (millisecond timestamps)
    final firstTime = (_dataPoints.first['t'] as num).toDouble();
    final lastTime = (_dataPoints.last['t'] as num).toDouble();
    
    if (firstTime > 1000000) {
      // Absolute timestamps (milliseconds since epoch) - use proportional index
      // Map video time (seconds) to data point index
      final videoDuration = _videoController?.value.duration.inSeconds.toDouble() ?? 4.0;
      final proportion = (time / videoDuration).clamp(0.0, 1.0);
      closestIndex = (proportion * (_dataPoints.length - 1)).round().clamp(0, _dataPoints.length - 1);
    } else {
      // Relative time values - use original matching logic
      double minDiff = double.infinity;
      for (int i = 0; i < _dataPoints.length; i++) {
        final pointTime = (_dataPoints[i]['t'] as num).toDouble();
        final diff = (pointTime - time).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestIndex = i;
        }
      }
    }
    
    final point = _dataPoints[closestIndex];
    
    // Update heatmap data (caller is responsible for setState)
    if (point.containsKey('raw_left') && point['raw_left'] != null) {
      try {
        // Normalize raw sensor values (0-4095) to display values (0-100)
        const double maxRawValue = 4095.0;
        _leftFootPressure = (point['raw_left'] as List).map((row) {
          return (row as List).map((val) {
            final rawVal = (val as num).toDouble();
            return (rawVal / maxRawValue * 100.0).clamp(0.0, 100.0);
          }).toList();
        }).toList();
        
        _rightFootPressure = (point['raw_right'] as List).map((row) {
          return (row as List).map((val) {
            final rawVal = (val as num).toDouble();
            return (rawVal / maxRawValue * 100.0).clamp(0.0, 100.0);
          }).toList();
        }).toList();
      } catch (e) {
        debugPrint('Error parsing heatmap data: $e');
        // Fallback
        _useGeneratedHeatmap(point);
      }
    } else {
      _useGeneratedHeatmap(point);
    }
  }

  void _useGeneratedHeatmap(Map<String, dynamic> point) {
    final leftWeight = (point['l'] as num).toDouble();
    final rightWeight = (point['r'] as num).toDouble();
    
    _leftFootPressure = _generateHeatmapFromWeight(leftWeight, true);
    _rightFootPressure = _generateHeatmapFromWeight(rightWeight, false);
  }

  List<List<double>> _generateHeatmapFromWeight(double weight, bool isLeftFoot) {
    // Generate 5x5 grid for SimpleGridHeatmap
    final List<List<double>> result = List.generate(5, (i) => List.generate(5, (j) => 0.0));
    
    // สร้าง heatmap ตามน้ำหนัก
    final basePressure = weight / 100.0 * 80.0; // แปลงเป็น 0-80
    
    for (int i = 0; i < 5; i++) {
      for (int j = 0; j < 5; j++) {
        // สร้างรูปแบบการกระจายน้ำหนัก
        double pressure = basePressure;
        
        // ส้นเท้า (แถวล่าง - row 0, 1)
        if (i <= 1) {
          pressure *= 1.2;
        }
        // นิ้วเท้า (แถวบน - row 3, 4)
        else if (i >= 3) {
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
    double currentTimeX, // Current playback position
  ) {
    // Get min and max X values from data
    final minX = leftSpots.isNotEmpty ? leftSpots.first.x : 0.0;
    final maxX = leftSpots.isNotEmpty ? leftSpots.last.x : 1.0;
    
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) {
          // Highlight 50% line (balanced)
          if (value == 50) {
            return FlLine(
              color: Colors.greenAccent.withOpacity(0.6),
              strokeWidth: 2,
              dashArray: [8, 4],
            );
          }
          return FlLine(
            color: Colors.white.withOpacity(0.1),
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 50,
            getTitlesWidget: (value, meta) {
              String label;
              Color color;
              if (value == 100) {
                label = 'L 100%';
                color = Colors.cyanAccent;
              } else if (value == 50) {
                label = '50%';
                color = Colors.greenAccent;
              } else if (value == 0) {
                label = 'R 0%';
                color = Colors.redAccent;
              } else {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              );
            },
            reservedSize: 45,
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (value, meta) => Text(
              '${value.toInt()}s',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
            reservedSize: 25,
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: minX,
      maxX: maxX,
      minY: 0,
      maxY: 100,
      // Playhead vertical line
      extraLinesData: ExtraLinesData(
        verticalLines: [
          VerticalLine(
            x: currentTimeX.clamp(minX, maxX),
            color: Colors.yellowAccent,
            strokeWidth: 3,
            dashArray: [5, 3],
            label: VerticalLineLabel(
              show: true,
              alignment: Alignment.topCenter,
              style: const TextStyle(color: Colors.yellowAccent, fontSize: 10, fontWeight: FontWeight.bold),
              labelResolver: (line) => '▼',
            ),
          ),
        ],
      ),
      lineBarsData: [
        // Left foot line (cyan)
        LineChartBarData(
          spots: leftSpots,
          isCurved: true,
          color: Colors.cyanAccent,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [Colors.cyanAccent.withOpacity(0.3), Colors.cyanAccent.withOpacity(0.0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        // Right foot line (red)
        LineChartBarData(
          spots: rightSpots,
          isCurved: true,
          color: Colors.redAccent,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [Colors.redAccent.withOpacity(0.3), Colors.redAccent.withOpacity(0.0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }
}
