import 'package:flutter/material.dart';

/// Брендовый логотип Aura Scanner — типографическая монограмма «AS»
/// на тонком слое glow. Реализован через Stack + Text widgets (а не
/// CustomPaint), чтобы Hero animation между splash и login была
/// плавной даже в debug-режиме: Flutter кеширует layout/paint текста,
/// и transition сводится к scale-интерполяции.
class AuraLogo extends StatelessWidget {
  final double size;
  final Color color;
  final Color highlight;

  const AuraLogo({
    super.key,
    this.size = 96,
    this.color = const Color(0xFF2CA5E0),
    this.highlight = const Color(0xFF8CDDFF),
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = size * 0.78;
    final offset = size * 0.18;

    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Radial glow за буквами — мягкий объём.
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withValues(alpha: 0.22),
                    color.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            // Буква S — справа, светлее.
            Transform.translate(
              offset: Offset(offset, 0),
              child: Text(
                'S',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  color: highlight,
                  height: 1.0,
                ),
              ),
            ),
            // Буква A — слева, с градиентом через ShaderMask.
            Transform.translate(
              offset: Offset(-offset, 0),
              child: ShaderMask(
                shaderCallback: (rect) => LinearGradient(
                  colors: [highlight, color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(rect),
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
              ),
            ),
            // Короткая линия-«подчёркивание» под монограммой.
            Positioned(
              bottom: size * 0.14,
              child: Container(
                width: size * 0.36,
                height: size * 0.025,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(size * 0.025 / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
