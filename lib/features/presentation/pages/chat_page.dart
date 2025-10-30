import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../data/services/call_message_service.dart';
import '../../data/model/notification_payload.dart';
import '../../data/model/chat_model.dart';
import '../../data/model/message_model.dart';
import '../../../core/utils/pip_manager.dart';
import '../../../core/widgets/pip_video_overlay.dart';
import '../../../core/utils/common_imports.dart';
import '../../../core/services/hive_service.dart';
import '../../../core/services/call_signal_service.dart';
import 'ios_incoming_call_page.dart';

class ChatPage extends StatefulWidget {
  final Map<String, dynamic> receiverUser;
  final Map<String, dynamic> currentUser;

  const ChatPage({
    super.key,
    required this.receiverUser,
    required this.currentUser,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode(); // Keep keyboard open

  Map<String, dynamic>? _replyingTo;
  String? _selectedMessageId;
  bool _showReactions = false;
  
  // OPTIMISTIC UI: Track messages being sent for instant appearance
  // Key = temporary message ID, Value = send status ('pending', 'sent', 'failed')
  final Map<String, String> _messageSendStatus = {};
  Timer? _sendingTimer; // Timer for cleanup
  
  // Typing indicator
  bool _isOtherUserTyping = false;
  Timer? _typingTimer;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _readReceiptSubscription;

  // Local-first
  List<Map<String, dynamic>> _localMessages = [];
  StreamSubscription? _fbSub; // background Firebase listener -> writes to Hive
  StreamSubscription? _hiveSub; // watch Hive changes -> update UI

  String get chatId =>
      _getChatId(widget.currentUser['uid'], widget.receiverUser['uid']);

  @override
  void initState() {
    super.initState();
    _loadLocalMessages(); // Load from Hive FIRST
    _startFirebaseSync(); // Background listener
    _startHiveWatch(); // React to local updates
    _markMessagesAsRead(); // Mark existing unread messages as read
    _startContinuousReadReceipts(); // Keep marking new messages as read
    _listenToTypingStatus(); // Listen for typing indicator
  }

  // Load messages from Hive instantly (0ms)
  Future<void> _loadLocalMessages() async {
    final startTime = DateTime.now();
    final messages = await HiveService.getMessages(chatId);

    if (mounted) {
      setState(() {
        _localMessages = messages
            .map((msg) => {
                  'messageId': msg.messageId,
                  'text': msg.text,
                  'senderId': msg.senderId,
                  'receiverId': msg.receiverId,
                  'timestamp':
                      Timestamp.fromMillisecondsSinceEpoch(msg.timestamp),
                  'isRead': msg.isRead,
                  'reactions': msg.reactions,
                  'isCallMessage': msg.isCallMessage,
                  'callMessageType': msg.callMessageType,
                  'callDuration': msg.callDuration,
                  'sendStatus': msg.sendStatus, // Include send status for icon display
                  if (msg.replyTo != null) 'replyTo': msg.replyTo, // Include replyTo when loading from Hive
                })
            .toList();
      });

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      print(
          '⚡ [ChatPage] Loaded ${messages.length} messages from Hive in ${elapsed}ms');
    }
  }

  // Sync Firebase messages to Hive (run in background)
  void _syncMessagesToHive(List<QueryDocumentSnapshot> firebaseMessages) async {
    if (firebaseMessages.isEmpty) return;
    
    // DON'T automatically delete temp messages here - let _sendMessage handle it
    // This prevents flicker when real message arrives
    
    final List<MessageModel> toSave = [];
    for (var doc in firebaseMessages) {
      final data = doc.data() as Map<String, dynamic>;
      try {
        final messageModel = MessageModel.fromFirestore(doc.id, data, chatId);
        toSave.add(messageModel);
      } catch (e) {
        print('⚠️ [ChatPage] Error parsing message: $e');
      }
    }
    if (toSave.isNotEmpty) {
      await HiveService.saveMessages(toSave);
      // Update chat metadata using the latest message (first doc is latest due to query ordering)
      final latest = firebaseMessages.first.data() as Map<String, dynamic>;
      final isCall = latest['isCallMessage'] == true;
      final lastText = isCall
          ? _callPreviewFromType(latest['callMessageType'] ?? '',
              (latest['callDuration'] as int?) ?? 0)
          : (latest['text'] ?? '');
      final lastMs = (latest['createdAt'] as int?) ??
          (latest['timestamp'] is Timestamp
              ? (latest['timestamp'] as Timestamp).millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch);
      final chatModel = ChatModel(
        chatId: chatId,
        otherUserId: widget.receiverUser['uid'],
        otherUserName: widget.receiverUser['name'] ?? 'Unknown',
        otherUserPhoto: widget.receiverUser['photoUrl'],
        lastMessage: lastText,
        lastMessageTime: lastMs,
        unreadCount: 0,
        isOnline: widget.receiverUser['isOnline'] ?? false,
        lastSenderId: latest['senderId'] as String?,
        isPinned: false,
        sortOrder: lastMs,
      );
      await HiveService.saveChat(chatModel);
    }
  }

  void _startFirebaseSync() {
    _fbSub?.cancel();
    _fbSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen((snap) => _syncMessagesToHive(snap.docs));
  }

  void _startHiveWatch() {
    _hiveSub?.cancel();
    _hiveSub = HiveService.watchMessages().listen((event) {
      final value = event.value;
      if (value is MessageModel) {
        if (value.chatId == chatId) {
          // Check if this is a message we just sent
          final isOurMessage = value.senderId == widget.currentUser['uid'];
          
          _loadLocalMessages();
          
          // Force scroll to bottom if we sent this message
          if (isOurMessage) {
            Future.delayed(const Duration(milliseconds: 50), () {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(0);
              }
            });
            Future.delayed(const Duration(milliseconds: 200), () {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(0);
              }
            });
          } else {
            // For received messages, only scroll if near bottom
            final wasAtBottom = _scrollController.hasClients && _scrollController.offset < 100;
            if (wasAtBottom) {
              Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
            }
          }
        }
      } else {
        _loadLocalMessages();
      }
    });
  }

