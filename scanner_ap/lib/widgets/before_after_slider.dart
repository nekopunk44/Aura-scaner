import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const _accent = Color(0xFF2CA5E0);
const _fogBg = Color(0xFF0F1923);

/// Сравнение «до/после» с перетаскиваемым вертикальным разделителем: слева —
/// оригинал (before), справа — результат (after). Слайдер занимает ровно
/// прямоугольник фото (по реальным пропорциям результата), линия/ручка — только
/// в его пределах.
class BeforeAfterSlider extends StatefulWidget {
  final File before;
  final File after;
  final String beforeLabel;
  final String afterLabel;

  const BeforeAfterSlider({
    super.key,
    required this.before,
    required this.after,
    required this.beforeLabel,
    required this.afterLabel,
  });

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _pos = 0.5; // положение разделителя 0..1
  double? _aspect; // реальное соотношение сторон фото (w/h)
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolveAspect();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  void _resolveAspect() {
    _stream = Image.file(widget.after).image.resolve(
          const ImageConfiguration(),
        );
    _listener = ImageStreamListener((info, _) {
      if (mounted && _aspect == null) {
        setState(() => _aspect = info.image.width / info.image.height);
      }
    }, onError: (_, __) {});
    _stream!.addListener(_listener!);
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspect;
    if (aspect == null) {
      return Center(child: Image.file(widget.after, fit: BoxFit.contain));
    }
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double w = constraints.maxWidth;
            final double dividerX = (_pos * w).clamp(0.0, w);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) {
                setState(() => _pos = (_pos + d.delta.dx / w).clamp(0.0, 1.0));
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(widget.after, fit: BoxFit.cover),
                    ClipRect(
                      clipper: _LeftClipper(dividerX),
                      child: Image.file(widget.before, fit: BoxFit.cover),
                    ),
                    Positioned(
                      left: dividerX - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.white),
                    ),
                    Positioned(
                      left: dividerX - 20,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.compare_arrows,
                              color: _fogBg, size: 22),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _label(widget.beforeLabel),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: _label(widget.afterLabel),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Обрезает виджет до левой части шириной [x] (для слоя «до»).
class _LeftClipper extends CustomClipper<Rect> {
  final double x;
  const _LeftClipper(this.x);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, x, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper oldClipper) => oldClipper.x != x;
}

/// «Туман» поверх фото на время обработки: размытие + затемнение, по центру
/// иконка, надпись, прогресс-полоса и проценты. Ставится как `Positioned.fill`
/// поверх изображения в Stack.
class ProcessingOverlay extends StatelessWidget {
  final double progress; // 0..1
  final String label;
  final IconData icon;

  const ProcessingOverlay({
    super.key,
    required this.progress,
    required this.label,
    this.icon = Icons.auto_fix_high,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: _fogBg.withValues(alpha: 0.45)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 42),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 240,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Полноэкранный осмотр результата с зумом/панорамой (pinch-to-zoom).
class ZoomView extends StatelessWidget {
  final File file;
  const ZoomView({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(child: Image.file(file, fit: BoxFit.contain)),
      ),
    );
  }
}
