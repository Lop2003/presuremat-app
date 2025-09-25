import 'dart:io';
import 'dart:math';

void main() async {
  print('Starting sensor simulator...');
  print('This will send random sensor data every 500ms');
  print('Press Ctrl+C to stop');
  
  final random = Random();
  
  while (true) {
    // สุ่มตำแหน่ง sensor (0-2, 0-2)
    int row = random.nextInt(3);
    int col = random.nextInt(3);
    
    // สุ่มค่า sensor (100-1000 เพราะ threshold คือ 100)
    int value = 100 + random.nextInt(900);
    
    // ส่งข้อมูลในรูปแบบ "row,col,value"
    print('$row,$col,$value');
    
    // รอ 500ms
    await Future.delayed(Duration(milliseconds: 500));
  }
}