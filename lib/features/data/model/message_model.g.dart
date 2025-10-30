// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MessageModelAdapter extends TypeAdapter<MessageModel> {
  @override
  final int typeId = 1;

  @override
  MessageModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MessageModel(
      messageId: fields[0] as String,
      chatId: fields[1] as String,
      text: fields[2] as String,
      senderId: fields[3] as String,
      receiverId: fields[4] as String,
      timestamp: fields[5] as int,
      isRead: fields[6] as bool,
      reactions: (fields[7] as Map?)?.cast<String, dynamic>(),
      replyTo: (fields[8] as Map?)?.cast<String, dynamic>(),
      isCallMessage: fields[9] as bool,
      callMessageType: fields[10] as String?,
      callDuration: fields[11] as int?,
      sendStatus: (fields[12] as String?) ?? 'sent', // Default to 'sent' for old messages
    );
  }

  @override
  void write(BinaryWriter writer, MessageModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.messageId)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.senderId)
      ..writeByte(4)
      ..write(obj.receiverId)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.isRead)
      ..writeByte(7)
      ..write(obj.reactions)
      ..writeByte(8)
      ..write(obj.replyTo)
      ..writeByte(9)
      ..write(obj.isCallMessage)
      ..writeByte(10)
      ..write(obj.callMessageType)
      ..writeByte(11)
      ..write(obj.callDuration)
      ..writeByte(12)
      ..write(obj.sendStatus);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
