import 'package:flutter/material.dart';
import 'dart:async';
import '../services/serial_service.dart';

class SensorDisplayScreen extends StatefulWidget {
  const SensorDisplayScreen({super.key});

  @override
  State<SensorDisplayScreen> createState() => _SensorDisplayScreenState();
}

class _SensorDisplayScreenState extends State<SensorDisplayScreen>
    with SingleTickerProviderStateMixin {
  final SerialService _serialService = SerialService();
  StreamSubscription<List<int>>? _dataSubscription;

  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _sensorCount = 0; // live packet counter
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _refreshPorts();
    _restoreConnection();
  }

  void _restoreConnection() {
    if (_serialService.isConnected) {
      setState(() {
        _isConnected = true;
        _selectedPort = _serialService.connectedPort;
      });
      _subscribeToData();
    }
  }

  void _subscribeToData() {
    _dataSubscription?.cancel();
    _dataSubscription = _serialService.dataStream.listen((data) {
      if (mounted) setState(() => _sensorCount++);
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _refreshPorts() {
    setState(() {
      _availablePorts = _serialService.getAvailablePorts();
    });
  }

  Future<void> _connectToPort() async {
    if (_selectedPort == null) return;
    setState(() => _isConnecting = true);

    try {
      await _serialService.connect(_selectedPort!);
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _sensorCount = 0;
      });
      _subscribeToData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Connected to $_selectedPort'),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Connection failed: $e')),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _disconnectFromPort() async {
    _dataSubscription?.cancel();
    await _serialService.disconnect();
    setState(() {
      _isConnected = false;
      _sensorCount = 0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.link_off, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Disconnected'),
            ],
          ),
          backgroundColor: Colors.grey[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Sensor Connection',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.refresh, color: Colors.white70, size: 18),
            ),
            onPressed: _refreshPorts,
            tooltip: 'Refresh Ports',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // Status Icon
              _buildStatusIcon(),
              const SizedBox(height: 24),

              // Status Text
              Text(
                _isConnected
                    ? 'Connected'
                    : _isConnecting
                        ? 'Connecting...'
                        : 'Not Connected',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _isConnected
                      ? const Color(0xFF10B981)
                      : _isConnecting
                          ? Colors.amber
                          : Colors.white70,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isConnected
                    ? 'Receiving data from $_selectedPort'
                    : 'Select a serial port to connect your force plate',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Connection Card
              _buildConnectionCard(),
              const SizedBox(height: 16),

              // Live stats when connected
              if (_isConnected) _buildLiveStatsCard(),
              
              const SizedBox(height: 24),

              // Action Hint
              if (_isConnected)
                _buildHintCard(
                  Icons.arrow_back,
                  'Go back to Dashboard to see live data',
                  const Color(0xFF3B82F6),
                )
              else if (_availablePorts.isEmpty)
                _buildHintCard(
                  Icons.usb_off,
                  'No ports detected. Check your USB connection and tap refresh.',
                  Colors.amber,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = _isConnecting
            ? 1.0 + _pulseController.value * 0.1
            : 1.0;
        final glowOpacity = _isConnected
            ? 0.3
            : _isConnecting
                ? _pulseController.value * 0.4
                : 0.1;

        return Transform.scale(
          scale: scale,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected
                  ? const Color(0xFF10B981).withOpacity(0.15)
                  : _isConnecting
                      ? Colors.amber.withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
              boxShadow: [
                BoxShadow(
                  color: (_isConnected
                          ? const Color(0xFF10B981)
                          : _isConnecting
                              ? Colors.amber
                              : Colors.white24)
                      .withOpacity(glowOpacity),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              _isConnected
                  ? Icons.sensors
                  : _isConnecting
                      ? Icons.sync
                      : Icons.sensors_off,
              size: 44,
              color: _isConnected
                  ? const Color(0xFF10B981)
                  : _isConnecting
                      ? Colors.amber
                      : Colors.white38,
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1E293B),
        border: Border.all(
          color: _isConnected
              ? const Color(0xFF10B981).withOpacity(0.3)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Port Label
          Text(
            'Serial Port',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.5),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),

          // Port Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                hint: Text(
                  _availablePorts.isEmpty ? 'No ports available' : 'Select Port',
                  style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 14),
                ),
                value: _selectedPort,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E293B),
                icon: Icon(
                  Icons.unfold_more,
                  color: Colors.white.withOpacity(0.4),
                  size: 20,
                ),
                items: _availablePorts.map((port) {
                  return DropdownMenuItem(
                    value: port,
                    child: Row(
                      children: [
                        Icon(Icons.usb, color: Colors.cyanAccent.withOpacity(0.6), size: 16),
                        const SizedBox(width: 10),
                        Text(port, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: _isConnected
                    ? null
                    : (value) => setState(() => _selectedPort = value),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Connect / Disconnect Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isConnecting
                  ? null
                  : _isConnected
                      ? _disconnectFromPort
                      : (_selectedPort != null ? _connectToPort : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isConnected
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF10B981),
                disabledBackgroundColor: Colors.white.withOpacity(0.08),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isConnecting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isConnected ? Icons.link_off : Icons.power,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isConnected ? 'Disconnect' : 'Connect',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatsCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF1E293B),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.15)),
      ),
      child: Row(
        children: [
          _buildStatItem(
            icon: Icons.usb,
            label: 'Port',
            value: _selectedPort ?? '—',
            color: Colors.cyanAccent,
          ),
          _buildDivider(),
          _buildStatItem(
            icon: Icons.speed,
            label: 'Packets',
            value: _formatCount(_sensorCount),
            color: const Color(0xFF10B981),
          ),
          _buildDivider(),
          _buildStatItem(
            icon: Icons.circle,
            label: 'Status',
            value: 'Live',
            color: const Color(0xFF10B981),
            showPulse: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool showPulse = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color.withOpacity(0.7), size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 36,
      color: Colors.white.withOpacity(0.06),
    );
  }

  Widget _buildHintCard(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.withOpacity(0.7), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
