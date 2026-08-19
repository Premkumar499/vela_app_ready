import 'dart:async';
import 'package:flutter/material.dart';

class ToastNotification extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismissed;

  const ToastNotification({
    super.key,
    required this.message,
    required this.isError,
    required this.onDismissed,
  });

  @override
  State<ToastNotification> createState() => _ToastNotificationState();
}

class _ToastNotificationState extends State<ToastNotification>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // Slide in from right (X = 1.5) to its leftward position (X = 0)
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(1.5, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    _controller.forward();

    // Dismiss after exactly 2 seconds
    _dismissTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) {
          widget.onDismissed();
        });
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Styling constants
    final bgColor = widget.isError ? const Color(0xFFDC2626) : const Color(0xFF1E293B);
    final iconColor = widget.isError ? Colors.white : const Color(0xFF38BDF8);
    final icon = widget.isError ? Icons.warning_amber_rounded : Icons.info_outline_rounded;

    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 24, right: 24),
          child: SlideTransition(
            position: _offsetAnimation,
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    // Specific border layouts per request screenshot:
                    // Error: Solid white outline border
                    // Clipboard/Success: Sleek left & right blue accent borders
                    border: widget.isError
                        ? Border.all(color: Colors.white, width: 2.0)
                        : Border(
                            left: BorderSide(color: iconColor, width: 5),
                            right: BorderSide(color: iconColor, width: 5),
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: iconColor, size: 24),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper method to show toast notification
void showToast(BuildContext context, String message, {bool isError = false}) {
  final overlayState = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => ToastNotification(
      message: message,
      isError: isError,
      onDismissed: () {
        entry.remove();
      },
    ),
  );
  overlayState.insert(entry);
}
