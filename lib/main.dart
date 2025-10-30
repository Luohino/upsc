import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

import 'core/constant/shared_prefs_constants.dart';
import 'core/utils/common_imports.dart';
import 'core/utils/fcm_helper.dart';
import 'core/utils/fcm_token_migration.dart';
import 'core/utils/permission_helper.dart';
import 'core/services/hive_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/utils/callkit_helper.dart';
import 'features/data/model/user.dart';
import 'features/data/model/notification_payload.dart';
import 'features/presentation/bloc/auth_bloc/auth_bloc.dart';
import 'features/presentation/pages/ios_incoming_call_page.dart';
import 'core/services/update_service.dart';
import 'core/services/call_signal_service.dart';
import 'firebase_options.dart';

// CRITICAL: This MUST be a top-level function for background notifications
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  print('🔔 [Background] Message received: ${message.messageId}');
  print('🔔 [Background] Data: ${message.data}');
  
  if (message.data.isNotEmpty) {
    NotificationPayload payload = NotificationPayload.fromJson(message.data);

    if (payload.callAction == CallAction.create ||
        payload.callAction == CallAction.join) {
      print('📞 [Background] Incoming call - showing CallKit notification');
      CallKitHelper.showCallkitIncoming(payload: payload);
    } else if (payload.callAction == CallAction.end) {
      print('📞 [Background] End call received');
      CallKitHelper.endAllCalls();
    } else if (payload.callAction == CallAction.message) {
      print('💬 [Background] New message from ${payload.callerName}');
      // Initialize local notification service if needed
      await LocalNotificationService.initialize();
      await LocalNotificationService.showMessageNotification(
        senderId: payload.userId ?? '',
        senderName: payload.callerName ?? 'Unknown',
        messageText: payload.messageText ?? '',
        chatId: payload.chatId ?? payload.callId ?? '',
        senderPhoto: payload.imageUrl,
      );
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 [Main] App starting...');

  // CRITICAL: Initialize Firebase FIRST
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('✅ [Main] Firebase initialized');

  // Register background message handler (works even when app is killed)
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  print('✅ [Main] Background message handler registered');

  // Initialize Hive for instant data access
  await HiveService.init();
  print('✅ [Main] Hive initialized');

  await initInjector();
  print('✅ [Main] Dependency injection initialized');

  // Wrap app with ProviderScope for Riverpod
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AuthBloc authBloc = sl<AuthBloc>();

  bool _isAuthenticated = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
    _initializeApp();
    _listenToAuthChanges();
  }

  // Listen to Firebase Auth state changes
  void _listenToAuthChanges() {
    firebase_auth.FirebaseAuth.instance.authStateChanges().listen((firebase_auth.User? user) {
      if (user == null) {
        print('🔓 [Auth] User signed out');
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
          });
        }
      } else {
        print('🔐 [Auth] User signed in: ${user.uid}');
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
          });
        }
      }
    });
  }

  // Initialize everything in correct order
  Future<void> _initializeApp() async {
    // 1. Initialize local notifications for action buttons
    await LocalNotificationService.initialize();
    print('✅ [Main] Local notifications initialized');

    // 2. Initialize FCM in background (don't block UI)
    _initFCM();

    // 3. Initialize CallKit listeners
    _initCallKitListeners();

    // 4. Sync current authenticated user to Firestore
    await _syncAuthenticatedUserToFirestore();

    // 5. Check auth state immediately (don't wait for FCM)
    await _checkAuthState();

    // 4. After first frame, check for updates (custom OTA or Play Core)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkAtLaunch();
    });
  }

  Future<void> _requestPermissions() async {
    try {
      await PermissionHelper.requestCallPermissions();
      print('✅ [Main] Call permissions requested');
    } catch (e) {
      print('❌ [Main] Error requesting permissions: $e');
    }
  }

  /// Sync authenticated user to Firestore if not already there
  Future<void> _syncAuthenticatedUserToFirestore() async {
    try {
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('🔄 [Sync] No authenticated user, skipping sync');
        return;
      }

      print('🔄 [Sync] Checking if user ${user.email} exists in Firestore...');

      // Check if user document exists in Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        print('✅ [Sync] User not in Firestore, creating document...');

        // Get FCM token
        String? fcmToken;
        try {
          fcmToken = await FirebaseMessaging.instance.getToken();
        } catch (e) {
          print('⚠️ [Sync] Could not get FCM token: $e');
        }

        // Create Firestore document
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'uid': user.uid,
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'photoUrl': user.photoURL ?? '',
          'fcmToken': fcmToken ?? '',
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
        }, SetOptions(merge: true));

        print('✅ [Sync] User document created in Firestore!');
      } else {
        print('✅ [Sync] User already exists in Firestore');
      }
    } catch (e) {
      print('❌ [Sync] Error syncing user to Firestore: $e');
    }
  }

  void _showCustomCallUI(Map<String, dynamic>? callData) {
    if (callData != null && callData['extra'] != null) {
      try {
        final payload = NotificationPayload.fromJson(
            Map<String, dynamic>.from(callData['extra'] as Map));

        // Navigate to our beautiful iOS UI
        final context = AppConstants.navigatorKey.currentContext;
        if (context != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => IOSIncomingCallPage(
                callerName: payload.name ?? payload.username ?? 'Unknown',
                callerImage: payload.imageUrl,
                isOutgoing: false,
                isVideo: payload.callType == CallType.video,
                otherPersonFcmToken:
                    payload.fcmToken, // Pass caller's FCM token
                callPayload: payload,
              ),
            ),
          ).then((_) {
            // End CallKit when user closes the page
            FlutterCallkitIncoming.endAllCalls();
          });
        }
      } catch (e) {
        print('❌ [Main] Error parsing call data: $e');
      }
    }
  }

  Future<void> _initFCM() async {
    try {
      await FCMHelper.init();

      // Run FCM token migration for existing users
      FCMTokenMigration.runMigrationIfNeeded();
    } catch (e) {
      print('FCM init error: $e');
    }
  }

  void _initCallKitListeners() {
    // Listen to CallKit events
    FlutterCallkitIncoming.onEvent.listen((event) async {
      print('📱 [CallKit Event] ${event?.event}: ${event?.body}');

      switch (event!.event) {
        case Event.actionCallIncoming:
          // Notification shown - immediately open our custom UI
          print(
              '📞 [CallKit] Incoming call notification - showing custom iOS UI');
          _showCustomCallUI(event.body);
          break;

        case Event.actionCallStart:
          // User tapped the notification - show custom UI
          print('👆 [CallKit] Notification tapped - showing custom iOS UI');
          _showCustomCallUI(event.body);
          break;

        case Event.actionCallAccept:
          // User accepted the call
          print('✅ [CallKit] Call accepted - showing custom iOS UI');
          _showCustomCallUI(event.body);
          break;

        case Event.actionCallDecline:
          print('❌ Call declined');
          await FlutterCallkitIncoming.endAllCalls();
          break;

        case Event.actionCallEnded:
          print('📞 Call ended');
          break;

        case Event.actionCallTimeout:
          print('⏱️ Call timeout');
          break;

        default:
          break;
      }
    });
  }

  Future<void> _checkAuthState() async {
    try {
      // Use SharedPreferences directly instead of through service locator
      final prefs = await SharedPreferences.getInstance();
      final userPref = prefs.getString(SharedPrefsConstant.userDetails);

      if (userPref != null && userPref.isNotEmpty) {
        try {
          User user = User.fromJson(jsonDecode(userPref));
          authBloc.user = user;
          authBloc.add(UpdateFCMTokenEvent());

          // Start Firestore-based call signal listener as FCM fallback
          final raw = jsonDecode(userPref) as Map<String, dynamic>;
          final curId = (user.userId?.isNotEmpty == true)
              ? user.userId!
              : (raw['uid'] as String? ?? '');
          CallSignalService.startListening(currentUserId: curId);

          if (mounted) {
            setState(() {
              _isAuthenticated = true;
              _isLoading = false;
            });
          }
        } catch (e) {
          print('Error loading user: $e');
          if (mounted) {
            setState(() {
              _isAuthenticated = false;
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error in _checkAuthState: $e');
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer(
      bloc: authBloc,
      listener: (context, state) {
        if (state is AuthMultipleLoginState) {
          showMultipleLoginAlertDialog();
        }
      },
      builder: (context, state) {
        if (_isLoading) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              primarySwatch: AppColors.primarySwatch,
              scaffoldBackgroundColor: AppColors.white,
            ),
            home: const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: AppColors.primarySwatch,
            scaffoldBackgroundColor: AppColors.white,
            brightness: Brightness.dark,
          ),
          navigatorKey: AppConstants.navigatorKey,
          scaffoldMessengerKey: AppConstants.scaffoldMessengerKey,
          onGenerateRoute: AppNavigator.materialAppRoutes,
          initialRoute:
              _isAuthenticated ? AppRoutes.infoPage : AppRoutes.googleAuthPage,
        );
      },
    );
  }

  Future showMultipleLoginAlertDialog() async {
    return await showDialog(
      barrierDismissible: false,
      context: AppConstants.navigatorKey.currentContext!,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: CupertinoAlertDialog(
            title: const Text('User login in multiple device'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRoutes.authenticationPage,
                    (route) => false,
                  );
                },
                child: const Text('Okay'),
              ),
            ],
          ),
        );
      },
    );
  }
}
