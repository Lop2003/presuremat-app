import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:golf_force_plate/screens/auth_screen.dart';
import 'package:golf_force_plate/screens/main_screen.dart';
import 'package:golf_force_plate/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // หน่วงเวลาเล็กน้อยเพื่อให้ Animation แสดงผล (ในโปรดักชั่นจริงๆ อาจเช็ค snapshot ตรงๆ ได้เลย)
          // แต่เพื่อความสวยงาม เราจะใช้ Future.delayed ในการ navigate หากโหลดเสร็จเร็วเกินไป
          if (snapshot.connectionState == ConnectionState.active) {
             Future.delayed(const Duration(milliseconds: 2000), () {
               if (context.mounted) {
                 Navigator.of(context).pushReplacement(
                   MaterialPageRoute(
                     builder: (_) => snapshot.hasData ? const MainScreen() : const AuthScreen(),
                   ),
                 );
               }
             });
          }

          return Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDark,
                            border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.2),
                                blurRadius: 30,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.sports_golf,
                            size: 64,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Golf Force Plate',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Professional Balance Analytics',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 48),
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
