import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:golf_force_plate/widgets/smooth_heatmap.dart';
import 'package:golf_force_plate/widgets/combined_heatmap.dart';
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
  double _playbackProportion = 0.0; // 0.0 to 1.0 - unified sync source
  bool _isPlaying = false;
  Timer? _playbackTimer;
  List<Map<String, dynamic>> _dataPoints = [];
  List<List<double>> _leftFootPressure = [];
  List<List<double>> _rightFootPressure = [];
  // Pre-computed heatmap frames for instant playback
  List<List<List<double>>> _precomputedLeft = [];
  List<List<List<double>>> _precomputedRight = [];
  // Pre-computed CoP trace (unified across both feet)
  List<Offset> _copTraceCombined = [];
  int _currentFrameIndex = 0;
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
    _syncTimer?.cancel();
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
            _precomputeHeatmapFrames();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _initializeVideo(swingData);
            });
          }

          // แปลงข้อมูลให้อยู่ในรูปแบบ FlSpot สำหรับกราฟ
          final List<FlSpot> leftDataPoints = [];
          final List<FlSpot> rightDataPoints = [];
          final List<FlSpot> forceDataPoints = [];
          
          // Detect if timestamps are absolute (milliseconds since epoch) or relative
          final firstTime = dataPoints.isNotEmpty ? (dataPoints.first['t'] as num).toDouble() : 0.0;
          final isAbsoluteTimestamp = firstTime > 1000000; // Likely epoch milliseconds
          final baseTime = isAbsoluteTimestamp ? firstTime : 0.0;
          
          // Find max force for normalization
          double maxForce = 1.0;
          for (var point in dataPoints) {
            final f = (point['total_force'] as num?)?.toDouble() ?? 0.0;
            if (f > maxForce) maxForce = f;
          }
          
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
            // Vertical Force (GRF) normalized to 0-100
            final force = (point['total_force'] as num?)?.toDouble() ?? 0.0;
            forceDataPoints.add(
              FlSpot(
                relativeTime,
                (force / maxForce * 100.0).clamp(0.0, 100.0),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(timestamp, dataPoints.length),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Video & Chart
                      Expanded(
                        flex: 1, // 50% width
                        child: Column(
                          children: [
                            if (_hasVideo) ...[
                              Expanded(flex: 3, child: _buildVideoSection()),
                              const SizedBox(height: 8),
                            ],
                            // Charts - 3 separate boxes
                            _hasVideo 
                                ? Column(
                                    children: [
                                      SizedBox(height: 85, child: _buildLeftChartBox(leftDataPoints)),
                                      const SizedBox(height: 6),
                                      SizedBox(height: 85, child: _buildRightChartBox(rightDataPoints)),
                                      const SizedBox(height: 6),
                                      SizedBox(height: 85, child: _buildGRFChartBox(forceDataPoints)),
                                    ],
                                  )
                                : Expanded(
                                    child: Column(
                                      children: [
                                        Expanded(child: _buildLeftChartBox(leftDataPoints)),
                                        const SizedBox(height: 6),
                                        Expanded(child: _buildRightChartBox(rightDataPoints)),
                                        const SizedBox(height: 6),
                                        Expanded(child: _buildGRFChartBox(forceDataPoints)),
                                      ],
                                    ),
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Right Column: Heatmap & Controls
                      Expanded(
                        flex: 1, // 50% width
                        child: Column(
                          children: [
                            Expanded(child: _buildHeatmapSection()),
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
      _currentSwingPhase = 'Ready';
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
      final isPlaying = _videoController!.value.isPlaying;

      if (isPlaying != _isPlaying) {
        if (mounted) setState(() => _isPlaying = isPlaying);
      }

      // Start high-frequency sync timer when playing (~60fps)
      if (isPlaying && _syncTimer == null) {
        _syncTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
          _syncHeatmapWithVideo();
        });
      } else if (!isPlaying && _syncTimer != null) {
        _syncTimer?.cancel();
        _syncTimer = null;
        // Do one final sync
        _syncHeatmapWithVideo();
      }

      final position = _videoController!.value.position;
      final duration = _videoController!.value.duration;
      if (position >= duration && !isPlaying) {
        if (mounted) setState(() => _isPlaying = false);
      }
    }
  }

  Timer? _syncTimer;

  void _syncHeatmapWithVideo() {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    final double seconds = position.inMilliseconds / 1000.0;
    
    if (mounted && (seconds - _currentTime).abs() > 0.01) {
      // Use video proportion to directly map to data index
      final videoDurationMs = duration.inMilliseconds;
      final proportion = videoDurationMs > 0 
          ? (position.inMilliseconds / videoDurationMs).clamp(0.0, 1.0) 
          : 0.0;
      _updateHeatmapForTime(seconds, proportion: proportion);
      setState(() {
        _currentTime = seconds;
        _playbackProportion = proportion;
      });
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            DateFormat('EEE, MMM d, yyyy - hh:mm a').format(timestamp),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$dataPointCount pts',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            _currentSwingPhase,
            style: const TextStyle(
              fontSize: 12,
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
          const SizedBox(height: 8),
          // Using SmoothHeatmap - smooth gradient heatmap
          Expanded(
            child: CombinedHeatmap(
              leftPressureData: _leftFootPressure,
              rightPressureData: _rightFootPressure,
              copTrace: _copTraceCombined,
              currentTraceIndex: _currentFrameIndex,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftChartBox(List<FlSpot> leftDataPoints) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF1F2937),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.arrow_back, color: Colors.cyanAccent, size: 12),
              ),
              const SizedBox(width: 4),
              const Text('Left Foot %', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.cyanAccent)),
            ],
          ),
          const SizedBox(height: 3),
          Expanded(
            child: LineChart(_buildSinglePlaybackData(leftDataPoints, Colors.cyanAccent, _playbackProportion)),
          ),
        ],
      ),
    );
  }

  Widget _buildRightChartBox(List<FlSpot> rightDataPoints) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF1F2937),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.arrow_forward, color: Colors.redAccent, size: 12),
              ),
              const SizedBox(width: 4),
              const Text('Right Foot %', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.redAccent)),
            ],
          ),
          const SizedBox(height: 3),
          Expanded(
            child: LineChart(_buildSinglePlaybackData(rightDataPoints, Colors.redAccent, _playbackProportion)),
          ),
        ],
      ),
    );
  }

  Widget _buildGRFChartBox(List<FlSpot> forceDataPoints) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF1F2937),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.fitness_center, color: Colors.blueAccent, size: 12),
              ),
              const SizedBox(width: 4),
              const Text('Vertical Force (GRF)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blueAccent)),
            ],
          ),
          const SizedBox(height: 3),
          Expanded(
            child: LineChart(
              _buildGRFPlaybackData(forceDataPoints, _playbackProportion),
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
    // Calculate maxTime: prefer video duration when available
    double maxTime = 0.0;
    if (_hasVideo && _videoController != null && _videoController!.value.isInitialized) {
      maxTime = _videoController!.value.duration.inMilliseconds / 1000.0;
    } else if (_dataPoints.isNotEmpty) {
      final firstTime = (_dataPoints.first['t'] as num).toDouble();
      final lastTime = (_dataPoints.last['t'] as num).toDouble();
      final isAbsoluteTimestamp = firstTime > 1000000;
      
      if (isAbsoluteTimestamp) {
        maxTime = (lastTime - firstTime) / 1000.0;
      } else {
        maxTime = lastTime;
      }
    }
    
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
              // Calculate proportion for direct data mapping
              final prop = maxTime > 0 ? (clamped / maxTime).clamp(0.0, 1.0) : 0.0;
              _updateHeatmapForTime(clamped, proportion: prop);
              setState(() {
                _currentTime = clamped;
                _playbackProportion = prop;
              });
              // Seek video in real-time (scrubbing)
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
        // Calculate maxTime in relative seconds
        double maxTime = 0.0;
        if (_dataPoints.isNotEmpty) {
          final firstTime = (_dataPoints.first['t'] as num).toDouble();
          final lastTime = (_dataPoints.last['t'] as num).toDouble();
          if (firstTime > 1000000) {
            maxTime = (lastTime - firstTime) / 1000.0;
          } else {
            maxTime = lastTime;
          }
        }
        
        if (_currentTime >= maxTime) {
          final prop = maxTime > 0 ? 1.0 : 0.0;
          _updateHeatmapForTime(_currentTime, proportion: prop);
          setState(() {
            _currentTime = maxTime;
            _playbackProportion = prop;
          });
          _pausePlayback();
          return;
        }
        final newTime = (_currentTime + 0.1).clamp(0.0, maxTime);
        final prop = maxTime > 0 ? (newTime / maxTime).clamp(0.0, 1.0) : 0.0;
        _updateHeatmapForTime(newTime, proportion: prop);
        setState(() {
          _currentTime = newTime;
          _playbackProportion = prop;
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
    _updateHeatmapForTime(0.0, proportion: 0.0);
    setState(() {
      _currentTime = 0.0;
      _playbackProportion = 0.0;
    });
  }

  /// Pre-compute all heatmap frames at load time for instant playback
  void _precomputeHeatmapFrames() {
    _precomputedLeft = [];
    _precomputedRight = [];
    _copTraceCombined = [];
    const double maxRawValue = 4095.0;

    for (final point in _dataPoints) {
      List<List<double>> left;
      List<List<double>> right;

      if (point.containsKey('raw_left') && point['raw_left'] != null) {
        try {
          left = (point['raw_left'] as List).map((row) {
            return (row as List).map((val) {
              final rawVal = (val as num).toDouble();
              return (rawVal / maxRawValue * 100.0).clamp(0.0, 100.0);
            }).toList();
          }).toList();
          right = (point['raw_right'] as List).map((row) {
            return (row as List).map((val) {
              final rawVal = (val as num).toDouble();
              return (rawVal / maxRawValue * 100.0).clamp(0.0, 100.0);
            }).toList();
          }).toList();
        } catch (_) {
          final leftWeight = (point['l'] as num).toDouble();
          final rightWeight = (point['r'] as num).toDouble();
          left = _generateHeatmapFromWeight(leftWeight, true);
          right = _generateHeatmapFromWeight(rightWeight, false);
        }
      } else {
        final leftWeight = (point['l'] as num).toDouble();
        final rightWeight = (point['r'] as num).toDouble();
        left = _generateHeatmapFromWeight(leftWeight, true);
        right = _generateHeatmapFromWeight(rightWeight, false);
      }

      _precomputedLeft.add(left);
      _precomputedRight.add(right);

      // Compute unified CoP across both feet
      _copTraceCombined.add(_computeCombinedCoP(left, right));
    }
    debugPrint('Pre-computed ${_precomputedLeft.length} heatmap frames with unified CoP');
  }

  /// Calculate unified Center of Pressure across both feet
  /// Left foot occupies X range 0.0-0.5, Right foot occupies 0.5-1.0
  /// Returns normalized Offset (0.0-1.0) where:
  ///   dx < 0.5 = weight biased LEFT, dx > 0.5 = weight biased RIGHT
  ///   dy = front-to-back position (0=toe, 1=heel)
  Offset _computeCombinedCoP(List<List<double>> leftGrid, List<List<double>> rightGrid) {
    double totalPressure = 0;
    double weightedX = 0;
    double weightedY = 0;

    final rows = leftGrid.length;
    final cols = leftGrid.isNotEmpty ? leftGrid[0].length : 0;

    // Process left foot (X range: 0.0 to 0.5)
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final p = leftGrid[r][c];
        if (p > 0) {
          totalPressure += p;
          // Map col to 0.0-0.5 range (left half)
          final x = cols > 1 ? (c / (cols - 1)) * 0.5 : 0.25;
          final y = rows > 1 ? r / (rows - 1) : 0.5;
          weightedX += p * x;
          weightedY += p * y;
        }
      }
    }

    // Process right foot (X range: 0.5 to 1.0)
    final rRows = rightGrid.length;
    final rCols = rightGrid.isNotEmpty ? rightGrid[0].length : 0;
    for (int r = 0; r < rRows; r++) {
      for (int c = 0; c < rCols; c++) {
        final p = rightGrid[r][c];
        if (p > 0) {
          totalPressure += p;
          // Map col to 0.5-1.0 range (right half)
          final x = rCols > 1 ? 0.5 + (c / (rCols - 1)) * 0.5 : 0.75;
          final y = rRows > 1 ? r / (rRows - 1) : 0.5;
          weightedX += p * x;
          weightedY += p * y;
        }
      }
    }

    if (totalPressure < 0.01) return const Offset(0.5, 0.5);

    return Offset(
      (weightedX / totalPressure).clamp(0.0, 1.0),
      (weightedY / totalPressure).clamp(0.0, 1.0),
    );
  }

  void _updateHeatmapForTime(double time, {double? proportion}) {
    if (_precomputedLeft.isEmpty) return;
    
    int index;
    if (proportion != null) {
      index = (proportion * (_precomputedLeft.length - 1)).round().clamp(0, _precomputedLeft.length - 1);
    } else {
      final p = _dataPoints.isNotEmpty
          ? (time / ((_dataPoints.last['t'] as num).toDouble() - (_dataPoints.first['t'] as num).toDouble()) * 1000.0).clamp(0.0, 1.0)
          : 0.0;
      index = (p * (_precomputedLeft.length - 1)).round().clamp(0, _precomputedLeft.length - 1);
    }
    
    // O(1) lookup
    _leftFootPressure = _precomputedLeft[index];
    _rightFootPressure = _precomputedRight[index];
    _currentFrameIndex = index;
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

  // Single line playback chart (reusable for Left%, Right%)
  LineChartData _buildSinglePlaybackData(
    List<FlSpot> spots,
    Color lineColor,
    double proportion,
  ) {
    final minX = spots.isNotEmpty ? spots.first.x : 0.0;
    final maxX = spots.isNotEmpty ? spots.last.x : 1.0;
    final currentTimeX = minX + proportion * (maxX - minX);
    
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Colors.white.withOpacity(0.08), strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 50,
            getTitlesWidget: (value, meta) {
              if (value == 100) return Padding(padding: const EdgeInsets.only(right: 3), child: Text('100', style: TextStyle(color: lineColor.withOpacity(0.6), fontSize: 7, fontWeight: FontWeight.bold)));
              if (value == 50) return Padding(padding: const EdgeInsets.only(right: 3), child: Text('50', style: TextStyle(color: lineColor.withOpacity(0.6), fontSize: 7, fontWeight: FontWeight.bold)));
              if (value == 0) return Padding(padding: const EdgeInsets.only(right: 3), child: Text('0', style: TextStyle(color: lineColor.withOpacity(0.6), fontSize: 7, fontWeight: FontWeight.bold)));
              return const SizedBox.shrink();
            },
            reservedSize: 24,
          ),
        ),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: minX, maxX: maxX, minY: 0, maxY: 100,
      extraLinesData: ExtraLinesData(
        verticalLines: [
          VerticalLine(x: currentTimeX.clamp(minX, maxX), color: Colors.yellowAccent, strokeWidth: 2, dashArray: [4, 3]),
        ],
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots, isCurved: true, color: lineColor, barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(colors: [lineColor.withOpacity(0.2), lineColor.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
        ),
      ],
    );
  }

  // GRF playback chart (Vertical Force only)
  LineChartData _buildGRFPlaybackData(
    List<FlSpot> forceSpots,
    double proportion,
  ) {
    final minX = forceSpots.isNotEmpty ? forceSpots.first.x : 0.0;
    final maxX = forceSpots.isNotEmpty ? forceSpots.last.x : 1.0;
    final currentTimeX = minX + proportion * (maxX - minX);
    
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Colors.white.withOpacity(0.08), strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 50,
            getTitlesWidget: (value, meta) {
              if (value == 100) return Padding(padding: const EdgeInsets.only(right: 3), child: Text('100', style: TextStyle(color: Colors.blueAccent.withOpacity(0.6), fontSize: 7, fontWeight: FontWeight.bold)));
              if (value == 50) return Padding(padding: const EdgeInsets.only(right: 3), child: Text('50', style: TextStyle(color: Colors.blueAccent.withOpacity(0.6), fontSize: 7, fontWeight: FontWeight.bold)));
              if (value == 0) return Padding(padding: const EdgeInsets.only(right: 3), child: Text('0', style: TextStyle(color: Colors.blueAccent.withOpacity(0.6), fontSize: 7, fontWeight: FontWeight.bold)));
              return const SizedBox.shrink();
            },
            reservedSize: 24,
          ),
        ),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: minX, maxX: maxX, minY: 0, maxY: 100,
      extraLinesData: ExtraLinesData(
        verticalLines: [
          VerticalLine(
            x: currentTimeX.clamp(minX, maxX),
            color: Colors.yellowAccent,
            strokeWidth: 2,
            dashArray: [4, 3],
          ),
        ],
      ),
      lineBarsData: [
        if (forceSpots.isNotEmpty)
          LineChartBarData(
            spots: forceSpots, isCurved: true, color: Colors.blueAccent, barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(colors: [Colors.blueAccent.withOpacity(0.25), Colors.blueAccent.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
          ),
      ],
    );
  }
}
