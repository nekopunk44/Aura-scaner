import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'camera_features.dart';

enum CaptureStatusOverlayKind {
  passport,
  idCard,
  document,
  batchDocument,
  restorePhoto,
  removeSpots,
  removeWatermark,
  eco,
}

class _StatusOverlayLayout {
  const _StatusOverlayLayout({
    required this.alignment,
    required this.padding,
    required this.maxWidth,
    required this.icon,
  });

  final Alignment alignment;
  final EdgeInsets padding;
  final double maxWidth;
  final IconData icon;
}

/// Контроллер режимов съёмки документов.
///
/// Управляет двумя режимами:
/// - **Автоматически** — ждёт 3 секунды после обнаружения документа, затем
///   разрешает съёмку. Показывает анимацию рамки при детекции.
/// - **Вручную** — съёмка доступна в любой момент без ожидания.
///
/// Используется во всех модулях камеры: документы, паспорт, ID-карта.
class CaptureModeController {
  String captureMode = 'Вручную';
  bool isDocumentDetected = false;
  bool isScanning = false;
  String? detectionWarning;
  Timer? detectionTimer;

  void resetDetectionState() {
    detectionTimer?.cancel();
    detectionTimer = null;
    isDocumentDetected = false;
    detectionWarning = null;
  }

  void startDetectionStream({
    required bool isDocumentMode,
    required Function(bool detected) onDetectionChanged,
    required AnimationController animationController,
  }) {
    resetDetectionState();
    onDetectionChanged(false);
    animationController.reverse(from: animationController.value);

    // Пока реального подтверждения нет, держим состояние сброшенным.
    // Live-анализ кадра выставит true только при вероятном документе.
    if (captureMode == 'Автоматически' && isDocumentMode) {
      isDocumentDetected = false;
      onDetectionChanged(false);
    }
  }

  bool canTakePicture({required bool isDocumentMode}) {
    if (isScanning) return false;

    // В документных режимах пользователь снимает только вручную.
    // Авто-режим работает как режим наведения/распознавания рамки.
    if (isDocumentMode) {
      return captureMode == 'Вручную';
    }

    return true;
  }

  void setCaptureMode(String mode) {
    captureMode = mode;
    if (mode == 'Вручную') {
      resetDetectionState();
    }
  }

  String _compactFeatureLabel(String featureName) {
    switch (featureName) {
      case Feat.idCard:
        return 'ID-карта';
      case 'Неограниченный документ':
      case 'Пакетный Документ':
      case '+100 страниц':
      case Feat.plus10Pages:
        return Feat.document;
      default:
        return featureName;
    }
  }

  String _compactPageLabel(String pageMode) {
    switch (pageMode) {
      case 'Лицевая':
        return 'Лицевая сторона';
      case 'Обратная':
        return 'Обратная сторона';
      case '1 страница':
        return 'Одна страница';
      case '2 страницы':
        return 'Две страницы';
      default:
        return pageMode;
    }
  }

  _StatusOverlayLayout _overlayLayoutFor(CaptureStatusOverlayKind kind) {
    switch (kind) {
      case CaptureStatusOverlayKind.passport:
        return const _StatusOverlayLayout(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(24, 78, 24, 0),
          maxWidth: 272,
          icon: Icons.book_outlined,
        );
      case CaptureStatusOverlayKind.idCard:
        return const _StatusOverlayLayout(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(24, 78, 24, 0),
          maxWidth: 246,
          icon: Icons.badge_outlined,
        );
      // Документ и пакетный документ: оверлей теперь Positioned.fill
      // (отсчёт от верха экрана). Карточка между верхней панелью
      // (заканчивается ~100px) и верхом рамки (~0.21 H) — по центру.
      case CaptureStatusOverlayKind.document:
        return const _StatusOverlayLayout(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(24, 64, 24, 0),
          maxWidth: 248,
          icon: Icons.description_outlined,
        );
      case CaptureStatusOverlayKind.batchDocument:
        return const _StatusOverlayLayout(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(24, 64, 24, 0),
          maxWidth: 252,
          icon: Icons.layers_outlined,
        );
      case CaptureStatusOverlayKind.restorePhoto:
        return const _StatusOverlayLayout(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(24, 78, 24, 0),
          maxWidth: 272,
          icon: Icons.auto_fix_high_outlined,
        );
      case CaptureStatusOverlayKind.removeSpots:
        return const _StatusOverlayLayout(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(24, 78, 24, 0),
          maxWidth: 272,
          icon: Icons.cleaning_services_outlined,
        );
      case CaptureStatusOverlayKind.removeWatermark:
        return const _StatusOverlayLayout(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(24, 78, 24, 0),
          maxWidth: 272,
          icon: Icons.auto_fix_off_outlined,
        );
      case CaptureStatusOverlayKind.eco:
        return const _StatusOverlayLayout(
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(24, 78, 24, 0),
          maxWidth: 272,
          icon: Icons.eco_outlined,
        );
    }
  }

