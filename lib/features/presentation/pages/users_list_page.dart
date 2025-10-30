import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/constant/shared_prefs_constants.dart';
import '../../../core/utils/common_imports.dart';
import 'chat_page.dart';

class UsersListPage extends StatefulWidget {
  const UsersListPage({super.key});

  @override
  State<UsersListPage> createState() => _UsersListPageState();
}

class _UsersListPageState extends State<UsersListPage> {
  String? currentUserId;
  Map<String, dynamic>? currentUser;
  List<Map<String, dynamic>>? _sortedUsers;
  bool _isSorting = false;
  bool _hasLoadedCache = false;
  final Map<String, StreamSubscription> _messageListeners = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadSortedUsersFromCache();
  }

  @override
  void dispose() {
    // Cancel all message listeners
    for (var listener in _messageListeners.values) {
      listener.cancel();
    }
    _messageListeners.clear();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userPref = prefs.getString(SharedPrefsConstant.userDetails);
      if (userPref != null && userPref.isNotEmpty) {
        setState(() {
          currentUser = jsonDecode(userPref);
          currentUserId = currentUser?['uid'];
        });
      } else {
        // No user data found, redirect to auth
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.googleAuthPage);
        }
      }
    } catch (e) {
      print('Error loading user: $e');
      // On error, redirect to auth
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.googleAuthPage);
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      // Update online status
      if (currentUserId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .update(
                {'isOnline': false, 'lastSeen': FieldValue.serverTimestamp()});
      }

      // Sign out from Google
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();

      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Navigate to Google Auth page
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.googleAuthPage,
          (route) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
      // Even if error, still navigate to auth
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.googleAuthPage,
          (route) => false,
        );
      }
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
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
  String _formatLastMessage(String lastMessage, String? lastSenderId) {
    if (lastMessage.isEmpty) {
      return 'Tap to start chatting';
    }
    // We store readable call labels like "Missed call", "Calling...", etc.
    if (_isCallMessage(lastMessage)) {
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

  /// Build readable label from call type
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

  /// Check if message is a call message
  bool _isCallMessage(String message) {
    final m = message.toLowerCase();
    return m.contains('call');
  }

  /// Get appropriate call icon based on message content
  IconData _getCallIcon(String message) {
    // We don't track audio/video here; use generic call icon
    return Icons.call;
  }

  /// Get call icon color based on call status
  Color _getCallIconColor(String message, String? lastSenderId) {
    final isSentByMe = lastSenderId == currentUserId;
    final m = message.toLowerCase();
    if (m.contains('missed call') && !isSentByMe) {
      return Colors.red.withOpacity(0.8);
    }
    return Colors.white.withOpacity(0.6);
  }

  Stream<QuerySnapshot> _getLastMessageStream(String chatId) {
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots();
  }

  void _setupMessageListener(String chatId) {
    // Listen to the chat document for real-time updates
    _messageListeners[chatId] = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .snapshots()
        .listen((chatDoc) {
      if (chatDoc.exists && mounted) {
        final chatData = chatDoc.data();
        final lastSenderId = chatData?['lastSenderId'] as String?;
        
        // Check if this is an incoming message (from someone else)
        if (lastSenderId != null && lastSenderId != currentUserId) {
          print('📬 [UsersListPage] Incoming message detected in chat $chatId');
          // Force UI update by invalidating cache
          setState(() {
            // This will trigger a rebuild with the latest data from StreamBuilder
          });
        }
      }
    });
  }

  String _getChatId(String userId1, String userId2) {
    return userId1.hashCode <= userId2.hashCode
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  Future<void> _loadSortedUsersFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('sorted_users_cache');
      if (cachedData != null) {
        final List<dynamic> decoded = jsonDecode(cachedData);
        _sortedUsers = decoded.map((e) {
          final user = Map<String, dynamic>.from(e);
          // Convert string back to DateTime
          if (user['_lastMessageTime'] is String) {
            user['_lastMessageTime'] = DateTime.parse(user['_lastMessageTime']);
          }
          return user;
        }).toList();
        _hasLoadedCache = true;
        if (mounted) setState(() {});
      }
    } catch (e) {
      print('Error loading sorted users cache: $e');
    }
  }

  Future<void> _saveSortedUsersToCache(List<Map<String, dynamic>> users) async {
    try {
      // Convert to serializable format - only save basic user info + sort time
      final serializableUsers = users.map((user) {
        final sortTime = user['_lastMessageTime'];
        return {
          'uid': user['uid'],
          'name': user['name'],
          'email': user['email'],
          'photoUrl': user['photoUrl'],
          'fcmToken': user['fcmToken'],
          'isOnline': user['isOnline'],
          '_lastMessageTime':
              sortTime is DateTime ? sortTime.toIso8601String() : null,
        };
      }).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'sorted_users_cache', jsonEncode(serializableUsers));
    } catch (e) {
      print('Error saving sorted users cache: $e');
    }
  }

  void _sortUsersInBackground(List<QueryDocumentSnapshot> users) async {
    // This runs in background, doesn't block UI
    final List<Map<String, dynamic>> usersWithTime = [];

    for (var userDoc in users) {
      final userData = userDoc.data() as Map<String, dynamic>;
      final userId = userData['uid'] as String;
      final chatId = _getChatId(currentUserId!, userId);

      final lastMsgSnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      DateTime? lastMessageTime;
      bool hasMessages = false;
      if (lastMsgSnapshot.docs.isNotEmpty) {
        final timestamp =
            lastMsgSnapshot.docs.first.data()['timestamp'] as Timestamp?;
        lastMessageTime = timestamp?.toDate();
        hasMessages = true;
      }

      usersWithTime.add({
        ...userData,
        '_lastMessageTime': lastMessageTime,
        '_hasMessages': hasMessages,
      });
    }

    // Sort: users with messages first (by time), then users without messages (alphabetically)
    usersWithTime.sort((a, b) {
      final aHasMessages = a['_hasMessages'] as bool? ?? false;
      final bHasMessages = b['_hasMessages'] as bool? ?? false;
      
      // If one has messages and the other doesn't, prioritize the one with messages
      if (aHasMessages && !bHasMessages) return -1;
      if (!aHasMessages && bHasMessages) return 1;
      
      // Both have messages - sort by time
      if (aHasMessages && bHasMessages) {
        final aTime = a['_lastMessageTime'] as DateTime?;
        final bTime = b['_lastMessageTime'] as DateTime?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      }
      
      // Both don't have messages - sort alphabetically by name
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    // Save to local storage
    await _saveSortedUsersToCache(usersWithTime);

    // Update UI with sorted list (only happens once)
    if (mounted) {
      setState(() {
        _sortedUsers = usersWithTime;
        _hasLoadedCache = true;
        _isSorting = false;
      });
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
          'Customer Support',
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('uid', isNotEqualTo: currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final allUsers = snapshot.data?.docs ?? [];
          
          // Filter to only show users with complete profile data
          final users = allUsers.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['email'] != null && 
                   data['name'] != null && 
                   data['email'].toString().isNotEmpty &&
                   data['name'].toString().isNotEmpty;
          }).toList();

          if (users.isEmpty) {
            return const Center(
              child: Text(
                'No users found',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            );
          }

          // Show cached sorted users immediately, or re-sort if cache was cleared
          List<Map<String, dynamic>> displayUsers;

          if (_sortedUsers != null && _hasLoadedCache) {
            // Use cached sorted list
            displayUsers = _sortedUsers!;
          } else {
            // No cache or cache was cleared - show unsorted, sort in background
            displayUsers =
                users.map((e) => e.data() as Map<String, dynamic>).toList();

            if (!_isSorting) {
              _isSorting = true;
              _hasLoadedCache = false; // Reset flag to allow re-sort
              _sortUsersInBackground(users);
            }
          }

          return ListView.builder(
            itemCount: displayUsers.length,
            itemBuilder: (context, index) {
              final userData = displayUsers[index];
              final userId = userData['uid'] as String;
              final chatId = _getChatId(currentUserId!, userId);

              // Set up real-time listener for this chat if not already listening
              if (!_messageListeners.containsKey(chatId)) {
                _setupMessageListener(chatId);
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _getLastMessageStream(chatId),
                builder: (context, messageSnapshot) {
                  String lastMessage = 'Tap to start chatting';
                  String lastMessageTime = '';
                  String? lastSenderId;
                  bool hasUnread = false;

                  if (messageSnapshot.hasData &&
                      messageSnapshot.data!.docs.isNotEmpty) {
                    final lastMsg = messageSnapshot.data!.docs.first.data()
                        as Map<String, dynamic>;
                    // Derive last message preview
                    lastSenderId = lastMsg['senderId'];
                    lastMessageTime =
                        _formatTimestamp(lastMsg['timestamp'] as Timestamp?);

                    // If it's a call message, build a readable label; else use text
                    if (lastMsg['isCallMessage'] == true) {
                      final type =
                          (lastMsg['callMessageType'] as String?) ?? '';
                      final durationSec =
                          (lastMsg['callDuration'] as int?) ?? 0;
                      lastMessage = _callPreviewFromType(type, durationSec);
                    } else {
                      lastMessage = lastMsg['text'] ?? '';
                    }

                    hasUnread = lastMsg['senderId'] != currentUserId &&
                        !(lastMsg['isRead'] ?? false);
                  }

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        // Navigate to chat page and wait for return
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatPage(
                              receiverUser: userData,
                              currentUser: currentUser!,
                            ),
                          ),
                        );

                        // When user returns, invalidate cache to trigger re-sort
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('sorted_users_cache');
                        setState(() {
                          _sortedUsers = null;
                          _hasLoadedCache = false;
                          _isSorting = false;
                        });
                        print(
                            '♻️ Cache invalidated on return from chat, will re-sort');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withOpacity(0.1),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Profile Picture
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: const Color(0xFF2C2C2E),
                              backgroundImage: userData['photoUrl'] != null &&
                                      userData['photoUrl'].isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      userData['photoUrl'])
                                  : null,
                              child: userData['photoUrl'] == null ||
                                      userData['photoUrl'].isEmpty
                                  ? Text(
                                      (userData['name'] ?? 'U')[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            // Name and Last Message
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
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      // Show call icon if it's a call message
                                      if (_isCallMessage(lastMessage)) ...[
                                        Icon(
                                          _getCallIcon(lastMessage),
                                          size: 14,
                                          color: _getCallIconColor(
                                              lastMessage, lastSenderId),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Expanded(
                                        child: Text(
                                          _formatLastMessage(
                                              lastMessage, lastSenderId),
                                          style: TextStyle(
                                            color: hasUnread
                                                ? Colors.white
                                                : Colors.white54,
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
                            // Time and Unread Badge
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (lastMessageTime.isNotEmpty)
                                  Text(
                                    lastMessageTime,
                                    style: TextStyle(
                                      color: hasUnread
                                          ? const Color(0xFF007AFF)
                                          : Colors.white54,
                                      fontSize: 12,
                                      fontWeight: hasUnread
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                if (hasUnread) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF007AFF),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
