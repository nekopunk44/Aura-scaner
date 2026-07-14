// id_card_photo_edit.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math' as math;

import 'save_options_id_card.dart';
import '../../../l10n/app_localizations.dart';

class EditState {
  XFile originalFile;
  String currentPath;
  double brightness;
  double contrast;
  int rotation; // 0, 90, 180, 270 градусов
  bool isGrayscale;

  EditState({
    required this.originalFile,
    required this.currentPath,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.rotation = 0,
    this.isGrayscale = false,
  });

  // копии состояния
  EditState copyWith({
    XFile? originalFile,
    String? currentPath,
    double? brightness,
    double? contrast,
    int? rotation,
    bool? isGrayscale,
  }) {
    return EditState(
      originalFile: originalFile ?? this.originalFile,
      currentPath: currentPath ?? this.currentPath,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      rotation: rotation ?? this.rotation,
      isGrayscale: isGrayscale ?? this.isGrayscale,
    );
  }
}

// --- ОСНОВНОЙ КЛАСС РЕДАКТОРА ---
class IdCardPhotoEditScreen extends StatefulWidget {
  final XFile frontImage;
  final XFile backImage;
  final Function(List<String> editedPaths) onSave;

  const IdCardPhotoEditScreen({
    super.key,
    required this.frontImage,
    required this.backImage,
    required this.onSave,
  });

  @override
  State<IdCardPhotoEditScreen> createState() => _IdCardPhotoEditScreenState();
}

class _IdCardPhotoEditScreenState extends State<IdCardPhotoEditScreen> {
  late EditState _frontState;
  late EditState _backState;

  late EditState _currentState;

  bool _isEditingFront = true;

  // Какая настройка-ползунок раскрыта сверху панели: 'brightness' / 'contrast'
  // / null. Кнопки Яркость и Контраст переключают её, а сам ползунок
  // появляется над рядом инструментов.
  String? _activeAdjust;

  // Режим встроенной обрезки: рамка прямо поверх превью (без внешнего экрана).
  bool _isCropping = false;
  Size? _cropImageSize; // натуральные пиксели изображения для обрезки

  @override
  void initState() {
    super.initState();
    _frontState = EditState(
      originalFile: widget.frontImage,
      currentPath: widget.frontImage.path,
    );
    _backState = EditState(
      originalFile: widget.backImage,
      currentPath: widget.backImage.path,
    );
    _currentState = _frontState;
  }

  // --- ЛОГИКА ПЕРЕКЛЮЧЕНИЯ ---
  void _toggleSide(bool isFront) {
    if (isFront == _isEditingFront) return;
    if (_isEditingFront) {
      _frontState = _currentState;
    } else {
      _backState = _currentState;
    }

    setState(() {
      _isEditingFront = isFront;
      _currentState = isFront ? _frontState : _backState;
    });
  }

  void _applyFilter() {
    setState(() {
      _currentState = _currentState.copyWith(
        isGrayscale: !_currentState.isGrayscale,
      );
    });
  }

  void _rotateImage() {
    setState(() {
      final newRotation = (_currentState.rotation + 90) % 360;
      _currentState = _currentState.copyWith(rotation: newRotation);
    });
  }

  /// Запекает текущий поворот в файл, чтобы кроппер показывал то же, что и
  /// превью (иначе обрезался бы неповёрнутый кадр, а поворот терялся).
  Future<String> _bakeRotation(String path, int rotation) async {
    if (rotation == 0) return path;
    try {
      final bytes = await File(path).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return path;
      image = img.copyRotate(image, angle: rotation);
      final tempDir = await getTemporaryDirectory();
      final out =
          '${tempDir.path}/idrot_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(out).writeAsBytes(img.encodeJpg(image, quality: 95));
      return out;
    } catch (_) {
      return path;
    }
  }

