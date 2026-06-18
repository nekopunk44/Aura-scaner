import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../../l10n/app_localizations.dart';

enum _SignatureControlPanel { width, color }

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  static const List<double> _widths = [2, 3, 5, 8];
  static const List<Color> _colors = [
    Color(0xFF101820),
    Color(0xFF2CA5E0),
    Color(0xFF34A853),
    Color(0xFFE67E22),
    Color(0xFFE74C3C),
  ];

  double _strokeWidth = 3;
  Color _penColor = const Color(0xFF101820);
  _SignatureControlPanel _activePanel = _SignatureControlPanel.width;

  late SignatureController _controller = _makeController();

  SignatureController _makeController({List<Point>? points}) {
    final controller = SignatureController(
      penStrokeWidth: _strokeWidth,
      penColor: _penColor,
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

  void _setPenColor(Color color) {
    if (color == _penColor) return;
    final preserved = List<Point>.from(_controller.points);
    _controller.dispose();
    setState(() {
      _penColor = color;
      _controller = _makeController(points: preserved);
    });
  }

  Future<Uint8List?> _export() async {
    if (_controller.isEmpty) return null;
    return _controller.toPngBytes();
  }

  bool _isRussian(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru';
  }

  String _colorTitle(BuildContext context) {
    return _isRussian(context) ? 'Цвет пера' : 'Pen color';
  }

  Widget _buildControlPanel(
    BuildContext context, {
    required AppLocalizations l10n,
    required Color cardBg,
    required Color textColor,
    required Color subColor,
    required Color chipBg,
    required Color accent,
    required bool isDark,
  }) {
    final overlayColor = isDark
        ? const Color(0xFF172436).withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.84);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFDCE5F0).withValues(alpha: 0.9);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: overlayColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _FilterTabChip(
                      title: l10n.sigPenWidth,
                      selected: _activePanel == _SignatureControlPanel.width,
                      accent: accent,
                      chipBg: chipBg,
                      textColor: textColor,
                      onTap: () {
                        setState(() => _activePanel = _SignatureControlPanel.width);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FilterTabChip(
                      title: _colorTitle(context),
                      selected: _activePanel == _SignatureControlPanel.color,
                      accent: accent,
                      chipBg: chipBg,
                      textColor: textColor,
                      onTap: () {
                        setState(() => _activePanel = _SignatureControlPanel.color);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _activePanel == _SignatureControlPanel.width
                    ? Row(
                        key: const ValueKey('width-panel'),
                        children: [
                          for (final width in _widths) ...[
                            Expanded(
                              child: _StrokeChip(
                                width: width,
                                selected: _strokeWidth == width,
                                accent: accent,
                                chipBg: chipBg,
                                textColor: textColor,
                                strokeColor: _penColor,
                                onTap: () => _setStrokeWidth(width),
                              ),
                            ),
                            if (width != _widths.last) const SizedBox(width: 8),
                          ],
                        ],
                      )
                : Align(
                    key: const ValueKey('color-panel'),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final color in _colors) ...[
                          _ColorChip(
                            color: color,
                            selected: _penColor == color,
                            accent: accent,
                            onTap: () => _setPenColor(color),
                          ),
                          if (color != _colors.last) const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ),
              ),
            ],
          ),
        ),
      ),
    );
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
                              bottom: 178,
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
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _buildControlPanel(
                        context,
                        l10n: l10n,
                        cardBg: cardBg,
                        textColor: textColor,
                        subColor: subColor,
                        chipBg: chipBg,
                        accent: accent,
                        isDark: isDark,
                      ),
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
  final Color strokeColor;
  final VoidCallback onTap;

  const _StrokeChip({
    required this.width,
    required this.selected,
    required this.accent,
    required this.chipBg,
    required this.textColor,
    required this.strokeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sampleBg = selected
        ? accent.withValues(alpha: 0.12)
        : textColor.withValues(alpha: 0.08);
    final sampleBorder = selected
        ? accent.withValues(alpha: 0.22)
        : textColor.withValues(alpha: 0.08);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : chipBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? accent
                : Colors.transparent,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${width.toStringAsFixed(0)} px',
              style: TextStyle(
                color: selected ? accent : textColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 22,
              width: double.infinity,
              decoration: BoxDecoration(
                color: sampleBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sampleBorder,
                ),
              ),
              child: Center(
                child: Container(
                  height: width,
                  width: 28,
                  decoration: BoxDecoration(
                    color: strokeColor,
                    borderRadius: BorderRadius.circular(width / 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterTabChip extends StatelessWidget {
  final String title;
  final bool selected;
  final Color accent;
  final Color chipBg;
  final Color textColor;
  final VoidCallback onTap;

  const _FilterTabChip({
    required this.title,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : chipBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.tune_rounded : Icons.chevron_right_rounded,
              size: 16,
              color: selected ? accent : textColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? accent : textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  final Color color;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ColorChip({
    required this.color,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? accent.withValues(alpha: 0.16) : Colors.transparent,
          border: Border.all(
            color: selected ? accent : Colors.white.withValues(alpha: 0.10),
            width: selected ? 2 : 1,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: selected
              ? const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 16,
                )
              : null,
        ),
      ),
    );
  }
}
