import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/hive_service.dart';
import '../../features/data/model/chat_model.dart';
import '../../features/data/model/message_model.dart';

/// Provider for chat list - reads from Hive instantly, updates reactively
final chatListProvider =
    StateNotifierProvider<ChatListNotifier, List<ChatModel>>((ref) {
  return ChatListNotifier();
});

class ChatListNotifier extends StateNotifier<List<ChatModel>> {
  ChatListNotifier() : super([]) {
    print('🎯 [ChatListNotifier] Initializing...');
    _loadChats();
    _listenToChanges();
  }

  /// Load chats from Hive INSTANTLY (synchronous, no await)
  void _loadChats() {
    final startTime = DateTime.now();

    // This is INSTANT - no async needed
    final chats = HiveService.getAllChatsSorted();
    state = chats;

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print(
        '⚡ [ChatListNotifier] Loaded ${chats.length} chats INSTANTLY in ${elapsed}ms');
  }

  /// Listen to Hive box changes and update state reactively
  void _listenToChanges() {
    HiveService.watchChats().listen((event) {
      print('🔄 [ChatListNotifier] Hive box changed, reloading chats...');
      _loadChats();
    });
  }

  /// Refresh chats (called after Firebase sync)
  void refresh() {
    print('🔄 [ChatListNotifier] Manual refresh requested');
    _loadChats();
  }
}

/// Provider for messages in a specific chat
final messagesProvider =
    StateNotifierProviderFamily<MessagesNotifier, List<MessageModel>, String>(
  (ref, chatId) {
    return MessagesNotifier(chatId);
  },
);

class MessagesNotifier extends StateNotifier<List<MessageModel>> {
  final String chatId;

  MessagesNotifier(this.chatId) : super([]) {
    print('🎯 [MessagesNotifier] Initializing for chat: $chatId');
    _loadMessages();
    _listenToChanges();
  }

  /// Load messages from Hive INSTANTLY (synchronous, no await)
  void _loadMessages() {
    final startTime = DateTime.now();

    // This is INSTANT - no async needed
    final messages = HiveService.getMessages(chatId);
    state = messages;

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    print(
        '⚡ [MessagesNotifier] Loaded ${messages.length} messages for $chatId INSTANTLY in ${elapsed}ms');
  }

  /// Listen to Hive box changes and update state reactively
  void _listenToChanges() {
    HiveService.watchMessages().listen((event) {
      // Only reload if the change affects this chat
      if (event.value is MessageModel) {
        final message = event.value as MessageModel;
        if (message.chatId == chatId) {
          print(
              '🔄 [MessagesNotifier] Message changed for $chatId, reloading...');
          _loadMessages();
        }
      } else {
        // Deletion event
        _loadMessages();
      }
    });
  }

  /// Refresh messages (called after Firebase sync)
  void refresh() {
    print('🔄 [MessagesNotifier] Manual refresh requested for $chatId');
    _loadMessages();
  }

  /// Add a new message (optimistic update)
  void addMessage(MessageModel message) {
    state = [message, ...state];
    print(
        '➕ [MessagesNotifier] Added message optimistically: ${message.messageId}');
  }

  /// Update a message
  void updateMessage(MessageModel updatedMessage) {
    state = state.map((msg) {
      return msg.messageId == updatedMessage.messageId ? updatedMessage : msg;
    }).toList();
    print('✏️ [MessagesNotifier] Updated message: ${updatedMessage.messageId}');
  }
}

/// Provider for unread count (derived from chat list)
final unreadCountProvider = Provider<int>((ref) {
  final chats = ref.watch(chatListProvider);
  final totalUnread = chats.fold<int>(0, (sum, chat) => sum + chat.unreadCount);
  print('📊 [unreadCountProvider] Total unread: $totalUnread');
  return totalUnread;
});

/// Provider for checking if a chat has any messages
final hasChatMessagesProvider = Provider.family<bool, String>((ref, chatId) {
  final messages = ref.watch(messagesProvider(chatId));
  return messages.isNotEmpty;
});
