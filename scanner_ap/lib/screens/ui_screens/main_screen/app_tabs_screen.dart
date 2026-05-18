import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../all_actions_screen.dart';
import 'my_documents_screen.dart';
import 'remote_documents_screen.dart';
import '../camera.dart';
import '../../../services/auth_service.dart';
import '../../auth/login_screen.dart';
import '../settings_screen.dart';
import '../premium_screen.dart';



void main() {
  runApp(const ScannerApp());
}

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Scanner App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentScreenIndex = 0;
  bool _isScanning = false;
  final GlobalKey<MyDocumentsScreenState> _docsKey = GlobalKey();

  void _onItemTapped(int index) {
    // Индекс 1 - это центральная кнопка "Сканировать"
    if (index == 1) {
      _navigateToCameraScreen();
    } else {
      // Индекс 0 -> index 0 (DocumentsScreen)
      // Индекс 2 -> index 1 (ActionsScreen)
      int screenIndex = index == 0 ? 0 : 1;
      setState(() {
        _currentScreenIndex = screenIndex;
      });
    }
  }

  void _navigateToCameraScreen() async {
    setState(() {
      _isScanning = true;
    });

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      await availableCameras();
    } catch (e) {
      debugPrint('Ошибка инициализации камеры: $e. Плейсхолдер для камеры.');
    }

    if (!mounted) {
      setState(() {
        _isScanning = false;
      });
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(onScanCompleted: _onDocumentScanned),
      ),
    );

    if (!mounted) return;
    setState(() => _isScanning = false);

    if (result != null) {
      _docsKey.currentState?.refreshDocuments();
      setState(() => _currentScreenIndex = 0);
    }
  }

  void _onDocumentScanned(String fullPath) {
    _docsKey.currentState?.refreshDocuments();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aura Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Облачные документы',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RemoteDocumentsScreen(
                    onLocalDocumentImported: () {
                      _docsKey.currentState?.refreshDocuments();
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.workspace_premium, color: Colors.amber),
            tooltip: 'Премиум',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PremiumScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await AuthService().logout();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentScreenIndex,
        children: [
          MyDocumentsScreen(key: _docsKey), // index 0
          AllActionsScreen(                   // index 1
            onDocumentImported: () {
              _docsKey.currentState?.refreshDocuments();
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentScreenIndex == 0 ? 0 : 2,
        onTap: _onItemTapped,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.description_outlined),
            label: 'Мои файлы',
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isScanning ? Colors.blue.shade200 : Colors.blue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.blueAccent.withValues(alpha: _isScanning ? 0.3 : 0.6), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: _isScanning
                  ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)
                  )
              )
                  : const Icon(Icons.qr_code_2, color: Colors.white, size: 28),
            ),
            label: '',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: 'Инструменты',
          ),
        ],
      ),
    );
  }
}
