import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/data/model/notification_payload.dart';
import '../constant/app_constants.dart';
import '../utils/common_imports.dart';
import '../../features/presentation/pages/ios_incoming_call_page.dart';

class CallSignalService {
  static StreamSubscription<QuerySnapshot>? _sub;

  static Future<void> sendCallSignal({
    required String toUserId,
    required NotificationPayload payload,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await FirebaseFirestore.instance.collection('call_signals').add({
        'toUserId': toUserId,
        'fromUserId': payload.userId,
        'createdAt': now,
        'ttlMs': 45 * 1000, // expire after 45s
        'status': 'pending',
        'payload': payload.toJson(),
      });
      showLog('📡 [CallSignal] Enqueued call signal to $toUserId');
    } catch (e) {
      showLog('❌ [CallSignal] Failed to write call signal: $e');
    }
  }

  static void startListening({required String currentUserId}) {
    if (currentUserId.isEmpty) {
      showLog('❌ [CallSignal] startListening called with empty userId');
      return;
    }
    _sub?.cancel();
    final cutoff = DateTime.now().millisecondsSinceEpoch - 60 * 1000;
    _sub = FirebaseFirestore.instance
        .collection('call_signals')
        .where('toUserId', isEqualTo: currentUserId)
        // Avoid composite index requirement; filter by time on client
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        final createdAt = (data['createdAt'] as num?)?.toInt() ?? 0;
        if (createdAt < cutoff) continue;
        if ((data['status'] as String?) != 'pending') continue;
        final payloadMap = Map<String, dynamic>.from(data['payload'] ?? {});
        final payload = NotificationPayload.fromJson(payloadMap);

        // Open incoming call UI
        final ctx = AppConstants.navigatorKey.currentContext;
        if (ctx != null) {
          Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => IOSIncomingCallPage(
                callerName: payload.name ?? payload.username ?? 'Unknown',
                callerImage: payload.imageUrl,
                isOutgoing: false,
                isVideo: payload.callType == CallType.video,
                callPayload: payload,
              ),
            ),
          );
        }

        // Mark delivered to avoid duplicates
        try {
          await change.doc.reference.update({'status': 'delivered'});
        } catch (_) {}

        // Auto-clean old signals
        _cleanupExpired();
      }
    });
  }

  static Future<void> _cleanupExpired() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final qs = await FirebaseFirestore.instance
          .collection('call_signals')
          .where('createdAt', isLessThan: now - 5 * 60 * 1000)
          .get();
      for (final d in qs.docs) {
        await d.reference.delete();
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