  // Build readable label for call message types (local-first UI)
  String _callPreviewFromType(String type, int durationSec) {
    switch (type) {
      case 'missedCall':
        return 'Missed call';
      case 'callEnded':
        if (durationSec > 0) {
          final m = durationSec ~/ 60;
          final s = durationSec % 60;
          return m > 0
              ? 'Call ended • $m:${s.toString().padLeft(2, '0')} min'
              : 'Call ended • $s sec';
        }
        return 'Call ended';
      case 'outgoingCall':
        return 'Calling...';
      case 'incomingCall':
        return 'Incoming call...';
      case 'callAccepted':
        return 'Call accepted';
      case 'inCall':
        return 'In a call...';
      default:
        return 'Call';
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose(); // Dispose focus node
    _fbSub?.cancel();
    _hiveSub?.cancel();
    _sendingTimer?.cancel();
    _typingTimer?.cancel();
    _typingSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _setTypingStatus(false); // Clear typing status on exit
    super.dispose();
  }

  Future<void> _markMessagesAsRead() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isEqualTo: widget.receiverUser['uid'])
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.update({
        'isRead': true,
        'sendStatus': 'read', // Update sendStatus to show blue tick
      });
      
      // Also update in Hive
      final data = doc.data() as Map<String, dynamic>;
      final messageModel = MessageModel.fromFirestore(doc.id, data, chatId);
      final updatedMessage = MessageModel(
        messageId: messageModel.messageId,
        chatId: messageModel.chatId,
        text: messageModel.text,
        senderId: messageModel.senderId,
        receiverId: messageModel.receiverId,
        timestamp: messageModel.timestamp,
        isRead: true,
        reactions: messageModel.reactions,
        replyTo: messageModel.replyTo,
        sendStatus: 'read', // Blue tick
        isCallMessage: messageModel.isCallMessage,
        callMessageType: messageModel.callMessageType,
        callDuration: messageModel.callDuration,
      );
      await HiveService.saveMessage(updatedMessage);
    }
    
    print('✅ [ChatPage] Marked ${snapshot.docs.length} messages as read (blue tick)');
  }
  
  /// Continuously listen for unread messages and mark them as read
  /// This ensures messages show blue tick when receiver is viewing chat
  void _startContinuousReadReceipts() {
    _readReceiptSubscription?.cancel();
    _readReceiptSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isEqualTo: widget.receiverUser['uid'])
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isEmpty) return;
      
      print('👁️ [ChatPage] Marking ${snapshot.docs.length} new messages as read...');
      
      for (var doc in snapshot.docs) {
        await doc.reference.update({
          'isRead': true,
          'sendStatus': 'read',
        });
        
        // Update in Hive
        final data = doc.data();
        final messageModel = MessageModel.fromFirestore(doc.id, data, chatId);
        final updatedMessage = MessageModel(
          messageId: messageModel.messageId,
          chatId: messageModel.chatId,
          text: messageModel.text,
          senderId: messageModel.senderId,
          receiverId: messageModel.receiverId,
          timestamp: messageModel.timestamp,
          isRead: true,
          reactions: messageModel.reactions,
          replyTo: messageModel.replyTo,
          sendStatus: 'read',
          isCallMessage: messageModel.isCallMessage,
          callMessageType: messageModel.callMessageType,
          callDuration: messageModel.callDuration,
        );
        await HiveService.saveMessage(updatedMessage);
      }
    });
  }

  String _getChatId(String userId1, String userId2) {
    return userId1.hashCode <= userId2.hashCode
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  /// Listen to other user's typing status
  void _listenToTypingStatus() {
    _typingSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(widget.receiverUser['uid'])
        .snapshots()
        .listen((snapshot) {
      if (mounted && snapshot.exists) {
        final data = snapshot.data();
        final isTyping = data?['isTyping'] == true;
        final lastUpdate = data?['timestamp'] as Timestamp?;
        
        // Only show typing if updated within last 3 seconds
        if (isTyping && lastUpdate != null) {
          final now = DateTime.now();
          final diff = now.difference(lastUpdate.toDate());
          if (diff.inSeconds < 3) {
            setState(() {
              _isOtherUserTyping = true;
            });
            return;
          }
        }
        
        setState(() {
          _isOtherUserTyping = false;
        });
      }
    });
  }

  /// Update typing status in Firestore
  void _setTypingStatus(bool isTyping) {
    FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(widget.currentUser['uid'])
        .set({
      'isTyping': isTyping,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Called when user types in text field
  void _onTextChanged(String text) {
    if (text.trim().isNotEmpty) {
      _setTypingStatus(true);
      
      // Cancel previous timer
      _typingTimer?.cancel();
      
      // Auto-clear typing status after 2 seconds of no typing
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _setTypingStatus(false);
      });
    } else {
      _setTypingStatus(false);
    }
  }

  // Auto-scroll to bottom when new message is added
  // Force = true will scroll even if user is scrolled up (used when sending message)
  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    
    // If force=true, scroll immediately without postFrameCallback
    if (force) {
      // Jump immediately to bottom
      _scrollController.jumpTo(0);
      print('📜 [Scroll] FORCE scrolled to bottom');
    } else {
      // Normal scroll with animation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _scrollController.offset < 100) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final messageText = _messageController.text.trim();
    
    // Clear text but DON'T unfocus - this keeps keyboard open
    _messageController.clear();

    // ===== CAPTURE REPLY DATA BEFORE CLEARING UI =====
    final replyToData = _replyingTo; // Capture reply data
    
    // ===== CLEAR REPLY UI IMMEDIATELY (no delay) =====
    if (_replyingTo != null && mounted) {
      setState(() {
        _replyingTo = null; // Clear immediately so UI updates instantly
      });
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    
    // ===== OPTIMISTIC UI: Show message INSTANTLY with temp ID =====
    final tempMessageId = 'temp_${nowMs}_${widget.currentUser['uid']}';
    
    final optimisticMessage = MessageModel(
      messageId: tempMessageId,
      chatId: chatId,
      text: messageText,
      senderId: widget.currentUser['uid'],
      receiverId: widget.receiverUser['uid'],
      timestamp: nowMs,
      isRead: false,
      reactions: {},
      replyTo: replyToData,
      sendStatus: 'pending', // Clock icon ⏰
    );
    
    // Save IMMEDIATELY to Hive - message shows up instantly!
    await HiveService.saveMessage(optimisticMessage);
    print('⚡ [ChatPage] Optimistic message shown INSTANTLY');
    
    final messageData = {
      'text': messageText,
      'senderId': widget.currentUser['uid'],
      'senderName': widget.currentUser['name'],
      'receiverId': widget.receiverUser['uid'],
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': nowMs,
      'isRead': false,
      'isDelivered': false,
      'reactions': {},
      'sendStatus': 'pending',
      if (replyToData != null) 'replyTo': replyToData,
    };
    
    // FORCE scroll to bottom IMMEDIATELY (no delay, no animation)
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
      print('📜 [Scroll] Jumped to bottom immediately');
    }
    // Retry after UI updates
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });

    // ===== FIREBASE: Save to Firestore in background =====
    try {
      final messageDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(messageData);

      final firebaseMessageId = messageDoc.id;
      print('✅ [ChatPage] Message sent to Firebase with ID: $firebaseMessageId');
      
      // ===== REPLACE temp message with real Firebase message =====
      // Delete temp first, then save real (seamless transition)
      await HiveService.deleteMessage(tempMessageId);
      
      final realMessage = MessageModel(
        messageId: firebaseMessageId,
        chatId: chatId,
        text: messageText,
        senderId: widget.currentUser['uid'],
        receiverId: widget.receiverUser['uid'],
        timestamp: nowMs,
        isRead: false,
        reactions: {},
        replyTo: replyToData,
        sendStatus: 'pending', // Still pending, waiting for delivery
      );
      
      await HiveService.saveMessage(realMessage);
      print('🔄 [ChatPage] Replaced temp with real Firebase message');

      // Update chat metadata in Firebase
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'lastMessage': messageText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageTimeMs': nowMs,
        'lastSenderId': widget.currentUser['uid'],
        'participants': [widget.currentUser['uid'], widget.receiverUser['uid']],
      }, SetOptions(merge: true));

      // CRITICAL: Update Hive INSTANTLY so chat list updates immediately
      final chatModel = ChatModel(
        chatId: chatId,
        otherUserId: widget.receiverUser['uid'],
        otherUserName: widget.receiverUser['name'] ?? 'Unknown',
        otherUserPhoto: widget.receiverUser['photoUrl'],
        lastMessage: messageText,
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
        unreadCount: 0,
        isOnline: widget.receiverUser['isOnline'] ?? false,
        lastSenderId: widget.currentUser['uid'],
        isPinned: false,
        sortOrder: DateTime.now().millisecondsSinceEpoch,
      );
      await HiveService.saveChat(chatModel);
      print('💾 [ChatPage] Chat metadata saved to Hive INSTANTLY');

      // Auto-scroll to bottom after sending message (delayed to ensure render)
      Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);

      // Send FCM notification to ALL receiver devices (robust multi-device)
      print(
          '\n📤 [MESSAGE NOTIFICATION] ========================================');
      print(
          '📤 [MESSAGE NOTIFICATION] Attempting to send message push notification...');
      print('📤 [MESSAGE NOTIFICATION] Receiver: ${widget.receiverUser["name"]}');
      print('📤 [MESSAGE NOTIFICATION] Receiver UID: ${widget.receiverUser["uid"]}');
      print(
          '📤 [MESSAGE NOTIFICATION] Message: ${messageText.length > 50 ? messageText.substring(0, 50) + "..." : messageText}');

      try {
        // CRITICAL: Fetch latest receiver data from Firestore to ensure fresh FCM token
        print('🔄 [MESSAGE NOTIFICATION] Fetching receiver data from Firestore...');
        final receiverDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.receiverUser['uid'])
            .get();
        
        if (receiverDoc.exists) {
          final receiverData = receiverDoc.data()!;
          print('✅ [MESSAGE NOTIFICATION] Receiver found in Firestore');
          print('🔑 [MESSAGE NOTIFICATION] Receiver fcmToken: ${receiverData['fcmToken'] != null ? "${receiverData['fcmToken'].toString().substring(0, 20)}..." : "null"}');
          print('🔑 [MESSAGE NOTIFICATION] Receiver deviceTokens: ${receiverData['deviceTokens']}');
        } else {
          print('⚠️ [MESSAGE NOTIFICATION] Receiver not found in Firestore!');
        }
        
        await FCMHelper.sendToAllUserTokens(
          userId: widget.receiverUser['uid'],
          payload: NotificationPayload(
            callAction: CallAction.message,
            callerName: widget.currentUser['name'] ?? 'Someone',
            userId: widget.currentUser['uid'],
            imageUrl: widget.currentUser['photoUrl'] ?? '',
            callId: chatId,
            chatId: chatId,
            receiverId: widget.receiverUser['uid'],
            receiverName: widget.receiverUser['name'] ?? '',
            receiverProfilePic: widget.receiverUser['photoUrl'] ?? '',
            messageText: messageText,
          ),
        );
        print('✅ [MESSAGE NOTIFICATION] FCM sent successfully');

        // ===== FCM DELIVERED: Update to 'delivered' status (double grey tick) =====
        try {
          // Check if message is already read - don't downgrade from read to delivered
          final currentMsg = await messageDoc.get();
          final currentData = currentMsg.data();
          final isAlreadyRead = currentData?['isRead'] == true || currentData?['sendStatus'] == 'read';
          
          if (isAlreadyRead) {
            print('👁️ [ChatPage] Message already READ, keeping blue tick');
          } else {
            await messageDoc.update({'isDelivered': true, 'sendStatus': 'delivered'});
            
            // ===== UPDATE: Message now DELIVERED (double grey tick) =====
            final deliveredMessage = MessageModel(
              messageId: firebaseMessageId,
              chatId: chatId,
              text: messageText,
              senderId: widget.currentUser['uid'],
              receiverId: widget.receiverUser['uid'],
              timestamp: nowMs,
              isRead: false,
              reactions: {},
              replyTo: replyToData,
              sendStatus: 'delivered', // ✓✓ Double grey tick
            );
            
            await HiveService.saveMessage(deliveredMessage);
            print('✅✅ [ChatPage] Updated to DELIVERED (double grey tick)');
          }
        } catch (e) {
          print('❌ [MESSAGE DELIVERY] Failed to mark as delivered: $e');
          
          // ===== FALLBACK: Update to SENT (single grey tick) =====
          // Check if already read first
          final currentMsg = HiveService.getMessage(firebaseMessageId);
          if (currentMsg?.sendStatus == 'read') {
            print('👁️ [ChatPage] Message already READ, keeping blue tick');
          } else {
            final sentMessage = MessageModel(
              messageId: firebaseMessageId,
              chatId: chatId,
              text: messageText,
              senderId: widget.currentUser['uid'],
              receiverId: widget.receiverUser['uid'],
              timestamp: nowMs,
              isRead: false,
              reactions: {},
              replyTo: replyToData,
              sendStatus: 'sent', // ✓ Single grey tick
            );
            
            await HiveService.saveMessage(sentMessage);
            print('✅ [ChatPage] Updated to SENT (single grey tick)');
          }
        }
      } catch (e) {
        print('❌ [MESSAGE NOTIFICATION] Error: $e');
        print(
            '📤 [MESSAGE NOTIFICATION] ========================================\n');
        showLog('Error sending notification: $e');
      }
      
    } catch (e) {
      // ===== NETWORK ERROR: Keep pending, retry automatically =====
      print('⚠️ [ChatPage] Network error sending message: $e');
      print('🔄 [ChatPage] Message will retry automatically (keeping clock icon)');
      
      // DON'T mark as failed - keep 'pending' status
      // Message stays with clock icon until network is restored
      // Firebase will automatically retry
      
      // Optionally: Show a subtle toast (no red error)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.white.withOpacity(0.8), size: 16),
                const SizedBox(width: 8),
                const Text('Sending when online...'),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'reactions.${widget.currentUser['uid']}': emoji,
    });

    setState(() {
      _showReactions = false;
      _selectedMessageId = null;
    });
  }

  /// Initiate a call with the receiver user
  /// 
  /// NAVIGATION FLOW:
  /// 1. User taps call icon in chat_page.dart AppBar
  /// 2. This method is called immediately
  /// 3. Instantly navigates to ios_incoming_call_page.dart with all required parameters
  /// 4. The call page handles all setup (permissions, WebRTC, FCM notifications) in its initState
  /// 5. When call ends, returns to this chat_page with status result
  /// 
  /// PARAMETERS PASSED TO CALL PAGE:
  /// - callerName: Name of the person being called (receiver)
  /// - callerImage: Profile picture URL of receiver
  /// - isOutgoing: true (this is an outgoing call from current user)
  /// - isVideo: true for video calls, false for audio calls
  /// - chatId: Unique chat ID for this conversation
  /// - senderId: Current user's ID (the caller)
  /// - receiverId: Other user's ID (the person being called)
  /// - currentUserName: Current user's name (for FCM notifications)
  /// - currentUserImage: Current user's profile picture (for FCM notifications)
  /// - otherPersonFcmToken: Receiver's FCM token (for sending call notifications)
  /// - callPayload: WebRTC room configuration
  /// 
  /// RESULT HANDLING:
  /// When the user returns from the call page, handle the call status:
  /// - 'missed': Call was not answered
  /// - 'ended': Call was completed normally
  /// - 'declined': Call was rejected
  void _initiateCall(bool isVideo) async {
    print('\n========================================');
    print('📞 [CHAT] User tapped ${isVideo ? "VIDEO" : "AUDIO"} call icon');
    print('📞 [CHAT] Initiating instant navigation to call screen...');
    print('========================================\n');

    // Create WebRTC payload for the call
    // The caller will CREATE the room, and receiver will JOIN it
    final callPayload = NotificationPayload(
      callAction: CallAction.create, // Caller will CREATE the room
      callType: isVideo ? CallType.video : CallType.audio,
      userId: widget.receiverUser['uid'], // Receiver's user ID
      name: widget.receiverUser['name'] ?? 'Unknown',
      username: widget.receiverUser['name'] ?? 'Unknown',
      imageUrl: widget.receiverUser['photoUrl'] ?? '',
      notificationId: DateTime.now().millisecondsSinceEpoch.toString(),
      webrtcRoomId: chatId, // Use chatId as the WebRTC room ID
    );

    // INSTANT NAVIGATION: Navigate immediately to call screen
    // All call setup (permissions, WebRTC init, FCM notifications) happens in the call page
    // This ensures the UI responds instantly when user taps the call button
    print('🚀 [CHAT] Navigating to IOSIncomingCallPage NOW');
    if (!mounted) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IOSIncomingCallPage(
          // Receiver information (person being called)
          callerName: widget.receiverUser['name'] ?? 'Unknown',
          callerImage: widget.receiverUser['photoUrl'],
          
          // Call configuration
          isOutgoing: true, // This is an outgoing call
          isVideo: isVideo,
          
          // Chat/User IDs for Firebase and WebRTC
          chatId: chatId,
          senderId: widget.currentUser['uid'], // Current user (caller)
          receiverId: widget.receiverUser['uid'], // Other user (receiver)
          
          // Current user info (for sending FCM notifications to receiver)
          currentUserName: widget.currentUser['name'] ?? 'Someone',
          currentUserImage: widget.currentUser['photoUrl'] ?? '',
          
          // Receiver's FCM token (for sending call notification)
          otherPersonFcmToken: widget.receiverUser['fcmToken'],
          
          // WebRTC room configuration
          callPayload: callPayload,
        ),
      ),
    );

    // CALL RESULT HANDLING
    // The call page returns a status when the call ends
    // Update chat with appropriate call status message
    print('📞 [CHAT] Returned from call screen');
    print('📞 [CHAT] Mounted status: $mounted');
    print('📞 [CHAT] Current context: ${context.mounted}');
    if (result is Map && result['status'] is String) {
      final status = result['status'] as String;
      print('📞 [CHAT] Call ended with status: $status');
      
      // Send appropriate call status message to Firestore
      // This creates a call log entry in the chat history
      if (status == 'missed') {
        // Call was not answered by receiver
        await CallMessageService.sendCallStatusMessage(
          chatId: chatId,
          senderId: widget.currentUser['uid'],
          receiverId: widget.receiverUser['uid'],
          type: CallMessageType.missedCall,
        );
        print('✅ [CHAT] Missed call status saved to chat');
      } else if (status == 'ended') {
        // Call was answered and then ended normally
        await CallMessageService.sendCallStatusMessage(
          chatId: chatId,
          senderId: widget.currentUser['uid'],
          receiverId: widget.receiverUser['uid'],
          type: CallMessageType.callEnded,
        );
        print('✅ [CHAT] Call ended status saved to chat');
      } else if (status == 'declined') {
        // Call was declined/cancelled by caller before answer
        print('📞 [CHAT] Call was declined/cancelled');
        // No message saved for declined calls to avoid clutter
      }
    }
    
    print('📞 [CHAT] Call flow complete, back to chat');
    print('📞 [CHAT] Chat page is still mounted: $mounted');
    print('📞 [CHAT] Staying on chat page, NOT navigating anywhere');
  }

  @override
  Widget build(BuildContext context) {
    final pipManager = PIPManager();
    return GestureDetector(
      // Only unfocus when tapping outside input area
      onTap: () {
        // Don't unfocus on tap - let user control keyboard
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E0E),
        appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF2C2C2E),
              backgroundImage: widget.receiverUser['photoUrl'] != null &&
                      widget.receiverUser['photoUrl'].isNotEmpty
                  ? CachedNetworkImageProvider(widget.receiverUser['photoUrl'])
                  : null,
              child: widget.receiverUser['photoUrl'] == null ||
                      widget.receiverUser['photoUrl'].isEmpty
                  ? Text(
                      (widget.receiverUser['name'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.receiverUser['name'] ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isOtherUserTyping)
                    Row(
                      children: [
                        Text(
                          'typing',
                          style: TextStyle(
                            color: Colors.green.shade400,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 16,
                          height: 12,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _TypingDot(delay: 0),
                              _TypingDot(delay: 200),
                              _TypingDot(delay: 400),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white),
            onPressed: () => _initiateCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white),
            onPressed: () => _initiateCall(true),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background wallpaper with dimmed overlay
          Positioned.fill(
            child: Stack(
              children: [
                // Wallpaper image
                Image.asset(
                  'assets/bg.png',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
                // Dimmed overlay
                Container(
                  color: Colors.black.withOpacity(0.6),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Expanded(
                child: Builder(builder: (context) {
                  final displayMessages = _localMessages;
                  if (displayMessages.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet',
                        style: TextStyle(color: Colors.white54),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: displayMessages.length,
                    itemBuilder: (context, index) {
                      final message = displayMessages[index];
                      final messageId = message['messageId'] ?? '';
                      final isSentByMe =
                          message['senderId'] == widget.currentUser['uid'];
                      
                      // Get send status for this message (pending/sent/failed)
                      final sendStatus = message['sendStatus'] as String? ?? 'sent';
                      
                      // Show date separator if date changed from previous message
                      final showDateSeparator = _shouldShowDateSeparator(displayMessages, index);
                      
                      return Column(
                        children: [
                          if (showDateSeparator) _buildDateSeparator(message),
                          _buildMessageBubble(
                            messageId,
                            message,
                            isSentByMe,
                            sendStatus,
                          ),
                        ],
                      );
                    },
                  );
                }),
              ),
              if (_replyingTo != null) _buildReplyingToWidget(),
              _buildMessageInput(),
            ],
          ),
          // PIP Overlay
          if (pipManager.isInPIPMode &&
              pipManager.localRenderer != null &&
              pipManager.remoteRenderer != null)
            PIPVideoOverlay(
              localRenderer: pipManager.localRenderer!,
              remoteRenderer: pipManager.remoteRenderer!,
              callerName: pipManager.callerName ?? 'Unknown',
              isVideoCall: pipManager.isVideoCall,
              onClose: () {
                if (pipManager.onEndCall != null) {
                  pipManager.onEndCall!();
                }
                setState(() {});
              },
              onExpand: () {
                pipManager.exitPIPMode();
                if (pipManager.onExpand != null) {
                  pipManager.onExpand!();
                }
              },
            ),
        ],
      ),
      ),
    );
  }

  /// Check if we should show date separator between messages
  bool _shouldShowDateSeparator(List<Map<String, dynamic>> messages, int index) {
    if (index == messages.length - 1) return true; // Always show for first message
    
    final currentMsg = messages[index];
    final nextMsg = messages[index + 1];
    
    final currentDate = _getMessageDate(currentMsg['timestamp']);
    final nextDate = _getMessageDate(nextMsg['timestamp']);
    
    if (currentDate == null || nextDate == null) return false;
    
    // Show separator if dates are different
    return currentDate.day != nextDate.day ||
           currentDate.month != nextDate.month ||
           currentDate.year != nextDate.year;
  }
  
  /// Get DateTime from message timestamp
  DateTime? _getMessageDate(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return null;
  }
  
  /// Build WhatsApp-style date separator
  Widget _buildDateSeparator(Map<String, dynamic> message) {
    final timestamp = message['timestamp'];
    final date = _getMessageDate(timestamp);
    if (date == null) return const SizedBox.shrink();
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    String dateText;
    if (difference.inDays == 0) {
      dateText = 'Today';
    } else if (difference.inDays == 1) {
      dateText = 'Yesterday';
    } else if (difference.inDays < 7) {
      dateText = DateFormat('EEEE').format(date); // Monday, Tuesday, etc.
    } else if (date.year == now.year) {
      dateText = DateFormat('d MMMM').format(date); // 23 September
    } else {
      dateText = DateFormat('d MMMM yyyy').format(date); // 23 September 2025
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            dateText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyingToWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            color: const Color(0xFF007AFF),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${_replyingTo!['senderName'] ?? 'Message'}',
                  style: const TextStyle(
                    color: Color(0xFF007AFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyingTo!['text'] ?? '',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            onPressed: () {
              setState(() {
                _replyingTo = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
      String messageId, Map<String, dynamic> message, bool isSentByMe, String sendStatus) {
    // Check if this is a call message
    final isCallMessage = message['isCallMessage'] == true;
    showLog(
        '💬 [ChatPage] Building message bubble. Is call message: $isCallMessage');
    if (isCallMessage) {
      showLog('📞 [ChatPage] This is a call message, rendering call bubble');
      return _buildCallMessageBubble(message);
    }

    final reactions = message['reactions'] as Map<String, dynamic>?;
    final hasReactions = reactions != null && reactions.isNotEmpty;
    final replyTo = message['replyTo'] as Map<String, dynamic>?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SwipeableMessageBubble(
        messageId: messageId,
        message: message,
        isSentByMe: isSentByMe,
        sendStatus: sendStatus,
        reactions: reactions,
        hasReactions: hasReactions,
        replyTo: replyTo,
        onReply: () {
          // Clean the message text by removing any timestamp prefix
          String cleanText = message['text'] ?? '';
          // Remove pattern like "[10/26, 7:56 PM] Username: "
          final timestampPattern = RegExp(
              r'^\[\d{1,2}/\d{1,2},\s*\d{1,2}:\d{2}\s*[AP]M\]\s*[^:]+:\s*');
          cleanText = cleanText.replaceFirst(timestampPattern, '');

          // Set reply data
          _replyingTo = {
            'text': cleanText,
            'senderName': isSentByMe ? 'You' : widget.receiverUser['name'],
          };
          
          // CRITICAL: Request focus FIRST to keep keyboard open
          _messageFocusNode.requestFocus();
          
          // Then update UI
          setState(() {});
        },
        onLongPress: () {
          setState(() {
            _selectedMessageId = messageId;
            _showReactions = true;
          });
          _showReactionPicker(messageId);
        },
        formatTime: _formatMessageTime,
      ),
    );
  }

  Widget _buildCallMessageBubble(Map<String, dynamic> message) {
    showLog('📞 [ChatPage] Building call message bubble');
    showLog('📞 [ChatPage] Message data: $message');

    final callTypeStr = message['callMessageType'] as String?;
    final callDuration = message['callDuration'] as int?;

    showLog('📞 [ChatPage] Call type string: $callTypeStr');
    showLog('📞 [ChatPage] Call duration: $callDuration');

    CallMessageType? callType;
    try {
      callType = CallMessageType.values.firstWhere(
        (e) => e.toString().split('.').last == callTypeStr,
      );
      showLog('✅ [ChatPage] Parsed call type: $callType');
    } catch (e) {
      showLog(
          '⚠️ [ChatPage] Could not parse call type, defaulting to missedCall: $e');
      callType = CallMessageType.missedCall;
    }

    final messageText = CallMessageService.getCallMessageText(
      callType,
      duration: callDuration != null ? Duration(seconds: callDuration) : null,
    );
    showLog('📞 [ChatPage] Call message text: $messageText');

    IconData icon;
    Color iconColor;
    switch (callType) {
      case CallMessageType.missedCall:
        icon = Icons.call_missed;
        iconColor = Colors.red;
        break;
      case CallMessageType.callAccepted:
      case CallMessageType.callEnded:
        icon = Icons.call;
        iconColor = const Color(0xFF4CD964);
        break;
      default:
        icon = Icons.phone_callback;
        iconColor = Colors.white54;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 8),
              Text(
                messageText,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatMessageTime(message['timestamp'] as Timestamp?),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReactionPicker(String messageId) {
    // Find the message
    final message = _localMessages.firstWhere(
      (m) => m['messageId'] == messageId,
      orElse: () => {},
    );
    final messageText = message['text'] ?? '';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12151B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'React to message',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ['❤️', '😂', '😮', '😢', '😡', '👍']
                      .map((emoji) => GestureDetector(
                            onTap: () {
                              _addReaction(messageId, emoji);
                              Navigator.pop(ctx);
                            },
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 32)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                // Copy button
                ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: messageText));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Message copied'),
                        duration: Duration(seconds: 1),
                        backgroundColor: Color(0xFF4CD964),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C2C2E),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 45),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocusNode,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                maxLines: 5, // Max 5 lines, then scrollable (WhatsApp-style)
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onTextChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              // Don't unfocus - just send
              if (_messageController.text.trim().isNotEmpty) {
                await _sendMessage();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF007AFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_upward,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMessageTime(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is int) {
      date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      return '';
    }

    return DateFormat('hh:mm a').format(date);
  }
}

// Mock DocumentSnapshot for local storage messages
class _MockDocumentSnapshot implements DocumentSnapshot {
  @override
  final String id;
  final Map<String, dynamic> _data;

  _MockDocumentSnapshot(this.id, this._data);

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic get(Object field) => _data[field.toString()];

  @override
  dynamic operator [](Object field) => _data[field.toString()];

  @override
  bool get exists => true;

  @override
  DocumentReference get reference => throw UnimplementedError();

  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
}

// Custom swipeable message bubble with smooth gesture handling
class _SwipeableMessageBubble extends StatefulWidget {
  final String messageId;
  final Map<String, dynamic> message;
  final bool isSentByMe;
  final Map<String, dynamic>? reactions;
  final bool hasReactions;
  final Map<String, dynamic>? replyTo;
  final VoidCallback onReply;
  final VoidCallback onLongPress;
  final String Function(dynamic) formatTime;
  final String sendStatus; // 'pending', 'sent', 'delivered', 'read', 'failed'

  const _SwipeableMessageBubble({
    required this.messageId,
    required this.message,
    required this.isSentByMe,
    required this.reactions,
    required this.hasReactions,
    required this.replyTo,
    required this.onReply,
    required this.onLongPress,
    required this.formatTime,
    required this.sendStatus,
  });

  @override
  State<_SwipeableMessageBubble> createState() =>
      _SwipeableMessageBubbleState();
}

class _SwipeableMessageBubbleState extends State<_SwipeableMessageBubble> {
  double _dragX = 0; // negative => left, positive => right

  // Clean reply text by removing timestamp prefix like "[10/26, 7:56 PM] Username: "
  String _cleanReplyText(String text) {
    final timestampPattern =
        RegExp(r'^\[\d{1,2}/\d{1,2},\s*\d{1,2}:\d{2}\s*[AP]M\]\s*[^:]+:\s*');
    return text.replaceFirst(timestampPattern, '');
  }
  
  // Build message text with clickable URLs
  Widget _buildMessageText(String text) {
    final urlPattern = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    );
    
    final matches = urlPattern.allMatches(text);
    
    if (matches.isEmpty) {
      // No URLs, just return plain text
      return Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
        ),
      );
    }
    
    // Has URLs, build with clickable links
    final spans = <InlineSpan>[];
    int lastIndex = 0;
    
    for (final match in matches) {
      // Add text before URL
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ));
      }
      
      // Add clickable URL
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(
          color: Color(0xFF64B5F6),
          fontSize: 15,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
      ));
      
      lastIndex = match.end;
    }
    
    // Add remaining text after last URL
    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ));
    }
    
    return RichText(
      text: TextSpan(children: spans),
    );
  }

  // ===== WHATSAPP-STYLE STATUS ICONS =====
  // Shows appropriate icon based on message send status:
  // - 'pending': Clock icon (message being sent)
  // - 'sent': Single grey tick (sent to server)
  // - 'delivered': Double grey tick (delivered to device)
  // - 'read': Double blue tick (read by receiver)
  // - 'failed': Red exclamation (failed to send)
  Widget _buildMessageStatusIcon(String sendStatus, bool isRead) {
    if (sendStatus == 'pending') {
      // Pending: Show clock icon while message is being sent
      return const Icon(
        Icons.access_time,
        size: 14,
        color: Colors.white54,
      );
    } else if (sendStatus == 'failed') {
      // Failed: Show red exclamation mark
      return const Icon(
        Icons.error_outline,
        size: 14,
        color: Colors.red,
      );
    } else if (isRead || sendStatus == 'read') {
      // Read: Double blue tick
      return const Icon(
        Icons.done_all,
        size: 14,
        color: Color(0xFF007AFF),
      );
    } else if (sendStatus == 'delivered') {
      // Delivered: Double grey tick
      return const Icon(
        Icons.done_all,
        size: 14,
        color: Colors.white54,
      );
    } else {
      // Sent: Single grey tick (default)
      return const Icon(
        Icons.done,
        size: 14,
        color: Colors.white54,
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: widget.onLongPress,
      onHorizontalDragUpdate: (d) {
        final dx = d.delta.dx;
        if (widget.isSentByMe) {
          // My message (right side): allow left swipe only
          if (dx < 0) setState(() => _dragX = (_dragX + dx).clamp(-40, 0));
        } else {
          // Incoming message (left side): allow right swipe only
          if (dx > 0) setState(() => _dragX = (_dragX + dx).clamp(0, 40));
        }
      },
      onHorizontalDragEnd: (_) {
        final shouldReply = (widget.isSentByMe && _dragX <= -36) ||
            (!widget.isSentByMe && _dragX >= 36);
        if (shouldReply) widget.onReply();
        setState(() => _dragX = 0);
      },
      child: Transform.translate(
        offset: Offset(
            widget.isSentByMe ? _dragX.clamp(-40, 0) : _dragX.clamp(0, 40), 0),
        child: Align(
          alignment:
              widget.isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: widget.isSentByMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: widget.isSentByMe
                      ? const Color(0xFF5B4AB8) // Purple for sender
                      : const Color(0xFF1F2C34), // Dark grey for receiver
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.replyTo != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: Colors.white.withOpacity(0.5),
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.replyTo!['senderName'] ?? '',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _cleanReplyText(widget.replyTo!['text'] ?? ''),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                    _buildMessageText(widget.message['text'] ?? ''),
                  ],
                ),
              ),
              if (widget.hasReactions)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.reactions!.values
                        .map((emoji) =>
                            Text(emoji, style: const TextStyle(fontSize: 14)))
                        .toList(),
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget
                        .formatTime(widget.message['timestamp'] as Timestamp?),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                  // Show status icon only for sent messages (not received)
                  if (widget.isSentByMe) ...[
                    const SizedBox(width: 4),
                    _buildMessageStatusIcon(
                      widget.sendStatus,
                      widget.message['isRead'] as bool? ?? false,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Animated typing dot indicator
class _TypingDot extends StatefulWidget {
  final int delay;
  
  const _TypingDot({required this.delay});
  
  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    // Delay start based on dot position
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.green.shade400.withOpacity(0.5 + (_animation.value * 0.5)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
