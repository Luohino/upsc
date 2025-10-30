import 'package:hive/hive.dart';

part 'chat_model.g.dart';

@HiveType(typeId: 0)
class ChatModel extends HiveObject {
  @HiveField(0)
  String chatId;

  @HiveField(1)
  String otherUserId;

  @HiveField(2)
  String otherUserName;

  @HiveField(3)
  String? otherUserPhoto;

  @HiveField(4)
  String lastMessage;

  @HiveField(5)
  int lastMessageTime; // millisecondsSinceEpoch

  @HiveField(6)
  int unreadCount;

  @HiveField(7)
  bool isOnline;

  @HiveField(8)
  String? lastSenderId;

  @HiveField(9)
  bool isPinned;

  @HiveField(10)
  int sortOrder; // Pre-computed sort order for instant display

  ChatModel({
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhoto,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastSenderId,
    this.isPinned = false,
    required this.sortOrder,
  });

  // Factory to create from Firestore data
  factory ChatModel.fromFirestore(
      Map<String, dynamic> data, String chatId, String currentUserId) {
    final participants = data['participants'] as List?;
    final otherUserId = participants?.firstWhere(
          (id) => id != currentUserId,
          orElse: () => 'unknown',
        ) ??
        'unknown';

    return ChatModel(
      chatId: chatId,
      otherUserId: otherUserId,
      otherUserName: data['otherUserName'] ?? 'Unknown',
      otherUserPhoto: data['otherUserPhoto'],
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: (data['lastMessageTime'] as num?)?.toInt() ?? 0,
      unreadCount: (data['unreadCount'] as num?)?.toInt() ?? 0,
      isOnline: data['isOnline'] ?? false,
      lastSenderId: data['lastSenderId'],
      isPinned: data['isPinned'] ?? false,
      sortOrder: (data['lastMessageTime'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chatId': chatId,
      'otherUserId': otherUserId,
      'otherUserName': otherUserName,
      'otherUserPhoto': otherUserPhoto,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime,
      'unreadCount': unreadCount,
      'isOnline': isOnline,
      'lastSenderId': lastSenderId,
      'isPinned': isPinned,
      'sortOrder': sortOrder,
    };
  }
}
