import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:golf_force_plate/screens/splash_screen.dart';
import 'package:golf_force_plate/theme.dart';

void main() async {
  // ตรวจสอบให้แน่ใจว่า Flutter ทำงานพร้อมแล้ว
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");

  // เริ่มต้นการเชื่อมต่อกับ Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
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