  /// Узнаёт натуральные размеры изображения (без вынесения на отдельный экран).
  Future<Size?> _imageSizeOf(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      return Size(image.width.toDouble(), image.height.toDouble());
    } catch (_) {
      return null;
    }
  }

  /// Включает встроенную обрезку: запекает текущий поворот в файл и показывает
  /// рамку прямо поверх превью (без перехода на внешний экран UCrop).
  Future<void> _startCrop() async {
    final baked = await _bakeRotation(
      _currentState.currentPath,
      _currentState.rotation,
    );
    final size = await _imageSizeOf(baked);
    if (!mounted || size == null) return;
    setState(() {
      _currentState = _currentState.copyWith(currentPath: baked, rotation: 0);
      _cropImageSize = size;
      _activeAdjust = null;
      _isCropping = true;
    });
  }

  void _cancelCrop() {
    setState(() {
      _isCropping = false;
      _cropImageSize = null;
    });
  }

  /// Применяет рамку обрезки (нормализованный прямоугольник 0..1) к файлу.
  Future<void> _applyCrop(Rect norm) async {
    final path = _currentState.currentPath;
    try {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        if (mounted) _cancelCrop();
        return;
      }
      final int w = image.width, h = image.height;
      final int x = (norm.left * w).round().clamp(0, w - 1);
      final int y = (norm.top * h).round().clamp(0, h - 1);
      final int cw = (norm.width * w).round().clamp(1, w - x);
      final int ch = (norm.height * h).round().clamp(1, h - y);
      final cropped = img.copyCrop(image, x: x, y: y, width: cw, height: ch);
      final tempDir = await getTemporaryDirectory();
      final out =
          '${tempDir.path}/idcrop_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(out).writeAsBytes(img.encodeJpg(cropped, quality: 95));
      if (!mounted) return;
      setState(() {
        _currentState = _currentState.copyWith(currentPath: out);
        _isCropping = false;
        _cropImageSize = null;
      });
    } catch (_) {
      if (mounted) _cancelCrop();
    }
  }

  void _autoEnhance() {
    setState(() {
      _currentState = _currentState.copyWith(brightness: 0.1, contrast: 0.2);
    });
  }

  void _updateBrightness(double value) {
    setState(() {
      _currentState = _currentState.copyWith(brightness: value);
    });
  }

  void _updateContrast(double value) {
    setState(() {
      _currentState = _currentState.copyWith(contrast: value);
    });
  }

  /// Раскрывает/сворачивает ползунок выбранной настройки над инструментами.
  void _selectAdjust(String which) {
    setState(() {
      _activeAdjust = _activeAdjust == which ? null : which;
    });
  }

  // --- ФУНКЦИЯ СОХРАНЕНИЯ И ПЕРЕХОДА ---
  Future<String> _prepareEditedImage(EditState state, String name) async {
    final bytes = await File(state.currentPath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return state.currentPath;

    if (state.rotation == 90 ||
        state.rotation == 180 ||
        state.rotation == 270) {
      image = img.copyRotate(image, angle: state.rotation);
    }
    if (state.isGrayscale) {
      image = img.grayscale(image);
    }
    // Та же формула, что в превью (_getColorFilter) — «что вижу, то и
    // сохранится». contrast вокруг 127.5, brightness — аддитивный сдвиг.
    if (state.brightness != 0.0 || state.contrast != 0.0) {
      final double c = 1.0 + state.contrast;
      final double off = -127.5 * state.contrast + 255.0 * state.brightness;
      for (final p in image) {
        p
          ..r = (p.r * c + off).clamp(0, 255)
          ..g = (p.g * c + off).clamp(0, 255)
          ..b = (p.b * c + off).clamp(0, 255);
      }
    }

    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/id_card_${name}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(outputPath).writeAsBytes(img.encodeJpg(image, quality: 95));
    return outputPath;
  }

  Future<void> _saveAndNavigate() async {
    if (_isEditingFront) {
      _frontState = _currentState;
    } else {
      _backState = _currentState;
    }

    final List<String> finalPaths = [
      await _prepareEditedImage(_frontState, 'front'),
      await _prepareEditedImage(_backState, 'back'),
    ];

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaveOptionsIdCardScreen(sourceFilePaths: finalPaths),
      ),
    );
  }

  ColorFilter _getColorFilter() {
    // Та же формула, что и при сохранении (_applyBrightnessContrast):
    // контраст вокруг середины 127.5, яркость — аддитивный сдвиг. Яркость/
    // контраст применяются и поверх Ч-Б (раньше Ч-Б их «съедал» в превью).
    final double c = 1.0 + _currentState.contrast;
    final double off =
        -127.5 * _currentState.contrast + 255.0 * _currentState.brightness;

    if (_currentState.isGrayscale) {
      final double lr = 0.2126 * c, lg = 0.7152 * c, lb = 0.0722 * c;
      return ColorFilter.matrix([
        lr,
        lg,
        lb,
        0,
        off,
        lr,
        lg,
        lb,
        0,
        off,
        lr,
        lg,
        lb,
        0,
        off,
        0,
        0,
        0,
        1,
        0,
      ]);
    }

    return ColorFilter.matrix([
      c,
      0,
      0,
      0,
      off,
      0,
      c,
      0,
      0,
      off,
      0,
      0,
      c,
      0,
      off,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  Widget _buildEditableImagePreview() {
    const double idCardAspectRatio = 1.6;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: AspectRatio(
        aspectRatio: idCardAspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: Transform.rotate(
            angle: _currentState.rotation * (3.1415926535 / 180),
            child: ColorFiltered(
              colorFilter: _getColorFilter(),
              child: Image.file(
                File(_currentState.currentPath),
                // contain — повёрнутый на 90° кадр виден целиком, не режется.
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        title: Text(l10n.editIdCardTitle),
        backgroundColor: const Color(0xFF141E2B),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.reset,
            onPressed: () {
              setState(() {
                if (_isEditingFront) {
                  _frontState = EditState(
                    originalFile: widget.frontImage,
                    currentPath: widget.frontImage.path,
                  );
                  _currentState = _frontState;
                } else {
                  _backState = EditState(
                    originalFile: widget.backImage,
                    currentPath: widget.backImage.path,
                  );
                  _currentState = _backState;
                }
              });
            },
          ),
        ],
      ),
      body: _isCropping
          ? _buildCropMode(l10n)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SideButton(
                        label: l10n.frontSide,
                        isSelected: _isEditingFront,
                        onPressed: () => _toggleSide(true),
                      ),
                      const SizedBox(width: 8),
                      _SideButton(
                        label: l10n.backSide,
                        isSelected: !_isEditingFront,
                        onPressed: () => _toggleSide(false),
                      ),
                    ],
                  ),
                ),

                Expanded(child: Center(child: _buildEditableImagePreview())),

                // Панель управления: инструменты + слайдеры + сохранение в одном
                // сгруппированном блоке (раньше иконки висели голыми на фоне).
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF141E2B),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    18,
                    16,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ползунок выбранной настройки — появляется над инструментами
                      // только когда выбрана Яркость или Контраст.
                      _buildActiveControl(l10n),
                      _buildToolRow(l10n),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _saveAndNavigate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            l10n.editIdCardSaveBothSides,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // Вспомогательные виджеты

  // Все 6 инструментов в один ряд. Каждый занимает равную долю (Expanded),
  // подпись ужимается под ширину ячейки (FittedBox), чтобы ничего не
  // переносилось и не обрезалось.
  Widget _buildToolRow(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _ToolIcon(
            icon: Icons.rotate_right,
            label: l10n.toolRotate,
            onTap: _rotateImage,
          ),
        ),
        Expanded(
          child: _ToolIcon(
            icon: Icons.wb_sunny,
            label: l10n.colorBrightness,
            isActive: _activeAdjust == 'brightness',
            onTap: () => _selectAdjust('brightness'),
          ),
        ),
        Expanded(
          child: _ToolIcon(
            icon: Icons.contrast,
            label: l10n.colorContrast,
            isActive: _activeAdjust == 'contrast',
            onTap: () => _selectAdjust('contrast'),
          ),
        ),
        Expanded(
          child: _ToolIcon(
            icon: Icons.filter_b_and_w,
            label: l10n.editToolBW,
            isActive: _currentState.isGrayscale,
            onTap: _applyFilter,
          ),
        ),
        Expanded(
          child: _ToolIcon(
            icon: Icons.crop,
            label: l10n.editToolCrop,
            onTap: _startCrop,
          ),
        ),
        Expanded(
          child: _ToolIcon(
            icon: Icons.auto_fix_high,
            label: l10n.editToolEnhance,
            onTap: _autoEnhance,
          ),
        ),
      ],
    );
  }

  /// Ползунок выбранной настройки над рядом инструментов. Пока ничего не
  /// выбрано — место не занимает (ряд инструментов прижат к картинке).
  Widget _buildActiveControl(AppLocalizations l10n) {
    Widget child;
    if (_activeAdjust == 'brightness') {
      child = _AdjustmentSlider(
        key: const ValueKey('brightness'),
        icon: Icons.wb_sunny,
        label: l10n.colorBrightness,
        value: _currentState.brightness,
        onChanged: _updateBrightness,
      );
    } else if (_activeAdjust == 'contrast') {
      child = _AdjustmentSlider(
        key: const ValueKey('contrast'),
        icon: Icons.contrast,
        label: l10n.colorContrast,
        value: _currentState.contrast,
        onChanged: _updateContrast,
      );
    } else {
      child = const SizedBox.shrink();
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: _activeAdjust == null ? 0 : 10),
        child: child,
      ),
    );
  }

  /// Режим обрезки: рамка прямо поверх превью + кнопки Отмена/Применить.
  /// Заменяет обычное тело редактора, оставаясь на том же экране.
  Widget _buildCropMode(AppLocalizations l10n) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _InlineCropper(
              imagePath: _currentState.currentPath,
              imageSize: _cropImageSize!,
              onCancel: _cancelCrop,
              onConfirm: _applyCrop,
            ),
          ),
        ),
      ],
    );
  }
}

