import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'common_imports.dart';
import 'package:flutter/services.dart';

class PermissionHelper {
  /// Request all permissions needed for CallKit full-screen UI
  static Future<void> requestCallPermissions() async {
    showLog('🔐 [Permissions] Requesting call permissions...');

    // Request notification permission FIRST
    final notificationStatus = await Permission.notification.request();
    showLog('🔐 [Permissions] Notification: $notificationStatus');

    // Request system alert window (display over other apps)
    final systemAlertStatus = await Permission.systemAlertWindow.request();
    showLog('🔐 [Permissions] System Alert Window: $systemAlertStatus');

    // Request phone permission (for CallKit)
    final phoneStatus = await Permission.phone.request();
    showLog('🔐 [Permissions] Phone: $phoneStatus');

    // Request microphone permission
    final micStatus = await Permission.microphone.request();
    showLog('🔐 [Permissions] Microphone: $micStatus');

    // Request camera permission
    final cameraStatus = await Permission.camera.request();
    showLog('🔐 [Permissions] Camera: $cameraStatus');

    // For Android 12+ (API 31+), request full-screen intent permission
    if (Platform.isAndroid) {
      try {
        await _requestFullScreenIntentPermission();
      } catch (e) {
        showLog('❌ [Permissions] Error requesting full-screen intent: $e');
      }
    }

    showLog('✅ [Permissions] All permissions requested');
  }

  /// Request full-screen intent permission for Android 12+
  static Future<void> _requestFullScreenIntentPermission() async {
    try {
      showLog(
          '📱 [Permissions] Requesting full-screen intent permission for Android 12+...');

      // Use platform channel to open full-screen intent settings
      const platform = MethodChannel('com.flutter.callkit/permissions');
      final bool? granted =
          await platform.invokeMethod('requestFullScreenIntent');

      showLog(
          '🔐 [Permissions] Full-screen intent permission: ${granted == true ? "granted" : "denied"}');

      if (granted != true) {
        showLog(
            '⚠️ [Permissions] Full-screen intent not granted - this is needed for incoming call UI');
      }
    } catch (e) {
      showLog(
          '⚠️ [Permissions] Platform channel not implemented, trying alternative method: $e');

      // Alternative: Show dialog to guide user
      showLog(
          '💡 [Permissions] Please enable "Display over other apps" in phone settings');
    }
  }

  /// Check if all critical permissions are granted
  static Future<bool> hasCallPermissions() async {
    final systemAlert = await Permission.systemAlertWindow.isGranted;
    final notification = await Permission.notification.isGranted;
    final phone = await Permission.phone.isGranted;

    showLog(
        '🔐 [Permissions] Check - System Alert: $systemAlert, Notification: $notification, Phone: $phone');

    return systemAlert && notification && phone;
  }
}
