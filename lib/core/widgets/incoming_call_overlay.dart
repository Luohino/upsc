import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../features/data/model/notification_payload.dart';
import '../utils/common_imports.dart';

class IncomingCallOverlay extends StatefulWidget {
  final NotificationPayload payload;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  const IncomingCallOverlay({
    super.key,
    required this.payload,
    required this.onAnswer,
    required this.onDecline,
  });

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  double _slidePosition = 0.0;
  double _maxSlideDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            // Caller Info
            Text(
              'incoming call',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.payload.name ?? widget.payload.username ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w300,
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
                        child: widget.payload.imageUrl != null &&
                                widget.payload.imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: widget.payload.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Center(
                                  child: Text(
                                    (widget.payload.name ?? 'U')[0]
                                        .toUpperCase(),
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
                                  (widget.payload.name ?? 'U')[0].toUpperCase(),
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
                    widget.payload.callType == CallType.video
                        ? Icons.videocam
                        : Icons.phone,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.payload.callType == CallType.video
                        ? 'Video Call'
                        : 'Voice Call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
            // Slide to Answer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _maxSlideDistance = constraints.maxWidth - 70;

                  return GestureDetector(
                    onHorizontalDragStart: (details) {
                      HapticFeedback.selectionClick();
                    },
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _slidePosition += details.delta.dx;
                        _slidePosition =
                            _slidePosition.clamp(0.0, _maxSlideDistance);
                      });

                      if (_slidePosition >= _maxSlideDistance * 0.9) {
                        HapticFeedback.mediumImpact();
                        widget.onAnswer();
                      }
                    },
                    onHorizontalDragEnd: (details) {
                      if (_slidePosition < _maxSlideDistance * 0.9) {
                        HapticFeedback.lightImpact();
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
                          AnimatedPositioned(
                            duration: _slidePosition == 0
                                ? const Duration(milliseconds: 300)
                                : const Duration(milliseconds: 0),
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
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.access_time,
                  label: 'Remind Me',
                  onTap: widget.onDecline,
                ),
                _buildActionButton(
                  icon: Icons.message,
                  label: 'Message',
                  onTap: widget.onDecline,
                ),
                _buildActionButton(
                  icon: Icons.call_end,
                  label: 'Decline',
                  color: Colors.red,
                  onTap: widget.onDecline,
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color == Colors.red
                  ? Colors.red
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
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
