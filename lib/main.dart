import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:golf_force_plate/screens/splash_screen.dart';
import 'package:golf_force_plate/theme.dart';

void main() async {
  // ตรวจสอบให้แน่ใจว่า Flutter ทำงานพร้อมแล้ว
  WidgetsFlutterBinding.ensureInitialized();
  // เริ่มต้นการเชื่อมต่อกับ Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const GolfForcePlateApp());
}

class GolfForcePlateApp extends StatelessWidget {
  const GolfForcePlateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Golf Force Plate',
      theme: appTheme,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
