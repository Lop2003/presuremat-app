import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:golf_force_plate/theme.dart'; // Import theme definitions
import 'package:golf_force_plate/widgets/smooth_heatmap.dart';
import 'package:golf_force_plate/widgets/combined_heatmap.dart';
import 'package:golf_force_plate/screens/sensor_display_screen.dart';
import 'package:golf_force_plate/screens/auth_screen.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'package:golf_force_plate/services/serial_service.dart'; // Import SerialService

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
  Offset _liveCoP = const Offset(0.5, 0.5); // Live Center of Pressure
  bool _showHeatmap = true;

  // Force tracking (matching Processing Ver2 logic)
  double _totalForceLeft = 0.0;
  double _totalForceRight = 0.0;
  static const double _forceThreshold = 300.0; // Min force to calculate balance
  
  // Total force history for dual-line graph
  List<FlSpot> _totalForceDataPoints = [];

  // Camera
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  bool _isRecording = false;

  final SupabaseClient _supabase = Supabase.instance.client;

  // Serial Port
  final SerialService _serialService = SerialService();
  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isSerialConnected = false;
  StreamSubscription<List<int>>? _serialSubscription;
  
  // Real-time recording buffer
  List<Map<String, dynamic>> _recordedDataBuffer = [];
  
  // Auto-recording based on pressure detection
  bool _autoRecordEnabled = true;       // Auto-record mode enabled
  int _lowForceCounter = 0;             // Count frames below threshold
  static const int _stopDelay = 15;     // Frames to wait before auto-stop (~1.5 sec at 100ms)

  @override
  void initState() {
    super.initState();
    _initializeGraphWithBaseline();
    _initializeHeatmapData();
    _initializeCamera();
    _restoreSerialConnection();
  }
  
  void _restoreSerialConnection() {
    // Check if singleton is already connected
    if (_serialService.isConnected) {
      _isSerialConnected = true;
      _selectedPort = _serialService.connectedPort;
      // Subscribe to data stream
      _serialSubscription?.cancel();
      _serialSubscription = _serialService.dataStream.listen(_processSerialData);
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(
          cameras.first,
          ResolutionPreset.medium,
        );
        _initializeControllerFuture = _cameraController!.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _initializeHeatmapData() {
    // Initialize with 5x5 grids of zeros (will be updated with real sensor data)
    _leftFootPressure = List.generate(5, (_) => List.filled(5, 0.0));
    _rightFootPressure = List.generate(5, (_) => List.filled(5, 0.0));
  }

  void _initializeGraphWithBaseline() {
    _leftDataPoints.clear();
    _rightDataPoints.clear();
    _graphXValue = 0;

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
    List<FlSpot> rightData, {
    String? videoPath,
    List<Map<String, dynamic>>? recordedData,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    
    String? publicVideoUrl;
    if (videoPath != null) {
      final videoFile = File(videoPath);
      if (videoFile.existsSync()) {
        try {
          final fileName = 'swing_${DateTime.now().millisecondsSinceEpoch}.mp4';
          final path = '${user.id}/$fileName';
          
          await _supabase.storage.from('swing-videos').upload(
            path,
            videoFile,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
          
          publicVideoUrl = _supabase.storage.from('swing-videos').getPublicUrl(path);
        } catch (e) {
          debugPrint('Error uploading video: $e');
        }
      }
    }

    final List<Map<String, dynamic>> dataPointsToSave;

    if (recordedData != null && recordedData.isNotEmpty) {
       dataPointsToSave = recordedData;
    } else {
       dataPointsToSave = [];
       for (int i = 0; i < leftData.length; i++) {
         dataPointsToSave.add({
           't': leftData[i].x,
           'l': leftData[i].y,
           'r': rightData[i].y,
         });
       }
    }

    final Map<String, dynamic> heatmapData = {
      'leftFoot': _leftFootPressure,
      'rightFoot': _rightFootPressure,
      'swingPhase': _swingPhase,
    };

    try {
      final Map<String, dynamic> sessionData = {
        'user_id': user.id,
        'timestamp': DateTime.now().toIso8601String(),
        'data_points': dataPointsToSave,
        'heatmap_data': heatmapData,
        'swing_phase': _swingPhase,
        'video_path': publicVideoUrl,
      };

      await _supabase.from('swings').insert(sessionData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Session saved successfully'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save session: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleRecordButtonPress() async {
    if (_isSwinging) return;

    // Start Video Recording
    if (_cameraController != null && 
        _cameraController!.value.isInitialized && 
        !_cameraController!.value.isRecordingVideo) {
      try {
        await _cameraController!.startVideoRecording();
        _isRecording = true;
      } catch (e) {
        debugPrint('Error starting video recording: $e');
      }
    }

    setState(() {
      _leftDataPoints = [];
      _rightDataPoints = [];
      _recordedDataBuffer = [];
      _graphXValue = 0;
      _isSwinging = true;
      _swingPhase = _isSerialConnected ? "Recording..." : "Backswing";
    });

    if (_isSerialConnected) {
       // Real Recording Path
       Future.delayed(const Duration(seconds: 4), () async {
          if (!mounted) return;
          
          _isRecording = false;
          _isSwinging = false;
          setState(() => _swingPhase = "Saving...");

          String? recordedPath;
          if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
            try {
              final file = await _cameraController!.stopVideoRecording();
              recordedPath = file.path;
            } catch (e) {
              debugPrint('Error stopping video recording: $e');
            }
          }

          // Use buffered data
          await _saveSwingSession([], [], videoPath: recordedPath, recordedData: List.from(_recordedDataBuffer));
          
          // Reset graph but keep serial streaming (don't call _returnToBaseline)
          if (mounted) {
            setState(() {
              _swingPhase = "Ready";
              _leftDataPoints = [];
              _rightDataPoints = [];
              _totalForceDataPoints = [];
              _graphXValue = 0;
            });
          }
       });
       return;
    }

    // Simulation Path
    final List<FlSpot> currentSwingL = [];
    final List<FlSpot> currentSwingR = [];
    double swingTime = 0.0;

    final backswingPeak = 30 + _random.nextDouble() * 10;
    final transitionPeak = 70 + _random.nextDouble() * 10;
    final finishPeak = 85 + _random.nextDouble() * 10;

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 40), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      swingTime += 0.04;
      double left;

      if (swingTime < 1.5) {
        if (mounted && _swingPhase != "Backswing") setState(() => _swingPhase = "Backswing");
        left = 50 - backswingPeak * (swingTime / 1.5);
      } else if (swingTime < 2.0) {
        if (mounted && _swingPhase != "Transition") setState(() => _swingPhase = "Transition");
        left =
            (50 - backswingPeak) + transitionPeak * ((swingTime - 1.5) / 0.5);
      } else if (swingTime < 3.5) {
        if (mounted && _swingPhase != "Finish") setState(() => _swingPhase = "Finish");
        left =
            (50 - backswingPeak + transitionPeak) +
            (finishPeak - (50 - backswingPeak + transitionPeak)) *
                ((swingTime - 2.0) / 1.5);
      } else {
        _isSwinging = false;
        if (mounted) setState(() => _swingPhase = "Saving...");
        timer.cancel();

        String? recordedPath;
        // Stop Video Recording
        if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
          try {
            final file = await _cameraController!.stopVideoRecording();
            _isRecording = false;
            recordedPath = file.path;
            debugPrint('Video saved to: ${file.path}');
          } catch (e) {
            debugPrint('Error stopping video recording: $e');
          }
        }

        _saveSwingSession(currentSwingL, currentSwingR, videoPath: recordedPath);
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
          _initializeGraphWithBaseline();
        }
        backTimer.cancel();
      } else {
        final newLeft = _leftWeightPercent - (_leftWeightPercent - 50.0) * 0.1;
        _updateData(newLeft, 100 - newLeft);
      }
    });
  }

  /// Auto-start recording when person steps on mat
  Future<void> _startAutoRecording() async {
    if (!mounted) return;
    
    // Start video recording FIRST (async, takes time to init)
    if (_cameraController != null && 
        _cameraController!.value.isInitialized && 
        !_cameraController!.value.isRecordingVideo) {
      try {
        await _cameraController!.startVideoRecording();
      } catch (e) {
        debugPrint('Error starting video recording: $e');
      }
    }
    
    // Reset data buffer AFTER video starts → both start at the same time
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _isSwinging = true;
      _swingPhase = "AUTO Recording...";
      _recordedDataBuffer = [];
      _leftDataPoints = [];
      _rightDataPoints = [];
      _totalForceDataPoints = [];
      _graphXValue = 0;
      _lowForceCounter = 0;
    });
    
    debugPrint('Auto-recording started');
  }

  /// Auto-stop recording when person steps off mat
  Future<void> _stopAutoRecording() async {
    if (!mounted) return;
    
    setState(() {
      _isRecording = false;
      _isSwinging = false;
      _swingPhase = "Saving...";
    });
    
    String? recordedPath;
    
    // Stop video recording
    if (_cameraController != null && _cameraController!.value.isRecordingVideo) {
      try {
        final file = await _cameraController!.stopVideoRecording();
        recordedPath = file.path;
      } catch (e) {
        debugPrint('Error stopping video recording: $e');
      }
    }
    
    // Save the recorded data
    if (_recordedDataBuffer.isNotEmpty) {
      await _saveSwingSession([], [], videoPath: recordedPath, recordedData: List.from(_recordedDataBuffer));
    }
    
    // Reset state
    if (mounted) {
      setState(() {
        _swingPhase = "Ready";
        _lowForceCounter = 0;
      });
    }
    
    debugPrint('Auto-recording stopped, saved ${_recordedDataBuffer.length} data points');
  }

  void _updateData(double left, double right) {
    if (!mounted) return;

    setState(() {
      _leftWeightPercent = left;
      _rightWeightPercent = right;

      _graphXValue += 0.04;

      if (_leftDataPoints.length > 50) {
        _leftDataPoints.removeAt(0);
        _rightDataPoints.removeAt(0);
      }

      _leftDataPoints.add(FlSpot(_graphXValue, left));
      _rightDataPoints.add(FlSpot(_graphXValue, right));

      // Generate random 5x5 grids for display when simulating
      _leftFootPressure = List.generate(5, (_) =>
        List.generate(5, (_) => _random.nextDouble() * 100)
      );
      _rightFootPressure = List.generate(5, (_) =>
        List.generate(5, (_) => _random.nextDouble() * 100)
      );
    });
  }

  void _initSerial() {
    setState(() {
      _availablePorts = _serialService.getAvailablePorts();
    });
  }

  void _showConnectionDialog() {
    _initSerial(); // Refresh ports
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to Sensor Board'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_availablePorts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No serial ports found.'),
                )
              else
                ..._availablePorts.map((port) => ListTile(
                      title: Text(port),
                      leading: const Icon(Icons.usb),
                      trailing: _selectedPort == port && _isSerialConnected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _connectToPort(port);
                      },
                    )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (_isSerialConnected)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _disconnectFromPort();
              },
              child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  Future<void> _connectToPort(String portName) async {
    try {
      await _serialService.connect(portName);
      setState(() {
        _selectedPort = portName;
        _isSerialConnected = true;
      });
      
      _serialSubscription?.cancel();
      _serialSubscription = _serialService.dataStream.listen(_processSerialData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to $portName')),
        );
      }
    } catch (e) {
      debugPrint('Error connecting to port: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _disconnectFromPort() async {
    await _serialService.disconnect();
    _serialSubscription?.cancel();
    setState(() {
      _isSerialConnected = false;
      _selectedPort = null;
    });
  }

  void _processSerialData(List<int> sensors) {
    if (!mounted) return;

    // Map sensors to 5x5 grids (raw values 0-4095)
    // Swapped: Left Foot uses sensors 32-56, Right Foot uses sensors 0-24
    final leftGrid5x5 = _mapTo5x5Grid(sensors, 32);
    final rightGrid5x5 = _mapTo5x5Grid(sensors, 0);

    // Calculate total force for each foot
    double leftTotal = 0;
    double rightTotal = 0;

    for(var row in leftGrid5x5) {
      for(var val in row) leftTotal += val;
    }
    for(var row in rightGrid5x5) {
      for(var val in row) rightTotal += val;
    }

    // Store raw force values
    _totalForceLeft = leftTotal;
    _totalForceRight = rightTotal;
    double totalSystemForce = leftTotal + rightTotal;
    
    // Apply threshold logic (matching Processing Ver2)
    double leftPercent;
    double rightPercent;
    
    if (totalSystemForce > _forceThreshold) {
      // Calculate actual balance when force is above threshold
      leftPercent = (leftTotal / totalSystemForce) * 100;
      rightPercent = (rightTotal / totalSystemForce) * 100;
    } else {
      // Below threshold: show 0% (no one standing)
      leftPercent = 0.0;
      rightPercent = 0.0;
    }
    
    // Normalize 5x5 grids to 0-100 for display
    const double maxRawValue = 4095.0;
    final leftGridDisplay = leftGrid5x5.map((row) => 
      row.map((v) => (v / maxRawValue * 100.0).clamp(0.0, 100.0)).toList()
    ).toList();
    final rightGridDisplay = rightGrid5x5.map((row) => 
      row.map((v) => (v / maxRawValue * 100.0).clamp(0.0, 100.0)).toList()
    ).toList();

    _updateDataFromSerial(leftPercent, rightPercent, leftGridDisplay, rightGridDisplay, totalSystemForce);
    
    // Auto-recording logic
    if (_autoRecordEnabled && _isSerialConnected) {
      final bool forceAboveThreshold = totalSystemForce > _forceThreshold;
      
      if (forceAboveThreshold) {
        // Person is standing on mat
        _lowForceCounter = 0; // Reset counter
        
        if (!_isRecording && !_isSwinging) {
          // Auto-start recording
          _startAutoRecording();
        }
      } else {
        // Force below threshold
        if (_isRecording) {
          _lowForceCounter++;
          
          if (_lowForceCounter >= _stopDelay) {
            // Auto-stop recording after delay
            _stopAutoRecording();
          }
        }
      }
    }
    
    // If recording, buffer the data
    if (_isRecording) {
      _recordedDataBuffer.add({
        't': DateTime.now().millisecondsSinceEpoch,
        'l': leftPercent,
        'r': rightPercent,
        'raw_left': leftGrid5x5,
        'raw_right': rightGrid5x5,
        'total_force': totalSystemForce,
      });
    }
  }

  List<List<double>> _mapTo5x5Grid(List<int> sensors, int startIndex) {
    List<List<double>> grid = [];
    for (int i = 0; i < 5; i++) {
      List<double> row = [];
      for (int j = 0; j < 5; j++) {
        // Index calculation: startIndex + (row * 5) + col
        int index = startIndex + (i * 5) + j;
        if (index < sensors.length) {
          row.add(sensors[index].toDouble());
        } else {
          row.add(0.0);
        }
      }
      grid.add(row);
    }
    return grid;
  }
  // _scaleTo10x6 removed - now using 5x5 grids directly with SimpleGridHeatmap
  
  void _updateDataFromSerial(double left, double right, List<List<double>> leftHeatmap, List<List<double>> rightHeatmap, double totalForce) {
      setState(() {
        _leftWeightPercent = left;
        _rightWeightPercent = right;

        _graphXValue += 0.04; // Approximate 25Hz or use real time diff

        if (_leftDataPoints.length > 50) {
          _leftDataPoints.removeAt(0);
          _rightDataPoints.removeAt(0);
          _totalForceDataPoints.removeAt(0);
        }

        _leftDataPoints.add(FlSpot(_graphXValue, left));
        _rightDataPoints.add(FlSpot(_graphXValue, right));
        
        // Normalize total force to 0-100 scale for graph display (max ~25000 for 25 sensors x 1000 each)
        final normalizedForce = (totalForce / 30000.0 * 100.0).clamp(0.0, 100.0);
        _totalForceDataPoints.add(FlSpot(_graphXValue, normalizedForce));

        _leftFootPressure = leftHeatmap;
        _rightFootPressure = rightHeatmap;

        // Compute live CoP across both feet
        _liveCoP = _computeLiveCoP(leftHeatmap, rightHeatmap);
      });
  }

  /// Compute unified Center of Pressure across both feet (live)
  /// Left foot occupies X 0.0-0.5, Right foot occupies X 0.5-1.0
  Offset _computeLiveCoP(List<List<double>> leftGrid, List<List<double>> rightGrid) {
    double totalP = 0, wx = 0, wy = 0;

    void processGrid(List<List<double>> grid, double xOffset, double xScale) {
      final rows = grid.length;
      final cols = rows > 0 ? grid[0].length : 0;
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final p = grid[r][c];
          if (p > 0) {
            totalP += p;
            wx += p * (xOffset + (cols > 1 ? c / (cols - 1) : 0.5) * xScale);
            wy += p * (rows > 1 ? r / (rows - 1) : 0.5);
          }
        }
      }
    }

    processGrid(leftGrid, 0.0, 0.5);   // left half
    processGrid(rightGrid, 0.5, 0.5);  // right half

    if (totalP < 0.01) return const Offset(0.5, 0.5);
    return Offset((wx / totalP).clamp(0.0, 1.0), (wy / totalP).clamp(0.0, 1.0));
  }
  @override
  void dispose() {
    _simulationTimer?.cancel();
    _leftDataPoints.clear();
    _rightDataPoints.clear();
    _cameraController?.dispose();
    _serialSubscription?.cancel(); // Cancel subscription but don't dispose singleton
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // App Bar
              _buildAppBar(context),
              const SizedBox(height: 16),
              // Main Content - Two Columns
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Column: Camera + Chart
                    Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        // Camera Preview
                        Expanded(flex: 3, child: _buildCameraPreview()),
                        const SizedBox(height: 8),
                        // Left % Chart
                        Expanded(flex: 1, child: _buildLeftChartCard()),
                        const SizedBox(height: 8),
                        // Right % Chart
                        Expanded(flex: 1, child: _buildRightChartCard()),
                        const SizedBox(height: 8),
                        // GRF Chart
                        Expanded(flex: 1, child: _buildGRFChartCard()),
                      ],
                    ),
                  ),
                    const SizedBox(width: 16),
                    // Right Column: Balance + Heatmap + Record
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          // Balance Bar (compact)
                          _buildWeightCards(),
                          const SizedBox(height: 12),
                          // Heatmap (takes most space)
                          if (_showHeatmap)
                            Expanded(child: _buildHeatmapSection()),
                          const SizedBox(height: 12),
                          // Record Button (compact)
                          SizedBox(height: 50, child: _buildRecordButton()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    decoration: BoxDecoration(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.05)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 15,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.sports_golf, color: AppColors.primary, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Force Plate',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
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

  Widget _buildStatusBadge() {
    Color statusColor = _swingPhase == 'Ready'
        ? AppColors.primary
        : AppColors.accent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
           width: 8,
           height: 8,
           decoration: BoxDecoration(
             color: statusColor,
             shape: BoxShape.circle,
             boxShadow: [
               BoxShadow(color: statusColor.withOpacity(0.6), blurRadius: 6, spreadRadius: 1)
             ]
           ),
        ),
        const SizedBox(width: 8),
        Text(
          _swingPhase.toUpperCase(),
          style: TextStyle(
            color: statusColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) => Row(
    children: [
      _buildIconButton(
        icon: Icons.usb,
        tooltip: _isSerialConnected ? 'Connected: $_selectedPort' : 'Connect Device',
        color: _isSerialConnected ? Colors.green : null,
        onPressed: _showConnectionDialog,
      ),
      const SizedBox(width: 8),
      _buildIconButton(
        icon: Icons.sensors,
        tooltip: 'Sensor Display',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SensorDisplayScreen()),
        ),
      ),
      const SizedBox(width: 8),
      _buildIconButton(
        icon: _showHeatmap ? Icons.visibility : Icons.visibility_off,
        tooltip: _showHeatmap ? 'Hide Heatmap' : 'Show Heatmap',
        onPressed: () => setState(() => _showHeatmap = !_showHeatmap),
      ),
      const SizedBox(width: 8),
      _buildIconButton(
        icon: Icons.logout,
        tooltip: 'Logout',
        color: AppColors.error,
        onPressed: () async {
          await _supabase.auth.signOut();
          if (context.mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const AuthScreen()),
            );
          }
        },
      ),
    ],
  );

  Widget _buildCameraPreview() {
    return Container(
      height: 400, // Match playback screen size
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Feed
          if (_initializeControllerFuture != null)
            FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    _cameraController != null &&
                    _cameraController!.value.isInitialized) {
                  return Center(
                    child: AspectRatio(
                      aspectRatio: _cameraController!.value.aspectRatio,
                      child: CameraPreview(_cameraController!),
                    ),
                  );
                } else {
                  return Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  );
                }
              },
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.grey[800]!,
                    Colors.grey[900]!,
                  ],
                ),
              ),
              child: Icon(
                Icons.videocam_off_outlined,
                size: 64,
                color: Colors.white.withOpacity(0.1),
              ),
            ),


          // Status Indicators
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: _isSwinging ? AppColors.error : AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isSwinging ? 'REC' : 'LIVE',
                    style: TextStyle(
                      color: _isSwinging ? AppColors.error : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Camera Controls (Mock)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.switch_camera, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: (color ?? Colors.white).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: color ?? AppColors.textSecondary, size: 22),
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  // Balance Bar Chart (like Processing Ver2)
  Widget _buildWeightCards() => Container(
    height: 80,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: AppColors.surfaceDark,
      border: Border.all(color: Colors.white.withOpacity(0.05)),
    ),
    child: Column(
      children: [
        // Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'L: ${_leftWeightPercent.toInt()}%',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Balance',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            Text(
              'R: ${_rightWeightPercent.toInt()}%',
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Balance Bar
        Container(
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[800],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                // Left (Green)
                Expanded(
                  flex: (_leftWeightPercent + _rightWeightPercent) > 0 
                      ? _leftWeightPercent.toInt().clamp(0, 100)
                      : 50,
                  child: Container(color: Colors.green),
                ),
                // Right (Red)
                Expanded(
                  flex: (_leftWeightPercent + _rightWeightPercent) > 0 
                      ? _rightWeightPercent.toInt().clamp(0, 100)
                      : 50,
                  child: Container(color: Colors.red),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildLeftChartCard() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: AppColors.surfaceDark,
      border: Border.all(color: Colors.white.withOpacity(0.05)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.arrow_back, color: Colors.cyanAccent, size: 14),
            ),
            const SizedBox(width: 6),
            const Text('Left Foot %', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.cyanAccent)),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LineChart(_buildSingleLineChartData(_leftDataPoints, Colors.cyanAccent), duration: const Duration(milliseconds: 0)),
        ),
      ],
    ),
  );

  Widget _buildRightChartCard() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      color: AppColors.surfaceDark,
      border: Border.all(color: Colors.white.withOpacity(0.05)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.arrow_forward, color: Colors.redAccent, size: 14),
            ),
            const SizedBox(width: 6),
            const Text('Right Foot %', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.redAccent)),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LineChart(_buildSingleLineChartData(_rightDataPoints, Colors.redAccent), duration: const Duration(milliseconds: 0)),
        ),
      ],
    ),
  );

  Widget _buildGRFChartCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: AppColors.surfaceDark,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 15,
          offset: const Offset(0, 6),
        ),
      ],
      border: Border.all(color: Colors.white.withOpacity(0.05)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.fitness_center, color: Colors.blueAccent, size: 16),
            ),
            const SizedBox(width: 8),
            const Text(
              'Vertical Force (GRF)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Z-axis', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LineChart(
            _buildGRFChartData(),
            duration: const Duration(milliseconds: 0),
          ),
        ),
      ],
    ),
  );

  Widget _buildHeatmapSection() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      color: AppColors.surfaceDark,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
      border: Border.all(color: Colors.white.withOpacity(0.05)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.thermostat, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Foot Pressure',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _swingPhase,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: CombinedHeatmap(
            leftPressureData: _leftFootPressure,
            rightPressureData: _rightFootPressure,
            copTrace: [_liveCoP],
            currentTraceIndex: 0,
            onTap: () => _updateHeatmapData(),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.backgroundDark,
            borderRadius: BorderRadius.circular(12),
          ),
          child: FittedBox(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildHeatmapLegendItem('Low', Colors.blue),
                const SizedBox(width: 12),
                _buildHeatmapLegendItem('Medium', Colors.cyan),
                const SizedBox(width: 12),
                _buildHeatmapLegendItem('High', Colors.yellow),
                const SizedBox(width: 12),
                _buildHeatmapLegendItem('Max', Colors.red),
              ],
            ),
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
      ],
    );
  }

  void _updateHeatmapData() {
    setState(() {
      // Generate random 5x5 grids for testing (values 0-100)
      _leftFootPressure = List.generate(5, (_) =>
        List.generate(5, (_) => _random.nextDouble() * 100)
      );
      _rightFootPressure = List.generate(5, (_) =>
        List.generate(5, (_) => _random.nextDouble() * 100)
      );
    });
  }

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

  Widget _buildRecordButton() {
    // When connected to serial: show auto-record status
    if (_isSerialConnected && _autoRecordEnabled) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: (_isRecording ? Colors.red : Colors.green).withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: _isRecording ? Colors.red.shade800 : const Color(0xFF1F2937),
              border: Border.all(
                color: _isRecording ? Colors.red : Colors.green,
                width: 2,
              ),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isRecording ? Icons.fiber_manual_record : Icons.sensors,
                    color: _isRecording ? Colors.red.shade200 : Colors.green,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isRecording ? 'AUTO RECORDING...' : 'AUTO • Step on mat to record',
                    style: TextStyle(
                      color: _isRecording ? Colors.white : Colors.grey.shade300,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    // Demo mode: manual record button
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: (_isSwinging ? AppColors.surfaceLight : AppColors.primary).withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton.icon(
          onPressed: _isSwinging ? null : _handleRecordButtonPress,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _isSwinging ? Icons.hourglass_top : Icons.play_circle_fill,
              size: 28,
              key: ValueKey(_isSwinging),
            ),
          ),
          label: Text(
            _isSwinging ? 'DEMO SWING...' : 'DEMO SWING',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isSwinging ? AppColors.surfaceLight : AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ),
    );
  }

  LineChartData _buildSingleLineChartData(List<FlSpot> dataPoints, Color lineColor) {
    return LineChartData(
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Colors.white.withOpacity(0.08), strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 50,
            getTitlesWidget: (value, meta) {
              if (value == 100) return Padding(padding: const EdgeInsets.only(right: 4), child: Text('100', style: TextStyle(color: lineColor.withOpacity(0.6), fontSize: 8, fontWeight: FontWeight.bold)));
              if (value == 50) return Padding(padding: const EdgeInsets.only(right: 4), child: Text('50', style: TextStyle(color: lineColor.withOpacity(0.6), fontSize: 8, fontWeight: FontWeight.bold)));
              if (value == 0) return Padding(padding: const EdgeInsets.only(right: 4), child: Text('0', style: TextStyle(color: lineColor.withOpacity(0.6), fontSize: 8, fontWeight: FontWeight.bold)));
              return const SizedBox.shrink();
            },
            reservedSize: 28,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: (_graphXValue - 2).clamp(0, double.infinity),
      maxX: _graphXValue < 2 ? 2 : _graphXValue,
      minY: 0,
      maxY: 100,
      lineBarsData: [
        _createLineChartBarData(dataPoints, lineColor),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) => AppColors.surfaceLight.withOpacity(0.9),
        ),
      ),
    );
  }

  LineChartData _buildGRFChartData() {
    return LineChartData(
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Colors.white.withOpacity(0.1), strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 50,
            getTitlesWidget: (value, meta) {
              if (value == 100) return const Padding(padding: EdgeInsets.only(right: 4), child: Text('Max', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)));
              if (value == 50) return const Padding(padding: EdgeInsets.only(right: 4), child: Text('50%', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)));
              if (value == 0) return const Padding(padding: EdgeInsets.only(right: 4), child: Text('0', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)));
              return const SizedBox.shrink();
            },
            reservedSize: 35,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: (_graphXValue - 2).clamp(0, double.infinity),
      maxX: _graphXValue < 2 ? 2 : _graphXValue,
      minY: 0,
      maxY: 100,
      lineBarsData: [
        _createLineChartBarData(_totalForceDataPoints, Colors.blueAccent),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) => AppColors.surfaceLight.withOpacity(0.9),
        ),
      ),
    );
  }

  LineChartBarData _createLineChartBarData(List<FlSpot> spots, Color color) {
    // Prevent empty list which causes chart overflow
    final safeSpots = spots.isEmpty ? [FlSpot(0, 50)] : spots;
    return LineChartBarData(
      spots: safeSpots,
      isCurved: true,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) {
          // Only show dot on the last (current) point
          if (index == spots.length - 1) {
            return FlDotCirclePainter(
              radius: 5,
              color: color,
              strokeWidth: 2,
              strokeColor: Colors.white,
            );
          }
          return FlDotCirclePainter(radius: 0, color: Colors.transparent);
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.3),
            color.withOpacity(0.0),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  final String label;
  final double percentage;
  final Color color;
  final String side;

  const _WeightCard({
    required this.label,
    required this.percentage,
    required this.color,
    required this.side,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(minHeight: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.surfaceDark,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
             AppColors.surfaceDark,
             AppColors.surfaceDark.withRed(35).withBlue(50), // Subtle shift
          ],
        ),
        boxShadow: [
          BoxShadow(
             color: color.withOpacity(0.1),
             blurRadius: 20,
             offset: const Offset(0, 10),
          )
        ],
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                 decoration: BoxDecoration(
                   color: color.withOpacity(0.2),
                   borderRadius: BorderRadius.circular(8),
                 ),
                 child: Text(side, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
             child: Text(
               '${percentage.toStringAsFixed(1)}%',
               style: TextStyle(
                 fontSize: 42,
                 fontWeight: FontWeight.bold,
                 color: Colors.white,
                 shadows: [
                   Shadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 15,
                   ),
                 ],
               ),
             ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
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
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
               BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
            ]
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
