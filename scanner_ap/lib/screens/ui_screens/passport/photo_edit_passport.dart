import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'save_options_passport.dart'; 

class PhotoEditScreen extends StatefulWidget {
  final List<XFile> imageFiles;
  final Function(List<String>)? onSave;

  const PhotoEditScreen({
    super.key,
    required this.imageFiles,
    this.onSave,
  });

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
    final cropped = await ImageCropper().cropImage(
      sourcePath: _editedPaths[_currentPageIndex],
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Обрезать фото',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Обрезать фото'),
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
    if (index >= 0 && index < widget.imageFiles.length && index != _currentPageIndex) {
      setState(() {
        _currentPageIndex = index;
        _rotation = _rotations[index];
        _brightness = _brightnessValues[index];
        _contrast = _contrastValues[index];
        _isGrayScale = _grayscaleValues[index];
      });
    }
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
    final outputPath = '${tempDir.path}/passport_page_${index}_${DateTime.now().microsecondsSinceEpoch}.jpg';
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
        builder: (_) => SaveOptionsScreen(
          sourceFilePaths: pathsToSave,
        ),
      ),
    );
  }

  Widget _buildPageSwitchingControls() {
    if (!_isMultiPageMode) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.imageFiles.length, (index) {
          final isSelected = _currentPageIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ActionChip(
              avatar: isSelected
                  ? const Icon(Icons.check_circle, color: Colors.black, size: 18)
                  : null,
              label: Text('Страница ${index + 1}'),
              onPressed: () => _switchPage(index),
              backgroundColor: isSelected ? Colors.amber : Colors.grey.shade800,
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected ? Colors.amber.shade700 : Colors.white30,
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
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0,      0,      0,      1, 0,
      ]);
    }

    return ColorFilter.matrix([
      _contrast, 0, 0, 0, _brightness * 255,
      0, _contrast, 0, 0, _brightness * 255,
      0, 0, _contrast, 0, _brightness * 255,
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isMultiPageMode
              ? 'Редактирование (${_currentPageIndex + 1} из ${widget.imageFiles.length})'
              : 'Редактирование',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Colors.white),
            onPressed: _resetFilters,
            tooltip: 'Сбросить',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPageSwitchingControls(), 

          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Transform.rotate(
                angle: _rotation * 3.1415926535 / 180,
                child: ColorFiltered(
                  colorFilter: _getColorFilter(),
                  child: Image.file(
                    _getCurrentFile(),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 70,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _EditToolButton(
                        icon: Icons.rotate_right,
                        label: 'Повернуть',
                        onTap: _rotateImage,
                      ),
                      _EditToolButton(
                        icon: Icons.filter_b_and_w,
                        label: 'Ч/Б',
                        onTap: () {
                          setState(() {
                            _isGrayScale = !_isGrayScale;
                            _grayscaleValues[_currentPageIndex] = _isGrayScale;
                          });
                        },
                        isActive: _isGrayScale,
                      ),
                      _EditToolButton(
                        icon: Icons.crop,
                        label: 'Обрезать',
                        onTap: _cropImage,
                      ),
                      _EditToolButton(
                        icon: Icons.auto_awesome,
                        label: 'Улучшить',
                        onTap: () {
                          setState(() {
                            _contrast = 1.2;
                            _brightness = 0.1;
                            _contrastValues[_currentPageIndex] = _contrast;
                            _brightnessValues[_currentPageIndex] = _brightness;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Автоулучшение применено')),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.brightness_6, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: _brightness,
                            min: -0.5,
                            max: 0.5,
                            divisions: 20,
                            onChanged: (value) {
                              setState(() {
                                _brightness = value;
                                _brightnessValues[_currentPageIndex] = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 60,
                          child: Text(
                            'Яркость',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Icon(Icons.contrast, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Slider(
                            value: _contrast,
                            min: 0.5,
                            max: 2.0,
                            divisions: 15,
                            onChanged: (value) {
                              setState(() {
                                _contrast = value;
                                _contrastValues[_currentPageIndex] = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 60,
                          child: Text(
                            'Контраст',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Кнопка сохранения
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveImage,
                    icon: const Icon(Icons.save, color: Colors.white, size: 20),
                    label: Text(
                      _isMultiPageMode
                          ? 'Сохранить все ${widget.imageFiles.length} страницы'
                          : 'Сохранить изменения',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isActive ? Colors.amber.withValues(alpha: 0.2) : Colors.white12,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? Colors.amber : Colors.white24,
                width: isActive ? 2 : 1,
              ),
            ),
            child: IconButton(
              icon: Icon(icon,
                  color: isActive ? Colors.amber : Colors.white,
                  size: 22),
              onPressed: onTap,
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.amber : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
