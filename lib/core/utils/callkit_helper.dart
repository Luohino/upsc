import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../features/data/model/notification_payload.dart';
import 'common_imports.dart';

class CallKitHelper {
  static Future<void> showCallkitIncoming({
    required NotificationPayload? payload,
  }) async {
    showLog('📱 [CallKit] showCallkitIncoming called');
    showLog('📱 [CallKit] Payload: ${payload?.toJson()}');

    // On web, CallKit doesn't work - show browser notification and navigate
    if (kIsWeb) {
      showLog('🌐 [CallKit] Web platform - showing incoming call UI');
      // Navigate to the call page immediately on web
      final context = AppConstants.navigatorKey.currentContext;
      if (context != null && payload != null) {
        if (payload.callType == CallType.video) {
          Navigator.pushNamed(
            context,
            AppRoutes.videoCallPage,
            arguments: payload,
          );
        } else if (payload.callType == CallType.audio) {
          Navigator.pushNamed(
            context,
            AppRoutes.audioCallPage,
            arguments: payload,
          );
        }
      }
      return;
    }

    showLog('📱 [CallKit] Mobile platform - setting up CallKit params');
    showLog('📱 [CallKit] Caller: ${payload?.username}');
    showLog('📱 [CallKit] Call type: ${payload?.callType}');

    // Mobile platforms - use only notification, NO CallKit UI
    final params = CallKitParams(
      id: payload?.notificationId,
      nameCaller: payload?.username,
      appName: 'UPSC',
      avatar: payload?.imageUrl ?? 'https://i.pravatar.cc',
      handle: payload?.callType == CallType.video
          ? 'Incoming video call'
          : 'Incoming audio call',
      type: 1, // Type 1 = notification only
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      extra: payload?.toJson(),
      headers: <String, dynamic>{'apiKey': 'Abc@123!', 'platform': 'flutter'},
      android: AndroidParams(
        isCustomNotification: false, // Disable CallKit custom UI completely
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0E0E0E',
        actionColor: '#4CD964',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: "Incoming Call",
        missedCallNotificationChannelName: "Missed Call",
        isShowCallID: false,
      ),
      ios: IOSParams(
        iconName: 'CallKitLogo',
        handleType: '',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    showLog('📱 [CallKit] CallKit params created');
    showLog('📱 [CallKit] ID: ${params.id}');
    showLog('📱 [CallKit] Name: ${params.nameCaller}');
    showLog('📱 [CallKit] Handle: ${params.handle}');

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
      showLog('✅ [CallKit] Full-screen call UI should now be showing!');
    } catch (e) {
      showLog('❌ [CallKit] Error showing CallKit: $e');
    }
  }

  static Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }
}
