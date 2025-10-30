import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../../features/data/model/notification_payload.dart';
import '../services/local_notification_service.dart';
import 'callkit_helper.dart';
import 'common_imports.dart';

// Background handler is now in main.dart as top-level function
// This is required for app-killed scenarios

class FCMHelper {
  static FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;

  static final String projectId = 'fir-d9456';
  static final String sendNotificationURL =
      'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';
  static final String verifyFcmTokenURL =
      'https://www.googleapis.com/auth/firebase.messaging';

  static String? fcmToken;

  static Future<void> init() async {
    try {
      showLog('🚀 [FCM] Starting FCM initialization...');

      // Request permission first
      final settings = await firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      showLog('✅ [FCM] Permission granted: ${settings.authorizationStatus}');

      // Background handler is registered in main.dart
      // Set up foreground message listeners
      firebaseMessaging.getInitialMessage().then(_onInitialMessage);
      FirebaseMessaging.onMessage.listen(_onMessage);

      // Get initial FCM token with retry logic
      fcmToken = await _getFirebaseTokenWithRetry();
      if (fcmToken != null && fcmToken!.isNotEmpty) {
        showLog(
            '✅ [FCM] Initial token obtained: ${fcmToken!.substring(0, 20)}...');
      } else {
        showLog('⚠️ [FCM] Token will be obtained later');
      }

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        showLog('🔄 [FCM] Token refreshed: ${newToken.substring(0, 20)}...');
        fcmToken = newToken;

        // Update Firestore with new token
        await _updateUserFCMToken(newToken);
      });
    } catch (e) {
      showLog('❌ [FCM] Initialization error: $e');
      // Don't rethrow - let the app continue without FCM
    }
  }

  static _onInitialMessage(RemoteMessage? message) {
    showLog(
        'onInitialMessage method called - payload - ${message?.data.toString()}');
    if (message?.data.isNotEmpty ?? false) {
      NotificationPayload payload =
          NotificationPayload.fromJson(message?.data ?? {});

      if (payload.callAction == CallAction.create ||
          payload.callAction == CallAction.join) {
        showLog('📞 [FCM] App opened from notification, showing call UI');

        // Show CallKit for background handling
        CallKitHelper.showCallkitIncoming(payload: payload);

        // ALSO show custom UI immediately when app is opened from notification
        Future.delayed(const Duration(milliseconds: 500), () {
          final context = AppConstants.navigatorKey.currentContext;
          if (context != null) {
            Navigator.pushNamed(
              context,
              AppRoutes.iosIncomingCallPage,
              arguments: {
                'callerName': payload.name ?? payload.username ?? 'Unknown',
                'callerImage': payload.imageUrl,
                'isOutgoing': false,
                'isVideo': payload.callType == CallType.video,
                'callPayload': payload,
              },
            );
          }
        });
      } else if (payload.callAction == CallAction.end) {
        CallKitHelper.endAllCalls();
      }
    }
  }

  static void _onMessage(RemoteMessage message) async {
    showLog('onMessage method called - payload - ${message.data.toString()}');
    if (message.data.isNotEmpty) {
      NotificationPayload payload = NotificationPayload.fromJson(message.data);

      if (payload.callAction == CallAction.create ||
          payload.callAction == CallAction.join) {
        showLog('📞 [FCM] Incoming call detected in foreground');

        // DON'T use CallKit - it shows buggy UI
        // Just show our custom UI directly
        final context = AppConstants.navigatorKey.currentContext;
        if (context != null) {
          showLog('📱 [FCM] App is in foreground, showing custom call UI');
          Navigator.pushNamed(
            context,
            AppRoutes.iosIncomingCallPage,
            arguments: {
              'callerName': payload.name ?? payload.username ?? 'Unknown',
              'callerImage': payload.imageUrl,
              'isOutgoing': false,
              'isVideo': payload.callType == CallType.video,
              'callPayload': payload,
            },
          );
        }
      } else if (payload.callAction == CallAction.end) {
        showLog('🔚 [FCM] Call end signal received');
        CallKitHelper.endAllCalls();
        
        // DON'T pop navigation - the call page already handles its own navigation
        // When a call ends, the call page pops itself back to chat_page
        // This FCM notification is just for ending CallKit, not for navigation
        // 
        // If we pop here, we'll navigate away from the chat page 2 seconds later,
        // which creates a bad UX where user returns to chat, then gets sent elsewhere
        showLog('✅ [FCM] CallKit ended, leaving navigation to call page');
      } else if (payload.callAction == CallAction.message) {
        showLog('💬 [Foreground] New message from ${payload.callerName}');
        // Show local notification with action buttons even in foreground
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

  /// Get FCM token with retry logic for reliability
  static Future<String?> _getFirebaseTokenWithRetry() async {
    String? token;
    const maxRetries = 5;

    for (int i = 0; i < maxRetries; i++) {
      try {
        token = await _getFirebaseToken();
        if (token != null && token.isNotEmpty) {
          return token;
        }

        // Wait before retry
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
          showLog('⏳ [FCM] Retry ${i + 1}/$maxRetries for token...');
        }
      } catch (e) {
        showLog('❌ [FCM] Token fetch attempt ${i + 1} failed: $e');
        if (i < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
        }
      }
    }

    return null;
  }

  static Future<String> _getFirebaseToken() async {
    String? fcmToken;
    if (kIsWeb) {
      // Web platform - get FCM token with VAPID key
      const vapidKey =
          'BD0RjQ3By4H6cM5eNDQandQ9dEXoorDimptemGDCSypwXgnKcS1HcsHqNbROF4qdUxVdiiraveUgEX040Ftga';
      try {
        fcmToken =
            await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
        if (fcmToken != null && fcmToken.isNotEmpty) {
          showLog('✅ Web FCM token retrieved successfully');
        } else {
          showLog('⚠️ Web FCM token is null or empty');
        }
      } catch (e) {
        showLog('❌ Web FCM token error: $e');
        fcmToken = ''; // Return empty string on error
      }
    } else if (Platform.isIOS) {
      String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      if (apnsToken != null) {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } else {
        await Future.delayed(Duration(seconds: 3));
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null) {
          fcmToken = await FirebaseMessaging.instance.getToken();
        }
      }
    } else {
      fcmToken = await FirebaseMessaging.instance.getToken();
    }
    return fcmToken ?? '';
  }

  static Future<http.Response?> sendNotification({
    required String fcmToken,
    NotificationPayload? payload,
  }) async {
    final client = await _getAuthClient();

    // Build notification title and body based on action type
    String title = '';
    String body = '';

    if (payload?.callAction == CallAction.message) {
      title = payload?.callerName ?? 'New Message';
      body = payload?.messageText ?? '';
    } else if (payload?.callAction == CallAction.create ||
        payload?.callAction == CallAction.join) {
      title = payload?.name ?? 'Incoming Call';
      body = 'Tap to answer';
    }

    final data = {
      "message": {
        "token": fcmToken,
        "data": payload?.toJson(),
        "notification": {
          "title": title,
          "body": body,
        },
        "android": {
          "priority": "high",
          "ttl": "0s", // Immediate delivery, don't queue
          "notification": {
            "sound": "default",
            "channelId": "high_importance_channel",
            "clickAction": "FLUTTER_NOTIFICATION_CLICK",
            "defaultSound": true,
            "defaultVibrateTimings": true,
          }
        },
        "apns": {
          "headers": {
            "apns-priority": "10",
            "apns-push-type": "alert",
          },
          "payload": {
            "aps": {
              "alert": {
                "title": title,
                "body": body,
              },
              "sound": "default",
              "content-available": 1,
              "badge": 1,
            }
          }
        },
        "fcm_options": {
          "analytics_label": "instant_message"
        }
      }
    };

    final response = await client.post(
      Uri.parse(sendNotificationURL),
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      showLog('Notification sent successfully: ${response.body}');
    } else {
      showLog('Failed to send notification: ${response.body}');
    }

    client.close();

    return response;
  }

  static Future<AutoRefreshingAuthClient> _getAuthClient() async {
    try {
      final serviceAccountJson = await loadFirebaseConfig();
      final serviceAccountCredentials =
          ServiceAccountCredentials.fromJson(serviceAccountJson);

      final authClient = await clientViaServiceAccount(
        serviceAccountCredentials,
        [verifyFcmTokenURL],
      );

      return authClient;
    } catch (e) {
      showLog('Error getting auth client: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> loadFirebaseConfig() async {
    final String jsonString =
        await rootBundle.loadString(AppAssets.firebaseConfig);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }

  /// Update current user's FCM token in Firestore (multi-device safe)
  static Future<void> _updateUserFCMToken(String newToken) async {
    try {
      final userPref = SharedPrefs.getUserDetails;
      if (userPref != null && userPref.isNotEmpty) {
        final userData = jsonDecode(userPref);
        final userId = userData['uid'];
        if (userId != null) {
          final userRef =
              FirebaseFirestore.instance.collection('users').doc(userId);
          await userRef.set({
            'fcmToken': newToken,
            'deviceTokens': FieldValue.arrayUnion([newToken]),
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          // Update local
          userData['fcmToken'] = newToken;
          final existing =
              (userData['deviceTokens'] as List?)?.cast<String>() ?? [];
          userData['deviceTokens'] = {...existing, newToken}.toList();
          await SharedPrefs.setUserDetails(jsonEncode(userData));

          showLog('✅ [FCM] Token saved/merged');
        }
      }
    } catch (e) {
      showLog('❌ [FCM] Error updating user FCM token: $e');
    }
  }

  /// Send to all device tokens for a given user and remove invalid tokens lazily
  static Future<void> sendToAllUserTokens({
    required String userId,
    required NotificationPayload payload,
  }) async {
    try {
      showLog('\n📤 [FCM] ========================================');
      showLog('📤 [FCM] sendToAllUserTokens called');
      showLog('📤 [FCM] Target user ID: $userId');
      showLog('📤 [FCM] Payload action: ${payload.callAction}');
      
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (!doc.exists) {
        showLog('❌ [FCM] User document does not exist for $userId');
        showLog('📤 [FCM] ========================================\n');
        return;
      }
      
      final data = doc.data() ?? {};
      showLog('📑 [FCM] User data keys: ${data.keys.toList()}');
      
      // Get tokens from deviceTokens array, or fall back to single fcmToken
      List tokensRaw = (data['deviceTokens'] as List?) ?? [];
      
      // If deviceTokens is empty but fcmToken exists, use it
      if (tokensRaw.isEmpty && data['fcmToken'] != null) {
        tokensRaw = [data['fcmToken']];
        showLog('💡 [FCM] deviceTokens empty, using fcmToken field instead');
      }
      
      showLog('🔑 [FCM] Raw tokens found: ${tokensRaw.length}');
      
      final tokens = tokensRaw
          .map((e) => e.toString())
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList();
      
      if (tokens.isEmpty) {
        showLog('⚠️ [FCM] No valid tokens for user $userId');
        showLog('📖 [FCM] User fcmToken field: ${data['fcmToken']}');
        showLog('📖 [FCM] User deviceTokens field: ${data['deviceTokens']}');
        showLog('📤 [FCM] ========================================\n');
        return;
      }
      
      showLog('✅ [FCM] Found ${tokens.length} valid token(s) to send to');
      
      for (int i = 0; i < tokens.length; i++) {
        final t = tokens[i];
        showLog('📨 [FCM] Sending to token ${i + 1}/${tokens.length}: ${t.substring(0, 20)}...');
        
        try {
          final resp = await sendNotification(fcmToken: t, payload: payload);
          
          if (resp != null) {
            showLog('📥 [FCM] Response status: ${resp.statusCode}');
            showLog('📥 [FCM] Response body: ${resp.body}');
            
            if (resp.statusCode == 200) {
              showLog('✅ [FCM] Notification sent successfully to token ${i + 1}');
            } else if (resp.statusCode == 404 &&
                (resp.body.contains('UNREGISTERED') ||
                    resp.body.contains('NotRegistered'))) {
              showLog('🧹 [FCM] Token is invalid, removing from Firestore');
              
              // Remove from deviceTokens array
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .set({
                'deviceTokens': FieldValue.arrayRemove([t]),
              }, SetOptions(merge: true));
              
              // ALSO clear the fcmToken field if it matches the stale token
              if (data['fcmToken'] == t) {
                showLog('🧹 [FCM] Also clearing stale fcmToken field');
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .update({
                  'fcmToken': null,
                });
              }
              
              showLog('✅ [FCM] Invalid token removed');
            } else {
              showLog('⚠️ [FCM] Unexpected response code: ${resp.statusCode}');
            }
          }
        } catch (e) {
          showLog('❌ [FCM] Error sending to token ${i + 1}: $e');
        }
      }
      
      showLog('📤 [FCM] ========================================\n');
    } catch (e) {
      showLog('❌ [FCM] sendToAllUserTokens failed: $e');
      showLog('📤 [FCM] ========================================\n');
    }
  }
}
