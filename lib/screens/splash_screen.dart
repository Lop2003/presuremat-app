import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:golf_force_plate/screens/auth_screen.dart';
import 'package:golf_force_plate/screens/main_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ขณะกำลังรอตรวจสอบสถานะ
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // ถ้ามีข้อมูลผู้ใช้ (ล็อกอินอยู่)
        if (snapshot.hasData) {
          return const MainScreen();
        }
        // ถ้าไม่มีข้อมูลผู้ใช้
        return const AuthScreen();
      },
    );
  }
}
