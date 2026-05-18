import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'login.dart';
import 'signup.dart';
import 'homescreen.dart';
import 'upload_rooms.dart'; // Import the upload script

  void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = MyHttpOverrides();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Upload room data to Firestore in background (uncomment to sync new assets)
    if (kDebugMode) {
      uploadRoomsToFirestore();
    }

    // 1. Tell Android to draw edge-to-edge behind system bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // 2. Make the status bar purely transparent so your background colors show through perfectly
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
    
    runApp(const MyApp());
  }

  class MyHttpOverrides extends HttpOverrides {
    @override
    HttpClient createHttpClient(SecurityContext? context) {
      return super.createHttpClient(context)
        ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    }
  }

  class MyApp extends StatelessWidget {
    const MyApp({super.key});

    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'googlesans'),
        initialRoute: '/',
        routes: {
          '/': (context) => const LoadingWrapper(child: AuthWrapper()),
        },
      );
    }
  }

  class AuthWrapper extends StatelessWidget {
    const AuthWrapper({super.key});

    @override
    Widget build(BuildContext context) {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // If the connection is active, check the auth state
          if (snapshot.connectionState == ConnectionState.active) {
            final User? user = snapshot.data;
            if (user == null) {
              return const WelcomeScreen();
            } else {
              // --- GUEST SESSION LIMIT LOGIC ---
              if (user.isAnonymous) {
                final lastSignIn = user.metadata.lastSignInTime;
                if (lastSignIn != null) {
                  // Define the session limit (e.g., 30 seconds)
                  const sessionLimit = Duration(seconds: 30);
                  final expiryTime = lastSignIn.add(sessionLimit);

                  if (DateTime.now().isAfter(expiryTime)) {
                    // Session expired, sign out immediately
                    FirebaseAuth.instance.signOut();
                    return const WelcomeScreen();
                  }
                }
              }
              // ----------------------------------
              return const HomeScreen();
            }
          }
          // While waiting for the auth state, show a blank or loading state
          // (LoadingWrapper already handles the initial delay)
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      );
    }
  }

  class WelcomeScreen extends StatelessWidget {
    const WelcomeScreen({super.key});

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        body: Stack(
          children: [
            // 1. BACKGROUND GRADIENT
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF293C60), Color(0xFF000000)],
                  stops: [0.0, 0.6],
                ),
              ),
            ),

            // 2. TOP RIGHT IMAGE
            Positioned(
              top: 30,
              right: 0,
              child: Image.asset(
                'assets/images/adbuLogo.png',
                width: 145,
                height: 145,
              ),
            ),

            // 3. MAIN CONTENT
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 200.0),
                  
                  // Welcome Text
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(-40 * (1 - value), 0),
                        child: Opacity(
                          opacity: value,
                          child: child,
                        ),
                      );
                    },
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) => const LinearGradient(
                        colors: [Color(0xFF9e4444), Color(0xFFd45b5b)],
                      ).createShader(bounds),
                      child: const Text(
                        'Welcome to',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 35,
                          fontWeight: FontWeight.w800,
                          wordSpacing: 2.0,
                        ),
                      ),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.only(bottom: 100.0),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 1700),
                      curve: Curves.easeOutExpo,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 50 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return const LinearGradient(
                            colors: [Color(0xFF3b359c), Color(0xFF6157fa)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds);
                        },
                        child: const Text(
                          'UniMap',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 65,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // AUTHENTICATION BUTTONS
                  Center(
                    child: Column(
                      children: [
                        _buildGradientButton(context, 'Login'),
                        const SizedBox(height: 25),
                        _buildGradientButton(context, 'Sign Up'),
                        const SizedBox(height: 25),
                        TextButton(
                          onPressed: () async {
                            try {
                              await FirebaseAuth.instance.signInAnonymously();
                              if (context.mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Guest Login Error: ${e.toString()}")),
                                );
                              }
                            }
                          },
                          child: const Text(
                            'Continue as Guest',
                            style: TextStyle(
                              color: Colors.white70,
                              decoration: TextDecoration.underline,
                              fontSize: 21,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget _buildGradientButton(BuildContext context, String text) {
      return Container(
        width: 300,
        height: 55,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF233587), Color(0xFF2975f0)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: ElevatedButton(
          onPressed: () {
            if (text == 'Login') {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const Login()));
            } else if (text == 'Sign Up') {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUp()));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  // Removed old MyApp code blocks as they are now in WelcomeScreen and AuthWrapper


// --- LOADING SCREEN WRAPPER ---
class LoadingWrapper extends StatefulWidget {
  final Widget child;
  const LoadingWrapper({super.key, required this.child});

  @override
  State<LoadingWrapper> createState() => _LoadingWrapperState();
}

class _LoadingWrapperState extends State<LoadingWrapper> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    // Delay to simulate loading and show the beautiful splash text
    Future.delayed(const Duration(milliseconds: 4000), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1400),
            curve: Curves.easeOutExpo,
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.8 + (0.2 * value), // Slight elegant scale-up
                child: Opacity(
                  opacity: value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Keep contents compactly centered
                    children: [
                      // Show the actual unimap logo instead of the placeholder
                      Image.asset(
                        'assets/images/unimapIcon.png',
                        width: 220,
                        height: 220,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    // Content goes to the main screen smoothly instantly after delay
    return widget.child;
  }
}
