import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../../l10n/app_localizations.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  static const List<double> _widths = [2, 3, 5, 8];
  double _strokeWidth = 3;

  late SignatureController _controller = _makeController();

  SignatureController _makeController({List<Point>? points}) {
    final controller = SignatureController(
      penStrokeWidth: _strokeWidth,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
      points: points,
    );
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    return controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setStrokeWidth(double width) {
    if (width == _strokeWidth) return;
    final preserved = List<Point>.from(_controller.points);
    _controller.dispose();
    setState(() {
      _strokeWidth = width;
      _controller = _makeController(points: preserved);
    });
  }

  Future<Uint8List?> _export() async {
    if (_controller.isEmpty) return null;
    return _controller.toPngBytes();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0B1420) : const Color(0xFFF5F8FC);
    final cardBg = isDark ? const Color(0xFF162233) : Colors.white;
    final appBarBg = isDark ? const Color(0xFF101A29) : const Color(0xFFF5F8FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final chipBg = isDark ? const Color(0xFF223247) : const Color(0xFFEAF1F8);
    const accent = Color(0xFF2CA5E0);

    final canUndo = _controller.points.isNotEmpty;
    final isEmpty = _controller.isEmpty;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text(
          l10n.sigAddTitle,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: l10n.undo,
            onPressed: canUndo ? _controller.undo : null,
            icon: Icon(Icons.undo, color: canUndo ? textColor : subColor),
          ),
          IconButton(
            tooltip: l10n.redo,
            onPressed: _controller.redo,
            icon: Icon(Icons.redo, color: textColor),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.draw_outlined,
                        color: accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.sigAddYours,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.sigHint,
                            style: TextStyle(
                              color: subColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      top: 14,
                      left: 10,
                      right: 10,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F1925).withValues(alpha: 0.35)
                              : const Color(0xFFD8E4F0).withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFEFC),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.34 : 0.08,
                            ),
                            blurRadius: 28,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: const _PaperGuidePainter(
                                    lineColor: Color(0xFFE8EEF5),
                                  ),
                                ),
                              ),
                            ),
                            if (isEmpty)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.96),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: const Color(0xFFDDE6EF),
                                        ),
                                      ),
                                      child: Text(
                                        l10n.sigHint,
                                        style: const TextStyle(
                                          color: Color(0xFF6B7A99),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Signature(
                              controller: _controller,
                              backgroundColor: Colors.transparent,
                            ),
                            Positioned(
                              left: 28,
                              right: 28,
                              bottom: 62,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.sigAddTitle,
                                    style: const TextStyle(
                                      color: Color(0xFF9AA8B8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD7E1EB),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.sigPenWidth,
                      style: TextStyle(
                        color: subColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final width in _widths) ...[
                          Expanded(
                            child: _StrokeChip(
                              width: width,
                              selected: _strokeWidth == width,
                              accent: accent,
                              chipBg: chipBg,
                              textColor: textColor,
                              onTap: () => _setStrokeWidth(width),
                            ),
                          ),
                          if (width != _widths.last) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canUndo ? _controller.clear : null,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(l10n.clearSelection),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: canUndo ? const Color(0xFFE74C3C) : subColor,
                        side: BorderSide(
                          color: canUndo
                              ? const Color(0xFFE74C3C)
                              : subColor.withValues(alpha: 0.3),
                        ),
                        backgroundColor: cardBg,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Builder(
                      builder: (btnContext) {
                        return ElevatedButton.icon(
                          onPressed: canUndo
                              ? () async {
                                  final bytes = await _export();
                                  if (bytes == null) return;
                                  if (!btnContext.mounted) return;
                                  Navigator.pop(btnContext, bytes);
                                }
                              : null,
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(l10n.actionDone),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            disabledBackgroundColor:
                                accent.withValues(alpha: 0.35),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaperGuidePainter extends CustomPainter {
  const _PaperGuidePainter({required this.lineColor});

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    const topInset = 54.0;
    const step = 42.0;
    for (double y = topInset; y < size.height - 96; y += step) {
      canvas.drawLine(
        Offset(24, y),
        Offset(size.width - 24, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGuidePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}

class _StrokeChip extends StatelessWidget {
  final double width;
  final bool selected;
  final Color accent;
  final Color chipBg;
  final Color textColor;
  final VoidCallback onTap;

  const _StrokeChip({
    required this.width,
    required this.selected,
    required this.accent,
    required this.chipBg,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accent : chipBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 12,
              child: Center(
                child: Container(
                  height: width,
                  width: 32,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : textColor,
                    borderRadius: BorderRadius.circular(width / 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${width.toStringAsFixed(0)}px',
              style: TextStyle(
                color: selected ? Colors.white : textColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
