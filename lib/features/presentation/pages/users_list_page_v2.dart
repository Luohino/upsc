import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constant/shared_prefs_constants.dart';
import '../../../core/utils/common_imports.dart';
import '../../../core/providers/chat_providers.dart';
import '../../../core/services/hive_service.dart';
import '../../data/model/chat_model.dart';
import 'chat_page.dart';

/// LOCAL-FIRST Users List Page
/// Loads chats INSTANTLY from Hive, syncs Firebase in background
class UsersListPageV2 extends ConsumerStatefulWidget {
  const UsersListPageV2({super.key});

  @override
  ConsumerState<UsersListPageV2> createState() => _UsersListPageV2State();
}

class _UsersListPageV2State extends ConsumerState<UsersListPageV2> {
  String? currentUserId;
  Map<String, dynamic>? currentUser;
  final Map<String, StreamSubscription> _chatListeners = {};
  final Map<String, StreamSubscription> _userListeners = {};
  
  // Cache user data in memory for instant access
  final Map<String, Map<String, dynamic>> _usersCache = {};

  @override
  void initState() {
    super.initState();
    print('🚀 [UsersListV2] Initializing...');
    _loadCurrentUser();
    _syncFirebaseInBackground();
  }

  Future<void> _loadCurrentUser() async {
    final startTime = DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();
      final userPref = prefs.getString(SharedPrefsConstant.userDetails);
      if (userPref != null && userPref.isNotEmpty) {
        setState(() {
          currentUser = jsonDecode(userPref);
          currentUserId = currentUser?['uid'];
        });

        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        print('⚡ [UsersListV2] Current user loaded in ${elapsed}ms');
      } else {
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.googleAuthPage);
        }
      }
    } catch (e) {
      print('❌ [UsersListV2] Error loading user: $e');
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.googleAuthPage);
      }
    }
  }

  /// Sync Firebase → Hive in background (NON-BLOCKING)
  void _syncFirebaseInBackground() async {
    if (currentUserId == null) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (currentUserId == null) return;
    }

    print('🔄 [UsersListV2] Starting Firebase → Hive sync in background...');

    try {
      // Get all users from Firestore who have authenticated
      // Only show users who have a valid document in Firestore users collection
      // This ensures we only show users who have signed in and saved their data
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('uid', isNotEqualTo: currentUserId)
          .get();

      // Filter users to only include those with complete profile data
      // (name, email, photoUrl) to avoid showing incomplete/test users
      final validUsers = usersSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['email'] != null && 
               data['name'] != null && 
               data['email'].toString().isNotEmpty &&
               data['name'].toString().isNotEmpty;
      }).toList();

      print(
          '📥 [UsersListV2] Got ${validUsers.length} valid users from Firebase (filtered from ${usersSnapshot.docs.length} total)');

      // For each user, set up real-time listeners for BOTH user data AND chats
      for (var userDoc in validUsers) {
        final userData = userDoc.data();
        final otherUserId = userData['uid'] as String;
        final chatId = _getChatId(currentUserId!, otherUserId);

        // Cache user data
        _usersCache[otherUserId] = userData;

        // CRITICAL: Listen to user document changes (FCM token updates)
        _setupUserListener(otherUserId);
        
        // Set up real-time listener for each chat
        _setupChatListener(chatId, otherUserId);
      }

      print('✅ [UsersListV2] Firebase sync completed with real-time listeners');
      
      // Trigger UI rebuild to show users
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ [UsersListV2] Error syncing Firebase: $e');
    }
  }

  /// Set up real-time listener for user data (FCM token, online status, etc.)
  void _setupUserListener(String userId) {
    // Cancel existing listener if any
    _userListeners[userId]?.cancel();

    _userListeners[userId] = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((userDoc) {
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        
        // Update cache with latest user data (including FCM token)
        _usersCache[userId] = userData;
        
        final fcmToken = userData['fcmToken'];
        final deviceTokens = (userData['deviceTokens'] as List?)?.cast<String>() ?? [];
        
        print('🔄 [UsersListV2] User ${userData['name']} data updated');
        print('   FCM Token: ${fcmToken != null ? "${fcmToken.toString().substring(0, 20)}..." : "null"}');
        print('   Device Tokens: ${deviceTokens.length}');
        
        // Trigger UI rebuild when user data changes
        if (mounted) {
          setState(() {});
        }
      }
    }, onError: (error) {
      print('❌ [UsersListV2] Error listening to user $userId: $error');
    });
  }

  /// Set up real-time listener for a specific chat
  void _setupChatListener(String chatId, String otherUserId) {
    // Cancel existing listener if any
    _chatListeners[chatId]?.cancel();

    // Listen to chat document changes in real-time
    _chatListeners[chatId] = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .snapshots()
        .listen((chatDoc) async {
      if (chatDoc.exists) {
        final chatData = chatDoc.data()!;
        
        // Get fresh user data from cache
        final userData = _usersCache[otherUserId] ?? {};

        final lastMs = (chatData['lastMessageTimeMs'] as num?)?.toInt() ??
            (chatData['lastMessageTime'] as Timestamp?)
                ?.millisecondsSinceEpoch ??
            0;

        // Check if the last message is from the other user (incoming)
        final lastSenderId = chatData['lastSenderId'] as String?;
        final isIncoming = lastSenderId != null && lastSenderId != currentUserId;

        if (isIncoming) {
          print(
              '📬 [UsersListV2] Incoming message from ${userData['name']}: ${chatData['lastMessage']}');
        }

        // Calculate unread count
        int unreadCount = 0;
        if (isIncoming) {
          // Query unread messages from this user
          final unreadSnapshot = await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .where('senderId', isEqualTo: otherUserId)
              .where('isRead', isEqualTo: false)
              .get();
          unreadCount = unreadSnapshot.docs.length;
        }

        final chat = ChatModel(
          chatId: chatId,
          otherUserId: otherUserId,
          otherUserName: userData['name'] ?? 'Unknown',
          otherUserPhoto: userData['photoUrl'],
          lastMessage: chatData['lastMessage'] ?? '',
          lastMessageTime: lastMs,
          unreadCount: unreadCount,
          isOnline: userData['isOnline'] ?? false,
          lastSenderId: lastSenderId,
          isPinned: false,
          sortOrder: lastMs,
        );

        await HiveService.saveChat(chat);

        // Trigger UI refresh
        ref.read(chatListProvider.notifier).refresh();
      }
    }, onError: (error) {
      print('❌ [UsersListV2] Error listening to chat $chatId: $error');
    });
  }

  String _getChatId(String userId1, String userId2) {
    return userId1.hashCode <= userId2.hashCode
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp == 0) return '';

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return DateFormat('hh:mm a').format(date);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE').format(date);
    } else {
      return DateFormat('MMM dd').format(date);
    }
  }

  /// Format last message for display, handling call messages
  String _formatLastMessage(ChatModel chat) {
    final lastMessage = chat.lastMessage;

    if (lastMessage.isEmpty) {
      return 'Tap to start chatting';
    }

    // Stored as readable labels like "Missed call", "Calling...", etc.
    if (lastMessage.toLowerCase().contains('call')) {
      return lastMessage;
    }
    // Regular text message
    return lastMessage;
  }

  /// Format call duration for display
  String _formatCallDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final secs = seconds % 60;
      return secs > 0 ? '${minutes}m ${secs}s' : '${minutes}m';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
  }

  /// Check if message is a call message
  bool _isCallMessage(String message) {
    final m = message.toLowerCase();
    return m.contains('call');
  }

  /// Get appropriate call icon based on message content
  IconData _getCallIcon(String message) {
    try {
      final messageData = jsonDecode(message);
      final type = messageData['type'];
      return type == 'video' ? Icons.videocam : Icons.call;
    } catch (e) {
      return Icons.call;
    }
  }

  /// Get call icon color based on call status
  Color _getCallIconColor(ChatModel chat) {
    final isSentByMe = chat.lastSenderId == currentUserId;
    final m = chat.lastMessage.toLowerCase();
    if (m.contains('missed call') && !isSentByMe) {
      return Colors.red.withOpacity(0.8);
    }
    return Colors.white.withOpacity(0.6);
  }

  @override
  void dispose() {
    // Cancel all chat listeners
    for (var listener in _chatListeners.values) {
      listener.cancel();
    }
    _chatListeners.clear();
    
    // Cancel all user listeners
    for (var listener in _userListeners.values) {
      listener.cancel();
    }
    _userListeners.clear();
    
    print('🧹 [UsersListV2] Disposed all listeners');
    super.dispose();
  }

  Future<void> _handleLogout() async {
    try {
      // Cancel all listeners before logout
      for (var listener in _chatListeners.values) {
        listener.cancel();
      }
      _chatListeners.clear();
      
      for (var listener in _userListeners.values) {
        listener.cancel();
      }
      _userListeners.clear();

      if (currentUserId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .update(
                {'isOnline': false, 'lastSeen': FieldValue.serverTimestamp()});
      }

      await GoogleSignIn().signOut();
      await HiveService.clearAllData(); // Clear local data

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.googleAuthPage,
          (route) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.googleAuthPage,
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0E0E0E),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    // Watch chat list from Hive (INSTANT, reactive)
    final chats = ref.watch(chatListProvider);
    
    // Get all users from cache
    final allUsers = _usersCache.values.toList();
    
    // Create a map of userId -> chat for quick lookup
    final chatsByUserId = <String, ChatModel>{};
    for (var chat in chats) {
      chatsByUserId[chat.otherUserId] = chat;
    }
    
    // Merge: users with chats + users without chats
    final List<dynamic> displayItems = [];
    
    // Add users with chats (sorted by last message time)
    final usersWithChats = chats.map((chat) {
      return {'type': 'chat', 'chat': chat};
    }).toList();
    displayItems.addAll(usersWithChats);
    
    // Add users without chats (sorted alphabetically)
    final usersWithoutChats = allUsers.where((user) {
      return !chatsByUserId.containsKey(user['uid']);
    }).toList();
    
    usersWithoutChats.sort((a, b) {
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });
    
    displayItems.addAll(usersWithoutChats.map((user) {
      return {'type': 'user', 'user': user};
    }));

    print('🎨 [UsersListV2] Building UI with ${chats.length} chats and ${usersWithoutChats.length} users without chats');

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacementNamed(context, AppRoutes.infoPage);
          },
        ),
        title: const Text(
          'UPSC',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF1C1C1E),
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('Logout', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: displayItems.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No conversations yet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Users will appear here when they send you a message\nor when you start a conversation',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: displayItems.length,
              itemBuilder: (context, index) {
                final item = displayItems[index];
                if (item['type'] == 'chat') {
                  return _buildChatTile(item['chat'] as ChatModel);
                } else {
                  return _buildUserTile(item['user'] as Map<String, dynamic>);
                }
              },
            ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> userData) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          // Navigate to chat page to start conversation
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                receiverUser: userData,
                currentUser: currentUser!,
              ),
            ),
          );
          
          // After returning, refresh to show new chat
          ref.read(chatListProvider.notifier).refresh();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.05),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF2C2C2E),
                backgroundImage: userData['photoUrl'] != null &&
                        userData['photoUrl'].isNotEmpty
                    ? CachedNetworkImageProvider(userData['photoUrl'])
                    : null,
                child:
                    userData['photoUrl'] == null || userData['photoUrl'].isEmpty
                        ? Text(
                            userData['name'] != null && userData['name'].isNotEmpty
                                ? userData['name'][0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : null,
              ),
              const SizedBox(width: 12),
              // User info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userData['name'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to start chatting',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Online indicator (optional)
              if (userData['isOnline'] == true)
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0E0E0E),
                      width: 2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatTile(ChatModel chat) {
    final hasUnread = chat.unreadCount > 0;
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chat.chatId)
          .collection('typing')
          .doc(chat.otherUserId)
          .snapshots(),
      builder: (context, typingSnapshot) {
        bool isTyping = false;
        
        if (typingSnapshot.hasData && typingSnapshot.data!.exists) {
          final data = typingSnapshot.data!.data() as Map<String, dynamic>?;
          final typingStatus = data?['isTyping'] == true;
          final lastUpdate = data?['timestamp'] as Timestamp?;
          
          // Only show typing if updated within last 3 seconds
          if (typingStatus && lastUpdate != null) {
            final now = DateTime.now();
            final diff = now.difference(lastUpdate.toDate());
            if (diff.inSeconds < 3) {
              isTyping = true;
            }
          }
        }
        
        return _buildChatTileContent(chat, hasUnread, isTyping);
      },
    );
  }

  Widget _buildChatTileContent(ChatModel chat, bool hasUnread, bool isTyping) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          // Navigate to chat
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                receiverUser: {
                  'uid': chat.otherUserId,
                  'name': chat.otherUserName,
                  'photoUrl': chat.otherUserPhoto,
                  'isOnline': chat.isOnline,
                },
                currentUser: currentUser!,
              ),
            ),
          );
          
          // After returning from chat, refresh to update read status
          ref.read(chatListProvider.notifier).refresh();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.05),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF2C2C2E),
                backgroundImage: chat.otherUserPhoto != null &&
                        chat.otherUserPhoto!.isNotEmpty
                    ? CachedNetworkImageProvider(chat.otherUserPhoto!)
                    : null,
                child:
                    chat.otherUserPhoto == null || chat.otherUserPhoto!.isEmpty
                        ? Text(
                            chat.otherUserName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : null,
              ),
              const SizedBox(width: 12),
              // Chat info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            chat.otherUserName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatTimestamp(chat.lastMessageTime),
                          style: TextStyle(
                            color: hasUnread
                                ? const Color(0xFF007AFF)
                                : Colors.white.withOpacity(0.4),
                            fontSize: 12,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Show call icon if it's a call message
                        if (!isTyping && _isCallMessage(chat.lastMessage)) ...[
                          Icon(
                            _getCallIcon(chat.lastMessage),
                            size: 14,
                            color: _getCallIconColor(chat),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: isTyping
                              ? Row(
                                  children: [
                                    Text(
                                      'typing',
                                      style: TextStyle(
                                        color: Colors.green.shade400,
                                        fontSize: 14,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    _TypingDots(),
                                  ],
                                )
                              : Text(
                                  _formatLastMessage(chat),
                                  style: TextStyle(
                                    color: hasUnread
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.6),
                                    fontSize: 14,
                                    fontWeight: hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Unread indicator
              if (hasUnread)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF007AFF),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Animated typing dots widget
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            final progress = (_controller.value - delay) % 1.0;
            final opacity = 0.3 + (0.7 * (1 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0));
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.green.shade400.withOpacity(opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
