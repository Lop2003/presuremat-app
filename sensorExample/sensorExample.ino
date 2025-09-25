// กำหนดขา GPIO ของ ESP32 สำหรับแถว (แนวนอน)
const byte rowPins[] = {13, 12, 14};
// กำหนดขา GPIO ของ ESP32 สำหรับคอลัมน์ (แนวตั้ง)
const byte colPins[] = {27, 26, 25};

// จำนวนแถวและคอลัมน์
const int ROWS = sizeof(rowPins) / sizeof(rowPins[0]);
const int COLS = sizeof(colPins) / sizeof(colPins[0]);

// กำหนดค่า Threshold
const int THRESHOLD = 100;

void setup() {
  Serial.begin(115200);

  // กำหนดขาแถว (แนวนอน) เป็น Output และกำหนดค่าเริ่มต้นเป็น LOW
  for (int i = 0; i < ROWS; i++) {
    pinMode(rowPins[i], OUTPUT);
    digitalWrite(rowPins[i], LOW);
  }

  // ตั้งค่าความละเอียดของ ADC
  analogReadResolution(12);
}

void loop() {
  // วนลูปเพื่อสแกนทีละแถว
  for (int r = 0; r < ROWS; r++) {
    // จ่ายไฟ (HIGH) ให้กับแถวปัจจุบันที่กำลังจะสแกน
    digitalWrite(rowPins[r], HIGH);

    // วนลูปเพื่ออ่านค่าจากทุกคอลัมน์
    for (int c = 0; c < COLS; c++) {
      int analogValue = analogRead(colPins[c]);

      // ถ้าค่าที่อ่านได้เกินค่า Threshold ให้ส่งข้อมูลไปยัง Serial
      if (analogValue > THRESHOLD) {
        Serial.print(r);
        Serial.print(",");
        Serial.print(c);
        Serial.print(",");
        Serial.println(analogValue);
        // ดีเลย์เพื่อป้องกันการอ่านค่าซ้ำ (Debouncing)
        delay(200);
      }
    }

    // หยุดจ่ายไฟ (LOW) ให้กับแถวปัจจุบัน
    digitalWrite(rowPins[r], LOW);
  }
}