import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../all_actions_screen.dart';
import 'my_documents_screen.dart';
import '../camera.dart';
import '../settings_screen.dart';
import '../../../l10n/app_localizations.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentScreenIndex = 0;
  bool _isScanning = false;
  final GlobalKey<MyDocumentsScreenState> _docsKey = GlobalKey();
  late final PageController _pageController;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  late final AnimationController _beamCtrl;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
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
    _pageController.dispose();
    _pulseCtrl.dispose();
    _beamCtrl.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      _navigateToCameraScreen();
    } else {
      final pageIndex = index == 0 ? 0 : 1;
      if (pageIndex == _currentScreenIndex) return;
      // Плавный переход через PageController.animateToPage — hardware-
      // accelerated slide, выглядит лучше AnimatedOpacity-перекрытия.
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _navigateToCameraScreen() async {
    setState(() => _isScanning = true);
    await Future.delayed(const Duration(milliseconds: 100));
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
                              MaterialPageRoute(
                                  builder: (_) => const SettingsScreen()),
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(Icons.settings_outlined,
                                  size: 22, color: iconColor),
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
          PageView(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            onPageChanged: (i) => setState(() => _currentScreenIndex = i),
            children: [
              MyDocumentsScreen(key: _docsKey),
              AllActionsScreen(
                onDocumentImported: () => _docsKey.currentState?.refreshDocuments(),
              ),
            ],
          ),
          // Плавающий «+» над bottomNavigationBar. Виден только на
          // вкладке «Файлы»; AnimatedScale прячет/показывает плавно.
          // bottom отсчитывается от верхнего края bottomNavigationBar
          // (Scaffold вырезает место под бар из body), поэтому 16 даёт
          // отступ от bottom-bar'а, а не от низа экрана.
          Positioned(
            right: 20,
            bottom: 16,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              scale: _currentScreenIndex == 0 ? 1.0 : 0.0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _currentScreenIndex == 0 ? 1.0 : 0.0,
                child: _ImportFab(
                  onTap: () => _docsKey.currentState?.showImportOptions(),
                ),
              ),
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
          // На широком экране таб-бар не должен растягиваться во всю
          // ширину. Считаем боковые отступы так, чтобы внутренняя
          // ширина не превышала 520. Не используем Center/ConstrainedBox
          // как обёртку — Scaffold.bottomNavigationBar требует фиксированную
          // высоту, а Center stretchится в высоту parent'а и Scaffold
          // отдаёт ему весь экран.
          final screenWidth = MediaQuery.of(context).size.width;
          final hPad = screenWidth > 552
              ? (screenWidth - 520) / 2
              : 16.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 20),
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
                      label: AppLocalizations.of(context).tabFiles,
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
                      label: AppLocalizations.of(context).tabTools,
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

class _ImportFab extends StatelessWidget {
  final VoidCallback onTap;
  const _ImportFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF6FCFF5), Color(0xFF2CA5E0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2CA5E0).withValues(alpha: 0.45),
                blurRadius: 16,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
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
