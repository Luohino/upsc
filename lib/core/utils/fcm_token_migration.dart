import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fcm_helper.dart';
import 'common_imports.dart';

/// One-time migration helper to update FCM token for current user
/// Call this once when app starts to ensure all users have valid FCM tokens
class FCMTokenMigration {
  static Future<void> migrateCurrentUserToken() async {
    try {
      final userPref = SharedPrefs.getUserDetails;
      if (userPref == null || userPref.isEmpty) {
        showLog('[Migration] No user logged in, skipping');
        return;
      }

      final userData = jsonDecode(userPref);
      final userId = userData['uid'];
      final currentStoredToken = userData['fcmToken'];

      if (userId == null) {
        showLog('[Migration] No user ID found, skipping');
        return;
      }

      // Get the latest FCM token
      final latestToken = FCMHelper.fcmToken;

      if (latestToken == null || latestToken.isEmpty) {
        showLog('⚠️ [Migration] FCM token not ready yet, will retry later');
        return;
      }

      // Check Firestore to see if token is null or invalid
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(userId);
      final userDoc = await userRef.get();
      final firestoreToken = (userDoc.exists && userDoc.data() != null)
          ? userDoc.data()!['fcmToken']
          : null;

      // Force update if:
      // 1. Firestore token is null/empty (invalid/expired)
      // 2. Local token doesn't match latest token
      // 3. Firestore token doesn't match latest token
      if (firestoreToken != null &&
          firestoreToken.isNotEmpty &&
          firestoreToken == latestToken &&
          currentStoredToken == latestToken) {
        showLog('✅ [Migration] FCM token already up to date');
        return;
      }

      if (firestoreToken == null || firestoreToken.isEmpty) {
        showLog(
            '⚠️ [Migration] Firestore FCM token is NULL/INVALID - forcing refresh');
      }

      showLog('🔄 [Migration] Updating FCM token for user: $userId');

      // Update Firestore (userDoc already fetched above)
      if (userDoc.exists) {
        await userRef.update({
          'fcmToken': latestToken,
          'deviceTokens': FieldValue.arrayUnion([latestToken]),  // Also add to deviceTokens array
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
        showLog('✅ [Migration] Firestore FCM token updated');
      } else {
        // Create user document if it doesn't exist
        await userRef.set({
          'uid': userId,
          'fcmToken': latestToken,
          'name': userData['name'] ?? '',
          'email': userData['email'] ?? '',
          'photoUrl': userData['photoUrl'] ?? '',
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
        showLog('✅ [Migration] User document created with FCM token');
      }

      // Update local storage
      userData['fcmToken'] = latestToken;
      await SharedPrefs.setUserDetails(jsonEncode(userData));
      showLog('✅ [Migration] Local FCM token updated');

      showLog('🎉 [Migration] FCM token migration completed successfully');
    } catch (e) {
      showLog('❌ [Migration] Error during FCM token migration: $e');
    }
  }

  /// Run this in your main.dart after FCM init to ensure all users get updated
  static Future<void> runMigrationIfNeeded() async {
    showLog('🔄 [Migration] Starting FCM token migration check...');

    // Try immediately first
    await migrateCurrentUserToken();

    // If token is still empty, keep trying in background
    _startBackgroundMigration();
  }

  /// Background migration that retries until FCM token is available
  static void _startBackgroundMigration() {
    int attempts = 0;
    const maxAttempts = 60; // Try for 30 seconds

    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      attempts++;

      final currentToken = FCMHelper.fcmToken;

      if (currentToken != null && currentToken.isNotEmpty) {
        showLog('✅ [Migration] FCM token available, running migration...');
        await migrateCurrentUserToken();
        timer.cancel();
      } else if (attempts >= maxAttempts) {
        showLog(
            '⚠️ [Migration] FCM token not available after ${maxAttempts * 500}ms');
        timer.cancel();
      } else if (attempts % 10 == 0) {
        showLog('⏳ [Migration] Waiting for FCM token... (${attempts * 500}ms)');
      }
    });
  }
}
