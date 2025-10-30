import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

@pragma('vm:entry-point')
class CallServiceHelper {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _isInitialized = false;

  /// Initialize the background service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _isInitialized = true;
  }

  /// Start the foreground service for an active call
  static Future<void> startCallService({
    required String callerName,
    required bool isVideoCall,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    await _service.startService();
    _service.invoke('updateNotification', {
      'callerName': callerName,
      'isVideoCall': isVideoCall,
    });
  }

  /// Stop the foreground service
  static Future<void> stopCallService() async {
    _service.invoke('stopService');
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    if (service is AndroidServiceInstance) {
      service.on('stopService').listen((event) {
        service.stopSelf();
      });

      service.on('updateNotification').listen((event) {
        final callerName = event?['callerName'] ?? 'Unknown';
        final isVideoCall = event?['isVideoCall'] ?? false;

        service.setAsForegroundService();
        service.setForegroundNotificationInfo(
          title: isVideoCall ? 'Video Call' : 'Audio Call',
          content: 'Ongoing call with $callerName',
        );
      });
    }
  }

  @pragma('vm:entry-point')
  static bool onIosBackground(ServiceInstance service) {
    return true;
  }
}
