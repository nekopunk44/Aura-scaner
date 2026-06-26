import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../all_actions_screen.dart';
import 'my_documents_screen.dart';
import '../camera.dart';
import '../settings_screen.dart';
import '../../../l10n/app_localizations.dart';

enum _FabDockTarget { none, search, appBar }

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

  // Перетаскиваемая позиция «+» (left/top в координатах body). null = дефолт.
  Offset? _fabPos;
  _FabDockTarget _fabDockTarget = _FabDockTarget.none;
  bool _fabDragging = false;
  final GlobalKey _bodyKey = GlobalKey();
  static const double _fabSize = 56;
  static const double _appBarDockLeft = 8;
  static const double _appBarDockTop = -53;
  static const double _bottomNavHeight = 76;
  static const double _bottomNavPadding = 20;
  static const double _fabNavClearance = 14;
  static const double _fabDockedWidth = 48;
  static const double _fabDockedHeight = 52;

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

    _loadFabPos();
  }

  Future<void> _loadFabPos() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('fab_x');
    final y = prefs.getDouble('fab_y');
    final savedTarget = prefs.getInt('fab_dock_target');
    final legacyDocked = prefs.getBool('fab_docked') ?? false;
    final target =
        savedTarget != null &&
            savedTarget >= 0 &&
            savedTarget < _FabDockTarget.values.length
        ? _FabDockTarget.values[savedTarget]
        : legacyDocked
        ? _FabDockTarget.search
        : _FabDockTarget.none;

    if (!mounted) return;
    if (target == _FabDockTarget.appBar) {
      setState(() {
        _fabPos = const Offset(_appBarDockLeft, _appBarDockTop);
        _fabDockTarget = target;
      });
      return;
    }
    if (x != null && y != null) {
      setState(() {
        _fabPos = Offset(x, y);
        _fabDockTarget = target;
      });
    }
  }

  Future<void> _saveFabPos() async {
    final pos = _fabPos;
    if (pos == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fab_x', pos.dx);
    await prefs.setDouble('fab_y', pos.dy);
    await prefs.setInt('fab_dock_target', _fabDockTarget.index);
    await prefs.setBool('fab_docked', _fabDockTarget == _FabDockTarget.search);
  }

  Size? _bodySize() {
    final bodyBox = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (bodyBox == null || !bodyBox.hasSize) return null;
    return bodyBox.size;
  }

  Offset _defaultFabPos(Size size) {
    const bottomGuard = _bottomNavHeight + _bottomNavPadding + _fabNavClearance;
    return Offset(
      size.width - _fabSize - 20,
      size.height - _fabSize - bottomGuard - 8,
    );
  }

  Offset _clampedFabPos(Size size, Offset pos, {required bool allowAppBar}) {
    const bottomGuard = _bottomNavHeight + _bottomNavPadding + _fabNavClearance;
    final maxX = math.max(8.0, size.width - _fabSize - 8);
    final maxY = math.max(
      allowAppBar ? _appBarDockTop : 8.0,
      size.height - _fabSize - bottomGuard,
    );
    final minY = allowAppBar ? _appBarDockTop : 8.0;
    return Offset(
      pos.dx.clamp(8.0, maxX).toDouble(),
      pos.dy.clamp(minY, maxY).toDouble(),
    );
  }

  void _updateFabDrag(DragUpdateDetails details) {
    final bodySize = _bodySize();
    if (bodySize == null) return;
    setState(() {
      final cur = _fabPos ?? _defaultFabPos(bodySize);
      _fabPos = _clampedFabPos(
        bodySize,
        cur + details.delta,
        allowAppBar: true,
      );
    });
  }

  void _endFabDrag() {
    final bodySize = _bodySize();
    if (bodySize == null) {
      setState(() => _fabDragging = false);
      _saveFabPos();
      return;
    }
    _settleFab(BoxConstraints.tight(bodySize), _defaultFabPos(bodySize));
  }

  void _cancelFabDrag() {
    setState(() => _fabDragging = false);
    _saveFabPos();
  }

  /// По отпусканию решает: пристыковать «+» в верхнюю панель, строку поиска
  /// или оставить свободным.
  void _settleFab(BoxConstraints constraints, Offset defaultPos) {
    final searchGlobal = _docsKey.currentState?.searchBarRect();
    final bodyBox = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    final bodySize = Size(constraints.maxWidth, constraints.maxHeight);
    final cur = _fabPos ?? defaultPos;
    final fabCenter = Offset(cur.dx + _fabSize / 2, cur.dy + _fabSize / 2);

    final appBarDropZone = Rect.fromLTWH(0, -80, 142, 112);
    if (appBarDropZone.contains(fabCenter)) {
      setState(() {
        _fabDragging = false;
        _fabDockTarget = _FabDockTarget.appBar;
        _fabPos = const Offset(_appBarDockLeft, _appBarDockTop);
      });
      _saveFabPos();
      return;
    }

    if (searchGlobal != null && bodyBox != null) {
      final searchLocal = searchGlobal.shift(
        -bodyBox.localToGlobal(Offset.zero),
      );
      if (searchLocal.inflate(24).contains(fabCenter)) {
        final dockLeft = (searchLocal.right - _fabDockedWidth)
            .clamp(8.0, constraints.maxWidth - _fabDockedWidth - 8)
            .toDouble();
        final dockTop = (searchLocal.center.dy - _fabDockedHeight / 2)
            .clamp(8.0, constraints.maxHeight - _fabDockedHeight - 8)
            .toDouble();
        setState(() {
          _fabDragging = false;
          _fabDockTarget = _FabDockTarget.search;
          _fabPos = Offset(dockLeft, dockTop);
        });
        _saveFabPos();
        return;
      }
    }
    setState(() {
      _fabDragging = false;
      _fabDockTarget = _FabDockTarget.none;
      _fabPos = _clampedFabPos(bodySize, cur, allowAppBar: false);
    });
    _saveFabPos();
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
    final scaffoldBg = isDark
        ? const Color(0xFF0F1923)
        : const Color(0xFFE8EFF9);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Scaffold(
          extendBody: true,
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
                        color: const Color(
                          0xFF2CA5E0,
                        ).withValues(alpha: 0.04 + glow * 0.08),
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
                                    const Color(
                                      0xFF2CA5E0,
                                    ).withValues(alpha: 0.15 + glow * 0.25),
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
                            child: _AppBarIconButton(
                              icon: Icons.settings_outlined,
                              color: iconColor,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
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
            key: _bodyKey,
            clipBehavior: Clip.none,
            children: [
              PageView(
                controller: _pageController,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentScreenIndex = i),
                children: [
                  MyDocumentsScreen(key: _docsKey),
                  AllActionsScreen(
                    onDocumentImported: () =>
                        _docsKey.currentState?.refreshDocuments(),
                  ),
                ],
              ),
            ],
          ),
          bottomNavigationBar: AnimatedBuilder(
            animation: _beamCtrl,
            builder: (context, _) {
              final t = _beamCtrl.value;
              final sine = (math.sin(t * 2 * math.pi) + 1) / 2;
              final glowAlpha = 0.08 + sine * 0.16;
              final borderAlpha = isDark
                  ? 0.06 + sine * 0.18
                  : 0.04 + sine * 0.10;
              // На широком экране таб-бар не должен растягиваться во всю
              // ширину. Считаем боковые отступы так, чтобы внутренняя
              // ширина не превышала 520. Не используем Center/ConstrainedBox
              // как обёртку — Scaffold.bottomNavigationBar требует фиксированную
              // высоту, а Center stretchится в высоту parent'а и Scaffold
              // отдаёт ему весь экран.
              final screenWidth = MediaQuery.of(context).size.width;
              final hPad = screenWidth > 552 ? (screenWidth - 520) / 2 : 16.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 20),
                child: Container(
                  height: 76,
                  decoration: BoxDecoration(
                    color: navBg,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: const Color(
                        0xFF2CA5E0,
                      ).withValues(alpha: borderAlpha),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF2CA5E0,
                        ).withValues(alpha: glowAlpha),
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
                          documentFilesAnimation: true,
                          onTap: () => _onItemTapped(0),
                        ),
                      ),
                      _ScanButton(
                        isScanning: _isScanning,
                        onTap: () => _onItemTapped(1),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.grid_view_outlined,
                          activeIcon: Icons.grid_view,
                          label: AppLocalizations.of(context).tabTools,
                          isSelected: _currentScreenIndex == 1,
                          selectedColor: navSelected,
                          unselectedColor: navUnselected,
                          toolsGridAnimation: true,
                          onTap: () => _onItemTapped(2),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildFloatingFab(context),
      ],
    );
  }

  // Плавающий перетаскиваемый «+» поверх ВСЕГО Scaffold (включая AppBar) —
  // в экранных координатах = верхний отступ + позиция в body-координатах.
  // Это держит кнопку над верхней панелью во время перетаскивания и даёт
  // плавную анимацию фиксации (AnimatedPositioned) в любую точку.
  Widget _buildFloatingFab(BuildContext context) {
    final mq = MediaQuery.of(context);
    const appBarHeight = 64.0;
    final topInset = mq.padding.top + appBarHeight; // экранный верх body
    final bodyW = mq.size.width;
    final bodyH = mq.size.height - topInset;

    const bottomGuard = _bottomNavHeight + _bottomNavPadding + _fabNavClearance;
    final maxX = math.max(8.0, bodyW - _fabSize - 8);
    final maxY = math.max(8.0, bodyH - _fabSize - bottomGuard);
    final defLeft = bodyW - _fabSize - 20;
    final defTop = bodyH - _fabSize - bottomGuard - 8;
    final left = (_fabPos?.dx ?? defLeft).clamp(8.0, maxX).toDouble();
    final canFloatOverAppBar =
        _fabDragging || _fabDockTarget == _FabDockTarget.appBar;
    final minY = canFloatOverAppBar ? _appBarDockTop : 8.0;
    final top = (_fabPos?.dy ?? defTop).clamp(minY, maxY).toDouble();

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, _) {
        var page = _currentScreenIndex.toDouble();
        if (_pageController.hasClients) {
          page = _pageController.page ?? page;
        }
        final pageProgress = page.clamp(0.0, 1.0).toDouble();
        final isAppBarDocked = _fabDockTarget == _FabDockTarget.appBar;
        final filesPageShift = isAppBarDocked ? 0.0 : -bodyW * pageProgress;
        final visibility = (1.0 - pageProgress).clamp(0.0, 1.0);

        return AnimatedPositioned(
          left: left,
          top: topInset + top,
          duration: _fabDragging
              ? Duration.zero
              : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: Transform.translate(
            offset: Offset(filesPageShift, 0),
            child: IgnorePointer(
              ignoring: visibility < 0.1,
              child: Opacity(
                opacity: visibility,
                child: Transform.scale(
                  scale: isAppBarDocked ? 1.0 : 0.92 + 0.08 * visibility,
                  child: GestureDetector(
                    onPanStart: (_) => setState(() {
                      _fabDragging = true;
                      _fabDockTarget = _FabDockTarget.none;
                      _fabPos = Offset(left, top);
                    }),
                    onPanUpdate: _updateFabDrag,
                    onPanEnd: (_) => _endFabDrag(),
                    onPanCancel: _cancelFabDrag,
                    child: _ImportFab(
                      dockTarget: _fabDockTarget,
                      onTap: () => _docsKey.currentState?.showImportOptions(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AppBarIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AppBarIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

class _ImportFab extends StatelessWidget {
  final VoidCallback onTap;
  final _FabDockTarget dockTarget;

  const _ImportFab({required this.onTap, required this.dockTarget});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = const Color(0xFF2CA5E0);
    final isSearchDocked = dockTarget == _FabDockTarget.search;
    final isAppBarDocked = dockTarget == _FabDockTarget.appBar;
    final isDocked = dockTarget != _FabDockTarget.none;
    const dockedRadius = BorderRadius.only(
      topRight: Radius.circular(14),
      bottomRight: Radius.circular(14),
      topLeft: Radius.circular(14),
      bottomLeft: Radius.circular(14),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: isSearchDocked
            ? dockedRadius
            : BorderRadius.circular(isAppBarDocked ? 22 : 28),
        child: AnimatedContainer(
          width: isAppBarDocked
              ? 44
              : isSearchDocked
              ? 48
              : 56,
          height: isAppBarDocked
              ? 44
              : isSearchDocked
              ? 52
              : 56,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: isAppBarDocked
              ? BoxDecoration(borderRadius: BorderRadius.circular(22))
              : isSearchDocked
              ? BoxDecoration(
                  borderRadius: dockedRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: isDark ? 0.10 : 0.08),
                      accent.withValues(alpha: isDark ? 0.05 : 0.04),
                    ],
                  ),
                  border: Border(
                    left: BorderSide(
                      color: accent.withValues(alpha: 0.34),
                      width: 1,
                    ),
                  ),
                )
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6FCFF5), Color(0xFF2CA5E0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              Icons.add_rounded,
              key: ValueKey(dockTarget),
              color: isDocked ? accent : Colors.white,
              size: isAppBarDocked
                  ? 26
                  : isSearchDocked
                  ? 25
                  : 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final bool documentFilesAnimation;
  final bool toolsGridAnimation;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    this.documentFilesAnimation = false,
    this.toolsGridAnimation = false,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  // Активная кнопка периодически оживает: обычные иконки пульсят,
  // «Файлы» добавляют элементы документа, «Инструменты» собирают grid.
  static const _interval = Duration(seconds: 3);

  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _rotation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.documentFilesAnimation
          ? const Duration(milliseconds: 1600)
          : widget.toolsGridAnimation
          ? const Duration(milliseconds: 1600)
          : const Duration(milliseconds: 700),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.22,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.22,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65,
      ),
    ]).animate(_controller);
    _rotation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.12), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.12), weight: 50),
      TweenSequenceItem(
        tween: Tween(
          begin: -0.12,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
    ]).animate(_controller);
    if (widget.isSelected) _startPulsing();
  }

  void _startPulsing() {
    _timer?.cancel();
    _controller.forward(from: 0); // первый пульс сразу при выборе
    _timer = Timer.periodic(_interval, (_) {
      if (mounted && widget.isSelected) _controller.forward(from: 0);
    });
  }

  void _stopPulsing() {
    _timer?.cancel();
    _timer = null;
    _controller.value = 0; // возврат таймлайна к началу
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _startPulsing();
    } else if (!widget.isSelected && oldWidget.isSelected) {
      _stopPulsing();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final shouldAnimateFiles = isSelected && widget.documentFilesAnimation;
    final shouldAnimateTools = isSelected && widget.toolsGridAnimation;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(28),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: AnimatedBuilder(
                key: ValueKey(isSelected),
                animation: _controller,
                builder: (context, child) {
                  if (shouldAnimateFiles) {
                    final progress = Curves.easeOutCubic.transform(
                      (_controller.value / 0.96).clamp(0.0, 1.0),
                    );
                    return _DocumentFilesIcon(
                      progress: progress,
                      color: widget.selectedColor,
                    );
                  }
                  if (shouldAnimateTools) {
                    return _ToolsGridIcon(
                      progress: _controller.value,
                      color: widget.selectedColor,
                    );
                  }
                  return Transform.rotate(
                    angle: isSelected ? _rotation.value : 0,
                    child: Transform.scale(
                      scale: isSelected ? _scale.value : 1.0,
                      child: child,
                    ),
                  );
                },
                child: Icon(
                  isSelected ? widget.activeIcon : widget.icon,
                  size: 24,
                  color: isSelected
                      ? widget.selectedColor
                      : widget.unselectedColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? widget.selectedColor
                    : widget.unselectedColor,
              ),
              child: Text(widget.label),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentFilesIcon extends StatelessWidget {
  final double progress;
  final Color color;

  const _DocumentFilesIcon({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: CustomPaint(
        painter: _DocumentFilesPainter(
          progress: progress.clamp(0.0, 1.0),
          color: color,
        ),
      ),
    );
  }
}

class _DocumentFilesPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _DocumentFilesPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final doc = Rect.fromLTWH(
      size.width * 0.18,
      size.height * 0.08,
      size.width * 0.64,
      size.height * 0.84,
    );
    final fold = size.width * 0.18;
    final radius = size.width * 0.09;

    final documentPath = Path()
      ..moveTo(doc.left + radius, doc.top)
      ..lineTo(doc.right - fold, doc.top)
      ..lineTo(doc.right, doc.top + fold)
      ..lineTo(doc.right, doc.bottom - radius)
      ..quadraticBezierTo(doc.right, doc.bottom, doc.right - radius, doc.bottom)
      ..lineTo(doc.left + radius, doc.bottom)
      ..quadraticBezierTo(doc.left, doc.bottom, doc.left, doc.bottom - radius)
      ..lineTo(doc.left, doc.top + radius)
      ..quadraticBezierTo(doc.left, doc.top, doc.left + radius, doc.top)
      ..close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color.withValues(alpha: 0.78)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(documentPath, fillPaint);
    canvas.drawPath(documentPath, strokePaint);

    final foldPath = Path()
      ..moveTo(doc.right - fold, doc.top)
      ..lineTo(doc.right - fold, doc.top + fold)
      ..lineTo(doc.right, doc.top + fold);
    canvas.drawPath(
      foldPath,
      strokePaint..color = color.withValues(alpha: 0.55),
    );

    final itemTop = doc.top + 8.4;
    for (var i = 0; i < 3; i++) {
      final appear = _itemProgress(progress, 0.08 + i * 0.18, 0.28 + i * 0.18);
      if (appear <= 0) continue;
      final y = itemTop + i * 5.0;
      final slide = (1 - appear) * -4.0;
      final alpha = appear.clamp(0.0, 1.0);
      final dotRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(doc.left + 3.4 + slide, y, 3.4, 3.4),
        const Radius.circular(1.1),
      );
      final itemPaint = Paint()
        ..color = color.withValues(alpha: 0.28 + alpha * 0.62)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(dotRect, itemPaint);

      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.24 + alpha * 0.58)
        ..strokeWidth = 1.35
        ..strokeCap = StrokeCap.round;
      final start = Offset(doc.left + 8.8 + slide, y + 1.7);
      final end = Offset(start.dx + 7.4 * alpha, y + 1.7);
      canvas.drawLine(start, end, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DocumentFilesPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }

  double _itemProgress(double value, double start, double end) {
    final raw = ((value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(raw);
  }
}

class _ToolsGridIcon extends StatelessWidget {
  final double progress;
  final Color color;

  const _ToolsGridIcon({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: CustomPaint(
        painter: _ToolsGridPainter(
          progress: progress.clamp(0.0, 1.0),
          color: color,
        ),
      ),
    );
  }
}

class _ToolsGridPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _ToolsGridPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final tile = size.width * 0.25;
    final gap = size.width * 0.08;
    final start = Offset(
      (size.width - tile * 2 - gap) / 2,
      (size.height - tile * 2 - gap) / 2,
    );
    final cells = [
      Rect.fromLTWH(start.dx, start.dy, tile, tile),
      Rect.fromLTWH(start.dx + tile + gap, start.dy, tile, tile),
      Rect.fromLTWH(start.dx + tile + gap, start.dy + tile + gap, tile, tile),
      Rect.fromLTWH(start.dx, start.dy + tile + gap, tile, tile),
    ];

    final segmentValue = (progress.clamp(0.0, 1.0) * 2).clamp(0.0, 1.999);
    final segment = segmentValue.floor();
    final local = Curves.easeInOutCubic.transform(segmentValue - segment);

    for (var i = 0; i < cells.length; i++) {
      final from = cells[(i + segment) % cells.length].center;
      final to = cells[(i + segment + 1) % cells.length].center;
      final center = Offset.lerp(from, to, local)!;
      final lift = math.sin(local * math.pi);
      final rect = Rect.fromCenter(
        center: center,
        width: tile * (0.94 + lift * 0.06),
        height: tile * (0.94 + lift * 0.06),
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(size.width * 0.055),
      );

      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.25 + lift * 0.08);
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.72 + lift * 0.20);

      if (lift > 0.08) {
        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..color = color.withValues(alpha: lift * 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        canvas.drawRRect(rrect, glowPaint);
      }

      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ToolsGridPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _ScanButton extends StatefulWidget {
  final bool isScanning;
  final VoidCallback onTap;

  const _ScanButton({required this.isScanning, required this.onTap});

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
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
                          color: const Color(
                            0xFF2CA5E0,
                          ).withValues(alpha: 0.3 + glow * 0.3),
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
              : const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white,
                  size: 30,
                ),
        ),
      ),
    );
  }
}
