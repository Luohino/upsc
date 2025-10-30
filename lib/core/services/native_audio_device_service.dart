import 'package:flutter/services.dart';

class NativeAudioDeviceService {
  static const platform = MethodChannel('com.upsc/audio_device');

  /// Get the current active audio output device
  /// Returns: "Bluetooth", "Speaker", "Earpiece", or "Unknown"
  static Future<AudioDeviceInfo> getCurrentAudioDevice() async {
    try {
      final Map<dynamic, dynamic> result =
          await platform.invokeMethod('getCurrentAudioDevice');

      print('📱 [Native] Audio device info received:');
      print('   Current Device: ${result['currentDevice']}');
      print('   Bluetooth SCO: ${result['isBluetoothScoOn']}');
      print('   Bluetooth A2DP: ${result['isBluetoothA2dpOn']}');
      print('   Speakerphone: ${result['isSpeakerphoneOn']}');

      return AudioDeviceInfo(
        currentDevice: result['currentDevice'] as String? ?? 'Unknown',
        isBluetoothScoOn: result['isBluetoothScoOn'] as bool? ?? false,
        isBluetoothA2dpOn: result['isBluetoothA2dpOn'] as bool? ?? false,
        isSpeakerphoneOn: result['isSpeakerphoneOn'] as bool? ?? false,
        availableDevices: (result['availableDevices'] as List<dynamic>?)
                ?.map((e) => AudioDevice.fromMap(e as Map<dynamic, dynamic>))
                .toList() ??
            [],
      );
    } on PlatformException catch (e) {
      print('❌ [Native] Failed to get audio device: ${e.message}');
      return AudioDeviceInfo(
        currentDevice: 'Unknown',
        isBluetoothScoOn: false,
        isBluetoothA2dpOn: false,
        isSpeakerphoneOn: false,
        availableDevices: [],
      );
    }
  }

  /// Get all available audio output devices
  static Future<List<AudioDevice>> getAvailableAudioDevices() async {
    try {
      final List<dynamic> result =
          await platform.invokeMethod('getAvailableAudioDevices');

      print('📱 [Native] Available audio devices: ${result.length}');
      for (var device in result) {
        print('   - ${device['type']}: ${device['name']}');
      }

      return result
          .map((e) => AudioDevice.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    } on PlatformException catch (e) {
      print('❌ [Native] Failed to get available devices: ${e.message}');
      return [];
    }
  }
}

class AudioDeviceInfo {
  final String currentDevice; // "Bluetooth", "Speaker", "Earpiece", "Unknown"
  final bool isBluetoothScoOn;
  final bool isBluetoothA2dpOn;
  final bool isSpeakerphoneOn;
  final List<AudioDevice> availableDevices;

  AudioDeviceInfo({
    required this.currentDevice,
    required this.isBluetoothScoOn,
    required this.isBluetoothA2dpOn,
    required this.isSpeakerphoneOn,
    required this.availableDevices,
  });

  bool get hasBluetoothDevice =>
      isBluetoothScoOn ||
      isBluetoothA2dpOn ||
      availableDevices.any((d) => d.type == 'Bluetooth');
}

class AudioDevice {
  final String type;
  final String name;
  final int? id;

  AudioDevice({
    required this.type,
    required this.name,
    this.id,
  });

  factory AudioDevice.fromMap(Map<dynamic, dynamic> map) {
    return AudioDevice(
      type: map['type'] as String? ?? 'Unknown',
      name: map['name'] as String? ?? 'Unknown',
      id: map['id'] as int?,
    );
  }
}
