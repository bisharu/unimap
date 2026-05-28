import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'homescreen.dart';
import 'profile_screens.dart';
import 'utils.dart';
import 'dart:ui' as ui;

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isObscure = true;

  String? _validateId(String id) => UniUtils.validateStudentId(id);

  Future<void> _handleLogin() async {
    final id = _idController.text.trim().toUpperCase();
    final password = _passwordController.text;

    if (id.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter ID and password')),
      );
      return;
    }

    // Custom ID Validation
    final idError = _validateId(id);
    if (idError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(idError)),
      );
      return;
    }

    // Password Mix Validation
    if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)').hasMatch(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must contain both letters and numbers')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Look up the email associated with this Student ID in Firestore
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('studentId', isEqualTo: id)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No account found for this ID')),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      final realEmail = userQuery.docs.first.data()['email'];

      // 2. Sign in with the real email
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: realEmail,
        password: password,
      );

            if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Invalid ID or password';
      if (e.code == 'user-not-found') {
        message = 'No account found for this ID';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFF1B1832), // Dark purple/blue background
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          children: [
            // Curved Background Card covering logo and text
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 350,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF983F76), Color(0xFF4B2361)], // Pinkish-purple to dark purple
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.elliptical(screenWidth, 120),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
            
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40.0, 160.0, 40.0, 80.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Login to\nyour account',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: Colors.white, // White text for contrast
                      ),
                    ),
                    const SizedBox(height: 110), // Pushes text fields down below the curve

                    // ID Field
                    TextField(
                      controller: _idController,
                      onChanged: (val) {
                        // Automatically uppercase the ID
                        _idController.value = _idController.value.copyWith(
                          text: val.toUpperCase(),
                          selection: TextSelection.collapsed(offset: val.length),
                        );
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Student ID / Staff ID',
                        hintStyle: const TextStyle(color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password Field
                    TextField(
                      controller: _passwordController,
                      obscureText: _isObscure,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Password',
                        hintStyle: const TextStyle(color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isObscure ? Icons.visibility_off : Icons.visibility,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _isObscure = !_isObscure;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Center(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PasswordChangeScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: Color(0xFFC084FC), // Light purple link
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFFC084FC),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 35),

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB53471), // Match the curved card
                          elevation: 5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                'Login',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // LOGO
            Positioned(
              top: 40,
              right: 10,
              child: Image.asset(
                'assets/images/adbuLogo.png',
                width: 130,
                height: 130,
              ),
            ),
            
            // BACK BUTTON
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
