import 'package:flutter/services.dart';

class AudioWakeLockHelper {
  static const _channel = MethodChannel('com.upsc/audio_wakelock');

  /// Acquire wake lock and set audio mode for call
  static Future<void> acquireWakeLock() async {
    try {
      await _channel.invokeMethod('acquireWakeLock');
    } catch (e) {
      print('Failed to acquire wake lock: $e');
    }
  }

  /// Release wake lock and restore normal audio mode
  static Future<void> releaseWakeLock() async {
    try {
      await _channel.invokeMethod('releaseWakeLock');
    } catch (e) {
      print('Failed to release wake lock: $e');
    }
  }

  /// Set audio mode
  static Future<void> setAudioMode(String mode) async {
    try {
      await _channel.invokeMethod('setAudioMode', {'mode': mode});
    } catch (e) {
      print('Failed to set audio mode: $e');
    }
  }
}
