  import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:golf_force_plate/theme.dart'; // Import theme definitions
import 'package:golf_force_plate/widgets/foot_heatmap.dart';
import 'package:golf_force_plate/screens/sensor_display_screen.dart';
import 'package:golf_force_plate/screens/auth_screen.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

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

  // Camera
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  bool _isRecording = false;

  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _initializeGraphWithBaseline();
    _initializeHeatmapData();
    _initializeCamera();
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
          // Proceed without video URL if upload fails, or handle as needed
        }
      }
    }

    final List<Map<String, double>> dataPoints = [];
    for (int i = 0; i < leftData.length; i++) {
      dataPoints.add({
        't': leftData[i].x,
        'l': leftData[i].y,
        'r': rightData[i].y,
      });
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
        'data_points': dataPoints,
        'heatmap_data': heatmapData,
        'swing_phase': _swingPhase,
        'video_path': publicVideoUrl, // Use the public URL here
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

  Future<void> _simulateSwing() async {
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
      _graphXValue = 0;
      _isSwinging = true;
      _swingPhase = "Backswing";
    });

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
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAppBar(context),
              const SizedBox(height: 24),
              _buildCameraPreview(),
              const SizedBox(height: 24),
              _buildWeightCards(),
              const SizedBox(height: 24),
              if (_showHeatmap) ...[
                _buildHeatmapSection(),
                const SizedBox(height: 24),
              ],
              _buildChartCard(),
              const SizedBox(height: 24),
              _buildRecordButton(),
              const SizedBox(height: 20),
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
                if (snapshot.connectionState == ConnectionState.done) {
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
              color: AppColors.secondary,
              side: 'L',
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
              color: AppColors.primary,
              side: 'R',
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildChartCard() => Container(
    height: 320,
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
                color: AppColors.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.show_chart, color: AppColors.secondary, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Balance Analysis',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _LegendItem(label: 'Left', color: AppColors.secondary),
            const SizedBox(width: 16),
            _LegendItem(label: 'Right', color: AppColors.primary),
          ],
        ),
        const SizedBox(height: 24),
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
        const SizedBox(height: 24),
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
                  const SizedBox(height: 12),
                  const Text(
                    'LEFT',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                children: [
                  FootHeatmap(
                    pressureData: _rightFootPressure,
                    isLeftFoot: false,
                    onTap: () => _updateHeatmapData(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'RIGHT',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
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
                _buildHeatmapLegendItem('Medium', Colors.yellow),
                const SizedBox(width: 12),
                _buildHeatmapLegendItem('High', Colors.orange),
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

  Widget _buildRecordButton() => Container(
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
        onPressed: _isSwinging ? null : _simulateSwing,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Icon(
            _isSwinging ? Icons.hourglass_top : Icons.play_circle_fill,
            size: 28,
            key: ValueKey(_isSwinging),
          ),
        ),
        label: Text(
          _isSwinging ? 'RECORDING SWING...' : 'START RECORDING',
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

  LineChartData _buildChartData() {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1, dashArray: [5, 5]),
        getDrawingVerticalLine: (value) =>
            FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1, dashArray: [5, 5]),
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
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            reservedSize: 40,
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: _graphXValue - 2,
      maxX: _graphXValue,
      minY: 0,
      maxY: 100,
      lineBarsData: [
        _createLineChartBarData(_leftDataPoints, AppColors.secondary),
        _createLineChartBarData(_rightDataPoints, AppColors.primary),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (touchedSpot) => AppColors.surfaceLight.withOpacity(0.9),
        ),
      ),
    );
  }

  LineChartBarData _createLineChartBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
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
