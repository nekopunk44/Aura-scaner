import 'package:flutter/material.dart';
import '../translate/camera_widget.dart';
import 'package:camera/camera.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Перевод',
      theme: ThemeData(
        primaryColor: Colors.blue,
      ),
      home: Scaffold(
        body: cameras.isEmpty
            ? const Center(
          child: CircularProgressIndicator.adaptive(),
        )
            : CameraWidget(camera: cameras.first), // задняя камера
      ),
    );
  }
}