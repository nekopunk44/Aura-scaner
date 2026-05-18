// id_card_photo_edit.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'save_options_id_card.dart';


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

  @override
  void initState() {
    super.initState();
    _frontState = EditState(originalFile: widget.frontImage, currentPath: widget.frontImage.path);
    _backState = EditState(originalFile: widget.backImage, currentPath: widget.backImage.path);
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

  Future<void> _cropImage() async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: _currentState.currentPath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Обрезать удостоверение',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.ratio16x9,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: 'Обрезать удостоверение'),
      ],
    );

    if (cropped == null || !mounted) return;

    setState(() {
      _currentState = _currentState.copyWith(
        currentPath: cropped.path,
        rotation: 0,
      );
    });
  }

  void _autoEnhance() {
    setState(() {
      _currentState = _currentState.copyWith(
        brightness: 0.1,
        contrast: 0.2,
      );
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

  // --- ФУНКЦИЯ СОХРАНЕНИЯ И ПЕРЕХОДА ---
  Future<String> _prepareEditedImage(EditState state, String name) async {
    final bytes = await File(state.currentPath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return state.currentPath;

    if (state.rotation == 90 || state.rotation == 180 || state.rotation == 270) {
      image = img.copyRotate(image, angle: state.rotation);
    }
    if (state.isGrayscale) {
      image = img.grayscale(image);
    }
    if (state.brightness != 0.0 || state.contrast != 0.0) {
      image = img.adjustColor(
        image,
        brightness: (state.brightness * 100).round(),
        contrast: (state.contrast * 100).round(),
      );
    }

    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/id_card_${name}_${DateTime.now().microsecondsSinceEpoch}.jpg';
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
        builder: (_) => SaveOptionsIdCardScreen(
          sourceFilePaths: finalPaths,
        ),
      ),
    );
  }

  ColorFilter _getColorFilter() {
    if (_currentState.isGrayscale) {
      return const ColorFilter.matrix([
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    }

    final contrast = 1.0 + _currentState.contrast;
    final brightness = _currentState.brightness * 255;
    return ColorFilter.matrix([
      contrast, 0, 0, 0, brightness,
      0, contrast, 0, 0, brightness,
      0, 0, contrast, 0, brightness,
      0, 0, 0, 1, 0,
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
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Редактирование Удостоверения'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                if (_isEditingFront) {
                  _frontState = EditState(originalFile: widget.frontImage, currentPath: widget.frontImage.path);
                  _currentState = _frontState;
                } else {
                  _backState = EditState(originalFile: widget.backImage, currentPath: widget.backImage.path);
                  _currentState = _backState;
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SideButton(
                  label: 'Лицевая сторона',
                  isSelected: _isEditingFront,
                  onPressed: () => _toggleSide(true),
                ),
                const SizedBox(width: 8),
                _SideButton(
                  label: 'Обратная сторона',
                  isSelected: !_isEditingFront,
                  onPressed: () => _toggleSide(false),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: _buildEditableImagePreview(),
            ),
          ),
          _buildToolRow(),

          _buildSliderPanel(),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _saveAndNavigate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Сохранить обе стороны', style: TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  // Вспомогательные виджеты

  Widget _buildToolRow() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ToolIcon(
            icon: Icons.rotate_right,
            label: 'Повернуть',
            onTap: _rotateImage,
          ),
          _ToolIcon(
            icon: Icons.filter_b_and_w,
            label: 'Ч/Б',
            isActive: _currentState.isGrayscale,
            onTap: _applyFilter,
          ),
          _ToolIcon(
            icon: Icons.crop,
            label: 'Обрезать',
            onTap: _cropImage,
          ),
          _ToolIcon(
            icon: Icons.auto_fix_high,
            label: 'Улучшить',
            onTap: _autoEnhance,
          ),
        ],
      ),
    );
  }

  Widget _buildSliderPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          _AdjustmentSlider(
            icon: Icons.wb_sunny,
            label: 'Яркость',
            value: _currentState.brightness,
            onChanged: _updateBrightness,
          ),
          _AdjustmentSlider(
            icon: Icons.contrast,
            label: 'Контраст',
            value: _currentState.contrast,
            onChanged: _updateContrast,
          ),
        ],
      ),
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
        backgroundColor: isSelected ? Colors.yellow.shade700 : Colors.grey.shade800,
        foregroundColor: isSelected ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(40),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              icon,
              color: isActive ? Colors.lightBlue : Colors.white,
              size: 28,
            ),
          ),
        ),
        Text(
          label,
          style: TextStyle(color: isActive ? Colors.lightBlue : Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}

class _AdjustmentSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _AdjustmentSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
        Expanded(
          child: Slider(
            value: value,
            min: -1.0,
            max: 1.0,
            divisions: 20,
            onChanged: onChanged,
            activeColor: Colors.blue,
            inactiveColor: Colors.grey.shade700,
          ),
        ),
        Text(
          label, 
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }
}