  String _overlayTitleFor(CaptureStatusOverlayKind kind, String featureName) {
    switch (kind) {
      case CaptureStatusOverlayKind.passport:
        return Feat.passport;
      case CaptureStatusOverlayKind.idCard:
        return 'ID-карта';
      case CaptureStatusOverlayKind.document:
      case CaptureStatusOverlayKind.batchDocument:
        return _compactFeatureLabel(featureName);
      case CaptureStatusOverlayKind.restorePhoto:
        return 'Восстановить';
      case CaptureStatusOverlayKind.removeSpots:
        return Feat.removeSpots;
      case CaptureStatusOverlayKind.removeWatermark:
        return 'Без водзнака';
      case CaptureStatusOverlayKind.eco:
        return 'Эко-сканер';
    }
  }

  Widget buildStatusOverlay({
    required bool isDocumentMode,
    required String pageMode,
    required String featureName,
    required CaptureStatusOverlayKind overlayKind,
    AppLocalizations? l10n,
  }) {
    // Карточка показывается и в авто-, и в ручном режиме: пользователь
    // всегда видит режим и номер страницы (раньше в ручном её не было).
    final visible = isDocumentMode;
    final layout = _overlayLayoutFor(overlayKind);

    late final String title;
    late final String subtitle;
    late final Color accentColor;

    if (isScanning) {
      title = l10n?.camProcessing ?? 'Обработка...';
      subtitle = 'Не двигайте устройство';
      accentColor = Colors.amber;
    } else if (detectionWarning != null) {
      title = _overlayTitleFor(overlayKind, featureName);
      subtitle = detectionWarning!;
      accentColor = const Color(0xFFFF8A3D);
    } else if (isDocumentDetected) {
      title = _overlayTitleFor(overlayKind, featureName);
      subtitle = 'Контур найден';
      accentColor = const Color(0xFF4CAF50);
    } else {
      title = _overlayTitleFor(overlayKind, featureName);
      subtitle = _compactPageLabel(pageMode);
      accentColor = const Color(0xFF2CA5E0);
    }

    final overlayCard = ClipRRect(
      key: ValueKey('overlay-$title-$subtitle'),
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        // Sigma умеренная: blur считается на каждом кадре превью камеры.
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          constraints: BoxConstraints(maxWidth: layout.maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.22),
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.08),
              ],
              stops: const [0, 0.35, 1],
            ),
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.32),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withValues(alpha: 0.16),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.16),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      layout.icon,
                      color: Colors.white.withValues(alpha: 0.95),
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.98),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: layout.alignment,
          child: Padding(
            padding: layout.padding,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              reverseDuration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide =
                    Tween<Offset>(
                      begin: const Offset(0, -0.08),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );

                return SlideTransition(
                  position: slide,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: visible
                  ? _AutoHideCard(
                      key: const ValueKey('overlay-card'),
                      signature: '$title|$subtitle',
                      pinned: isScanning || detectionWarning != null,
                      child: overlayCard,
                    )
                  : const SizedBox.shrink(key: ValueKey('overlay-hidden')),
            ),
          ),
        ),
      ),
    );
  }
}

/// Автоскрытие статус-карточки: появляется при смене содержимого (режим,
/// номер страницы, «Контур найден») и через пару секунд плавно уезжает
/// вверх, освобождая место рамке. Во время сканирования и при
/// предупреждениях остаётся видимой.
class _AutoHideCard extends StatefulWidget {
  const _AutoHideCard({
    super.key,
    required this.signature,
    required this.pinned,
    required this.child,
  });

  final String signature;
  final bool pinned;
  final Widget child;

  @override
  State<_AutoHideCard> createState() => _AutoHideCardState();
}

class _AutoHideCardState extends State<_AutoHideCard> {
  Timer? _timer;
  bool _shown = true;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_AutoHideCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature ||
        oldWidget.pinned != widget.pinned) {
      if (!_shown) setState(() => _shown = true);
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    if (widget.pinned) return;
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.pinned || _shown;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -0.3),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 380),
        child: widget.child,
      ),
    );
  }
}
