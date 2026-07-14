import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'save_options_passport.dart';
import '../../../l10n/app_localizations.dart';

class PhotoEditScreen extends StatefulWidget {
  final List<XFile> imageFiles;
  final Function(List<String>)? onSave;

  const PhotoEditScreen({super.key, required this.imageFiles, this.onSave});

  @override
  State<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends State<PhotoEditScreen> {
  late List<String> _editedPaths;
  late List<double> _rotations;
  late List<double> _brightnessValues;
  late List<double> _contrastValues;
  late List<bool> _grayscaleValues;
  double _rotation = 0.0;
  double _brightness = 0.0;
  double _contrast = 1.0;
  bool _isGrayScale = false;
  int _currentPageIndex = 0;
  String? _activeAdjust;

  @override
  void initState() {
    super.initState();
    _editedPaths = widget.imageFiles.map((f) => f.path).toList();
    _rotations = List.filled(widget.imageFiles.length, 0.0);
    _brightnessValues = List.filled(widget.imageFiles.length, 0.0);
    _contrastValues = List.filled(widget.imageFiles.length, 1.0);
    _grayscaleValues = List.filled(widget.imageFiles.length, false);
    _resetFilters();
  }

  File _getCurrentFile() {
    return File(_editedPaths[_currentPageIndex]);
  }

  bool get _isMultiPageMode => widget.imageFiles.length > 1;

  void _rotateImage() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
      _rotations[_currentPageIndex] = _rotation;
    });
  }

  Future<void> _cropImage() async {
    final l10n = AppLocalizations.of(context);
    final cropped = await ImageCropper().cropImage(
      sourcePath: _editedPaths[_currentPageIndex],
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: l10n.editCropPhotoTitle,
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: l10n.editCropPhotoTitle),
      ],
    );

    if (cropped == null || !mounted) return;

    setState(() {
      _editedPaths[_currentPageIndex] = cropped.path;
      _rotation = 0.0;
      _rotations[_currentPageIndex] = 0.0;
    });
  }

  void _resetFilters() {
    setState(() {
      _activeAdjust = null;
      _rotation = 0.0;
      _brightness = 0.0;
      _contrast = 1.0;
      _isGrayScale = false;
      _rotations[_currentPageIndex] = _rotation;
      _brightnessValues[_currentPageIndex] = _brightness;
      _contrastValues[_currentPageIndex] = _contrast;
      _grayscaleValues[_currentPageIndex] = _isGrayScale;
    });
  }

  void _switchPage(int index) {
    if (index >= 0 &&
        index < widget.imageFiles.length &&
        index != _currentPageIndex) {
      setState(() {
        _currentPageIndex = index;
        _rotation = _rotations[index];
        _brightness = _brightnessValues[index];
        _contrast = _contrastValues[index];
        _isGrayScale = _grayscaleValues[index];
      });
    }
  }

  void _selectAdjust(String which) {
    setState(() => _activeAdjust = _activeAdjust == which ? null : which);
  }

  void _autoEnhance() {
    setState(() {
      _contrast = 1.2;
      _brightness = 0.1;
      _contrastValues[_currentPageIndex] = _contrast;
      _brightnessValues[_currentPageIndex] = _brightness;
    });
  }

  Future<String> _prepareEditedImage(int index) async {
    final bytes = await File(_editedPaths[index]).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return _editedPaths[index];

    final angle = _rotations[index].round();
    if (angle == 90 || angle == 180 || angle == 270) {
      image = img.copyRotate(image, angle: angle);
    }
    if (_grayscaleValues[index]) {
      image = img.grayscale(image);
    }
    if (_brightnessValues[index] != 0.0 || _contrastValues[index] != 1.0) {
      image = img.adjustColor(
        image,
        brightness: (_brightnessValues[index] * 100).round(),
        contrast: ((_contrastValues[index] - 1.0) * 100).round(),
      );
    }

    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/passport_page_${index}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(outputPath).writeAsBytes(img.encodeJpg(image, quality: 95));
    return outputPath;
  }

  Future<void> _saveImage() async {
    if (widget.onSave != null) {
      widget.onSave!(_editedPaths);
    }

    final List<String> pathsToSave = [];
    for (int i = 0; i < _editedPaths.length; i++) {
      pathsToSave.add(await _prepareEditedImage(i));
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaveOptionsScreen(sourceFilePaths: pathsToSave),
      ),
    );
  }

  Widget _buildPageSwitchingControls(AppLocalizations l10n) {
    if (!_isMultiPageMode) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.imageFiles.length, (index) {
          final isSelected = _currentPageIndex == index;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton(
                onPressed: () => _switchPage(index),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected
                      ? const Color(0xFF2CA5E0)
                      : const Color(0xFF1E2A3A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFF54C7FF)
                          : Colors.white24,
                    ),
                  ),
                ),
                child: Text(
                  l10n.pageLabel(index + 1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  ColorFilter _getColorFilter() {
    if (_isGrayScale) {
      return const ColorFilter.matrix([
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    }

    return ColorFilter.matrix([
      _contrast,
      0,
      0,
      0,
      _brightness * 255,
      0,
      _contrast,
      0,
      0,
      _brightness * 255,
      0,
      0,
      _contrast,
      0,
      _brightness * 255,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  Widget _buildActiveControl(AppLocalizations l10n) {
    if (_activeAdjust == null) return const SizedBox.shrink();
    final brightness = _activeAdjust == 'brightness';
    final value = brightness ? _brightness : _contrast - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            brightness ? Icons.wb_sunny : Icons.contrast,
            color: Colors.white70,
            size: 22,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 78,
            child: Text(
              brightness ? l10n.colorBrightness : l10n.colorContrast,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: brightness ? -0.5 : -0.5,
              max: brightness ? 0.5 : 1.0,
              divisions: brightness ? 20 : 15,
              activeColor: const Color(0xFF2CA5E0),
              inactiveColor: Colors.white24,
              onChanged: (next) {
                setState(() {
                  if (brightness) {
                    _brightness = next;
                    _brightnessValues[_currentPageIndex] = next;
                  } else {
                    _contrast = 1 + next;
                    _contrastValues[_currentPageIndex] = _contrast;
                  }
                });
              },
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${value >= 0 ? '+' : ''}${(value * 100).round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolRow(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _EditToolButton(
            icon: Icons.rotate_right,
            label: l10n.toolRotate,
            onTap: _rotateImage,
          ),
        ),
        Expanded(
          child: _EditToolButton(
            icon: Icons.wb_sunny,
            label: l10n.colorBrightness,
            isActive: _activeAdjust == 'brightness',
            onTap: () => _selectAdjust('brightness'),
          ),
        ),
        Expanded(
          child: _EditToolButton(
            icon: Icons.contrast,
            label: l10n.colorContrast,
            isActive: _activeAdjust == 'contrast',
            onTap: () => _selectAdjust('contrast'),
          ),
        ),
        Expanded(
          child: _EditToolButton(
            icon: Icons.filter_b_and_w,
            label: l10n.editToolBW,
            isActive: _isGrayScale,
            onTap: () {
              setState(() {
                _isGrayScale = !_isGrayScale;
                _grayscaleValues[_currentPageIndex] = _isGrayScale;
              });
            },
          ),
        ),
        Expanded(
          child: _EditToolButton(
            icon: Icons.crop,
            label: l10n.editToolCrop,
            onTap: _cropImage,
          ),
        ),
        Expanded(
          child: _EditToolButton(
            icon: Icons.auto_fix_high,
            label: l10n.editToolEnhance,
            onTap: _autoEnhance,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141E2B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isMultiPageMode
              ? l10n.editTitleWithCount(
                  _currentPageIndex + 1,
                  widget.imageFiles.length,
                )
              : l10n.editTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Colors.white),
            onPressed: _resetFilters,
            tooltip: l10n.reset,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPageSwitchingControls(l10n),

          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Transform.rotate(
                  angle: _rotation * 3.1415926535 / 180,
                  child: ColorFiltered(
                    colorFilter: _getColorFilter(),
                    child: Image.file(_getCurrentFile(), fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),

          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              16,
              18,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF141E2B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _buildActiveControl(l10n),
                ),
                _buildToolRow(l10n),

                const SizedBox(height: 16),

                // Кнопка сохранения
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saveImage,
                    icon: const Icon(Icons.save_rounded, size: 20),
                    label: Text(
                      _isMultiPageMode
                          ? l10n.editSaveAllPages(widget.imageFiles.length)
                          : l10n.editSaveChanges,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
}

class _EditToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _EditToolButton({
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
                shape: BoxShape.circle,
                color: isActive
                    ? accent.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.07),
                border: Border.all(
                  color: isActive ? accent : Colors.white24,
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: isActive ? accent : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 5),
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
                    fontWeight: FontWeight.w500,
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
