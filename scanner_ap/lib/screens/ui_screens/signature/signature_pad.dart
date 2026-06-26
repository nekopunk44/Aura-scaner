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
  static const Color _accent = Color(0xFF2CA5E0);
  static const Color _doneColor = Color(0xFF34A853);

  static const List<Color> _colors = [
    Color(0xFF101820),
    _accent,
    _doneColor,
    Color(0xFFE67E22),
    Color(0xFFE74C3C),
  ];

  double _strokeWidth = 3;
  Color _penColor = const Color(0xFF101820);
  _SignatureControlPanel? _activePanel = _SignatureControlPanel.width;

  late SignatureController _controller = _makeController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sigHint),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2200),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 214),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    });
  }

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

  String _widthToolLabel(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Толщина'
        : 'Width';
  }

  Widget _buildControlPanel(
    BuildContext context, {
    required AppLocalizations l10n,
    required Color accent,
    required Color subColor,
    required bool isDark,
    required bool canUndo,
  }) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: ColoredBox(
          color: const Color(
            0xFF101820,
          ).withValues(alpha: isDark ? 0.78 : 0.74),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.bottomCenter,
                child: _activePanel == null
                    ? const SizedBox.shrink(key: ValueKey('closed'))
                    : _buildActivePanel(
                        context,
                        key: const ValueKey('open-panel'),
                        accent: accent,
                        isDark: isDark,
                      ),
              ),
              _buildToolBar(
                l10n: l10n,
                accent: accent,
                subColor: subColor,
                canUndo: canUndo,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivePanel(
    BuildContext context, {
    required Key key,
    required Color accent,
    required bool isDark,
  }) {
    final overlayColor = isDark
        ? const Color(0xFF0F1923).withValues(alpha: 0.72)
        : const Color(0xFF101820).withValues(alpha: 0.78);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.08);

    return ClipRect(
      key: key,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: overlayColor,
            border: Border(
              top: BorderSide(color: borderColor),
              bottom: BorderSide(color: borderColor),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: _activePanel == _SignatureControlPanel.width
                ? _buildWidthPanel(key: const ValueKey('width'), accent: accent)
                : _buildColorPanel(
                    key: const ValueKey('color'),
                    accent: accent,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildWidthPanel({required Key key, required Color accent}) {
    final value = _strokeWidth.clamp(1.0, 10.0).toDouble();
    return Row(
      key: key,
      children: [
        Container(
          width: 52,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDDE6EF)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 26,
              height: value,
              decoration: BoxDecoration(
                color: _penColor,
                borderRadius: BorderRadius.circular(value / 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 9,
                elevation: 0,
                pressedElevation: 1,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              trackShape: const RoundedRectSliderTrackShape(),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value,
              min: 1,
              max: 10,
              label: '${value.toStringAsFixed(1)} px',
              onChanged: _setStrokeWidth,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorPanel({required Key key, required Color accent}) {
    return Center(
      key: key,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
              if (color != _colors.last) const SizedBox(width: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolBar({
    required AppLocalizations l10n,
    required Color accent,
    required Color subColor,
    required bool canUndo,
  }) {
    final isCompact = MediaQuery.of(context).size.width < 360;
    final tileWidth = isCompact ? 76.0 : 86.0;
    final iconSize = isCompact ? 19.0 : 21.0;
    final fontSize = isCompact ? 10.0 : 11.0;
    final widthLabel = _widthToolLabel(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: const Color(0xFF101820).withValues(alpha: 0.72),
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
          child: SizedBox(
            height: isCompact ? 92 : 98,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth - 20,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        SizedBox(
                          width: tileWidth,
                          child: _toolButton(
                            icon: Icons.refresh_rounded,
                            label: l10n.clearSelection,
                            active: canUndo,
                            enabled: canUndo,
                            accent: accent,
                            activeColor: const Color(0xFFE74C3C),
                            disabledColor: subColor,
                            tileWidth: tileWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            isCompact: isCompact,
                            onTap: _controller.clear,
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _toolButton(
                            icon: Icons.line_weight_rounded,
                            label: widthLabel,
                            active:
                                _activePanel == _SignatureControlPanel.width,
                            accent: accent,
                            tileWidth: tileWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            isCompact: isCompact,
                            onTap: () =>
                                _togglePanel(_SignatureControlPanel.width),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _toolButton(
                            icon: Icons.palette_outlined,
                            label: l10n.geoStampColor,
                            active:
                                _activePanel == _SignatureControlPanel.color,
                            accent: accent,
                            tileWidth: tileWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            isCompact: isCompact,
                            onTap: () =>
                                _togglePanel(_SignatureControlPanel.color),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _toolButton(
                            icon: Icons.check_rounded,
                            label: l10n.actionDone,
                            active: canUndo,
                            enabled: canUndo,
                            accent: accent,
                            activeColor: _doneColor,
                            disabledColor: subColor,
                            tileWidth: tileWidth,
                            iconSize: iconSize,
                            fontSize: fontSize,
                            isCompact: isCompact,
                            onTap: () async {
                              final navigator = Navigator.of(context);
                              final bytes = await _export();
                              if (bytes == null) return;
                              if (!mounted) return;
                              navigator.pop(bytes);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _togglePanel(_SignatureControlPanel panel) {
    setState(() {
      _activePanel = _activePanel == panel ? null : panel;
    });
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required bool active,
    required Color accent,
    Color? activeColor,
    Color? disabledColor,
    bool enabled = true,
    required double tileWidth,
    required double iconSize,
    required double fontSize,
    required bool isCompact,
    required VoidCallback onTap,
  }) {
    final selectedColor = activeColor ?? accent;
    final mutedColor = disabledColor ?? Colors.white54;
    final effectiveActive = enabled && active;
    final contentColor = enabled
        ? effectiveActive
              ? Colors.white
              : Colors.white.withValues(alpha: 0.7)
        : mutedColor.withValues(alpha: 0.55);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: tileWidth,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 3 : 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: isCompact ? 40 : 46,
                height: isCompact ? 40 : 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled
                      ? effectiveActive
                            ? selectedColor
                            : Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.08),
                  boxShadow: effectiveActive
                      ? [
                          BoxShadow(
                            color: selectedColor.withValues(alpha: 0.50),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: contentColor),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) {
                    return Icon(
                      icon,
                      color: color ?? contentColor,
                      size: iconSize,
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1.15,
                      color: contentColor,
                      fontWeight: effectiveActive
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      softWrap: false,
                    ),
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
    final scaffoldBg = isDark
        ? const Color(0xFF0B1420)
        : const Color(0xFFF5F8FC);
    final appBarBg = isDark ? const Color(0xFF101A29) : const Color(0xFFF5F8FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    const accent = _accent;

    final canUndo = _controller.points.isNotEmpty;

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
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Stack(
                children: [
                  Positioned.fill(
                    top: 10,
                    left: 6,
                    right: 6,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF132133).withValues(alpha: 0.34)
                            : const Color(0xFFE6EEF7).withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFEFA),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFE4ECF5),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.24 : 0.06,
                          ),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: const _PaperGuidePainter(
                                  lineColor: Color(0xFFF0F4FA),
                                ),
                              ),
                            ),
                          ),
                          Signature(
                            controller: _controller,
                            backgroundColor: Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildControlPanel(
            context,
            l10n: l10n,
            accent: accent,
            subColor: subColor,
            isDark: isDark,
            canUndo: canUndo,
          ),
        ],
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

    const topInset = 62.0;
    const step = 48.0;
    for (double y = topInset; y < size.height - 56; y += step) {
      canvas.drawLine(Offset(28, y), Offset(size.width - 28, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGuidePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
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
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF101820);

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
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: selected
              ? Icon(Icons.check_rounded, color: checkColor, size: 16)
              : null,
        ),
      ),
    );
  }
}
