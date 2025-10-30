import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'message_model.g.dart';

@HiveType(typeId: 1)
class MessageModel extends HiveObject {
  @HiveField(0)
  String messageId;

  @HiveField(1)
  String chatId;

  @HiveField(2)
  String text;

  @HiveField(3)
  String senderId;

  @HiveField(4)
  String receiverId;

  @HiveField(5)
  int timestamp; // millisecondsSinceEpoch

  @HiveField(6)
  bool isRead;

  @HiveField(7)
  Map<String, dynamic>? reactions;

  @HiveField(8)
  Map<String, dynamic>? replyTo;

  @HiveField(9)
  bool isCallMessage;

  @HiveField(10)
  String? callMessageType;

  @HiveField(11)
  int? callDuration;

  @HiveField(12)
  // Message send status: 'pending', 'sent', 'delivered', 'read', 'failed'
  // 'pending' = message being sent (show clock icon)
  // 'sent' = sent to server (show single grey tick)
  // 'delivered' = delivered to receiver (show double grey tick)
  // 'read' = read by receiver (show double blue tick)
  // 'failed' = failed to send (show red exclamation)
  String sendStatus;

  MessageModel({
    required this.messageId,
    required this.chatId,
    required this.text,
    required this.senderId,
    required this.receiverId,
    required this.timestamp,
    this.isRead = false,
    this.reactions,
    this.replyTo,
    this.isCallMessage = false,
    this.callMessageType,
    this.callDuration,
    this.sendStatus = 'sent', // Default to 'sent' for existing/received messages
  });

  // Factory to create from Firestore data
  factory MessageModel.fromFirestore(
    String messageId,
    Map<String, dynamic> data,
    String chatId,
  ) {
    int timestamp = 0;
    if (data['timestamp'] != null) {
      if (data['timestamp'] is Timestamp) {
        timestamp = (data['timestamp'] as Timestamp).millisecondsSinceEpoch;
      } else if (data['timestamp'] is int) {
        timestamp = data['timestamp'] as int;
      }
    }

    return MessageModel(
      messageId: messageId,
      chatId: chatId,
      text: data['text'] ?? '',
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      timestamp: timestamp,
      isRead: data['isRead'] ?? false,
      reactions: data['reactions'] != null
          ? Map<String, dynamic>.from(data['reactions'])
          : null,
      replyTo: data['replyTo'] != null
          ? Map<String, dynamic>.from(data['replyTo'])
          : null,
      isCallMessage: data['isCallMessage'] ?? false,
      callMessageType: data['callMessageType'],
      callDuration: data['callDuration'],
      sendStatus: data['sendStatus'] ?? 
                  (data['isRead'] == true ? 'read' : 'sent'), // Derive from isRead if no sendStatus
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'chatId': chatId,
      'text': text,
      'senderId': senderId,
      'receiverId': receiverId,
      'timestamp': timestamp,
      'isRead': isRead,
      'reactions': reactions,
      'replyTo': replyTo,
      'isCallMessage': isCallMessage,
      'callMessageType': callMessageType,
      'callDuration': callDuration,
      'sendStatus': sendStatus,
    };
  }
}
