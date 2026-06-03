import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'login.dart';
import 'signup.dart';
import 'package:video_player/video_player.dart';
import 'homescreen.dart';
  void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = MyHttpOverrides();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

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
                  // Define the session limit (e.g., 1 hour)
                  const sessionLimit = Duration(hours: 1);
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

  class WelcomeScreen extends StatefulWidget {
    const WelcomeScreen({super.key});

    @override
    State<WelcomeScreen> createState() => _WelcomeScreenState();
  }

  class _WelcomeScreenState extends State<WelcomeScreen> {
    late VideoPlayerController _controller;

    @override
    void initState() {
      super.initState();
      _controller = VideoPlayerController.asset('assets/Video/main.mp4')
        ..initialize().then((_) {
          _controller.setPlaybackSpeed(0.5); // Reduce playback speed
          _controller.setVolume(0.0);
          _controller.setLooping(true);
          _controller.play();
          setState(() {});
        });
    }

    @override
    void dispose() {
      _controller.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            if (_controller.value.isInitialized)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 5),
                  // Logo
                  Image.asset(
                    'assets/images/adbuLogo.png',
                    width: 170,
                    height: 170,
                  ),
                  const SizedBox(height: 7),
                  
                  // Welcome to
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'googlesans',
                      ),
                      children: [
                        TextSpan(
                          text: 'Welcome ',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'to',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  // UniMap
                  const Text(
                    'UniMap',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF), // white
                      fontSize: 65,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  
                  const SizedBox(height: 25),
                  
                  // Buttons
                  _buildGlowButton(context, 'Login'),
                  const SizedBox(height: 25),
                  _buildGlowButton(context, 'Sign Up'),
                  
                  const SizedBox(height: 25),
                  
                  // Continue as Guest
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
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 60), // Pushes the content a bit higher
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

    Widget _buildGlowButton(BuildContext context, String text) {
      return Container(
        width: 280,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B47FA).withOpacity(0.4), // Purple glow
              blurRadius: 25,
              spreadRadius: 2,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () {
              if (text == 'Login') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const Login()));
              } else if (text == 'Sign Up') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUp()));
              }
            },
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
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
    
    // Delay to simulate loading and show the logo for exactly 3 seconds
    Future.delayed(const Duration(milliseconds: 3000), () {
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
        backgroundColor: const Color(0xFF1A237E),
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
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
                      ClipOval(
                        child: Image.asset(
                          'assets/images/Logo.jpg',
                          width: 220,
                          height: 220,
                          fit: BoxFit.cover,
                        ),
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