// --- ВИДЖЕТЫ КОМПОНЕНТОВ ---

class _SideButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  const _SideButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? const Color(0xFF2CA5E0)
            : const Color(0xFF1E2A3A),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _ToolIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2CA5E0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isActive
                    ? accent.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.07),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive
                      ? accent
                      : Colors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: isActive ? accent : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            // FittedBox ужимает длинные подписи под ширину ячейки —
            // ни переноса, ни обрезки.
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: isActive ? accent : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
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

class _AdjustmentSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _AdjustmentSlider({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 22),
        const SizedBox(width: 10),
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: -1.0,
            max: 1.0,
            divisions: 20,
            onChanged: onChanged,
            activeColor: const Color(0xFF2CA5E0),
            inactiveColor: Colors.white24,
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            // Значение в процентах вместо дублирующей подписи.
            '${value >= 0 ? '+' : ''}${(value * 100).round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// Встроенная обрезка: интерактивная рамка прямо поверх изображения (без
/// перехода на внешний экран). Возвращает результат как нормализованный
/// прямоугольник 0..1 относительно изображения через [onConfirm].
class _InlineCropper extends StatefulWidget {
  final String imagePath;
  final Size imageSize; // натуральные пиксели
  final VoidCallback onCancel;
  final ValueChanged<Rect> onConfirm;

  const _InlineCropper({
    required this.imagePath,
    required this.imageSize,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<_InlineCropper> createState() => _InlineCropperState();
}

class _InlineCropperState extends State<_InlineCropper> {
  // Рамка в нормализованных координатах изображения (0..1). Не зависит от
  // размеров области — пересчёт при layout тривиален.
  Rect _norm = const Rect.fromLTRB(0, 0, 1, 1);

  // Зона захвата угла (для пальца) и минимальный размер рамки в долях.
  static const double _handle = 32;
  static const double _minNorm = 0.1;

  /// Прямоугольник, в который BoxFit.contain вписывает изображение в [box].
  Rect _displayRect(Size box) {
    final double iw = widget.imageSize.width;
    final double ih = widget.imageSize.height;
    final double scale = math.min(box.width / iw, box.height / ih);
    final double w = iw * scale;
    final double h = ih * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  void _dragCorner(int corner, Offset delta, Rect disp) {
    setState(() {
      final double dx = delta.dx / disp.width;
      final double dy = delta.dy / disp.height;
      double l = _norm.left, t = _norm.top, r = _norm.right, b = _norm.bottom;
      switch (corner) {
        case 0: // верх-лево
          l += dx;
          t += dy;
          break;
        case 1: // верх-право
          r += dx;
          t += dy;
          break;
        case 2: // низ-право
          r += dx;
          b += dy;
          break;
        case 3: // низ-лево
          l += dx;
          b += dy;
          break;
      }
      l = l.clamp(0.0, r - _minNorm);
      t = t.clamp(0.0, b - _minNorm);
      r = r.clamp(l + _minNorm, 1.0);
      b = b.clamp(t + _minNorm, 1.0);
      _norm = Rect.fromLTRB(l, t, r, b);
    });
  }

  void _dragBody(Offset delta, Rect disp) {
    setState(() {
      double dx = delta.dx / disp.width;
      double dy = delta.dy / disp.height;
      dx = dx.clamp(-_norm.left, 1 - _norm.right);
      dy = dy.clamp(-_norm.top, 1 - _norm.bottom);
      _norm = _norm.shift(Offset(dx, dy));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final box = Size(c.maxWidth, c.maxHeight);
              final disp = _displayRect(box);
              final crop = Rect.fromLTRB(
                disp.left + _norm.left * disp.width,
                disp.top + _norm.top * disp.height,
                disp.left + _norm.right * disp.width,
                disp.top + _norm.bottom * disp.height,
              );
              return Stack(
                children: [
                  // Изображение в его реальном соотношении сторон.
                  Positioned.fromRect(
                    rect: disp,
                    child: Image.file(File(widget.imagePath), fit: BoxFit.fill),
                  ),
                  // Затемнение вне рамки + сама рамка/сетка/уголки.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _CropOverlayPainter(crop)),
                    ),
                  ),
                  // Перетаскивание всей рамки за середину.
                  Positioned.fromRect(
                    rect: crop,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) => _dragBody(d.delta, disp),
                    ),
                  ),
                  // 4 угла поверх (приоритет над перетаскиванием рамки).
                  ..._cornerHandles(crop, disp),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    l10n.actionCancel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => widget.onConfirm(_norm),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    l10n.wmApply,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _cornerHandles(Rect crop, Rect disp) {
    final corners = [
      crop.topLeft,
      crop.topRight,
      crop.bottomRight,
      crop.bottomLeft,
    ];
    return List.generate(4, (i) {
      final p = corners[i];
      return Positioned(
        left: p.dx - _handle / 2,
        top: p.dy - _handle / 2,
        width: _handle,
        height: _handle,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (d) => _dragCorner(i, d.delta, disp),
        ),
      );
    });
  }
}

/// Рисует затемнение вне рамки, белую рамку, сетку «правило третей» и
/// акцентные уголки.
class _CropOverlayPainter extends CustomPainter {
  final Rect crop;
  const _CropOverlayPainter(this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    // Затемнение всего, кроме «дырки» рамки.
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(crop),
    );
    canvas.drawPath(outside, dim);

    // Рамка.
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(crop, border);

    // Сетка (правило третей).
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    for (int i = 1; i < 3; i++) {
      final double gx = crop.left + crop.width * i / 3;
      final double gy = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(gx, crop.top), Offset(gx, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, gy), Offset(crop.right, gy), grid);
    }

    // Акцентные уголки.
    final corner = Paint()
      ..color = const Color(0xFF2CA5E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const double len = 18;
    canvas.drawLine(crop.topLeft, crop.topLeft + const Offset(len, 0), corner);
    canvas.drawLine(crop.topLeft, crop.topLeft + const Offset(0, len), corner);
    canvas.drawLine(
      crop.topRight,
      crop.topRight + const Offset(-len, 0),
      corner,
    );
    canvas.drawLine(
      crop.topRight,
      crop.topRight + const Offset(0, len),
      corner,
    );
    canvas.drawLine(
      crop.bottomRight,
      crop.bottomRight + const Offset(-len, 0),
      corner,
    );
    canvas.drawLine(
      crop.bottomRight,
      crop.bottomRight + const Offset(0, -len),
      corner,
    );
    canvas.drawLine(
      crop.bottomLeft,
      crop.bottomLeft + const Offset(len, 0),
      corner,
    );
    canvas.drawLine(
      crop.bottomLeft,
      crop.bottomLeft + const Offset(0, -len),
      corner,
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) => old.crop != crop;
}
