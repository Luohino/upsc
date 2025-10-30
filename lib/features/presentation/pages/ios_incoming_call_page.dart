import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_audio_output/flutter_audio_output.dart'; // Audio output management
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/common_imports.dart';
import '../../../core/utils/audio_service_handler.dart';
import '../../../core/utils/audio_wakelock_helper.dart';
import '../../../core/utils/call_service_helper.dart';
import '../../../core/utils/pip_manager.dart';
import '../../../core/services/call_audio_service.dart';
import '../../../core/services/call_signal_service.dart';
import '../../data/services/call_message_service.dart';
import '../../data/model/notification_payload.dart';
import '../bloc/signaling_bloc/signaling_bloc.dart';
import 'ios_active_call_page.dart';
import 'chat_page.dart';

/// iOS-style incoming/outgoing call page with WebRTC integration
/// 
/// PARAMETERS:
/// - callerName: Name of the OTHER person in the call (receiver for outgoing, caller for incoming)
/// - callerImage: Profile picture URL of the other person
/// - isOutgoing: true if current user initiated the call, false if receiving
/// - isVideo: true for video calls, false for audio-only calls
/// - chatId: Unique chat ID used as WebRTC room ID
/// - senderId: User ID of the call initiator (caller)
/// - receiverId: User ID of the call receiver
/// - currentUserName: Name of the current user (for FCM notifications sent to receiver)
/// - currentUserImage: Profile picture of current user (for FCM notifications)
/// - otherPersonFcmToken: FCM token of the other person (for sending notifications)
/// - callPayload: WebRTC configuration payload
/// 
/// CALL FLOW FOR OUTGOING CALLS:
/// 1. User taps call button in chat_page.dart
/// 2. chat_page instantly navigates here with all parameters
/// 3. initState immediately:
///    a. Requests permissions (mic/camera)
///    b. Sends call status message to Firestore chat
///    c. Sends FCM notification to receiver's devices
///    d. Initializes WebRTC and creates room
///    e. Starts outgoing ringtone
/// 4. When receiver answers or call ends, returns to chat_page with status
/// 
/// CALL FLOW FOR INCOMING CALLS:
/// 1. Receiver gets FCM notification
/// 2. App navigates here from notification handler
/// 3. initState plays incoming ringtone
/// 4. User slides to answer, WebRTC initializes and joins room
/// 5. When call ends, returns to appropriate screen
class IOSIncomingCallPage extends StatefulWidget {
  final String callerName;
  final String? callerImage;
  final bool isOutgoing;
  final bool isVideo;
  final String? chatId;
  final String? senderId;
  final String? receiverId;
  final String? currentUserName; // NEW: Current user's name for FCM
  final String? currentUserImage; // NEW: Current user's image for FCM
  final String?
      otherPersonFcmToken; // FCM token of the other person in the call
  final NotificationPayload? callPayload; // For WebRTC

  const IOSIncomingCallPage({
    super.key,
    required this.callerName,
    this.callerImage,
    this.isOutgoing = false,
    this.isVideo = false,
    this.chatId,
    this.senderId,
    this.receiverId,
    this.currentUserName,
    this.currentUserImage,
    this.otherPersonFcmToken,
    this.callPayload,
  });

  @override
  State<IOSIncomingCallPage> createState() => _IOSIncomingCallPageState();
}

