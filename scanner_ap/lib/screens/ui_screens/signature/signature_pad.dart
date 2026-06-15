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
    final c = SignatureController(
      penStrokeWidth: _strokeWidth,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
      points: points,
    );
    c.addListener(() {
      if (mounted) setState(() {});
    });
    return c;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setStrokeWidth(double w) {
    if (w == _strokeWidth) return;
    final preserved = List<Point>.from(_controller.points);
    _controller.dispose();
    setState(() {
      _strokeWidth = w;
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
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final chipBg = isDark ? const Color(0xFF2A3A4F) : const Color(0xFFEEF3FA);
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: [
              // Холст для подписи — всегда светлый, чтобы чёрная ручка
              // была отчётливо видна и в тёмной теме.
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        if (isEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.draw_outlined,
                                      size: 56,
                                      color: const Color(0xFFB8C5D6),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.sigHint,
                                      style: TextStyle(
                                        color: const Color(0xFF6B7A99),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Signature(
                          controller: _controller,
                          backgroundColor: Colors.transparent,
                        ),
                        // Базовая линия — визуальная подсказка где поставить.
                        Positioned(
                          left: 32,
                          right: 32,
                          bottom: 48,
                          child: Container(
                            height: 1,
                            color: const Color(0xFFE0E6EE),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
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
                        for (final w in _widths) ...[
                          Expanded(
                            child: _StrokeChip(
                              width: w,
                              selected: _strokeWidth == w,
                              accent: accent,
                              chipBg: chipBg,
                              textColor: textColor,
                              onTap: () => _setStrokeWidth(w),
                            ),
                          ),
                          if (w != _widths.last) const SizedBox(width: 8),
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
                        side: BorderSide(color: canUndo ? const Color(0xFFE74C3C) : subColor.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Builder(builder: (btnContext) {
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
                          disabledBackgroundColor: accent.withValues(alpha: 0.35),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      );
                    }),
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
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Превью толщины линии — пользователь сразу видит результат.
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
