import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/utils/common_imports.dart';
import '../../../core/utils/audio_service_handler.dart';
import '../../../core/utils/audio_wakelock_helper.dart';
import '../../../core/utils/call_service_helper.dart';
import '../../data/services/call_message_service.dart';
import '../../data/model/notification_payload.dart';
import '../bloc/signaling_bloc/signaling_bloc.dart';

class IOSActiveCallPage extends StatefulWidget {
  final String callerName;
  final String? callerImage;
  final bool isVideo;
  final RTCVideoRenderer? localRenderer;
  final RTCVideoRenderer? remoteRenderer;
  final SignalingBloc? signalingBloc;
  final NotificationPayload? callPayload;
  final String? chatId;
  final String? senderId;
  final String? receiverId;
  final String? otherPersonFcmToken;

  const IOSActiveCallPage({
    super.key,
    required this.callerName,
    this.callerImage,
    this.isVideo = false,
    this.localRenderer,
    this.remoteRenderer,
    this.signalingBloc,
    this.callPayload,
    this.chatId,
    this.senderId,
    this.receiverId,
    this.otherPersonFcmToken,
  });

  @override
  State<IOSActiveCallPage> createState() => _IOSActiveCallPageState();
}

class _IOSActiveCallPageState extends State<IOSActiveCallPage> {
  bool _isMuted = false;
  bool _isSpeakerOn = true; // Speaker ON by default for voice calls
  bool _isBluetoothConnected = false;
  Timer? _callTimer;
  int _secondsElapsed = 0;

  @override
  void initState() {
    super.initState();
    _startCallTimer();
    _checkBluetoothStatus();

    // Ensure speaker is on
    if (widget.localRenderer != null) {
      Helper.setSpeakerphoneOn(true);
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();

    // Clean up WebRTC resources
    if (widget.localRenderer != null) {
      AudioServiceManager.stopCall();
      AudioWakeLockHelper.releaseWakeLock();
      CallServiceHelper.stopCallService();
      widget.localRenderer?.dispose();
      widget.remoteRenderer?.dispose();
      widget.signalingBloc?.dispose();
    }

    super.dispose();
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  Future<void> _checkBluetoothStatus() async {
    // In a real implementation, you would check for actual bluetooth connections
    // For now, this is a placeholder
    // You can use packages like flutter_blue_plus to detect bluetooth devices
    setState(() {
      _isBluetoothConnected = false; // Set based on actual bluetooth status
    });
  }

  String _formatCallDuration() {
    final minutes = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _toggleMute() async {
    setState(() {
      _isMuted = !_isMuted;
    });

    // Toggle microphone on local stream
    if (widget.localRenderer?.srcObject != null) {
      final audioTracks = widget.localRenderer!.srcObject!.getAudioTracks();
      for (var track in audioTracks) {
        track.enabled = !_isMuted;
      }
      showLog('🎤 Mute toggled: $_isMuted');
    }
  }

  void _toggleSpeaker() async {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });

    // Toggle speaker mode
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    showLog('🔊 Speaker toggled: $_isSpeakerOn');
  }

  void _switchToChat() {
    // NAVIGATION: Return to chat page
    // Using Navigator.pop returns to the previous screen in the navigation stack
    // This will return to the chat_page.dart that initiated the call
    Navigator.pop(context);
  }

  void _endCall() async {
    _callTimer?.cancel();

    // Send end call notification to the other person
    if (widget.otherPersonFcmToken != null &&
        widget.otherPersonFcmToken!.isNotEmpty) {
      try {
        print('📤 [Call End] Sending end call notification to other person...');
        await FCMHelper.sendNotification(
          fcmToken: widget.otherPersonFcmToken!,
          payload: NotificationPayload(
            callAction: CallAction.end,
            notificationId: widget.callPayload?.notificationId ??
                DateTime.now().millisecondsSinceEpoch.toString(),
            webrtcRoomId: widget.callPayload?.webrtcRoomId ?? widget.chatId,
          ),
        );
        print('✅ [Call End] End call notification sent successfully');
      } catch (e) {
        print('❌ [Call End] Error sending end call notification: $e');
      }
    }

    // End WebRTC call
    if (widget.signalingBloc != null &&
        widget.callPayload != null &&
        widget.localRenderer != null) {
      AudioServiceManager.stopCall();
      AudioWakeLockHelper.releaseWakeLock();
      CallServiceHelper.stopCallService();
      widget.signalingBloc!.add(HangUpCallEvent(
        localRender: widget.localRenderer!,
        payload: widget.callPayload!,
      ));
    }

    // Send call ended status
    if (widget.chatId != null &&
        widget.senderId != null &&
        widget.receiverId != null) {
      try {
        await CallMessageService.sendCallStatusMessage(
          chatId: widget.chatId!,
          senderId: widget.senderId!,
          receiverId: widget.receiverId!,
          type: CallMessageType.callEnded,
        );
        print('📞 Call ended status sent to Firestore');
      } catch (e) {
        print('❌ Error sending call ended status: $e');
      }
    }

    // Save call history
    try {
      final userPref = SharedPrefs.getUserDetails;
      if (userPref != null) {
        final currentUser = jsonDecode(userPref);
        await FirebaseFirestore.instance.collection('calls').add({
          'callerId': currentUser['uid'],
          'callerName': currentUser['name'],
          'receiverName': widget.callerName,
          'status': 'ended',
          'duration': _secondsElapsed,
          'callType': widget.isVideo ? 'video' : 'audio',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      showLog('Error saving call history: $e');
    }

    // NAVIGATION FIX: Return to the chat page that initiated the call
    // This active call page is opened from ios_incoming_call_page.dart (line 261 or line 743)
    // which was itself opened from chat_page.dart (line 631)
    // Using Navigator.pop here returns to ios_incoming_call_page, which then auto-pops to chat_page
    // OR if the user manually ended the call here, it goes directly back to the previous screen
    // Either way, we end up back at the chat_page.dart that started the call, NOT info_page.dart
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Call Status
            Text(
              widget.isVideo ? 'Video Call' : 'Voice Call',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
            // Caller Name
            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 8),
            // Call Duration
            Text(
              _formatCallDuration(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 60),
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
                          child: CircularProgressIndicator(color: Colors.white),
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
            const Spacer(),
            // Bluetooth Indicator
            if (_isBluetoothConnected)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.bluetooth_connected,
                      color: Color(0xFF007AFF),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Bluetooth Connected',
                      style: TextStyle(
                        color: const Color(0xFF007AFF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            // Control Buttons Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        label: 'mute',
                        isActive: _isMuted,
                        onTap: _toggleMute,
                      ),
                      _buildControlButton(
                        icon: Icons.dialpad,
                        label: 'keypad',
                        onTap: () {
                          // Show keypad
                        },
                      ),
                      _buildControlButton(
                        icon:
                            _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                        label: 'speaker',
                        isActive: _isSpeakerOn,
                        onTap: _toggleSpeaker,
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: Icons.person_add,
                        label: 'add call',
                        onTap: () {
                          // Add call functionality
                        },
                      ),
                      if (widget.isVideo)
                        _buildControlButton(
                          icon: Icons.videocam_off,
                          label: 'video',
                          onTap: () {
                            // Toggle video
                          },
                        ),
                      _buildControlButton(
                        icon: Icons.chat,
                        label: 'chat',
                        onTap: _switchToChat,
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // End Call Button
                  GestureDetector(
                    onTap: _endCall,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF007AFF)
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
