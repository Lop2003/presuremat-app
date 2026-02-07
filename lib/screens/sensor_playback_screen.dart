import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class SensorPlaybackScreen extends StatefulWidget {
  final String sessionId;
  final String sessionTitle;

  const SensorPlaybackScreen({
    super.key,
    required this.sessionId,
    required this.sessionTitle,
  });

  @override
  State<SensorPlaybackScreen> createState() => _SensorPlaybackScreenState();
}

class _SensorPlaybackScreenState extends State<SensorPlaybackScreen> {
  List<SensorReading> _sensorReadings = [];
  bool _isLoading = true;
  String _error = '';

  // Playback controls
  bool _isPlaying = false;
  Timer? _playbackTimer;
  int _currentIndex = 0;

  // Current sensor grid state
  List<List<int>> _currentSensorGrid = List.generate(3, (i) => List.filled(3, 0));

  @override
  void initState() {
    super.initState();
    _loadSensorReadings();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSensorReadings() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      final List<dynamic> data = await Supabase.instance.client
          .from('sensor_readings')
          .select()
          .eq('session_id', widget.sessionId)
          .order('timestamp', ascending: true);

      final List<SensorReading> readings = [];
      for (var item in data) {
        readings.add(SensorReading.fromSupabase(item));
      }

      setState(() {
        _sensorReadings = readings;
        _isLoading = false;
        if (readings.isNotEmpty) {
          _updateSensorGridForIndex(0);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
            _error = e.toString();
            _isLoading = false;
        });
      }
    }
  }

  void _updateSensorGridForIndex(int index) {
    if (index < 0 || index >= _sensorReadings.length) return;

    // Reset grid
    _currentSensorGrid = List.generate(3, (i) => List.filled(3, 0));

    // Get readings in a small time window around current index
    final currentTime = _sensorReadings[index].timestamp;
    final windowMs = 200; // 200ms window

    for (int i = 0; i < _sensorReadings.length; i++) {
      final reading = _sensorReadings[i];
      final timeDiff = reading.timestamp.difference(currentTime).inMilliseconds.abs();
      
      if (timeDiff <= windowMs) {
        // Apply reading to grid
        if (reading.row >= 0 && reading.row < 3 && reading.col >= 0 && reading.col < 3) {
          _currentSensorGrid[reading.row][reading.col] = reading.value;
        }
      }
    }

    if (mounted) {
        setState(() {
        _currentIndex = index;
        });
    }
  }

  void _startPlayback() {
    if (_sensorReadings.isEmpty) return;

    setState(() => _isPlaying = true);
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_currentIndex >= _sensorReadings.length - 1) {
        _pausePlayback();
        return;
      }

      _updateSensorGridForIndex(_currentIndex + 1);
    });
  }

  void _pausePlayback() {
    setState(() => _isPlaying = false);
    _playbackTimer?.cancel();
  }

  void _resetPlayback() {
    _pausePlayback();
    if (_sensorReadings.isNotEmpty) {
      _updateSensorGridForIndex(0);
    }
  }

  void _seekToPosition(double position) {
    if (_sensorReadings.isEmpty) return;
    
    final index = (position * (_sensorReadings.length - 1)).round();
    _updateSensorGridForIndex(index);
  }

  Color _getColorFromValue(int value) {
    if (value == 0) return Colors.grey[300]!;
    
    // สร้างสีตามความเข้มของค่า (0-4095 สำหรับ 12-bit ADC)
    double intensity = (value / 4095.0).clamp(0.0, 1.0);
    return Color.lerp(Colors.green[200], Colors.red[800], intensity)!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sensor Playback'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load sensor data',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error,
                        style: TextStyle(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSensorReadings,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _sensorReadings.isEmpty
                  ? const Center(
                      child: Text(
                        'No sensor data found in this session',
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSessionHeader(),
                          const SizedBox(height: 24),
                          _buildSensorGrid(),
                          const SizedBox(height: 24),
                          _buildPlaybackControls(),
                          const SizedBox(height: 24),
                          _buildDataInfo(),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildSessionHeader() {
    if (_sensorReadings.isEmpty) return const SizedBox();

    final startTime = _sensorReadings.first.timestamp;
    final endTime = _sensorReadings.last.timestamp;
    final duration = endTime.difference(startTime);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.sessionTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Started: ${DateFormat('MMM dd, yyyy - HH:mm:ss').format(startTime)}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            Text(
              'Duration: ${duration.inMinutes}m ${duration.inSeconds % 60}s',
              style: TextStyle(color: Colors.grey[600]),
            ),
            Text(
              'Total Readings: ${_sensorReadings.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorGrid() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sensor Grid (3x3)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1.0,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: 9,
                itemBuilder: (context, index) {
                  int row = index ~/ 3;
                  int col = index % 3;
                  int value = _currentSensorGrid[row][col];

                  return Container(
                    decoration: BoxDecoration(
                      color: _getColorFromValue(value),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '($row,$col)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          value.toString(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackControls() {
    final progress = _sensorReadings.isEmpty ? 0.0 : _currentIndex / (_sensorReadings.length - 1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Playback Controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            
            // Progress Slider
            Slider(
              value: progress.clamp(0.0, 1.0),
              min: 0.0,
              max: 1.0,
              onChanged: _sensorReadings.isEmpty ? null : (value) {
                _seekToPosition(value);
              },
              activeColor: Theme.of(context).primaryColor,
            ),
            
            // Time Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reading ${_currentIndex + 1} of ${_sensorReadings.length}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                Text(
                  _sensorReadings.isEmpty ? '--:--' : 
                  DateFormat('HH:mm:ss.SSS').format(_sensorReadings[_currentIndex].timestamp),
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Control Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _sensorReadings.isEmpty ? null : _resetPlayback,
                  icon: const Icon(Icons.replay),
                  label: const Text('Reset'),
                ),
                ElevatedButton.icon(
                  onPressed: _sensorReadings.isEmpty ? null : (_isPlaying ? _pausePlayback : _startPlayback),
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(_isPlaying ? 'Pause' : 'Play'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPlaying ? Colors.orange : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataInfo() {
    if (_sensorReadings.isEmpty || _currentIndex >= _sensorReadings.length) {
      return const SizedBox();
    }

    final currentReading = _sensorReadings[_currentIndex];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Reading Details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Position: (${currentReading.row}, ${currentReading.col})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Value: ${currentReading.value}'),
                      Text('Timestamp: ${DateFormat('HH:mm:ss.SSS').format(currentReading.timestamp)}'),
                    ],
                  ),
                ),
                CircleAvatar(
                  backgroundColor: _getColorFromValue(currentReading.value),
                  child: Text(
                    '${currentReading.row},${currentReading.col}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SensorReading {
  final int row;
  final int col;
  final int value;
  final DateTime timestamp;

  SensorReading({
    required this.row,
    required this.col,
    required this.value,
    required this.timestamp,
  });

  factory SensorReading.fromSupabase(Map<String, dynamic> data) {
    return SensorReading(
      row: data['row_index'] ?? 0,
      col: data['col_index'] ?? 0,
      value: data['value'] ?? 0,
      timestamp: DateTime.parse(data['timestamp']),
    );
  }
}
