// PhotoPreviewScreen.dart
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'photo_edit_passport.dart';

/// Превью отсканированных страниц в фирменном стиле приложения:
/// тёмный градиентный фон, свайп-карточки страниц (PageView) с тенью,
/// точки-индикатор и стеклянные кнопки действий внизу.
class PhotoPreviewScreen extends StatefulWidget {
  final List<XFile> imageFiles;

  final void Function()? onConfirm;
  final void Function()? onRetake;

  const PhotoPreviewScreen({
    super.key,
    required this.imageFiles,
    this.onConfirm,
    this.onRetake,
  });

  @override
  State<PhotoPreviewScreen> createState() => _PhotoPreviewScreenState();
}

class _PhotoPreviewScreenState extends State<PhotoPreviewScreen> {
  late final PageController _pageCtrl =
      PageController(viewportFraction: 0.88);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _openEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoEditScreen(
          imageFiles: widget.imageFiles,
          onSave: (editedPaths) {
            Navigator.popUntil(context, (route) => route.isFirst);
            widget.onConfirm?.call();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final files = widget.imageFiles;
    final multi = files.length > 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1923), Color(0xFF13253A), Color(0xFF0D2137)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Шапка: закрыть + заголовок + счётчик страниц ────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    _GlassIconButton(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            l10n.previewTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (multi)
                            Text(
                              l10n.previewPagesCount(files.length),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Симметричный спейсер под ширину кнопки закрытия.
                    const SizedBox(width: 42),
                  ],
                ),
              ),

              // ── Карточки страниц ────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: files.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) {
                    final active = index == _currentPage;
                    return AnimatedScale(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      scale: active ? 1.0 : 0.94,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 16,
                        ),
                        child: Stack(
                          children: [
                            // Карточка со страницей.
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.14),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.45),
                                      blurRadius: 24,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(19),
                                  child: Image.file(
                                    File(files[index].path),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            // Чип с номером страницы.
                            Positioned(
                              left: 12,
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Text(
                                  l10n.pageLabel(index + 1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ── Точки-индикатор ─────────────────────────────────────────
              if (multi)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < files.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _currentPage ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _currentPage
                                ? const Color(0xFF2CA5E0)
                                : Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),

              // ── Действия ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: widget.onRetake,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: Text(l10n.actionRetry),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.30),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF35D07F), Color(0xFF1FA463)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF26C060)
                                    .withValues(alpha: 0.38),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _openEditor,
                            icon: const Icon(Icons.check_circle_rounded,
                                size: 20),
                            label: Text(
                              multi
                                  ? l10n.editCount(files.length)
                                  : l10n.passportUseButton,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Круглая «стеклянная» кнопка для шапки (закрыть).
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}
