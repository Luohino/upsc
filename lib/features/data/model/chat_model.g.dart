// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatModelAdapter extends TypeAdapter<ChatModel> {
  @override
  final int typeId = 0;

  @override
  ChatModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatModel(
      chatId: fields[0] as String,
      otherUserId: fields[1] as String,
      otherUserName: fields[2] as String,
      otherUserPhoto: fields[3] as String?,
      lastMessage: fields[4] as String,
      lastMessageTime: fields[5] as int,
      unreadCount: fields[6] as int,
      isOnline: fields[7] as bool,
      lastSenderId: fields[8] as String?,
      isPinned: fields[9] as bool,
      sortOrder: fields[10] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ChatModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.chatId)
      ..writeByte(1)
      ..write(obj.otherUserId)
      ..writeByte(2)
      ..write(obj.otherUserName)
      ..writeByte(3)
      ..write(obj.otherUserPhoto)
      ..writeByte(4)
      ..write(obj.lastMessage)
      ..writeByte(5)
      ..write(obj.lastMessageTime)
      ..writeByte(6)
      ..write(obj.unreadCount)
      ..writeByte(7)
      ..write(obj.isOnline)
      ..writeByte(8)
      ..write(obj.lastSenderId)
      ..writeByte(9)
      ..write(obj.isPinned)
      ..writeByte(10)
      ..write(obj.sortOrder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
