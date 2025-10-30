import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constant/shared_prefs_constants.dart';
import '../utils/common_imports.dart';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Initialize local notifications with action buttons
  static Future<void> initialize() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Request permissions (skip on first call, will be auto-requested on first show)
    try {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    } catch (e) {
      showLog('⚠️ [LocalNotification] Permission request skipped: $e');
      // Continue anyway - permissions will be requested when first notification is shown
    }

    _initialized = true;
    showLog('✅ [LocalNotification] Initialized with action buttons');
  }

  /// Handle notification tap and action buttons
  static Future<void> _onNotificationTapped(
      NotificationResponse response) async {
    showLog(
        '🔔 [LocalNotification] Tapped: ${response.actionId ?? "notification"}');
    showLog('🔔 [LocalNotification] Payload: ${response.payload}');

    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final data = jsonDecode(response.payload!);
      final chatId = data['chatId'] as String?;
      final senderId = data['senderId'] as String?;
      final senderName = data['senderName'] as String?;
      final senderPhoto = data['senderPhoto'] as String?;
      final messageText = data['messageText'] as String?;

      if (chatId == null) return;

      // Handle action button taps
      if (response.actionId == 'mark_read') {
        // Mark all messages from this sender as read
        await _markMessagesAsRead(chatId, senderId);
        showLog('✅ [LocalNotification] Messages marked as read');
      } else if (response.actionId == 'reply') {
        // Open chat page for reply
        final context = AppConstants.navigatorKey.currentContext;
        if (context != null) {
          // Get current user
          final prefs = await SharedPreferences.getInstance();
          final userPref = prefs.getString(SharedPrefsConstant.userDetails);
          if (userPref != null && userPref.isNotEmpty) {
            final currentUser = jsonDecode(userPref);

            Navigator.pushNamed(
              context,
              AppRoutes.chatPage,
              arguments: {
                'receiverUser': {
                  'uid': senderId,
                  'name': senderName,
                  'photoUrl': senderPhoto,
                },
                'currentUser': currentUser,
              },
            );
          }
        }
      } else {
        // Just notification tap (no action button) - open chat
        final context = AppConstants.navigatorKey.currentContext;
        if (context != null) {
          final prefs = await SharedPreferences.getInstance();
          final userPref = prefs.getString(SharedPrefsConstant.userDetails);
          if (userPref != null && userPref.isNotEmpty) {
            final currentUser = jsonDecode(userPref);

            Navigator.pushNamed(
              context,
              AppRoutes.chatPage,
              arguments: {
                'receiverUser': {
                  'uid': senderId,
                  'name': senderName,
                  'photoUrl': senderPhoto,
                },
                'currentUser': currentUser,
              },
            );
          }
        }
      }
    } catch (e) {
      showLog('❌ [LocalNotification] Error handling tap: $e');
    }
  }

  /// Mark all unread messages from a sender as read
  static Future<void> _markMessagesAsRead(
      String chatId, String? senderId) async {
    if (senderId == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isEqualTo: senderId)
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.update({'isRead': true});
      }
    } catch (e) {
      showLog('❌ [LocalNotification] Error marking messages as read: $e');
    }
  }

  /// Show message notification with action buttons
  static Future<void> showMessageNotification({
    required String senderId,
    required String senderName,
    required String messageText,
    required String chatId,
    String? senderPhoto,
  }) async {
    if (!_initialized) await initialize();

    // Create notification payload
    final payload = jsonEncode({
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'senderPhoto': senderPhoto,
      'messageText': messageText,
    });

    // Android notification with action buttons (using high_importance_channel)
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'high_importance_channel', // Must match channel in MainActivity
      'Messages',
      channelDescription: 'Instant message notifications',
      importance: Importance.max, // Maximum importance for instant delivery
      priority: Priority.max,
      styleInformation: BigTextStyleInformation(
        messageText,
        contentTitle: senderName,
        summaryText: 'New message',
      ),
      actions: [
        const AndroidNotificationAction(
          'reply',
          'Reply',
          icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          showsUserInterface: true,
        ),
        const AndroidNotificationAction(
          'mark_read',
          'Mark as Read',
          showsUserInterface: false,
        ),
      ],
    );

    // iOS notification (no action buttons in foreground, but works in background)
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Use chatId as notification ID to group messages from same chat
    final notificationId = chatId.hashCode;

    await _notificationsPlugin.show(
      notificationId,
      senderName,
      messageText,
      details,
      payload: payload,
    );

    showLog(
        '🔔 [LocalNotification] Shown: $senderName - ${messageText.length > 30 ? messageText.substring(0, 30) + "..." : messageText}');
  }

  /// Cancel a notification
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }
}
