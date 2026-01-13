import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:golf_force_plate/theme.dart'; // Import theme
import 'package:google_sign_in/google_sign_in.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:golf_force_plate/screens/main_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = true;
  String _userEmail = '';
  String _userPassword = '';
  String _userName = '';
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _trySubmit() async {
    final isValid = _formKey.currentState!.validate();
    FocusScope.of(context).unfocus();

    if (isValid) {
      setState(() => _isLoading = true);
      _formKey.currentState!.save();
      UserCredential userCredential;

      try {
        if (_isLogin) {
          userCredential = await FirebaseAuth.instance
              .signInWithEmailAndPassword(
                email: _userEmail,
                password: _userPassword,
              );
        } else {
          userCredential = await FirebaseAuth.instance
              .createUserWithEmailAndPassword(
                email: _userEmail,
                password: _userPassword,
              );

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({'username': _userName, 'email': _userEmail});
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account created successfully!'),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        
        if (mounted) {
           Navigator.of(context).pushReplacement(
             MaterialPageRoute(builder: (context) => const MainScreen()),
           );
        }
      } on FirebaseAuthException catch (err) {
        var message = 'An error occurred, please check your credentials!';
        if (err.message != null) {
          message = err.message!;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } catch (err) {
        print(err);
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google Sign-In is not available on desktop. Please use Email/Password login.',
              ),
              backgroundColor: AppColors.accent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);

      if (userCredential.additionalUserInfo?.isNewUser == true) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
              'username': googleUser.displayName ?? 'Google User',
              'email': googleUser.email,
              'photoUrl': googleUser.photoUrl,
            });
      }
      
      if (mounted) {
         Navigator.of(context).pushReplacement(
           MaterialPageRoute(builder: (context) => const MainScreen()),
         );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google Sign-In failed: ${error.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithDemoAccount() async {
    setState(() => _isLoading = true);

    const demoEmail = 'demo@golfforceplate.com';
    const demoPassword = 'demo123456';

    try {
      UserCredential userCredential;
      try {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: demoEmail,
          password: demoPassword,
        );
      } catch (e) {
        userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: demoEmail,
              password: demoPassword,
            );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
              'username': 'Demo User',
              'email': demoEmail,
              'photoUrl': null,
            });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demo account signed in successfully!'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pushReplacement(
           MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Demo sign-in failed: ${error.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundDark,
              AppColors.backgroundDark.withBlue(30),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.2),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: const Icon(
                        Icons.sports_golf,
                        size: 60,
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
                    const SizedBox(height: 8),
                    Text(
                      'Analyze your golf swing balance',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 48),

                    Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundDark,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.all(4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _isLogin = true),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _isLogin
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            'Login',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: _isLogin
                                                  ? Colors.white
                                                  : Colors.white54,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () =>
                                            setState(() => _isLogin = false),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: !_isLogin
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            'Sign Up',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: !_isLogin
                                                  ? Colors.white
                                                  : Colors.white54,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),

                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: !_isLogin ? 100 : 0,
                                clipBehavior: Clip.antiAlias,
                                decoration: const BoxDecoration(),
                                child: SingleChildScrollView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: !_isLogin
                                      ? Column(
                                          children: [
                                            _buildTextField(
                                              key: 'username',
                                              label: 'Username',
                                              icon: Icons.person_outline,
                                              validator: (value) {
                                                if (value!.isEmpty ||
                                                    value.length < 4) {
                                                  return '4+ chars required.';
                                                }
                                                return null;
                                              },
                                              onSaved: (value) =>
                                                  _userName = value!,
                                            ),
                                            const SizedBox(height: 16),
                                          ],
                                        )
                                      : null,
                                ),
                              ),

                              _buildTextField(
                                key: 'email',
                                label: 'Email Address',
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value!.isEmpty || !value.contains('@')) {
                                    return 'Invalid email.';
                                  }
                                  return null;
                                },
                                onSaved: (value) => _userEmail = value!,
                              ),
                              const SizedBox(height: 16),

                              _buildTextField(
                                key: 'password',
                                label: 'Password',
                                icon: Icons.lock_outline,
                                obscureText: true,
                                validator: (value) {
                                  if (value!.isEmpty || value.length < 7) {
                                    return '7+ chars required.';
                                  }
                                  return null;
                                },
                                onSaved: (value) => _userPassword = value!,
                              ),
                              const SizedBox(height: 24),

                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: Colors.white.withOpacity(0.1),
                                      thickness: 1,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: Colors.white.withOpacity(0.1),
                                      thickness: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              SizedBox(
                                height: 56,
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : _signInWithGoogle,
                                  icon: const FaIcon(
                                    FontAwesomeIcons.google,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    'Sign in with Google',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              if (!kIsWeb &&
                                  (Platform.isWindows ||
                                      Platform.isLinux ||
                                      Platform.isMacOS))
                                SizedBox(
                                  height: 56,
                                  child: OutlinedButton.icon(
                                    onPressed: _isLoading
                                        ? null
                                        : _signInWithDemoAccount,
                                    icon: const Icon(
                                      Icons.person,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                    label: const Text(
                                      'Sign in with Demo Account',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      side: const BorderSide(
                                        color: AppColors.primary,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 24),

                              SizedBox(
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _trySubmit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 8,
                                    shadowColor: AppColors.primary.withOpacity(0.4),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _isLogin ? 'Login' : 'Create Account',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      _isLogin
                          ? 'New to Golf Force Plate?'
                          : 'Already have an account?',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLogin = !_isLogin;
                        });
                      },
                      child: Text(
                        _isLogin ? 'Create Account' : 'Login Instead',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String key,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
    void Function(String?)? onSaved,
  }) {
    return TextFormField(
      key: ValueKey(key),
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onSaved: onSaved,
      style: const TextStyle(fontSize: 16, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.6), size: 22),
        fillColor: AppColors.backgroundDark.withOpacity(0.5),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
