import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'save_options_document.dart';
import '../../../l10n/app_localizations.dart';


class ImageEditState {
  String path;
  double rotation;
  double brightness;
  double contrast;
  bool isGrayScale;

  ImageEditState({
    required this.path,
    this.rotation = 0.0,
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.isGrayScale = false,
  });

  void reset() {
    rotation = 0.0;
    brightness = 0.0;
    contrast = 1.0;
    isGrayScale = false;
  }
}

class DocumentCameraEditScreen extends StatefulWidget {
  final List<XFile> imageFiles;
  final Function(List<String>)? onSave;

  const DocumentCameraEditScreen({
    super.key,
    required this.imageFiles,
    this.onSave,
  });

  @override
  State<DocumentCameraEditScreen> createState() => _DocumentCameraEditScreenState();
}

class _DocumentCameraEditScreenState extends State<DocumentCameraEditScreen> {

  late List<ImageEditState> _editStates;
  int _currentPageIndex = 0;


  ImageEditState get _currentEditState => _editStates[_currentPageIndex];
  double get _rotation => _currentEditState.rotation;
  set _rotation(double value) => _currentEditState.rotation = value;
  double get _brightness => _currentEditState.brightness;
  set _brightness(double value) => _currentEditState.brightness = value;
  double get _contrast => _currentEditState.contrast;
  set _contrast(double value) => _currentEditState.contrast = value;
  bool get _isGrayScale => _currentEditState.isGrayScale;
  set _isGrayScale(bool value) => _currentEditState.isGrayScale = value;

  @override
  void initState() {
    super.initState();
    _editStates = widget.imageFiles.map((f) => ImageEditState(path: f.path)).toList();
  }

  File _getCurrentFile() => File(_currentEditState.path);
  bool get _isMultiPageMode => _editStates.length > 1;
  int get _pageCount => _editStates.length;

  void _rotateImage() {
    setState(() { _rotation = (_rotation + 90) % 360; });
  }

  Future<void> _cropImage() async {
    final l10n = AppLocalizations.of(context);
    final cropped = await ImageCropper().cropImage(
      sourcePath: _currentEditState.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: l10n.editCropDocTitle,
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(title: l10n.editCropDocTitle),
      ],
    );

    if (cropped == null || !mounted) return;

    setState(() {
      _currentEditState.path = cropped.path;
      _currentEditState.rotation = 0.0;
    });
  }

  void _resetFilters() {
    setState(() { _currentEditState.reset(); });
  }

  void _switchPage(int index) {
    if (index >= 0 && index < _editStates.length && index != _currentPageIndex) {
      setState(() { _currentPageIndex = index; });
    }
  }

  Future<void> _deleteCurrentPage() async {
    if (_editStates.length <= 1) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.actionDelete),
        content: Text(l10n.editDeletePageConfirm(_currentPageIndex + 1)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.actionDelete,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _editStates.removeAt(_currentPageIndex);
      if (_currentPageIndex >= _editStates.length) {
        _currentPageIndex = _editStates.length - 1;
      }
    });
  }

  void _saveImage() {
    final List<String> pathsToSave = _editStates.map((s) => s.path).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaveOptionsScreen(
          sourceFilePaths: pathsToSave,
          editStates: _editStates,
        ),
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
    final l10n = AppLocalizations.of(context);
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
              ? l10n.editTitleWithCount(_currentPageIndex + 1, _pageCount)
              : l10n.editTitle,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (_isMultiPageMode)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _deleteCurrentPage,
              tooltip: l10n.actionDelete,
            ),
          IconButton(
            icon: const Icon(Icons.restart_alt, color: Colors.white),
            onPressed: _resetFilters,
            tooltip: l10n.reset,
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
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    children: [
                      _EditToolButton(
                        icon: Icons.rotate_right,
                        label: l10n.toolRotate,
                        onTap: _rotateImage,
                      ),
                      _EditToolButton(
                        icon: Icons.filter_b_and_w,
                        label: l10n.editToolBW,
                        onTap: () {
                          setState(() {
                            _isGrayScale = !_isGrayScale;
                          });
                        },
                        isActive: _isGrayScale,
                      ),
                      _EditToolButton(
                        icon: Icons.crop,
                        label: l10n.editToolCrop,
                        onTap: _cropImage,
                      ),
                      _EditToolButton(
                        icon: Icons.auto_awesome,
                        label: l10n.editToolEnhance,
                        onTap: () {
                          setState(() {
                            _contrast = 1.2;
                            _brightness = 0.1;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.editAutoEnhanced)),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
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
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 60,
                            child: Text(l10n.colorBrightness, style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 60,
                            child: Text(l10n.colorContrast, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveImage,
                      icon: const Icon(Icons.save, color: Colors.white, size: 20),
                      label: Text(
                        _isMultiPageMode
                            ? l10n.editSaveAllPages(_pageCount)
                            : l10n.editSaveChanges,
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageSwitchingControls() {
    if (!_isMultiPageMode) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _editStates.length,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          itemBuilder: (context, index) {
            final l10n = AppLocalizations.of(context);
            final isSelected = _currentPageIndex == index;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ActionChip(
                avatar: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.black, size: 18)
                    : null,
                label: Text(l10n.pageLabel(index + 1)),
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
          },
        ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
