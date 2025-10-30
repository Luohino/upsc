import 'package:audioplayers/audioplayers.dart';

/// Service to manage call audio (outgoing ringtone & incoming device ringtone)
/// Ringtones automatically follow system audio routing (Speaker/Bluetooth/Earpiece)
class CallAudioService {
  static final CallAudioService _instance = CallAudioService._internal();
  factory CallAudioService() => _instance;
  CallAudioService._internal();

  final AudioPlayer _outgoingPlayer = AudioPlayer();
  final AudioPlayer _incomingPlayer = AudioPlayer();
  bool _isPlayingOutgoing = false;
  bool _isPlayingIncoming = false;

  /// Play outgoing call ringtone (old phone ring sound)
  /// This plays when YOU call someone
  Future<void> playOutgoingRingtone() async {
    if (_isPlayingOutgoing) {
      print('⚠️ [CallAudio] Outgoing ringtone is already playing, skipping...');
      return;
    }

    try {
      print('\n🔊 [CallAudio] ========================================');
      print('🔊 [CallAudio] Starting OUTGOING call ringtone...');
      print('🔊 [CallAudio] Source: old-phone-ring-272648.mp3');

      await _outgoingPlayer.setReleaseMode(ReleaseMode.loop);
      print('✅ [CallAudio] Set release mode to LOOP');

      // Set audio context to follow call routing (Speaker/Bluetooth/Earpiece)
      // IMPORTANT: Don't force speaker, let the system use current audio route
      await _outgoingPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: {
              AVAudioSessionOptions.allowBluetooth,
              AVAudioSessionOptions.allowBluetoothA2DP,
              // Removed defaultToSpeaker to prevent forcing speaker
            },
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,  // Changed to false to use current route
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.voiceCommunication,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
      print('✅ [CallAudio] Audio context set to follow call audio routing');

      await _outgoingPlayer.setVolume(1.0);
      print('✅ [CallAudio] Set volume to MAX (1.0)');

      await _outgoingPlayer.play(AssetSource('old-phone-ring-272648.mp3'));
      _isPlayingOutgoing = true;

      print('✅ [CallAudio] OUTGOING RINGTONE IS NOW PLAYING! 🔊');
      print('📞 [CallAudio] Old phone ring sound looping...');
      print('🔊 [CallAudio] ========================================\n');
    } catch (e) {
      print('\n❌ [CallAudio] ========================================');
      print('❌ [CallAudio] CRITICAL ERROR playing outgoing ringtone!');
      print('❌ [CallAudio] Error: $e');
      print('❌ [CallAudio] Asset path: old-phone-ring-272648.mp3');
      print('❌ [CallAudio] ========================================\n');
    }
  }

  /// Stop outgoing call ringtone
  /// Called when: receiver answers OR you cancel the call
  Future<void> stopOutgoingRingtone() async {
    if (!_isPlayingOutgoing) {
      print('ℹ️ [CallAudio] Outgoing ringtone is not playing, nothing to stop');
      return;
    }

    try {
      print('\n🔇 [CallAudio] ========================================');
      print('🔇 [CallAudio] Stopping OUTGOING ringtone...');

      await _outgoingPlayer.stop();
      _isPlayingOutgoing = false;

      print('✅ [CallAudio] OUTGOING RINGTONE STOPPED successfully!');
      print('🔇 [CallAudio] ========================================\n');
    } catch (e) {
      print('\n❌ [CallAudio] ========================================');
      print('❌ [CallAudio] ERROR stopping outgoing ringtone!');
      print('❌ [CallAudio] Error: $e');
      print('❌ [CallAudio] ========================================\n');
    }
  }

  /// Play incoming call ringtone (notification sound)
  /// This plays when SOMEONE calls you
  /// Note: CallKit will also play the system ringtone on top of this
  Future<void> playIncomingRingtone() async {
    if (_isPlayingIncoming) {
      print('⚠️ [CallAudio] Incoming ringtone is already playing, skipping...');
      return;
    }

    try {
      print('\n🔔 [CallAudio] ========================================');
      print('🔔 [CallAudio] Starting INCOMING call ringtone...');
      print('🔔 [CallAudio] Source: notification.mp3');
      print('🔔 [CallAudio] Note: CallKit will also play system ringtone');

      await _incomingPlayer.setReleaseMode(ReleaseMode.loop);
      print('✅ [CallAudio] Set release mode to LOOP');

      await _incomingPlayer.setVolume(1.0);
      print('✅ [CallAudio] Set volume to MAX (1.0)');

      await _incomingPlayer.play(AssetSource('notification.mp3'));
      _isPlayingIncoming = true;

      print('✅ [CallAudio] INCOMING RINGTONE IS NOW PLAYING! 🔔');
      print('📲 [CallAudio] Notification sound looping...');
      print('🔔 [CallAudio] ========================================\n');
    } catch (e) {
      print('\n❌ [CallAudio] ========================================');
      print('❌ [CallAudio] CRITICAL ERROR playing incoming ringtone!');
      print('❌ [CallAudio] Error: $e');
      print('❌ [CallAudio] CallKit will handle the system ringtone');
      print('❌ [CallAudio] ========================================\n');
    }
  }

  /// Stop incoming call ringtone
  /// Called when: you accept OR decline the call
  Future<void> stopIncomingRingtone() async {
    if (!_isPlayingIncoming) {
      print('ℹ️ [CallAudio] Incoming ringtone is not playing, nothing to stop');
      return;
    }

    try {
      print('\n🔇 [CallAudio] ========================================');
      print('🔇 [CallAudio] Stopping INCOMING ringtone...');

      await _incomingPlayer.stop();
      _isPlayingIncoming = false;

      print('✅ [CallAudio] INCOMING RINGTONE STOPPED successfully!');
      print('🔇 [CallAudio] ========================================\n');
    } catch (e) {
      print('\n❌ [CallAudio] ========================================');
      print('❌ [CallAudio] ERROR stopping incoming ringtone!');
      print('❌ [CallAudio] Error: $e');
      print('❌ [CallAudio] ========================================\n');
    }
  }

  /// Stop all ringtones
  Future<void> stopAll() async {
    print('\n🚨 [CallAudio] ========================================');
    print('🚨 [CallAudio] STOPPING ALL RINGTONES...');
    print('🚨 [CallAudio] Outgoing playing: $_isPlayingOutgoing');
    print('🚨 [CallAudio] Incoming playing: $_isPlayingIncoming');

    await stopOutgoingRingtone();
    await stopIncomingRingtone();

    print('✅ [CallAudio] ALL RINGTONES STOPPED!');
    print('🚨 [CallAudio] ========================================\n');
  }

  /// Cleanup
  Future<void> dispose() async {
    await stopAll();
    await _outgoingPlayer.dispose();
    await _incomingPlayer.dispose();
  }
}
