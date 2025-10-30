import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class PIPManager {
  static final PIPManager _instance = PIPManager._internal();
  factory PIPManager() => _instance;
  PIPManager._internal();

  // PIP state
  bool _isInPIPMode = false;
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  VoidCallback? _onEndCall;
  VoidCallback? _onExpand;
  String? _callerName;
  bool _isVideoCall = false;

  bool get isInPIPMode => _isInPIPMode;
  RTCVideoRenderer? get localRenderer => _localRenderer;
  RTCVideoRenderer? get remoteRenderer => _remoteRenderer;
  VoidCallback? get onEndCall => _onEndCall;
  VoidCallback? get onExpand => _onExpand;
  String? get callerName => _callerName;
  bool get isVideoCall => _isVideoCall;

  void enterPIPMode({
    required RTCVideoRenderer localRenderer,
    required RTCVideoRenderer remoteRenderer,
    required VoidCallback onEndCall,
    required VoidCallback onExpand,
    required String callerName,
    required bool isVideoCall,
  }) {
    _isInPIPMode = true;
    _localRenderer = localRenderer;
    _remoteRenderer = remoteRenderer;
    _onEndCall = onEndCall;
    _onExpand = onExpand;
    _callerName = callerName;
    _isVideoCall = isVideoCall;
  }

  void exitPIPMode() {
    _isInPIPMode = false;
    _localRenderer = null;
    _remoteRenderer = null;
    _onEndCall = null;
    _onExpand = null;
    _callerName = null;
    _isVideoCall = false;
  }

  void updateRenderers({
    RTCVideoRenderer? localRenderer,
    RTCVideoRenderer? remoteRenderer,
  }) {
    if (localRenderer != null) _localRenderer = localRenderer;
    if (remoteRenderer != null) _remoteRenderer = remoteRenderer;
  }
}
