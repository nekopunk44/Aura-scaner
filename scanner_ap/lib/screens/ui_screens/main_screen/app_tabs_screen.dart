import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../all_actions_screen.dart';
import 'my_documents_screen.dart';
import '../camera.dart';
import '../settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentScreenIndex = 0;
  bool _isScanning = false;
  final GlobalKey<MyDocumentsScreenState> _docsKey = GlobalKey();

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  late final AnimationController _beamCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _beamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _beamCtrl.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      _navigateToCameraScreen();
    } else {
      setState(() {
        _currentScreenIndex = index == 0 ? 0 : 1;
      });
    }
  }

  void _navigateToCameraScreen() async {
    setState(() => _isScanning = true);
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      await availableCameras();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }

    if (!mounted) {
      setState(() => _isScanning = false);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final iconColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);
    final navSelected = const Color(0xFF2CA5E0);
    final navUnselected = isDark ? Colors.white38 : const Color(0xFFAAB4C8);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final navBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, _) {
            final glow = _pulseAnim.value;
            return Container(
              decoration: BoxDecoration(
                color: appBarBg,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2CA5E0).withValues(alpha: 0.04 + glow * 0.08),
                    blurRadius: 10 + glow * 8,
                    offset: const Offset(0, 3),
                  ),
                  if (isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        bottom: 0,
                        left: 48,
                        right: 48,
                        child: Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                const Color(0xFF2CA5E0).withValues(alpha: 0.15 + glow * 0.25),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'Aura Scanner',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Positioned(
                        right: 8,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(Icons.settings_outlined, size: 22, color: iconColor),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          _FadeTab(visible: _currentScreenIndex == 0, child: MyDocumentsScreen(key: _docsKey)),
          _FadeTab(
            visible: _currentScreenIndex == 1,
            child: AllActionsScreen(
              onDocumentImported: () => _docsKey.currentState?.refreshDocuments(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _beamCtrl,
        builder: (context, _) {
          final t = _beamCtrl.value;
          final sine = (math.sin(t * 2 * math.pi) + 1) / 2;
          final glowAlpha = 0.08 + sine * 0.16;
          final borderAlpha = isDark ? 0.06 + sine * 0.18 : 0.04 + sine * 0.10;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Container(
              height: 76,
              decoration: BoxDecoration(
                color: navBg,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: const Color(0xFF2CA5E0).withValues(alpha: borderAlpha),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2CA5E0).withValues(alpha: glowAlpha),
                    blurRadius: 16 + sine * 12,
                    spreadRadius: sine * 2,
                    offset: const Offset(0, 2),
                  ),
                  if (isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: Icons.description_outlined,
                      activeIcon: Icons.description,
                      label: 'Файлы',
                      isSelected: _currentScreenIndex == 0,
                      selectedColor: navSelected,
                      unselectedColor: navUnselected,
                      onTap: () => _onItemTapped(0),
                    ),
                  ),
                  _ScanButton(isScanning: _isScanning, onTap: () => _onItemTapped(1)),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.grid_view_outlined,
                      activeIcon: Icons.grid_view,
                      label: 'Инструменты',
                      isSelected: _currentScreenIndex == 1,
                      selectedColor: navSelected,
                      unselectedColor: navUnselected,
                      onTap: () => _onItemTapped(2),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FadeTab extends StatelessWidget {
  final bool visible;
  final Widget child;
  const _FadeTab({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: child,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(
                isSelected ? activeIcon : icon,
                key: ValueKey(isSelected),
                size: 24,
                color: isSelected ? selectedColor : unselectedColor,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? selectedColor : unselectedColor,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanButton extends StatefulWidget {
  final bool isScanning;
  final VoidCallback onTap;

  const _ScanButton({required this.isScanning, required this.onTap});

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isScanning ? null : widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final glow = _ctrl.value;
            return Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: widget.isScanning
                    ? const Color(0xFF2CA5E0).withValues(alpha: 0.6)
                    : const Color(0xFF2CA5E0),
                shape: BoxShape.circle,
                boxShadow: widget.isScanning
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFF2CA5E0).withValues(alpha: 0.3 + glow * 0.3),
                          blurRadius: 10 + glow * 14,
                          spreadRadius: glow * 3,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: child,
            );
          },
          child: widget.isScanning
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.qr_code_scanner, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
