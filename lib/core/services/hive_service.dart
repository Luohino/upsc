import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import '../../features/data/model/chat_model.dart';
import '../../features/data/model/message_model.dart';

/// Local-first database service using Hive for instant data access
/// All UI operations read from Hive - Firebase only syncs in background
class HiveService {
  static const String _chatsBoxName = 'chats';
  static const String _messagesBoxName = 'messages';

  static Box<ChatModel>? _chatsBox;
  static Box<MessageModel>? _messagesBox;

  /// Initialize Hive and open boxes
  static Future<void> init() async {
    final startTime = DateTime.now();
    print('📦 [HiveService] Initializing Hive...');

    await Hive.initFlutter();

    // Register adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ChatModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(MessageModelAdapter());
    }

    // Open boxes
    _chatsBox = await Hive.openBox<ChatModel>(_chatsBoxName);
    _messagesBox = await Hive.openBox<MessageModel>(_messagesBoxName);

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print('✅ [HiveService] Hive initialized in ${elapsed}ms');
    print('📊 [HiveService] Chats loaded: ${_chatsBox!.length}');
    print('📊 [HiveService] Messages loaded: ${_messagesBox!.length}');
  }

  // ==================== CHAT OPERATIONS ====================

  /// Get all chats sorted by last message time (INSTANT - no async needed)
  static List<ChatModel> getAllChatsSorted() {
    final startTime = DateTime.now();

    if (_chatsBox == null) {
      print('⚠️ [HiveService] Chats box not initialized');
      return [];
    }

    final chats = _chatsBox!.values.toList();

    // Sort by pinned first, then by last message time (pre-computed)
    chats.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.sortOrder.compareTo(a.sortOrder);
    });

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print(
        '⚡ [HiveService] getAllChatsSorted: ${chats.length} chats in ${elapsed}ms');

    return chats;
  }

  /// Save or update a chat (used by Firebase sync)
  static Future<void> saveChat(ChatModel chat) async {
    final startTime = DateTime.now();

    await _chatsBox?.put(chat.chatId, chat);

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print('💾 [HiveService] saveChat: ${chat.chatId} in ${elapsed}ms');
  }

  /// Save multiple chats at once (batch operation)
  static Future<void> saveChats(List<ChatModel> chats) async {
    final startTime = DateTime.now();

    final map = {for (var chat in chats) chat.chatId: chat};
    await _chatsBox?.putAll(map);

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print('💾 [HiveService] saveChats: ${chats.length} chats in ${elapsed}ms');
  }

  /// Get a specific chat by ID (INSTANT)
  static ChatModel? getChat(String chatId) {
    return _chatsBox?.get(chatId);
  }

  /// Delete a chat
  static Future<void> deleteChat(String chatId) async {
    await _chatsBox?.delete(chatId);
    print('🗑️ [HiveService] deleteChat: $chatId');
  }

  /// Watch chats for changes (reactive stream)
  static Stream<BoxEvent> watchChats() {
    return _chatsBox!.watch();
  }

  // ==================== MESSAGE OPERATIONS ====================

  /// Get all messages for a chat sorted by timestamp (INSTANT)
  static List<MessageModel> getMessages(String chatId) {
    final startTime = DateTime.now();

    if (_messagesBox == null) {
      print('⚠️ [HiveService] Messages box not initialized');
      return [];
    }

    final allMessages =
        _messagesBox!.values.where((msg) => msg.chatId == chatId).toList();

    // Sort by timestamp descending (newest first)
    allMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print(
        '⚡ [HiveService] getMessages: ${allMessages.length} messages for $chatId in ${elapsed}ms');

    return allMessages;
  }

  /// Save a message (used by Firebase sync or when sending)
  static Future<void> saveMessage(MessageModel message) async {
    final startTime = DateTime.now();

    await _messagesBox?.put(message.messageId, message);

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print('💾 [HiveService] saveMessage: ${message.messageId} in ${elapsed}ms');
  }

  /// Update message ID (e.g., from optimistic to Firebase ID) WITHOUT deleting
  /// This prevents the message from disappearing during the transition
  static Future<void> updateMessageId({
    required String oldId,
    required String newId,
    required MessageModel updatedMessage,
  }) async {
    final startTime = DateTime.now();

    // Save with new ID first (this keeps the message visible)
    await _messagesBox?.put(newId, updatedMessage);
    
    // Then delete the old ID (message stays visible with new ID)
    await _messagesBox?.delete(oldId);

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print('🔄 [HiveService] updateMessageId: $oldId → $newId in ${elapsed}ms');
  }

  /// Save multiple messages at once (batch operation)
  static Future<void> saveMessages(List<MessageModel> messages) async {
    final startTime = DateTime.now();

    final map = {for (var msg in messages) msg.messageId: msg};
    await _messagesBox?.putAll(map);

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print(
        '💾 [HiveService] saveMessages: ${messages.length} messages in ${elapsed}ms');
  }

  /// Delete a message
  static Future<void> deleteMessage(String messageId) async {
    await _messagesBox?.delete(messageId);
    print('🗑️ [HiveService] deleteMessage: $messageId');
  }

  /// Delete all messages for a chat
  static Future<void> deleteMessagesForChat(String chatId) async {
    final messagesToDelete = _messagesBox!.values
        .where((msg) => msg.chatId == chatId)
        .map((msg) => msg.messageId)
        .toList();

    await _messagesBox?.deleteAll(messagesToDelete);
    print(
        '🗑️ [HiveService] deleteMessagesForChat: $chatId (${messagesToDelete.length} messages)');
  }

  /// Watch messages for a specific chat (reactive stream)
  static Stream<BoxEvent> watchMessages() {
    return _messagesBox!.watch();
  }

  /// Get message by ID (INSTANT)
  static MessageModel? getMessage(String messageId) {
    return _messagesBox?.get(messageId);
  }

  // ==================== UTILITY OPERATIONS ====================

  /// Clear all data (useful for logout)
  static Future<void> clearAllData() async {
    print('🗑️ [HiveService] Clearing all local data...');
    await _chatsBox?.clear();
    await _messagesBox?.clear();
    print('✅ [HiveService] All data cleared');
  }

  /// Get statistics
  static Map<String, int> getStats() {
    return {
      'chats': _chatsBox?.length ?? 0,
      'messages': _messagesBox?.length ?? 0,
    };
  }

  /// Close all boxes (call on app dispose)
  static Future<void> close() async {
    await _chatsBox?.close();
    await _messagesBox?.close();
    print('📦 [HiveService] Boxes closed');
  }
}
