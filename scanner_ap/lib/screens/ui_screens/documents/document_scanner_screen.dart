import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:image_cropper/image_cropper.dart' as cropper;
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_editor_plus/image_editor_plus.dart';

class DocumentScannerScreen extends StatefulWidget {
  final String imagePath;

  const DocumentScannerScreen({super.key, required this.imagePath});

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen> {
  File? _editedImage;
  bool _isEditing = false;
  bool _isScanning = false;


  @override
  void initState () {
    super.initState();
    _editedImage = File(widget.imagePath);
    _checkPermissions();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 10),
              Text(
                message,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _checkPermissions() async {
    if (await Permission.storage.request().isGranted) {
      debugPrint('Storage permission granted');
    } else {
      debugPrint('Storage permission denied');
    }
  }

  Future<void> _saveImageToGallery() async {
    if (_editedImage == null || !await _editedImage!.exists()) {
      _showErrorSnackBar('Image file not found');
      return;
    }
    try {
      final String fileName =
          'Document_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String newPath = 'Android/emulated/storage';
      bool success = true;

      if(success == true) {
        _showSaveBottomSheet(fileName, newPath);
      }
    } catch (e) {
      debugPrint('Error daving image: $e');
      _showErrorSnackBar('Error saving image: $e');
    }
  }

  Future<void> _cropImage() async {
    if (_editedImage == null || !await _editedImage!.exists()) {
      debugPrint('Image file doesn`t exist: ${_editedImage?.path}');
      _showErrorSnackBar('Image file not found');
      return;
    }
    debugPrint('Attempting to crop image');
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final croppedFile = await cropper.ImageCropper().cropImage(
        sourcePath: _editedImage!.path,
        compressFormat: cropper.ImageCompressFormat.jpg,
        compressQuality: 90,
        aspectRatio: cropper.CropAspectRatio(ratioX: 4, ratioY: 3),
        uiSettings: [
          cropper.AndroidUiSettings(
            toolbarTitle: 'Crop Document',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: cropper.CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          cropper.IOSUiSettings(
            title: 'Crop Document',
            aspectRatioLockEnabled: false,
          ),
        ],
      );
      if (croppedFile != null) {
        debugPrint('Image cropped successfully: ${croppedFile.path}');
        setState(() {
          _editedImage = File(croppedFile.path);
        });

        messenger.showSnackBar(
          SnackBar(
            content: Padding(
              padding: EdgeInsets.all(10),
              child: Container(
                height: 40,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified, color: Colors.green, size: 20),
                    SizedBox(width: 20),
                    Text(
                      'Image cropped successfully',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            backgroundColor: Colors.transparent,
            duration: Duration(seconds: 1),
          ),
        );
      } else {
      debugPrint('Cropping was cancelled');
      }
    } catch (e) {
      _showErrorSnackBar('Falled to crop image $e');
    }
  }

  Future<void> _scanDocument() async {
    setState(() => _isScanning = true);
    try {
      final String? scannedImagePath = await FlutterDocScanner()
          .getScanDocuments();
      if (scannedImagePath != null) {
        setState(() {
          _editedImage = File(scannedImagePath);
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to scan document');
    }
    setState(() => _isScanning = false);
  }

  Future<void> _editImage() async {
    try {
      final editImage = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageEditor(image: _editedImage!),
        ),
      );
      if (editImage != null && editImage is File) {
        setState(() {
          _editedImage = editImage;
        });
      }
    } catch (e) {
      debugPrint('Error editing image: $e');
    }
  }

  void _showSaveBottomSheet(String imageName, String imagePath) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: GestureDetector(
              onTap: () {},
              child: DraggableScrollableSheet(
                builder: (_, controller) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[700],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Document Saved',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 15),
                        Row(
                          children: [
                            Icon(Icons.image, color: Colors.white, size: 20),
                            SizedBox(height: 10),
                            Expanded(
                              child: Text(
                                imagePath,
                                style: TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.folder,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(height: 10),
                                Expanded(
                                  child: Text(
                                    imagePath,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.share,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  onPressed: () {_shareImage();},
                                ),
                                Text(
                                  'Share',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            IconButton(
                              onPressed: () { _viewGallery();},
                              icon: Icon(
                                Icons.photo_library,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            Text('View in Gallery', style: TextStyle(color: Colors.white),)
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }


  void _shareImage() {
      debugPrint('Sharing image: ${_editedImage!.path}');
  }

  void _viewGallery() {
      debugPrint('View image in gallery: ${_editedImage!.path}');
  }

  Future<void> _saveImage() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        _showErrorSnackBar('Storage permission required to save images');
        return;
      }
    }
    await _saveImageToGallery();
  }


  Future<void> _applyFilter () async{
    setState (() => _isEditing = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState (() => _isEditing = false);

    SnackBar(
      content: Padding(
        padding: EdgeInsets.all(10),
        child: Container(
          height: 40,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 20),
              Text(
                'filters applied',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,),
              ),
            ],
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      duration: Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop,
          icon: Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text('Document Scanner', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: _isEditing || _isScanning
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : PhotoView(
              imageProvider: FileImage(_editedImage!),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
            ),
      bottomNavigationBar: Container(
        height: 80,
        color: Colors.black,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              onPressed: _applyFilter,
              icon: Icon(Icons.filter, color: Colors.white, size: 28),
              tooltip: 'Apply Filter',
            ),
            IconButton(
              onPressed: _cropImage,
              icon: Icon(Icons.crop, color: Colors.white, size: 28),
              tooltip: 'Crop Document',
            ),
            IconButton(
              onPressed: _editImage,
              icon: Icon(Icons.edit, color: Colors.white, size: 28),
              tooltip: 'Edit Image',
            ),
            IconButton(
              onPressed: _scanDocument,
              icon: Icon(Icons.document_scanner, color: Colors.white, size: 28),
              tooltip: 'Scan document',
            ),
            IconButton(
              onPressed: _saveImage,
              icon: Icon(Icons.check_circle, color: Colors.white, size: 28),
              tooltip: 'Save Document',
            ),
          ],
        ),
      ),
    );
  }
}
