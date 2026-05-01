import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  String? _validateId(String id) {
    id = id.toUpperCase();
    if (!id.startsWith('DC')) {
      return 'ID must start with "DC"';
    }
    if (id.length > 13) {
      return 'ID cannot exceed 13 characters';
    }
    if (id.length < 6) {
      return 'ID is too short (needs DC + 4 digits)';
    }

    final lastFour = id.substring(id.length - 4);
    final numericValue = int.tryParse(lastFour);

    if (numericValue == null || !RegExp(r'^\d{4}$').hasMatch(lastFour)) {
      return 'Last 4 characters must be digits';
    }

    if (numericValue < 0 || numericValue > 100) {
      return 'Last 4 digits must be between 0000 and 0100';
    }

    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(id)) {
      return 'ID can only contain uppercase letters and numbers';
    }

    return null;
  }

  Future<void> _handleSignUp() async {
    final name = _nameController.text.trim();
    final id = _idController.text.trim().toUpperCase();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // 1. Basic Empty Validation
    if (name.isEmpty || id.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    // 2. Custom ID Validation
    final idError = _validateId(id);
    if (idError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(idError)),
      );
      return;
    }

    // 3. Password Match Validation
    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    // 4. Letters and Numbers Mix Validation
    if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)').hasMatch(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must contain both letters and numbers')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Firebase Auth uses emails. We'll use id@unimap.local as a virtual email.
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: '${id.toLowerCase()}@unimap.local',
        password: password,
      );

      // Save user profile to Firestore
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'name': name,
        'uid': userCredential.user!.uid,
        'studentId': id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created successfully! Please login.')),
        );
        // Redirect to Login Screen
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const Login()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          // Check if Password and Name also match for the existing ID
          final signinResult = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: '${id.toLowerCase()}@unimap.local',
            password: password,
          );
          
          final doc = await FirebaseFirestore.instance.collection('users').doc(signinResult.user!.uid).get();
          final existingName = doc.data()?['name'];
          
          // Sign back out as we only wanted to verify credentials
          await FirebaseAuth.instance.signOut();

          if (existingName == name) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This ID is already registered')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This ID is already taken')),
            );
          }
        } catch (signinError) {
          // Password didn't match
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This ID is already taken')),
          );
        }
      } else {
        String message = 'Error: ${e.message ?? "An error occurred"}';
        if (e.code == 'weak-password') {
          message = 'The password is too weak';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
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
              Color(0xFF8C968C),
            ],
          ),
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30.0, 150.0, 30.0, 60.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create your\naccount',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 25),
                    
                    // Name Field
                    TextField(
                      controller: _nameController,
                      onChanged: (val) {
                        if (val.isEmpty) return;
                        
                        // Capitalize first letter of each word
                        String titleCase = val.split(' ').map((word) {
                          if (word.isEmpty) return word;
                          return word[0].toUpperCase() + word.substring(1);
                        }).join(' ');
                        
                        if (val != titleCase) {
                          final selection = _nameController.selection;
                          _nameController.value = TextEditingValue(
                            text: titleCase,
                            selection: selection,
                          );
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Name',
                        hintStyle: const TextStyle(color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Password Field
                    TextField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Set password',
                        hintStyle: const TextStyle(color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() => _isPasswordVisible = !_isPasswordVisible);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Confirm Password Field
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Confirm password',
                        hintStyle: const TextStyle(color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    const SizedBox(height: 35),

                    // Sign Up Button
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSignUp,
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
                                'Sign up',
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
