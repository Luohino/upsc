import 'package:audio_service/audio_service.dart';
import 'dart:io' show Platform;

class CallAudioHandler extends BaseAudioHandler {
  CallAudioHandler() {
    // Set up initial playback state
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.pause,
        MediaControl.stop,
      ],
      playing: true,
      processingState: AudioProcessingState.ready,
    ));
  }

  Future<void> startCall(
      {required String callerName, required bool isVideoCall}) async {
    // Update media item for the ongoing call
    mediaItem.add(MediaItem(
      id: 'call_${DateTime.now().millisecondsSinceEpoch}',
      album: 'Ongoing Call',
      title: callerName,
      artist: isVideoCall ? 'Video Call' : 'Audio Call',
      duration: const Duration(hours: 1),
      artUri: Uri.parse('https://i.pravatar.cc/128'),
    ));

    // Update playback state to playing
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.stop,
      ],
      playing: true,
      processingState: AudioProcessingState.ready,
    ));
  }

  @override
  Future<void> stop() async {
    // Clear the media item and stop
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
    await super.stop();
  }

  @override
  Future<void> pause() async {
    // Keep playing even if pause is called
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
    ));
  }

  @override
  Future<void> play() async {
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
    ));
  }
}

class AudioServiceManager {
  static AudioHandler? _audioHandler;
  static bool _initAttempted = false;
  static bool _initedOk = false;

  static Future<void> init() async {
    if (_initedOk || _initAttempted) return;
    _initAttempted = true;

    // Temporary Android workaround: skip AudioService to avoid Activity crash until manifest is fixed.
    if (Platform.isAndroid) {
      _initedOk = false;
      _audioHandler = null;
      return;
    }

    try {
      _audioHandler = await AudioService.init(
        builder: () => CallAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.upsc.channel.audio',
          androidNotificationChannelName: 'Call Audio',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
      _initedOk = true;
    } catch (e, _) {
      // Avoid crashing if platform init fails
      _audioHandler = null;
    }
  }

  static Future<void> startCall(
      {required String callerName, required bool isVideoCall}) async {
    await init();
    if (_initedOk && _audioHandler is CallAudioHandler) {
      await (_audioHandler as CallAudioHandler).startCall(
        callerName: callerName,
        isVideoCall: isVideoCall,
      );
    }
  }

  static Future<void> stopCall() async {
    await _audioHandler?.stop();
  }
}
