import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocalStorageService {
  static const String _messagesPrefix = 'cached_messages_';
  static const String _lastSyncPrefix = 'last_sync_';

  // Save messages to local storage
  static Future<void> saveMessagesToLocal(
      String chatId, List<Map<String, dynamic>> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = jsonEncode(messages);
      await prefs.setString('$_messagesPrefix$chatId', messagesJson);
      await prefs.setInt(
          '$_lastSyncPrefix$chatId', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('Error saving messages to local: $e');
    }
  }

  // Load messages from local storage
  static Future<List<Map<String, dynamic>>> loadMessagesFromLocal(
      String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getString('$_messagesPrefix$chatId');

      if (messagesJson != null) {
        final List<dynamic> decoded = jsonDecode(messagesJson);
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('Error loading messages from local: $e');
    }
    return [];
  }

  // Add a single message to local cache
  static Future<void> addMessageToLocal(
      String chatId, Map<String, dynamic> message) async {
    try {
      final messages = await loadMessagesFromLocal(chatId);

      // Add timestamp if not present
      if (message['timestamp'] == null) {
        message['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      } else if (message['timestamp'] is Timestamp) {
        message['timestamp'] =
            (message['timestamp'] as Timestamp).millisecondsSinceEpoch;
      }

      // Add message ID if not present
      if (message['id'] == null) {
        message['id'] = 'local_${DateTime.now().millisecondsSinceEpoch}';
      }

      messages.insert(0, message);

      // Keep only last 500 messages to avoid storage issues
      if (messages.length > 500) {
        messages.removeRange(500, messages.length);
      }

      await saveMessagesToLocal(chatId, messages);
    } catch (e) {
      print('Error adding message to local: $e');
    }
  }

  // Update message reactions in local storage
  static Future<void> updateMessageReaction(
      String chatId, String messageId, String userId, String emoji) async {
    try {
      final messages = await loadMessagesFromLocal(chatId);

      for (var message in messages) {
        if (message['id'] == messageId) {
          if (message['reactions'] == null) {
            message['reactions'] = {};
          }
          message['reactions'][userId] = emoji;
          break;
        }
      }

      await saveMessagesToLocal(chatId, messages);
    } catch (e) {
      print('Error updating reaction in local: $e');
    }
  }

  // Mark messages as read in local storage
  static Future<void> markMessagesAsReadLocal(
      String chatId, String currentUserId) async {
    try {
      final messages = await loadMessagesFromLocal(chatId);

      for (var message in messages) {
        if (message['senderId'] != currentUserId) {
          message['isRead'] = true;
        }
      }

      await saveMessagesToLocal(chatId, messages);
    } catch (e) {
      print('Error marking messages as read in local: $e');
    }
  }

  // Get last sync time
  static Future<DateTime?> getLastSyncTime(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('$_lastSyncPrefix$chatId');
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      print('Error getting last sync time: $e');
    }
    return null;
  }

  // Clear all cached messages for a chat
  static Future<void> clearChatCache(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_messagesPrefix$chatId');
      await prefs.remove('$_lastSyncPrefix$chatId');
    } catch (e) {
      print('Error clearing chat cache: $e');
    }
  }

  // Get all cached chat IDs
  static Future<List<String>> getCachedChatIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final chatIds = <String>[];

      for (var key in keys) {
        if (key.startsWith(_messagesPrefix)) {
          chatIds.add(key.replaceFirst(_messagesPrefix, ''));
        }
      }

      return chatIds;
    } catch (e) {
      print('Error getting cached chat IDs: $e');
      return [];
    }
  }

  // Save user data to local storage
  static Future<void> saveUserToLocal(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = userData['uid'];
      await prefs.setString('cached_user_$userId', jsonEncode(userData));
    } catch (e) {
      print('Error saving user to local: $e');
    }
  }

  // Load user data from local storage
  static Future<Map<String, dynamic>?> loadUserFromLocal(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('cached_user_$userId');
      if (userJson != null) {
        return jsonDecode(userJson);
      }
    } catch (e) {
      print('Error loading user from local: $e');
    }
    return null;
  }

  // Save last message for quick access in users list
  static Future<void> saveLastMessage(
    String chatId,
    String message,
    int timestamp,
    String senderId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMsg = {
        'text': message,
        'timestamp': timestamp,
        'senderId': senderId,
      };
      await prefs.setString('last_msg_$chatId', jsonEncode(lastMsg));
    } catch (e) {
      print('Error saving last message: $e');
    }
  }

  // Load last message
  static Future<Map<String, dynamic>?> loadLastMessage(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMsgJson = prefs.getString('last_msg_$chatId');
      if (lastMsgJson != null) {
        return jsonDecode(lastMsgJson);
      }
    } catch (e) {
      print('Error loading last message: $e');
    }
    return null;
  }
}
