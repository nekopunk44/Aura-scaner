import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'document_camera_edit.dart';

class MultiPageDocumentPreviewScreen extends StatefulWidget {
  final List<XFile> imageFiles;
  final void Function(List<String> editedPaths)? onSaveBatch;
  final VoidCallback? onRetakeAll;

  const MultiPageDocumentPreviewScreen({
    super.key,
    required this.imageFiles,
    this.onSaveBatch,
    this.onRetakeAll,
  });

  @override
  State<MultiPageDocumentPreviewScreen> createState() =>
      _MultiPageDocumentPreviewScreenState();
}

class _MultiPageDocumentPreviewScreenState
    extends State<MultiPageDocumentPreviewScreen> {
  late final PageController _pageController = PageController(
    viewportFraction: 0.88,
  );
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentCameraEditScreen(
          imageFiles: widget.imageFiles,
          onSave: (editedPaths) {
            Navigator.popUntil(context, (route) => route.isFirst);
            widget.onSaveBatch?.call(editedPaths);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final files = widget.imageFiles;
    final hasMultiplePages = files.length > 1;

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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    _CloseButton(onTap: () => Navigator.pop(context)),
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
                          if (hasMultiplePages)
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
                    const SizedBox(width: 42),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: files.length,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemBuilder: (context, index) {
                    final isActive = index == _currentPage;
                    return AnimatedScale(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      scale: isActive ? 1 : 0.94,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 16,
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF13253A),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(19),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ImageFiltered(
                                        imageFilter: ui.ImageFilter.blur(
                                          sigmaX: 18,
                                          sigmaY: 18,
                                        ),
                                        child: Image.file(
                                          File(files[index].path),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      ColoredBox(
                                        color: Colors.black.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                      Image.file(
                                        File(files[index].path),
                                        fit: BoxFit.contain,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 12,
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
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
              if (hasMultiplePages)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < files.length; index++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: index == _currentPage ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: index == _currentPage
                                ? const Color(0xFF2CA5E0)
                                : Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: SizedBox(
                  width: double.infinity,
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
                          color: const Color(
                            0xFF26C060,
                          ).withValues(alpha: 0.38),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _openEditor,
                      icon: const Icon(Icons.edit_rounded, size: 20),
                      label: Text(
                        l10n.actionEdit,
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
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: const SizedBox(
        width: 42,
        height: 42,
        child: Icon(Icons.close_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}
