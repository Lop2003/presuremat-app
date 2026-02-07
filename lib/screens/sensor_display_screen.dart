import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/sensor_data_service.dart';
import '../services/serial_service.dart';
import 'sensor_playback_screen.dart' as playback;

class SensorDisplayScreen extends StatefulWidget {
  const SensorDisplayScreen({super.key});

  @override
  State<SensorDisplayScreen> createState() => _SensorDisplayScreenState();
}

class _SensorDisplayScreenState extends State<SensorDisplayScreen> {
  // Use shared SerialService singleton
  final SerialService _serialService = SerialService();
  StreamSubscription<List<int>>? _dataSubscription;
  
  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isConnected = false;
  List<SensorData> _sensorDataList = [];

  // Store sensor data for each point (now 8x8 grid for 64 sensors)
  List<List<int>> _sensorGrid = List.generate(8, (i) => List.filled(8, 0));

  // Database related variables
  final SensorDataService _sensorDataService = SensorDataService();
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isRecording = false;
  String? _currentSessionId;
  List<SensorReading> _pendingSensorReadings = [];

  @override
  void initState() {
    super.initState();
    _refreshPorts();
    _restoreConnection();
  }
  
  void _restoreConnection() {
    // Restore connection state from singleton
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
    _dataSubscription = _serialService.dataStream.listen(_handleSensorData);
  }

  @override
  void dispose() {
    _dataSubscription?.cancel(); // Only cancel subscription, don't disconnect
    super.dispose();
  }

  void _refreshPorts() {
    setState(() {
      _availablePorts = _serialService.getAvailablePorts();
    });
  }

  Future<void> _connectToPort() async {
    if (_selectedPort == null) return;

    try {
      await _serialService.connect(_selectedPort!);
      
      setState(() {
        _isConnected = true;
      });
      
      _subscribeToData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เชื่อมต่อกับ $_selectedPort สำเร็จ')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  Future<void> _disconnectFromPort() async {
    // หยุดการบันทึกก่อนถ้ากำลังบันทึกอยู่
    if (_isRecording) {
      await _stopRecording();
    }

    _dataSubscription?.cancel();
    await _serialService.disconnect();

    // ตรวจสอบว่า widget ยังไม่ถูก dispose
    if (mounted) {
      setState(() {
        _isConnected = false;
        _sensorDataList.clear();
        _sensorGrid = List.generate(8, (i) => List.filled(8, 0));
      });
    }
  }
  
  // Handle incoming 64-sensor data from SerialService
  void _handleSensorData(List<int> sensors) {
    if (!mounted) return;
    
    setState(() {
      // Update 8x8 grid (64 sensors)
      for (int i = 0; i < 8 && i < sensors.length ~/ 8; i++) {
        for (int j = 0; j < 8; j++) {
          int index = i * 8 + j;
          if (index < sensors.length) {
            _sensorGrid[i][j] = sensors[index];
          }
        }
      }
      
      // Add to data list for display
      final timestamp = DateTime.now();
      // Just log total pressure for real-time view
      int totalPressure = sensors.fold(0, (sum, val) => sum + val);
      _sensorDataList.insert(
        0,
        SensorData(row: 0, col: 0, value: totalPressure, timestamp: timestamp),
      );
      
      if (_sensorDataList.length > 100) {
        _sensorDataList.removeRange(100, _sensorDataList.length);
      }
    });
    
    // Record if recording is active
    if (_isRecording && _currentSessionId != null) {
      // For now, just record summary data
      _pendingSensorReadings.add(
        SensorReading(
          row: 0,
          col: 0,
          value: sensors.fold(0, (sum, val) => sum + val),
          timestamp: DateTime.now(),
          sessionId: _currentSessionId!,
        ),
      );
      
      if (_pendingSensorReadings.length >= 10) {
        _savePendingReadings();
      }
    }
  }

  // เริ่มบันทึกข้อมูล
  Future<void> _startRecording() async {
    try {
      // ตรวจสอบว่า user login แล้วหรือยัง
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณา Login ก่อนบันทึกข้อมูล')),
          );
        }
        return;
      }

      final sessionId = await _sensorDataService.createSession(
        title: 'Sensor Session ${DateTime.now().toString().substring(0, 19)}',
        description: 'Real-time sensor data recording',
      );