class _IOSIncomingCallPageState extends State<IOSIncomingCallPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAnswering = false;
  double _slidePosition = 0.0;
  double _maxSlideDistance = 0.0; // Will be calculated based on screen width

  // WebRTC components
  RTCVideoRenderer localRender = RTCVideoRenderer();
  RTCVideoRenderer remoteRender = RTCVideoRenderer();
  SignalingBloc? signalingBloc;
  bool _isCallStarted = false;
  bool _micMuted = false;
  bool _speakerOn = true;
  
  // ============================================================
  // AUDIO OUTPUT MANAGEMENT (flutter_audio_output)
  // ============================================================
  List<AudioInput> _availableAudioOutputs = []; // All available output devices
  AudioInput? _currentAudioOutput; // Currently active audio output
  String _currentManualRoute = 'Earpiece'; // Track manual route selection
  bool _isManualSwitching = false; // Flag to prevent listener conflicts
  // ============================================================
  
  bool _isEnteringPIP = false; // Flag to prevent disposal when entering PIP

  /// Initialize call page
  /// 
  /// STATE SETUP FOR OUTGOING CALLS:
  /// When user initiates a call from chat_page:
  /// 1. Audio output detection starts immediately
  /// 2. Permission requests happen in background
  /// 3. Firestore call status message is sent
  /// 4. FCM notification sent to receiver's devices
  /// 5. WebRTC room creation begins
  /// 6. Outgoing ringtone starts playing
  /// 
  /// STATE SETUP FOR INCOMING CALLS:
  /// When user receives a call from FCM notification:
  /// 1. Audio output detection starts
  /// 2. Incoming ringtone plays
  /// 3. User sees slide-to-answer UI
  /// 4. WebRTC setup waits for user to answer
  @override
  void initState() {
    super.initState();

    print('\n========================================');
    print(
        '📱 [CALL INIT] ${widget.isOutgoing ? "OUTGOING" : "INCOMING"} CALL STARTED');
    print('📱 [CALL INIT] Caller: ${widget.callerName}');
    print('📱 [CALL INIT] Call Type: ${widget.isVideo ? "VIDEO" : "AUDIO"}');
    print('📱 [CALL INIT] Chat ID: ${widget.chatId}');
    print('📱 [CALL INIT] Sender ID: ${widget.senderId}');
    print('📱 [CALL INIT] Receiver ID: ${widget.receiverId}');
    print(
        '📱 [CALL INIT] Other FCM Token: ${widget.otherPersonFcmToken != null ? widget.otherPersonFcmToken!.substring(0, 20.clamp(0, widget.otherPersonFcmToken!.length)) + "..." : "null"}');
    print('========================================\n');

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // ============================================================
    // AUDIO OUTPUT DETECTION + CALL SETUP
    // ============================================================
    _initializeAudioOutputDetection().then((_) {
      // After audio output is initialized, handle call type
      if (!widget.isOutgoing) {
        // INCOMING CALL: Play ringtone and wait for user to answer
        print('🔔 [INCOMING CALL] This is an INCOMING call, playing ringtone...');
        _playRingtone();
      } else {
        // OUTGOING CALL: Start full call setup immediately
        print('📞 [OUTGOING CALL] This is an OUTGOING call, starting setup...');
        _setupOutgoingCall();
      }
    });
    // ============================================================

    // Request permissions in background (don't block UI)
    _requestPermissionsEarly();
  }
  
  /// Setup outgoing call
  /// Called automatically in initState for outgoing calls
  /// Sends Firestore message, FCM notification, starts WebRTC, plays ringtone
  Future<void> _setupOutgoingCall() async {
    try {
      // 1. SEND CALL STATUS TO FIRESTORE CHAT
      // This creates a "Calling..." message in the chat history
      if (widget.chatId != null && widget.senderId != null && widget.receiverId != null) {
        print('💾 [OUTGOING] Sending call status to Firestore chat...');
        await CallMessageService.sendCallStatusMessage(
          chatId: widget.chatId!,
          senderId: widget.senderId!,
          receiverId: widget.receiverId!,
          type: CallMessageType.outgoingCall,
        );
        print('✅ [OUTGOING] Call status message sent to Firestore');
      }
      
      // 2. SEND FCM NOTIFICATION TO RECEIVER
      // Notify receiver on all their devices about incoming call
      if (widget.receiverId != null && widget.currentUserName != null) {
        print('\n📤 [OUTGOING] ========================================');
        print('📤 [OUTGOING] Sending FCM notification to receiver...');
        
        final notificationId = DateTime.now().millisecondsSinceEpoch.toString();
        final fcmPayload = NotificationPayload(
          callAction: CallAction.join, // Receiver will JOIN the room
          callType: widget.isVideo ? CallType.video : CallType.audio,
          userId: widget.senderId ?? '',
          name: widget.currentUserName ?? 'Someone',
          imageUrl: widget.currentUserImage ?? '',
          fcmToken: FCMHelper.fcmToken,
          notificationId: notificationId,
          webrtcRoomId: widget.chatId ?? '',
        );
        
        try {
          // Send to all receiver's devices
          await FCMHelper.sendToAllUserTokens(
            userId: widget.receiverId!,
            payload: fcmPayload,
          );
          
          // Firestore fallback signal (in case FCM fails)
          await CallSignalService.sendCallSignal(
            toUserId: widget.receiverId!,
            payload: fcmPayload,
          );
          
          print('✅ [OUTGOING] FCM notification sent to all devices');
          print('📡 [OUTGOING] Firestore fallback signal sent');
        } catch (e) {
          print('❌ [OUTGOING] Error sending FCM notification: $e');
          // Continue anyway - call can still work if receiver is in-app
        }
        
        print('📤 [OUTGOING] ========================================\n');
      }
      
      // 3. PLAY OUTGOING RINGTONE
      // Play ringtone so caller hears "ringing" sound
      print('🔊 [OUTGOING] Playing outgoing ringtone...');
      CallAudioService().playOutgoingRingtone();
      
      // 4. INITIALIZE WEBRTC
      // Start WebRTC call setup immediately
      if (widget.callPayload != null) {
        print('⚡ [OUTGOING] Initializing WebRTC room...');
        await _initializeWebRTC();
        print('✅ [OUTGOING] WebRTC initialized');
      } else {
        print('⚠️ [OUTGOING] No WebRTC payload, call cannot connect');
      }
      
    } catch (e) {
      print('❌ [OUTGOING] Error in call setup: $e');
      // Don't fail silently - show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error setting up call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _requestPermissionsEarly() async {
    // Request permissions in background so they're ready when user answers
    print('🎤 [Incoming Call] Pre-requesting microphone permission...');
    final micStatus = await Permission.microphone.request();
    if (micStatus.isGranted) {
      print('✅ [Incoming Call] Microphone permission granted');
    } else {
      print('⚠️ [Incoming Call] Microphone permission not granted');
    }

    // Request camera for video calls
    if (widget.isVideo) {
      print('📹 [Incoming Call] Pre-requesting camera permission...');
      final cameraStatus = await Permission.camera.request();
      if (cameraStatus.isGranted) {
        print('✅ [Incoming Call] Camera permission granted');
      } else {
        print('⚠️ [Incoming Call] Camera permission not granted');
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioPlayer.stop();
    _audioPlayer.dispose();

    // Stop all ringtones
    CallAudioService().stopAll();

    // ============================================================
    // CLEANUP AUDIO OUTPUT LISTENER
    // ============================================================
    FlutterAudioOutput.removeListener();
    // ============================================================

    // Clean up WebRTC ONLY if NOT entering PIP mode
    if (_isCallStarted && !_isEnteringPIP) {
      print('🛑 Disposing WebRTC resources (call ended)');
      AudioServiceManager.stopCall();
      AudioWakeLockHelper.releaseWakeLock();
      CallServiceHelper.stopCallService();
      localRender.dispose();
      remoteRender.dispose();
      signalingBloc?.dispose();
    } else if (_isEnteringPIP) {
      print('📺 Keeping WebRTC alive for PIP mode');
    }

    super.dispose();
  }

  Future<void> _playRingtone() async {
    try {
      print('\n🔔 [RINGTONE] ========================================');
      print('🔔 [RINGTONE] Attempting to play incoming call ringtone...');
      print('🔔 [RINGTONE] Source: notification.mp3 (device default fallback)');

      // Set to loop continuously
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      print('✅ [RINGTONE] Set release mode to LOOP');

      // Set volume to max
      await _audioPlayer.setVolume(1.0);
      print('✅ [RINGTONE] Set volume to MAX (1.0)');

      // Play device default notification/ringtone sound
      // This uses the system's default notification sound
      await _audioPlayer
          .play(
        AssetSource('notification.mp3'),
        volume: 1.0,
      )
          .then((_) {
        print('✅ [RINGTONE] Successfully started playing ringtone');
        print('🔊 [RINGTONE] RINGTONE IS NOW PLAYING!');
      }).catchError((e) {
        // If asset doesn't exist, just log - the CallKit notification will handle the ringtone
        print(
            '⚠️ [RINGTONE] Asset not found, using CallKit notification ringtone instead');
        print('⚠️ [RINGTONE] Error: $e');
      });

      print('🔔 [RINGTONE] ========================================\n');
    } catch (e) {
      print('❌ [RINGTONE] CRITICAL ERROR playing ringtone!');
      print('❌ [RINGTONE] Error: $e');
      print('⚠️ [RINGTONE] CallKit will handle the system ringtone');
    }
  }

  Future<void> _initializeWebRTC() async {
    if (widget.callPayload == null) return;

    try {
      print('🔊 Initializing WebRTC audio call...');

      // Initialize renderers
      await localRender.initialize();
      await remoteRender.initialize();

      // Start audio services
      AudioWakeLockHelper.acquireWakeLock();
      AudioServiceManager.startCall(
        callerName: widget.callerName,
        isVideoCall: widget.isVideo,
      );
      CallServiceHelper.startCallService(
        callerName: widget.callerName,
        isVideoCall: widget.isVideo,
      );

      // Initialize signaling
      signalingBloc = sl<SignalingBloc>();

      signalingBloc!.onAddRemoteStream = (stream) {
        remoteRender.srcObject = stream;
        print('✅ Remote stream added');
        if (mounted) {
          setState(() {});

          // If this is an outgoing call, navigate to active call page when remote connects
          if (widget.isOutgoing && !_isAnswering) {
            print('🚀 Remote connected, navigating to active call UI...');
            _isAnswering = true; // Prevent duplicate navigation

            // Stop outgoing ringtone when call is answered
            CallAudioService().stopOutgoingRingtone();

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => IOSActiveCallPage(
                  callerName: widget.callerName,
                  callerImage: widget.callerImage,
                  isVideo: widget.isVideo,
                  localRenderer: localRender,
                  remoteRenderer: remoteRender,
                  signalingBloc: signalingBloc,
                  callPayload: widget.callPayload,
                  chatId: widget.chatId,
                  senderId: widget.senderId,
                  receiverId: widget.receiverId,
                  otherPersonFcmToken: widget.otherPersonFcmToken,
                ),
              ),
            );
          }
        }
      };

      signalingBloc!.onDisconnect = () {
        print('📞 Call disconnected');
        _endCall();
      };

      // Open camera/microphone
      localRender.srcObject = await Helper.openCamera({
        'video': widget.isVideo,
        'audio': true,
      });

      // Audio output is already being managed by flutter_audio_output
      // Ensure WebRTC doesn't override our audio route
      // Apply current audio route to WebRTC
      if (_currentAudioOutput != null) {
        if (_currentAudioOutput!.port == AudioPort.speaker) {
          await Helper.setSpeakerphoneOn(true);
        } else {
          await Helper.setSpeakerphoneOn(false);
        }
        print('🎧 [WebRTC] Applied audio route: ${_currentAudioOutput!.name}');
      }

      // Create or join room
      if (widget.callPayload!.callAction == CallAction.create) {
        signalingBloc!.add(
          CreateRtcRoomEvent(
            localStream: localRender.srcObject!,
            roomId: widget.callPayload!.webrtcRoomId ?? '',
          ),
        );
        print('🏚️ Created WebRTC room');
      } else if (widget.callPayload!.callAction == CallAction.join) {
        signalingBloc!.add(
          JoinRtcRoomEvent(
            localStream: localRender.srcObject!,
            roomId: widget.callPayload!.webrtcRoomId ?? '',
          ),
        );
        print('🚪 Joined WebRTC room');
      }

      _isCallStarted = true;
      print('✅ WebRTC call started successfully');
    } catch (e) {
      print('❌ Error initializing WebRTC: $e');
    }
  }

  // ============================================================
  // 2. INITIALIZE AUDIO OUTPUT DETECTION
  // Detects available devices and listens for changes
  // ============================================================
  Future<void> _initializeAudioOutputDetection() async {
    try {
      print('\n🎧 [AUDIO OUTPUT] Initializing audio output detection...');
      
      // Get all available audio outputs (Bluetooth, Speaker, Earpiece, etc.)
      _availableAudioOutputs = await FlutterAudioOutput.getAvailableInputs();
      
      print('📦 [AUDIO OUTPUT] Available devices: ${_availableAudioOutputs.length}');
      for (var output in _availableAudioOutputs) {
        print('   - ${output.name} (${output.port})');
      }
      
      // ============================================================
      // FALLBACK: If no devices detected, use manual fallback
      // ============================================================
      if (_availableAudioOutputs.isEmpty) {
        print('⚠️ [AUDIO OUTPUT] No devices from flutter_audio_output, using manual fallback...');
        print('📱 [AUDIO OUTPUT] Manual audio routing will be available');
        print('📱 [AUDIO OUTPUT] Options: Speaker, Bluetooth, Earpiece');
        
        // Default to speaker off (earpiece/bluetooth)
        if (mounted) {
          setState(() {
            _speakerOn = false;
          });
        }
        
        // Since we can't detect devices, we'll provide manual options in the UI
        return;
      }
      // ============================================================
      
      // Get currently active audio output
      _currentAudioOutput = await FlutterAudioOutput.getCurrentOutput();
      print('✅ [AUDIO OUTPUT] Current device: ${_currentAudioOutput?.name} (${_currentAudioOutput?.port})');
      
      // Set initial audio route based on available devices
      // Priority: Bluetooth > Earpiece > Speaker
      bool initialRouteSet = false;
      
      // Check if Bluetooth is available and switch to it
      AudioInput? bluetoothDevice;
      try {
        bluetoothDevice = _availableAudioOutputs.firstWhere(
          (device) => device.port == AudioPort.bluetooth,
        );
      } catch (e) {
        // No Bluetooth found
        bluetoothDevice = null;
      }
      
      if (bluetoothDevice != null) {
        print('🎧 [AUDIO OUTPUT] Bluetooth available, routing audio to Bluetooth...');
        await FlutterAudioOutput.changeToBluetooth();
        _currentAudioOutput = bluetoothDevice;
        initialRouteSet = true;
      } else {
        // No Bluetooth, use earpiece/receiver
        print('🔊 [AUDIO OUTPUT] No Bluetooth, routing to Earpiece...');
        await FlutterAudioOutput.changeToReceiver();
        
        AudioInput? receiverDevice;
        try {
          receiverDevice = _availableAudioOutputs.firstWhere(
            (device) => device.port == AudioPort.receiver,
          );
        } catch (e) {
          // If no receiver found, keep current
          receiverDevice = _currentAudioOutput;
        }
        
        if (receiverDevice != null) {
          _currentAudioOutput = receiverDevice;
        }
        initialRouteSet = true;
      }
      
      // Update UI with initial state
      if (mounted) {
        setState(() {
          _speakerOn = _currentAudioOutput?.port == AudioPort.speaker;
        });
      }
      
      // ============================================================
      // 3. LISTEN FOR DEVICE CHANGES (Bluetooth connect/disconnect, etc.)
      // ============================================================
      FlutterAudioOutput.setListener(() async {
        print('🔄 [AUDIO OUTPUT] Device changed!');
        
        // Refresh current output
        final newOutput = await FlutterAudioOutput.getCurrentOutput();
        print('   New device: ${newOutput.name} (${newOutput.port})');
        
        // Only update UI if we're not manually switching
        // This prevents the listener from overriding user selection
        if (!_isManualSwitching && mounted) {
          setState(() {
            _currentAudioOutput = newOutput;
            _speakerOn = newOutput.port == AudioPort.speaker;
          });
        } else if (_isManualSwitching) {
          print('   🚫 Skipping UI update during manual switch');
        }
        
        // Always refresh available devices list
        _refreshAvailableAudioOutputs();
      });
      // ============================================================
      
      print('✅ [AUDIO OUTPUT] Audio output detection initialized!\n');
    } catch (e) {
      print('❌ [AUDIO OUTPUT] Error initializing audio output: $e');
      print('❌ [AUDIO OUTPUT] Stack trace: $e');
    }
  }
  
  // ============================================================
  // 4. REFRESH AVAILABLE AUDIO OUTPUTS
  // Called when devices are plugged/unplugged
  // ============================================================
  Future<void> _refreshAvailableAudioOutputs() async {
    try {
      final outputs = await FlutterAudioOutput.getAvailableInputs();
      if (mounted) {
        setState(() {
          _availableAudioOutputs = outputs;
        });
      }
      print('🔄 [AUDIO OUTPUT] Refreshed devices: ${outputs.length} available');
    } catch (e) {
      print('⚠️ [AUDIO OUTPUT] Error refreshing devices: $e');
    }
  }
  // ============================================================
  
  // ============================================================
  // 5. SWITCH AUDIO OUTPUT DEVICE
  // Called when user selects a device from the UI
  // ============================================================
  Future<void> _switchAudioOutput(AudioInput output) async {
    try {
      print('🔊 [AUDIO OUTPUT] Switching to: ${output.name} (${output.port})');
      
      // Set flag to prevent listener from overriding our selection
      _isManualSwitching = true;
      
      // Switch to the selected audio output based on port type
      bool success = false;
      switch (output.port) {
        case AudioPort.speaker:
          success = await FlutterAudioOutput.changeToSpeaker();
          break;
        case AudioPort.bluetooth:
          success = await FlutterAudioOutput.changeToBluetooth();
          break;
        case AudioPort.receiver:
          success = await FlutterAudioOutput.changeToReceiver();
          break;
        case AudioPort.headphones:
          success = await FlutterAudioOutput.changeToHeadphones();
          break;
        default:
          print('⚠️ [AUDIO OUTPUT] Unknown port type: ${output.port}');
      }
      
      if (success) {
        // Update UI immediately with user's selection
        if (mounted) {
          setState(() {
            _currentAudioOutput = output;
            _speakerOn = output.port == AudioPort.speaker;
          });
        }
        print('✅ [AUDIO OUTPUT] Switched to ${output.name}');
        
        // Clear flag after a delay to allow the switch to complete
        Future.delayed(const Duration(milliseconds: 500), () {
          _isManualSwitching = false;
        });
      } else {
        print('❌ [AUDIO OUTPUT] Failed to switch to ${output.name}');
        _isManualSwitching = false;
      }
    } catch (e) {
      print('❌ [AUDIO OUTPUT] Error switching output: $e');
      _isManualSwitching = false;
    }
  }
  // ============================================================
  
  // ============================================================
  // FALLBACK: Manual audio routing using WebRTC Helper
  // Used when flutter_audio_output doesn't detect devices
  // ============================================================
  Future<void> _applyManualAudioRoute(String route) async {
    print('🔊 [MANUAL] Applying audio route: $route');
    
    try {
      switch (route) {
        case 'Speaker':
          await Helper.setSpeakerphoneOn(true);
          if (mounted) {
            setState(() {
              _speakerOn = true;
              _currentManualRoute = 'Speaker';
            });
          }
          print('✅ [MANUAL] Switched to Speaker');
          break;
          
        case 'Bluetooth':
        case 'Earpiece':
          await Helper.setSpeakerphoneOn(false);
          if (mounted) {
            setState(() {
              _speakerOn = false;
              _currentManualRoute = route;
            });
          }
          print('✅ [MANUAL] Switched to $route (setSpeakerphoneOn=false)');
          break;
      }
    } catch (e) {
      print('❌ [MANUAL] Error switching audio route: $e');
    }
  }
  // ============================================================
  
  // ============================================================
  // 6. SHOW AUDIO ROUTING OPTIONS SHEET
  // Displays ALL available audio outputs to the user
  // ============================================================
  void _showAudioRoutingSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  'Audio Output',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(color: Color(0xFF2C2C2E)),
              // Dynamically build options for ALL available devices
              if (_availableAudioOutputs.isEmpty) ...[
                // FALLBACK: Show manual options when flutter_audio_output fails
                _buildAudioRouteOption(
                  icon: Icons.volume_up,
                  label: 'Speaker',
                  isSelected: _speakerOn && _currentManualRoute == 'Speaker',
                  onTap: () {
                    Navigator.pop(context);
                    _applyManualAudioRoute('Speaker');
                  },
                ),
                _buildAudioRouteOption(
                  icon: Icons.bluetooth_audio,
                  label: 'Bluetooth',
                  isSelected: !_speakerOn && _currentManualRoute == 'Bluetooth',
                  onTap: () {
                    Navigator.pop(context);
                    _applyManualAudioRoute('Bluetooth');
                  },
                ),
                _buildAudioRouteOption(
                  icon: Icons.phone_in_talk,
                  label: 'Earpiece',
                  isSelected: !_speakerOn && _currentManualRoute == 'Earpiece',
                  onTap: () {
                    Navigator.pop(context);
                    _applyManualAudioRoute('Earpiece');
                  },
                ),
              ] else ...[
                // Normal mode: Show devices from flutter_audio_output
                ...(_availableAudioOutputs.map((output) {
                  return _buildAudioRouteOption(
                    icon: _getIconForOutputType(output.port),
                    label: output.name,
                    isSelected: _currentAudioOutput?.name == output.name,
                    onTap: () {
                      Navigator.pop(context);
                      _switchAudioOutput(output);
                    },
                  );
                }).toList()),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  // Helper: Get icon for audio output port
  IconData _getIconForOutputType(AudioPort port) {
    switch (port) {
      case AudioPort.bluetooth:
        return Icons.bluetooth_audio;
      case AudioPort.speaker:
        return Icons.volume_up;
      case AudioPort.receiver:
        return Icons.phone_in_talk;
      case AudioPort.headphones:
        return Icons.headset;
      default:
        return Icons.volume_up;
    }
  }
  // ============================================================

  Widget _buildAudioRouteOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFF007AFF) : Colors.white,
        size: 28,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF007AFF) : Colors.white,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(
              Icons.check,
              color: Color(0xFF007AFF),
            )
          : null,
      onTap: onTap,
    );
  }

  void _handleAnswer() async {
    print('\n✅ [CALL ANSWER] ========================================');
    print('✅ [CALL ANSWER] User ACCEPTED the call!');
    print('✅ [CALL ANSWER] Caller: ${widget.callerName}');
    print('✅ [CALL ANSWER] Call Type: ${widget.isVideo ? "VIDEO" : "AUDIO"}');
    print('✅ [CALL ANSWER] Stopping ringtones...');

    setState(() {
      _isAnswering = true;
    });

    // Stop audio player
    await _audioPlayer.stop();
    print('🔇 [CALL ANSWER] Stopped audio player');

    // Stop all ringtones when call is answered
    await CallAudioService().stopAll();
    print('🔇 [CALL ANSWER] Stopped all ringtones via CallAudioService');

    // Stop CallKit ringtone
    await FlutterCallkitIncoming.endAllCalls();
    print('🔇 [CALL ANSWER] Ended CallKit notification');
    print('✅ [CALL ANSWER] All ringtones stopped successfully!');
    print('✅ [CALL ANSWER] ========================================\n');

    // Start WebRTC if not already started (for incoming calls)
    if (!_isCallStarted && widget.callPayload != null) {
      print('🔊 [CALL ANSWER] Receiver accepting call, starting WebRTC...');
      print('🔊 [CALL ANSWER] Room ID: ${widget.callPayload!.webrtcRoomId}');
      await _initializeWebRTC();

      // Send call accepted status
      if (widget.chatId != null &&
          widget.senderId != null &&
          widget.receiverId != null) {
        print('💾 [CALL ANSWER] Sending call accepted status to Firestore...');
        await CallMessageService.sendCallStatusMessage(
          chatId: widget.chatId!,
          senderId: widget.receiverId!, // Receiver is now sender of this status
          receiverId:
              widget.senderId!, // Original sender is now receiver of status
          type: CallMessageType.callAccepted,
        );
        print('✅ [CALL ANSWER] Call accepted status sent to Firestore');
      }
    }

    // Navigate to active call page with WebRTC controls
    print('🚀 [CALL ANSWER] Navigating to active call UI...');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => IOSActiveCallPage(
            callerName: widget.callerName,
            callerImage: widget.callerImage,
            isVideo: widget.isVideo,
            localRenderer: localRender,
            remoteRenderer: remoteRender,
            signalingBloc: signalingBloc,
            callPayload: widget.callPayload,
            chatId: widget.chatId,
            senderId: widget.senderId,
            receiverId: widget.receiverId,
            otherPersonFcmToken: widget.otherPersonFcmToken,
          ),
        ),
      );
    }
  }

  void _endCall() {
    print('📞 [END CALL] Ending call and returning to chat...');
    if (_isCallStarted && signalingBloc != null) {
      AudioServiceManager.stopCall();
      AudioWakeLockHelper.releaseWakeLock();
      CallServiceHelper.stopCallService();
      signalingBloc!.add(HangUpCallEvent(
        localRender: localRender,
        payload: widget.callPayload!,
      ));
    }
    
    // NAVIGATION: Return to chat page that initiated the call
    // Since calls are now ALWAYS initiated from chat_page.dart via instant Navigator.push,
    // a simple Navigator.pop will ALWAYS return to the correct chat_page instance.
    // The chat_page is in the navigation stack right below this call page.
    // 
    // Navigation Stack:
    // [info_page] -> [users_list] -> [chat_page] -> [THIS CALL PAGE]
    //                                      ^
    //                                      |
    //                                Navigator.pop returns here
    if (mounted) {
      print('🔙 [END CALL] Popping back to chat page...');
      Navigator.pop(context, {'status': 'ended'});
      print('✅ [END CALL] Returned to chat page');
    }
  }

  void _handleDecline() async {
    print('\n❌ [CALL DECLINE] ========================================');
    print('❌ [CALL DECLINE] User DECLINED/CANCELLED the call!');
    print('❌ [CALL DECLINE] Caller: ${widget.callerName}');
    print('❌ [CALL DECLINE] Is Outgoing: ${widget.isOutgoing}');
    print('❌ [CALL DECLINE] Stopping ringtones...');

    await _audioPlayer.stop();
    print('🔇 [CALL DECLINE] Stopped audio player');

    // Stop all ringtones
    await CallAudioService().stopAll();
    print('🔇 [CALL DECLINE] Stopped all ringtones via CallAudioService');

    // Stop CallKit ringtone
    await FlutterCallkitIncoming.endAllCalls();
    print('🔇 [CALL DECLINE] Ended CallKit notification');
    print('❌ [CALL DECLINE] All ringtones stopped successfully!');
    print('❌ [CALL DECLINE] ========================================\n');

    // End WebRTC call if active
    if (_isCallStarted && signalingBloc != null) {
      signalingBloc!.add(HangUpCallEvent(
        localRender: localRender,
        payload: widget.callPayload!,
      ));
    }

    // NAVIGATION: Return to chat page that initiated the call
    // Since calls are now ALWAYS initiated from chat_page.dart via instant Navigator.push,
    // a simple Navigator.pop will ALWAYS return to the correct chat_page instance.
    // The chat_page is in the navigation stack right below this call page.
    // 
    // Navigation Stack:
    // [info_page] -> [users_list] -> [chat_page] -> [THIS CALL PAGE]
    //                                      ^
    //                                      |
    //                                Navigator.pop returns here
    final resultStatus = widget.isOutgoing ? 'missed' : 'declined';
    if (mounted) {
      print('🔙 [CALL DECLINE] Popping back to chat page with status: $resultStatus');
      Navigator.pop(context, {'status': resultStatus});
      print('✅ [CALL DECLINE] Returned to chat page');
    }

    // Show feedback snackbar after navigation
    final message = widget.isOutgoing ? 'Call cancelled' : 'Call declined';
    // Use a delayed execution to show snackbar after navigation completes
    Future.delayed(const Duration(milliseconds: 100), () {
      if (AppConstants.navigatorKey.currentContext != null) {
        ScaffoldMessenger.of(AppConstants.navigatorKey.currentContext!)
            .showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            // Caller Info - CENTER ALIGNED
            Center(
              child: Text(
                widget.isOutgoing ? 'Calling...' : 'incoming call',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                widget.callerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Profile Picture with Pulse Animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulse ring
                    Container(
                      width: 200 + (_pulseController.value * 40),
                      height: 200 + (_pulseController.value * 40),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white
                              .withOpacity(0.3 * (1 - _pulseController.value)),
                          width: 2,
                        ),
                      ),
                    ),
                    // Inner pulse ring
                    Container(
                      width: 180 + (_pulseController.value * 20),
                      height: 180 + (_pulseController.value * 20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white
                              .withOpacity(0.5 * (1 - _pulseController.value)),
                          width: 2,
                        ),
                      ),
                    ),
                    // Profile Picture
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2C2C2E),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: widget.callerImage != null &&
                                widget.callerImage!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.callerImage!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Center(
                                  child: Text(
                                    widget.callerName[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 60,
                                      fontWeight: FontWeight.w300,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  widget.callerName[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 60,
                                    fontWeight: FontWeight.w300,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const Spacer(),
            // Call Type Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isVideo ? Icons.videocam : Icons.phone,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isVideo ? 'Video Call' : 'Voice Call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
            // Slide to Answer (only for incoming)
            if (!widget.isOutgoing) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate max slide distance based on actual container width
                    _maxSlideDistance = constraints.maxWidth -
                        70; // 70 = button width (60) + padding (10)

                    return GestureDetector(
                      onHorizontalDragStart: (details) {
                        // Light haptic feedback when user starts dragging
                        HapticFeedback.selectionClick();
                      },
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _slidePosition += details.delta.dx;
                          // Clamp to valid range
                          _slidePosition =
                              _slidePosition.clamp(0.0, _maxSlideDistance);
                        });

                        // Answer when slid 90% of the way
                        if (_slidePosition >= _maxSlideDistance * 0.9 &&
                            !_isAnswering) {
                          HapticFeedback
                              .mediumImpact(); // Stronger haptic when call is answered
                          _handleAnswer();
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        // Spring back if not slid far enough
                        if (_slidePosition < _maxSlideDistance * 0.9 &&
                            !_isAnswering) {
                          HapticFeedback
                              .lightImpact(); // Light feedback when releasing
                          setState(() {
                            _slidePosition = 0.0;
                          });
                        }
                      },
                      child: Container(
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(35),
                        ),
                        child: Stack(
                          children: [
                            // Text fades out as slider moves
                            Center(
                              child: Opacity(
                                opacity:
                                    (1 - (_slidePosition / _maxSlideDistance))
                                        .clamp(0.0, 1.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.arrow_forward,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'slide to answer',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.6),
                                        fontSize: 18,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Animated slider button
                            AnimatedPositioned(
                              duration: _slidePosition == 0
                                  ? const Duration(
                                      milliseconds: 300) // Smooth spring-back
                                  : const Duration(
                                      milliseconds: 0), // Instant during drag
                              curve: Curves.easeOutCubic,
                              left: _slidePosition,
                              top: 5,
                              bottom: 5,
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Color.lerp(
                                    const Color(0xFF4CD964),
                                    Colors.green.shade600,
                                    (_slidePosition / _maxSlideDistance)
                                        .clamp(0.0, 1.0),
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF4CD964)
                                          .withOpacity(0.5),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.phone,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),
            ],
            // Action Buttons - Audio Controls
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 32,
              runSpacing: 24,
              children: [
                // ============================================================
                // AUDIO ROUTE BUTTON (shows REAL current device name)
                // ============================================================
                _buildActionButton(
                  icon: _availableAudioOutputs.isEmpty
                      ? (_currentManualRoute == 'Speaker' 
                          ? Icons.volume_up 
                          : _currentManualRoute == 'Bluetooth'
                              ? Icons.bluetooth_audio
                              : Icons.phone_in_talk)
                      : _getIconForOutputType(
                          _currentAudioOutput?.port ?? AudioPort.speaker
                        ),
                  label: _availableAudioOutputs.isEmpty
                      ? _currentManualRoute
                      : (_currentAudioOutput?.name ?? 'Speaker'),
                  color: (_availableAudioOutputs.isEmpty && _currentManualRoute != 'Earpiece') ||
                         (_currentAudioOutput?.port != AudioPort.receiver)
                      ? const Color(0xFF007AFF)
                      : Colors.white,
                  onTap: () {
                    _showAudioRoutingSheet();
                  },
                ),
                // ============================================================
                // Mute button
                _buildActionButton(
                  icon: _micMuted ? Icons.mic_off : Icons.mic,
                  label: _micMuted ? 'Unmute' : 'Mute',
                  color: _micMuted ? Colors.red : Colors.white,
                  onTap: () async {
                    if (!_isCallStarted || localRender.srcObject == null) return;
                    
                    setState(() {
                      _micMuted = !_micMuted;
                    });
                    
                    // Mute/unmute audio track
                    final audioTracks = localRender.srcObject!.getAudioTracks();
                    if (audioTracks.isNotEmpty) {
                      audioTracks[0].enabled = !_micMuted;
                      print(_micMuted ? '🔇 Microphone muted' : '🎤 Microphone unmuted');
                    }
                  },
                ),
                // Decline/End button
                _buildActionButton(
                  icon: Icons.call_end,
                  label: widget.isOutgoing ? 'End' : 'Decline',
                  color: Colors.red,
                  onTap: _handleDecline,
                ),
              ],
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    Color color = Colors.white,
    required VoidCallback onTap,
  }) {
    final isActiveColor = color != Colors.white && color != Colors.red;
    final backgroundColor = color == Colors.red
        ? Colors.red
        : isActiveColor
            ? color.withOpacity(0.3)
            : Colors.white.withOpacity(0.15);
    
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              border: isActiveColor
                  ? Border.all(color: color, width: 2)
                  : null,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isActiveColor ? color : Colors.white,
              fontSize: 12,
              fontWeight: isActiveColor ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
