import 'package:cloud_firestore/cloud_firestore.dart';

class SensorDataService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'sensor_readings';

  /// บันทึกข้อมูล sensor reading เดี่ยว
  Future<void> saveSensorReading({
    required int row,
    required int col,
    required int value,
    required DateTime timestamp,
    String? sessionId,
  }) async {
    try {
      await _firestore.collection(_collection).add({
        'row': row,
        'col': col,
        'value': value,
        'timestamp': Timestamp.fromDate(timestamp),
        'sessionId': sessionId ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving sensor reading: $e');
      rethrow;
    }
  }

  /// บันทึกข้อมูล sensor readings หลายๆ ตัวในครั้งเดียว (batch)
  Future<void> saveSensorReadingsBatch(List<SensorReading> readings) async {
    try {
      final batch = _firestore.batch();

      for (final reading in readings) {
        final docRef = _firestore.collection(_collection).doc();
        batch.set(docRef, {
          'row': reading.row,
          'col': reading.col,
          'value': reading.value,
          'timestamp': Timestamp.fromDate(reading.timestamp),
          'sessionId': reading.sessionId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e) {
      print('Error saving sensor readings batch: $e');
      rethrow;
    }
  }

  /// สร้าง session ใหม่สำหรับการบันทึกข้อมูล
  Future<String> createSession({String? title, String? description}) async {
    try {
      final sessionDoc = await _firestore.collection('sensor_sessions').add({
        'title': title ?? 'Sensor Session ${DateTime.now().toString()}',
        'description': description ?? '',
        'startTime': FieldValue.serverTimestamp(),
        'endTime': null,
        'totalReadings': 0,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return sessionDoc.id;
    } catch (e) {
      print('Error creating session: $e');
      rethrow;
    }
  }

  /// อัพเดท session เมื่อสิ้นสุดการบันทึก
  Future<void> endSession(String sessionId, int totalReadings) async {
    try {
      await _firestore.collection('sensor_sessions').doc(sessionId).update({
        'endTime': FieldValue.serverTimestamp(),
        'totalReadings': totalReadings,
        'isActive': false,
      });
    } catch (e) {
      print('Error ending session: $e');
      rethrow;
    }
  }

  /// ดึงข้อมูล sessions ทั้งหมด
  Stream<QuerySnapshot> getSessions() {
    return _firestore
        .collection('sensor_sessions')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// ดึงข้อมูล sensor readings ของ session เฉพาะ
  Stream<QuerySnapshot> getSensorReadings(String sessionId) {
    return _firestore
        .collection(_collection)
        .where('sessionId', isEqualTo: sessionId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// ลบ session และข้อมูลที่เกี่ยวข้อง
  Future<void> deleteSession(String sessionId) async {
    try {
      final batch = _firestore.batch();

      // ลบ session document
      batch.delete(_firestore.collection('sensor_sessions').doc(sessionId));

      // ลบ sensor readings ที่เกี่ยวข้อง
      final readings = await _firestore
          .collection(_collection)
          .where('sessionId', isEqualTo: sessionId)
          .get();

      for (final doc in readings.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
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
      'row': row,
      'col': col,
      'value': value,
      'timestamp': Timestamp.fromDate(timestamp),
      'sessionId': sessionId,
    };
  }
}