      setState(() {
        _isRecording = true;
        _currentSessionId = sessionId;
        _pendingSensorReadings.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('เริ่มบันทึกข้อมูลแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการเริ่มบันทึก: $e')),
        );
      }
    }
  }

  // หยุดบันทึกข้อมูล
  Future<void> _stopRecording() async {
    if (!_isRecording || _currentSessionId == null) return;

    try {
      // บันทึกข้อมูลที่ค้างอยู่
      if (_pendingSensorReadings.isNotEmpty) {
        await _sensorDataService.saveSensorReadingsBatch(
          _pendingSensorReadings,
        );
      }

      // อัพเดท session ว่าสิ้นสุดแล้ว
      await _sensorDataService.endSession(
        _currentSessionId!,
        _pendingSensorReadings.length, // This might need accumulation in updated logic if batch cleared
      );

      setState(() {
        _isRecording = false;
        _currentSessionId = null;
        _pendingSensorReadings.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('หยุดบันทึกข้อมูลแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการหยุดบันทึก: $e')),
        );
      }
    }
  }

  // Old methods removed - now using _handleSensorData(List<int>) from SerialService stream

  // บันทึกข้อมูลที่ค้างอยู่ลง database
  Future<void> _savePendingReadings() async {
    if (_pendingSensorReadings.isEmpty) return;

    try {
      final readingsToSave = List<SensorReading>.from(_pendingSensorReadings);
      _pendingSensorReadings.clear();

      await _sensorDataService.saveSensorReadingsBatch(readingsToSave);
    } catch (e) {
      print('Error saving pending readings: $e');
      // ถ้าบันทึกไม่สำเร็จ ให้เอาข้อมูลกลับไป
      // (ในการใช้งานจริงอาจจะต้องมี retry mechanism)
    }
  }

  Color _getColorFromValue(int value) {
    if (value == 0) return Colors.grey[300]!;

    // สร้างสีตามความเข้มของค่า (0-4095 สำหรับ 12-bit ADC)
    double intensity = (value / 4095.0).clamp(0.0, 1.0);
    return Color.lerp(Colors.green[200], Colors.red[800], intensity)!;
  }

  // แสดง dialog สำหรับดูข้อมูลที่บันทึกไว้
  void _showSavedDataDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ข้อมูลที่บันทึกไว้',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _sensorDataService.getSessions(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Text('ยังไม่มีข้อมูลที่บันทึกไว้'),
                        );
                      }

                      final sessions = snapshot.data!;

                      return ListView.builder(
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final data = sessions[index];
                          final id = data['id'] as String;

                          return Card(
                            child: ListTile(
                              title: Text(
                                data['title'] ?? 'Untitled Session',
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (data['description'] != null &&
                                      data['description'].toString().isNotEmpty)
                                    Text(
                                      data['description'].toString(),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  Text(
                                    'Total: ${data['total_readings'] ?? 0}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Status: ${data['is_active'] == true ? 'Active' : 'Done'}',
                                    style: TextStyle(
                                      color: data['is_active'] == true
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.visibility),
                                    onPressed: () =>
                                        _showSessionDetails(id),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _deleteSession(id),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // แสดงรายละเอียดของ session โดยไปยังหน้า playback
  void _showSessionDetails(String sessionId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => playback.SensorPlaybackScreen(
          sessionId: sessionId,
          sessionTitle: 'Sensor Session',
        ),
      ),
    );
  }

  // ลบ session
  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: const Text(
            'คุณแน่ใจหรือไม่ว่าต้องการลบข้อมูลนี้? การดำเนินการนี้ไม่สามารถยกเลิกได้',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _sensorDataService.deleteSession(sessionId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ลบข้อมูลสำเร็จ')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาดในการลบข้อมูล: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Display'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => _showSavedDataDialog(),
            tooltip: 'ดูข้อมูลที่บันทึกไว้',
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshPorts),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ส่วนเลือก Port และเชื่อมต่อ
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Serial Port Connection',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            hint: const Text('เลือก Port'),
                            value: _selectedPort,
                            isExpanded: true,
                            items: _availablePorts.map((port) {
                              return DropdownMenuItem(
                                value: port,
                                child: Text(
                                  port,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: _isConnected
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedPort = value;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: _isConnected
                              ? _disconnectFromPort
                              : _connectToPort,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isConnected
                                ? Colors.red
                                : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_isConnected ? 'Disconnect' : 'Connect'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: ${_isConnected ? 'Connected' : 'Disconnected'}',
                      style: TextStyle(
                        color: _isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    // ปุ่มสำหรับเริ่ม/หยุดการบันทึก
                    if (_isConnected) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isRecording
                                  ? _stopRecording
                                  : _startRecording,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isRecording
                                    ? Colors.orange
                                    : Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              icon: Icon(
                                _isRecording
                                    ? Icons.stop
                                    : Icons.fiber_manual_record,
                              ),
                              label: Text(
                                _isRecording ? 'หยุดบันทึก' : 'เริ่มบันทึก',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Recording: ${_isRecording ? 'ON' : 'OFF'}${_isRecording ? ' (${_pendingSensorReadings.length} pending)' : ''}',
                        style: TextStyle(
                          color: _isRecording ? Colors.blue : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ส่วนแสดง Sensor Grid
            if (_isConnected) ...[
              Text(
                'Sensor Grid (8x8)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 8,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2,
                          ),
                      itemCount: 64,
                      itemBuilder: (context, index) {
                        int row = index ~/ 8;
                        int col = index % 8;
                        int value = _sensorGrid[row][col];

                        return Container(
                          decoration: BoxDecoration(
                            color: _getColorFromValue(value),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              value.toString(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ส่วนแสดงข้อมูลแบบ Real-time
              Text(
                'Real-time Data',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 300, // กำหนดความสูงคงที่
                child: Card(
                  child: _sensorDataList.isEmpty
                      ? const Center(
                          child: Text(
                            'รอข้อมูลจาก Sensor...',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _sensorDataList.length,
                          itemBuilder: (context, index) {
                            final data = _sensorDataList[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getColorFromValue(data.value),
                                child: Text(
                                  '${data.row},${data.col}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text('Value: ${data.value}'),
                              subtitle: Text(
                                'Pos: (${data.row}, ${data.col}) - ${data.timestamp.toString().substring(11, 19)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SensorData {
  final int row;
  final int col;
  final int value;
  final DateTime timestamp;

  SensorData({
    required this.row,
    required this.col,
    required this.value,
    required this.timestamp,
  });
}
