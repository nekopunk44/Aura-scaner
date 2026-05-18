import 'package:flutter/material.dart';

enum NotificationType { error, success, info }

class AppNotification {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String message,
    NotificationType type = NotificationType.error,
    Duration duration = const Duration(seconds: 3),
  }) {
    _current?.remove();
    _current = null;

    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => _NotificationToast(
        message: message,
        type: type,
        duration: duration,
        onDismiss: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
      ),
    );

    _current = entry;
    overlay.insert(entry);
  }
}

class _NotificationToast extends StatefulWidget {
  final String message;
  final NotificationType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const _NotificationToast({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_NotificationToast> createState() => _NotificationToastState();
}

class _NotificationToastState extends State<_NotificationToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.5)));

    _ctrl.forward();

    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (icon, accent) = switch (widget.type) {
      NotificationType.error   => (Icons.error_outline_rounded,   const Color(0xFFFF5C5C)),
      NotificationType.success => (Icons.check_circle_outline_rounded, const Color(0xFF4CAF50)),
      NotificationType.info    => (Icons.info_outline_rounded,    const Color(0xFF2CA5E0)),
    };

    final bg = isDark ? const Color(0xFF1E2D3D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final shadow = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.12);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: GestureDetector(
                onTap: _dismiss,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.35),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: shadow,
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: accent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.close_rounded,
                            size: 18,
                            color: textColor.withValues(alpha: 0.35)),
                      ],
                    ),
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
