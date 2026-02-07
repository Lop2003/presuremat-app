import 'package:supabase_flutter/supabase_flutter.dart';

class SensorDataService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _readingsTable = 'sensor_readings';
  final String _sessionsTable = 'sensor_sessions';

  /// บันทึกข้อมูล sensor reading เดี่ยว
  Future<void> saveSensorReading({
    required int row,
    required int col,
    required int value,
    required DateTime timestamp,
    String? sessionId,
  }) async {
    try {
      await _supabase.from(_readingsTable).insert({
        'row_index': row,
        'col_index': col,
        'value': value,
        'timestamp': timestamp.toIso8601String(),
        'session_id': sessionId,
      });
    } catch (e) {
      print('Error saving sensor reading: $e');
      rethrow;
    }
  }

  /// บันทึกข้อมูล sensor readings หลายๆ ตัวในครั้งเดียว (batch)
  Future<void> saveSensorReadingsBatch(List<SensorReading> readings) async {
    try {
      final List<Map<String, dynamic>> data = readings.map((r) => r.toMap()).toList();
      await _supabase.from(_readingsTable).insert(data);
    } catch (e) {
      print('Error saving sensor readings batch: $e');
      rethrow;
    }
  }

  /// สร้าง session ใหม่สำหรับการบันทึกข้อมูล
  Future<String> createSession({String? title, String? description}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final response = await _supabase.from(_sessionsTable).insert({
        'user_id': user.id,
        'title': title ?? 'Sensor Session ${DateTime.now().toString()}',
        'description': description ?? '',
        'start_time': DateTime.now().toIso8601String(),
        'total_readings': 0,
        'is_active': true,
      }).select().single();

      return response['id'] as String;
    } catch (e) {
      print('Error creating session: $e');
      rethrow;
    }
  }

  /// อัพเดท session เมื่อสิ้นสุดการบันทึก
  Future<void> endSession(String sessionId, int totalReadings) async {
    try {
      await _supabase.from(_sessionsTable).update({
        'end_time': DateTime.now().toIso8601String(),
        'total_readings': totalReadings,
        'is_active': false,
      }).eq('id', sessionId);
    } catch (e) {
      print('Error ending session: $e');
      rethrow;
    }
  }

  /// ดึงข้อมูล sessions ทั้งหมด (Realtime)
  Stream<List<Map<String, dynamic>>> getSessions() {
    return _supabase
        .from(_sessionsTable)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((event) => event);
  }

  /// ดึงข้อมูล sensor readings ของ session เฉพาะ (Realtime)
  Stream<List<Map<String, dynamic>>> getSensorReadings(String sessionId) {
    return _supabase
        .from(_readingsTable)
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('timestamp', ascending: false)
        .map((event) => event);
  }

  /// ลบ session (Cascade delete will handle readings if configured, otherwise delete manually)
  Future<void> deleteSession(String sessionId) async {
    try {
      // Assuming ON DELETE CASCADE is set in Supabase schema for foreign key
      await _supabase.from(_sessionsTable).delete().eq('id', sessionId);
    } catch (e) {
      print('Error deleting session: $e');
      rethrow;
    }
  }
}

class SensorReading {
  final int row;
  final int col;
  final int value;
  final DateTime timestamp;
  final String sessionId;

  SensorReading({
    required this.row,
    required this.col,
    required this.value,
    required this.timestamp,
    required this.sessionId,
  });

  Map<String, dynamic> toMap() {
    return {
      'row_index': row,
      'col_index': col,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'session_id': sessionId,
    };
  }
}
