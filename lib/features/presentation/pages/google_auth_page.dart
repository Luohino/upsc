import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../core/utils/common_imports.dart';
import '../../../core/utils/fcm_helper.dart';
import '../../../core/constant/shared_prefs_constants.dart';

class GoogleAuthPage extends StatefulWidget {
  const GoogleAuthPage({super.key});

  @override
  State<GoogleAuthPage> createState() => _GoogleAuthPageState();
}

class _GoogleAuthPageState extends State<GoogleAuthPage> {
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool _isLoading = false;

  /// Generate a fresh FCM token on every login
  /// This ensures stale/expired tokens are always replaced with valid ones
  Future<String> _getOrCreateFCMToken(String userId) async {
    try {
      print('🔄 [Google Auth] Generating fresh FCM token on login...');

      // ALWAYS generate a fresh token - never reuse old ones that might be stale
      // Try to get current token from FCM
      String? currentToken = FCMHelper.fcmToken;

      if (currentToken != null && currentToken.isNotEmpty) {
        print(
            '✅ [Google Auth] FCM token available immediately: ${currentToken.substring(0, 20)}...');
        return currentToken;
      }

      // Token not ready yet - try to force fetch it
      print('⏳ [Google Auth] FCM token not ready, attempting to fetch...');
      try {
        currentToken = await FirebaseMessaging.instance.getToken();
        if (currentToken != null && currentToken.isNotEmpty) {
          print(
              '✅ [Google Auth] Successfully fetched FCM token: ${currentToken.substring(0, 20)}...');
          FCMHelper.fcmToken = currentToken; // Update static variable
          return currentToken;
        }
      } catch (e) {
        print('❌ [Google Auth] Failed to fetch FCM token: $e');
      }

      print(
          '⏳ [Google Auth] FCM token not available, will update in background');
      return ''; // Empty string, will be updated in background
    } catch (e) {
      print('❌ [Google Auth] Error checking FCM token: $e');
      return FCMHelper.fcmToken ?? '';
    }
  }

  /// Background task to update FCM token - retries until token is available
  /// This runs in the background and NEVER blocks the UI
  void _scheduleBackgroundFCMTokenUpdate(String userId, String? initialToken) {
    print(
        '🔄 [Google Auth] Scheduling background FCM token update for user: $userId');

    // If we already have a token, we're done
    if (initialToken != null && initialToken.isNotEmpty) {
      print(
          '✅ [Google Auth] FCM token already available, no background update needed');
      return;
    }

    // Otherwise, start background polling
    print('🔄 [Google Auth] Starting background FCM token polling...');

    int attempts = 0;
    const maxAttempts = 60; // Try for 30 seconds total

    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      attempts++;

      final currentToken = FCMHelper.fcmToken;

      if (currentToken != null && currentToken.isNotEmpty) {
        // Token is now available!
        print(
            '✅ [Google Auth] FCM token became available after ${attempts * 500}ms: ${currentToken.substring(0, 20)}...');

        try {
          // Update Firestore
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({'fcmToken': currentToken});

          print('✅ [Google Auth] FCM token updated in Firestore successfully!');

          // Update local storage
          final prefs = await SharedPreferences.getInstance();
          final userPref = prefs.getString(SharedPrefsKeys.userDetails);
          if (userPref != null) {
            final userData = jsonDecode(userPref);
            userData['fcmToken'] = currentToken;
            await prefs.setString(
                SharedPrefsKeys.userDetails, jsonEncode(userData));
            print('✅ [Google Auth] FCM token updated in local storage!');
          }
        } catch (e) {
          print('❌ [Google Auth] Error updating FCM token: $e');
        }

        timer.cancel();
      } else if (attempts >= maxAttempts) {
        print(
            '⚠️ [Google Auth] FCM token still not available after ${maxAttempts * 500}ms, giving up');
        print(
            '💡 [Google Auth] Token will be updated on next app restart via migration');
        timer.cancel();
      } else if (attempts % 10 == 0) {
        // Log progress every 5 seconds
        print(
            '⏳ [Google Auth] Still waiting for FCM token... (${attempts * 500}ms elapsed)');
      }
    });
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Step 1: Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser != null) {
        print('🔑 [Google Auth] User signed in: ${googleUser.email}');

        // Step 2: Get Google Auth credentials
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final credential = firebase_auth.GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        // Step 3: Sign in to Firebase Authentication
        print('🔐 [Google Auth] Authenticating with Firebase...');
        final firebase_auth.UserCredential userCredential = 
            await firebase_auth.FirebaseAuth.instance.signInWithCredential(credential);
        final firebase_auth.User? firebaseUser = userCredential.user;

        if (firebaseUser == null) {
          throw Exception('Firebase authentication failed');
        }

        print('✅ [Google Auth] Firebase Auth successful! UID: ${firebaseUser.uid}');

        // Step 4: Get FCM token
        String? fcmToken = await _getOrCreateFCMToken(firebaseUser.uid);
        print(
            '📱 [Google Auth] FCM token: ${fcmToken.isNotEmpty ? "${fcmToken.substring(0, 20)}..." : "(will get later)"}');

        print('💾 [Google Auth] Firebase UID: ${firebaseUser.uid}');
        print('📧 [Google Auth] Email: ${firebaseUser.email}');
        print(
            '🔑 [Google Auth] Saving user with FCM token: ${fcmToken.isNotEmpty ? "${fcmToken.substring(0, 20)}..." : "(empty)"}');

        // Prepare user data for Firestore (with FieldValue)
        final firestoreUserData = {
          'uid': firebaseUser.uid,
          'name': firebaseUser.displayName ?? '',
          'email': firebaseUser.email ?? '',
          'photoUrl': firebaseUser.photoURL ?? '',
          'fcmToken': fcmToken,
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
        };

        // Prepare user data for local storage (with regular timestamp)
        final localUserData = {
          'uid': firebaseUser.uid,
          'name': firebaseUser.displayName ?? '',
          'email': firebaseUser.email ?? '',
          'photoUrl': firebaseUser.photoURL ?? '',
          'fcmToken': fcmToken,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
          'isOnline': true,
        };

        // Save to Firestore IMMEDIATELY
        // This is required because Flutter cannot fetch users from Firebase Authentication
        // Only users who sign in will appear in the users list
        print('💾 [Google Auth] Saving to Firestore...');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid)
            .set(firestoreUserData, SetOptions(merge: true));

        print('✅ [Google Auth] User saved to Firestore!');

        // Schedule background FCM token update (non-blocking)
        _scheduleBackgroundFCMTokenUpdate(firebaseUser.uid, fcmToken);

        // Save to local storage (without FieldValue)
        await SharedPrefs.setString(
          SharedPrefsKeys.userDetails,
          jsonEncode(localUserData),
        );

        // Navigate to home page
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.infoPage);
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo or App Name
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Welcome',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sign in to start messaging and calling',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 60),
                // Google Sign In Button
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _handleGoogleSignIn,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/google_logo.png',
                                  height: 24,
                                  width: 24,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.g_mobiledata,
                                      size: 24,
                                      color: Colors.black,
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 40),
                Text(
                  'By continuing, you agree to our Terms of Service\nand Privacy Policy',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.4),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
