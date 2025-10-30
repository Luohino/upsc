import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/message_model.dart';
import '../../../core/services/hive_service.dart';
import '../model/chat_model.dart';

class CallMessageService {
  static Future<String> sendCallStatusMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required CallMessageType type,
    Duration? callDuration,
  }) async {
    print('\n📞 [CALL MESSAGE] ========================================');
    print('📞 [CALL MESSAGE] Sending call status message...');
    print('📞 [CALL MESSAGE] Chat ID: $chatId');
    print('📞 [CALL MESSAGE] Sender: $senderId');
    print('📞 [CALL MESSAGE] Receiver: $receiverId');
    print('📞 [CALL MESSAGE] Type: ${type.toString().split('.').last}');
    if (callDuration != null) {
      print('📞 [CALL MESSAGE] Duration: ${callDuration.inSeconds} seconds');
    }

    // Generate a temporary message ID for Hive (will be replaced with Firestore ID)
    final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Human readable text that we also store in Chat metadata
    final displayText = getCallMessageText(type, duration: callDuration);

    // STEP 1: Save to Hive IMMEDIATELY for instant UI update (message + chat)
    print('💾 [CALL MESSAGE] Saving to Hive for instant display...');
    final hiveMessage = MessageModel(
      messageId: tempMessageId,
      chatId: chatId,
      text: '', // Call messages don't have text
      senderId: senderId,
      receiverId: receiverId,
      timestamp: currentTimestamp,
      isRead: false,
      isCallMessage: true,
      callMessageType: type.toString().split('.').last,
      callDuration: callDuration?.inSeconds,
    );

    try {
      await HiveService.saveMessage(hiveMessage);
      // Update or create chat metadata locally so list shows "Missed call/Calling..."
      final existing = HiveService.getChat(chatId);
      final chat = ChatModel(
        chatId: chatId,
        otherUserId: existing?.otherUserId ?? receiverId,
        otherUserName: existing?.otherUserName ?? 'Unknown',
        otherUserPhoto: existing?.otherUserPhoto,
        lastMessage: displayText,
        lastMessageTime: currentTimestamp,
        unreadCount: existing?.unreadCount ?? 0,
        isOnline: existing?.isOnline ?? false,
        lastSenderId: senderId,
        isPinned: existing?.isPinned ?? false,
        sortOrder: currentTimestamp,
      );
      await HiveService.saveChat(chat);
      print('✅ [CALL MESSAGE] Saved to Hive instantly (message + chat)!');
    } catch (e) {
      print('❌ [CALL MESSAGE] Hive save failed: $e');
      // Continue anyway - Firebase is the source of truth
    }

    // STEP 2: Save to Firebase (source of truth)
    final messageData = {
      'senderId': senderId,
      'receiverId': receiverId,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': currentTimestamp,
      'isRead': false,
      'isCallMessage': true,
      'callMessageType': type.toString().split('.').last,
      if (callDuration != null) 'callDuration': callDuration.inSeconds,
    };

    print('📤 [CALL MESSAGE] Sending to Firebase...');

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(messageData);

      print('✅ [CALL MESSAGE] Saved to Firebase! Doc ID: ${docRef.id}');

      // STEP 3: Update parent chat metadata in Firestore so list shows call status
      try {
        await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
          'lastMessage': displayText,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageTimeMs': currentTimestamp,
          'lastSenderId': senderId,
          'participants': [senderId, receiverId],
        }, SetOptions(merge: true));
        print('✅ [CALL MESSAGE] Updated chat metadata in Firestore');
      } catch (e) {
        print('⚠️ [CALL MESSAGE] Failed to update chat metadata: $e');
      }

      // STEP 4: Update Hive with real Firebase ID (message)
      print('🔄 [CALL MESSAGE] Updating Hive with real message ID...');
      try {
        // Delete temp message
        await HiveService.deleteMessage(tempMessageId);

        // Save with real ID
        final updatedMessage = MessageModel(
          messageId: docRef.id,
          chatId: chatId,
          text: '',
          senderId: senderId,
          receiverId: receiverId,
          timestamp: currentTimestamp,
          isRead: false,
          isCallMessage: true,
          callMessageType: type.toString().split('.').last,
          callDuration: callDuration?.inSeconds,
        );
        await HiveService.saveMessage(updatedMessage);
        print('✅ [CALL MESSAGE] Hive updated with real ID');
      } catch (e) {
        print('⚠️ [CALL MESSAGE] Failed to update Hive ID: $e');
      }

      print('📞 [CALL MESSAGE] ========================================\n');
      return docRef.id;
    } catch (e) {
      print('❌ [CALL MESSAGE] Firebase error: $e');
      print('📞 [CALL MESSAGE] ========================================\n');
      rethrow;
    }
  }

  static String getCallMessageText(CallMessageType type, {Duration? duration}) {
    switch (type) {
      case CallMessageType.outgoingCall:
        return 'Calling...';
      case CallMessageType.incomingCall:
        return 'Incoming call...';
      case CallMessageType.missedCall:
        return 'Missed call';
      case CallMessageType.callAccepted:
        return 'Call accepted';
      case CallMessageType.callEnded:
        if (duration != null) {
          final minutes = duration.inMinutes;
          final seconds = duration.inSeconds % 60;
          if (minutes > 0) {
            return 'Call ended • $minutes:${seconds.toString().padLeft(2, '0')} min';
          }
          return 'Call ended • $seconds sec';
        }
        return 'Call ended';
      case CallMessageType.inCall:
        return 'In a call...';
    }
  }
}

enum CallMessageType {
  outgoingCall,
  incomingCall,
  missedCall,
  callAccepted,
  callEnded,
  inCall,
}
