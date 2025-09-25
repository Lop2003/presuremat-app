import 'dart:math';

/// สคริปต์สำหรับจำลองข้อมูล sensor ESP32
/// จะส่งข้อมูลในรูปแบบ "row,col,value" ทุกๆ 500ms
/// ใช้สำหรับทดสอบแอป Flutter โดยไม่ต้องมี ESP32 จริง

void main() async {
  print('🚀 Starting ESP32 Sensor Simulator...');
  print('📡 Format: row,col,value');
  print('⏱️  Interval: 500ms');
  print('🛑 Press Ctrl+C to stop');
  print('=' * 50);

  final random = Random();
  int sequenceNumber = 0;

  // จำลองการทำงานของ sensor ที่มีการเปลี่ยนแปลงตามเวลา
  while (true) {
    sequenceNumber++;

    // สุ่มจำนวน sensor ที่จะส่งข้อมูลในรอบนี้ (1-3 sensors)
    int activeSensors = 1 + random.nextInt(3);

    for (int i = 0; i < activeSensors; i++) {
      // สุ่มตำแหน่ง sensor (0-2, 0-2)
      int row = random.nextInt(3);
      int col = random.nextInt(3);

      // สุ่มค่า sensor โดยมี pattern ที่สมจริงมากขึ้น
      int baseValue = 150 + random.nextInt(800); // 150-950

      // เพิ่ม noise เล็กน้อย
      int noise = random.nextInt(50) - 25;
      int value = (baseValue + noise).clamp(100, 4095);

      // ส่งข้อมูลในรูปแบบ "row,col,value"
      print('$row,$col,$value');

      // ดีเลย์เล็กน้อยระหว่าง sensor ในรอบเดียวกัน
      if (i < activeSensors - 1) {
        await Future.delayed(Duration(milliseconds: 50));
      }
    }

    // แสดง debug info ทุกๆ 10 รอบ
    if (sequenceNumber % 10 == 0) {
      print('// Sequence: $sequenceNumber, Active sensors: $activeSensors');
    }

    // รอ 500ms ก่อนรอบถัดไป
    await Future.delayed(Duration(milliseconds: 500));
  }
}

/// ฟังก์ชันสำหรับจำลองแรงกดจากเท้า
/// จะสร้าง pattern ที่เหมือนการกดจริงๆ
List<MapEntry<String, int>> simulateFootPressure() {
  final random = Random();
  final List<MapEntry<String, int>> pressurePoints = [];

  // จำลอง pressure points ที่เป็นไปได้จากการยืน/เดิน
  final List<List<int>> footPattern = [
    [0, 1], // นิ้วเท้า
    [1, 1], // ฝ่าเท้ากลาง
    [2, 0], [2, 1], [2, 2], // ส้นเท้า
  ];

  // เลือก 1-3 จุดจาก pattern
  int numPoints = 1 + random.nextInt(3);

  for (int i = 0; i < numPoints; i++) {
    final point = footPattern[random.nextInt(footPattern.length)];
    final value = 200 + random.nextInt(600); // 200-800
    pressurePoints.add(MapEntry('${point[0]},${point[1]}', value));
  }

  return pressurePoints;
}
