import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class PIPVideoOverlay extends StatefulWidget {
  final RTCVideoRenderer localRenderer;
  final RTCVideoRenderer remoteRenderer;
  final VoidCallback onClose;
  final VoidCallback onExpand;
  final String callerName;
  final bool isVideoCall;

  const PIPVideoOverlay({
    super.key,
    required this.localRenderer,
    required this.remoteRenderer,
    required this.onClose,
    required this.onExpand,
    required this.callerName,
    this.isVideoCall = true,
  });

  @override
  State<PIPVideoOverlay> createState() => _PIPVideoOverlayState();
}

class _PIPVideoOverlayState extends State<PIPVideoOverlay> {
  Offset _position = const Offset(20, 100);
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() => _isDragging = true);
        },
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx).clamp(
                0.0,
                MediaQuery.of(context).size.width - 160,
              ),
              (_position.dy + details.delta.dy).clamp(
                0.0,
                MediaQuery.of(context).size.height - 220,
              ),
            );
          });
        },
        onPanEnd: (_) {
          setState(() => _isDragging = false);
        },
        onTap: widget.onExpand,
        child: Container(
          width: 140,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Video or Audio UI
              if (widget.isVideoCall) ...[
                // Remote video (main)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(
                    widget.remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
                // Local video (small inset)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    width: 50,
                    height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: RTCVideoView(
                        widget.localRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Audio call UI
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.withOpacity(0.8),
                        Colors.purple.withOpacity(0.8),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.phone_in_talk,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.callerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'In call...',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Close button
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
              // Drag indicator
              if (_isDragging)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
