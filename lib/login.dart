import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'homescreen.dart';
import 'profile_screens.dart';
import 'utils.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

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
      // Map the ID back to the virtual email used during registration
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: '$id@unimap.local',
        password: password,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Invalid ID or password';
      if (e.code == 'user-not-found') {
        message = 'No account found for this ID';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFDCD6CA),
              Color(0xFF6E7A6E),
            ],
          ),
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40.0, 180.0, 40.0, 80.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Login to\nyour account',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 80),

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
                      obscureText: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Password',
                        hintStyle: const TextStyle(color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
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
                            color: Color(0xFF0040FF),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                            decorationColor: Color(0xFF0040FF),
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
                          backgroundColor: const Color(0xFF1E5D6A),
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
            Positioned(
              top: 30,
              right: 0,
              child: Image.asset(
                'assets/images/adbuLogo.png',
                width: 145,
                height: 145,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
