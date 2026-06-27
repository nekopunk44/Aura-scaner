import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../../l10n/app_localizations.dart';

const String onboardingCompletedKey = 'onboarding_completed';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;
  static const _pageCount = 3;

  late final AnimationController _ctaCtrl;
  late final Animation<double> _ctaFade;
  late final Animation<Offset> _ctaSlide;

  @override
  void initState() {
    super.initState();
    _ctaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _ctaFade = CurvedAnimation(parent: _ctaCtrl, curve: Curves.easeOut);
    _ctaSlide = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctaCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    _ctaCtrl.dispose();
    super.dispose();
  }

  Future<void> _markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingCompletedKey, true);
  }

  Future<void> _goToLogin() async {
    await _markDone();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _goToRegister() async {
    await _markDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  void _next() {
    if (_currentPage >= _pageCount - 1) return;
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int i) {
    setState(() => _currentPage = i);
    if (i == _pageCount - 1) {
      _ctaCtrl.forward(from: 0);
    } else {
      _ctaCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1923) : const Color(0xFFE8F2FF);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white70 : const Color(0xFF6B7A99);
    final isLast = _currentPage == _pageCount - 1;

    final pages = [
      _OnboardingPage(
        pageIndex: 0,
        title: l10n.onboarding1Title,
        description: l10n.onboarding1Desc,
        textColor: textColor,
        subColor: subColor,
        isDark: isDark,
      ),
      _OnboardingPage(
        pageIndex: 1,
        title: l10n.onboarding2Title,
        description: l10n.onboarding2Desc,
        textColor: textColor,
        subColor: subColor,
        isDark: isDark,
      ),
      _OnboardingPage(
        pageIndex: 2,
        title: l10n.onboarding3Title,
        description: l10n.onboarding3Desc,
        textColor: textColor,
        subColor: subColor,
        isDark: isDark,
      ),
    ];

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _goToLogin,
                child: Text(
                  l10n.actionSkip,
                  style: TextStyle(color: subColor, fontSize: 14),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: _onPageChanged,
                itemBuilder: (_, i) => pages[i],
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pageCount, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF2CA5E0)
                        : subColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            // Bottom CTA
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 320),
              crossFadeState: isLast
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2CA5E0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      l10n.onboardingNext,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              secondChild: FadeTransition(
                opacity: _ctaFade,
                child: SlideTransition(
                  position: _ctaSlide,
                  child: _CtaBlock(
                    isDark: isDark,
                    l10n: l10n,
                    onGetStarted: _goToRegister,
                    onLogIn: _goToLogin,
                    onSignUp: _goToRegister,
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

// ─── CTA block ────────────────────────────────────────────────────────────────

class _CtaBlock extends StatelessWidget {
  final bool isDark;
  final AppLocalizations l10n;
  final VoidCallback onGetStarted;
  final VoidCallback onLogIn;
  final VoidCallback onSignUp;

  const _CtaBlock({
    required this.isDark,
    required this.l10n,
    required this.onGetStarted,
    required this.onLogIn,
    required this.onSignUp,
  });

  static const _accent = Color(0xFF2CA5E0);
  static const _accentDark = Color(0xFF1A8FC8);

  @override
  Widget build(BuildContext context) {
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF6B7A99);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFF2CA5E0).withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accent, _accentDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.38),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: onGetStarted,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: Text(
                  l10n.onboardingGetStarted,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton(
              onPressed: onLogIn,
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: borderColor, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                l10n.onboardingLogIn,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.onboardingNewHere,
                style: TextStyle(fontSize: 13.5, color: subColor),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onSignUp,
                child: Text(
                  l10n.onboardingSignUp,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                    decoration: TextDecoration.underline,
                    decorationColor: _accent.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Single onboarding page ───────────────────────────────────────────────────

class _OnboardingPage extends StatefulWidget {
  final int pageIndex;
  final String title;
  final String description;
  final Color textColor;
  final Color subColor;
  final bool isDark;

  const _OnboardingPage({
    required this.pageIndex,
    required this.title,
    required this.description,
    required this.textColor,
    required this.subColor,
    required this.isDark,
  });

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  bool _cloudUploadDone = false;

  static const _durations = [
    Duration(milliseconds: 4200), // doc scanner
    Duration(milliseconds: 5800), // OCR
    Duration(milliseconds: 5200), // cloud sync
  ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: widget.pageIndex == 2
          ? const Duration(milliseconds: 1150)
          : _durations[widget.pageIndex],
    );

    if (widget.pageIndex == 2) {
      _anim.addStatusListener((status) {
        if (status == AnimationStatus.completed && !_cloudUploadDone) {
          if (!mounted) return;
          setState(() => _cloudUploadDone = true);
          _anim.duration = const Duration(milliseconds: 1700);
          _anim.repeat();
        }
      });
      _anim.forward();
    } else {
      _anim.repeat();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  CustomPainter _painter(double t) {
    const accent = Color(0xFF2CA5E0);
    switch (widget.pageIndex) {
      case 0:
        return _DocScanPainter(t: t, accent: accent, isDark: widget.isDark);
      case 1:
        return _OcrPainter(t: t, accent: accent, isDark: widget.isDark);
      default:
        return _CloudSyncPainter(
          t: t,
          accent: accent,
          isDark: widget.isDark,
          uploadComplete: _cloudUploadDone,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // Animated scene
          Center(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => SizedBox(
                width: 166,
                height: 166,
                child: CustomPaint(painter: _painter(_anim.value)),
              ),
            ),
          ),

          const SizedBox(height: 38),

          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: widget.textColor,
              height: 1.15,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(height: 14),

          Text(
            widget.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.65,
              color: widget.subColor,
            ),
          ),

          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

// ─── Page 0: document scanner painter ────────────────────────────────────────

class _DocScanPainter extends CustomPainter {
  final double t;
  final Color accent;
  final bool isDark;

  const _DocScanPainter({
    required this.t,
    required this.accent,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Radial gradient glow — no hard edge
    final glowR = size.width * 0.72;
    canvas.drawCircle(
      Offset(cx, cy),
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.28 : 0.18),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowR)),
    );

    // Document rect (portrait)
    final dw = size.width * 0.58;
    final dh = size.height * 0.74;
    final dl = cx - dw / 2;
    final dt = cy - dh / 2;
    final dr = cx + dw / 2;
    final db = cy + dh / 2;
    final docRRect = RRect.fromLTRBR(dl, dt, dr, db, const Radius.circular(5));

    canvas.drawRRect(
      docRRect.shift(const Offset(0, 7)),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.18 : 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Document fill — radial inner glow
    final docFillRect = Rect.fromLTRB(dl, dt, dr, db);
    canvas.drawRRect(
      docRRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.85,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.12 : 0.72),
            accent.withValues(alpha: isDark ? 0.10 : 0.10),
          ],
        ).createShader(docFillRect),
    );

    // Document glow stroke (blurred outer halo)
    canvas.drawRRect(
      docRRect,
      Paint()
        ..color = accent.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Document crisp inner stroke
    canvas.drawRRect(
      docRRect,
      Paint()
        ..color = accent.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Text line stubs
    final lp = Paint()
      ..color = accent.withValues(alpha: 0.22)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final lx0 = dl + dw * 0.10;
    for (var i = 0; i < 5; i++) {
      final y = dt + dh * (0.16 + i * 0.15);
      final lx1 = dl + dw * (i < 4 ? 0.88 : 0.56);
      canvas.drawLine(Offset(lx0, y), Offset(lx1, y), lp);
    }

    // Scan beam sweeps down and returns without a hard restart.
    final scanT = t <= 0.5 ? t * 2 : (1 - t) * 2;
    final easedScanT = scanT < 0.5
        ? 2 * scanT * scanT
        : 1 - ((-2 * scanT + 2) * (-2 * scanT + 2)) / 2;
    final beamY = dt + (dh - 2) * easedScanT;

    // Beam area glow (vertical gradient, blurred)
    final glowRect = Rect.fromLTRB(dl - 4, beamY - 12, dr + 4, beamY + 12);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.35),
            accent.withValues(alpha: 0),
          ],
        ).createShader(glowRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Beam line (horizontal gradient + crisp)
    final beamRect = Rect.fromLTRB(dl, beamY - 1.5, dr, beamY + 1.5);
    canvas.drawRect(
      beamRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.92),
            accent,
            accent.withValues(alpha: 0.92),
            accent.withValues(alpha: 0),
          ],
          stops: const [0, 0.18, 0.5, 0.82, 1.0],
        ).createShader(beamRect),
    );

    // Corner bracket glow (blurred outer)
    final cpGlow = Paint()
      ..color = accent.withValues(alpha: 0.40)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    // Corner bracket crisp
    final cp = Paint()
      ..color = accent
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cs = 10.0;
    const co = 3.5;
    void bracket(Offset a, Offset b, Offset c) {
      for (final p in [cpGlow, cp]) {
        canvas.drawLine(a, b, p);
        canvas.drawLine(b, c, p);
      }
    }

    bracket(
      Offset(dl - co, dt + cs),
      Offset(dl - co, dt - co),
      Offset(dl + cs, dt - co),
    );
    bracket(
      Offset(dr + co, dt + cs),
      Offset(dr + co, dt - co),
      Offset(dr - cs, dt - co),
    );
    bracket(
      Offset(dl - co, db - cs),
      Offset(dl - co, db + co),
      Offset(dl + cs, db + co),
    );
    bracket(
      Offset(dr + co, db - cs),
      Offset(dr + co, db + co),
      Offset(dr - cs, db + co),
    );
  }

  @override
  bool shouldRepaint(_DocScanPainter old) => old.t != t || old.isDark != isDark;
}

// ─── Page 1: OCR / data extraction painter ───────────────────────────────────

class _OcrPainter extends CustomPainter {
  final double t;
  final Color accent;
  final bool isDark;

  const _OcrPainter({
    required this.t,
    required this.accent,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final glowR = size.width * 0.70;
    canvas.drawCircle(
      Offset(cx, cy),
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.28 : 0.18),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowR)),
    );

    final dw = size.width * 0.62;
    final dh = size.height * 0.72;
    final dl = cx - dw / 2;
    final dt = cy - dh / 2 + 2;
    final dr = cx + dw / 2;
    final db = dt + dh;
    final docRRect = RRect.fromLTRBR(dl, dt, dr, db, const Radius.circular(7));

    canvas.drawRRect(
      docRRect.shift(const Offset(0, 7)),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.18 : 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    canvas.drawRRect(
      docRRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.85,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.12 : 0.72),
            accent.withValues(alpha: isDark ? 0.10 : 0.10),
          ],
        ).createShader(Rect.fromLTRB(dl, dt, dr, db)),
    );

    canvas.drawRRect(
      docRRect,
      Paint()
        ..color = accent.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      docRRect,
      Paint()
        ..color = accent.withValues(alpha: 0.60)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    const lineCount = 5;
    final spacing = dh / (lineCount + 1);
    final lineYs = List.generate(lineCount, (i) => dt + spacing * (i + 1));

    final scanT = t <= 0.5 ? t * 2 : (1 - t) * 2;
    final easedScanT = _easeInOut(scanT);
    final scanPosition = easedScanT * (lineCount - 1);
    final segment = scanPosition.floor().clamp(0, lineCount - 2).toInt();
    final segmentT = scanPosition - segment;
    final activeY = _lerp(lineYs[segment], lineYs[segment + 1], segmentT);
    const widthFactors = [0.72, 0.84, 0.78, 0.64, 0.50];

    for (var i = 0; i < lineCount; i++) {
      final influence = _clamp01(1 - (scanPosition - i).abs());
      canvas.drawLine(
        Offset(dl + dw * 0.12, lineYs[i]),
        Offset(dl + dw * widthFactors[i], lineYs[i]),
        Paint()
          ..color = accent.withValues(alpha: 0.18 + influence * 0.28)
          ..strokeWidth = 1.8 + influence * 0.35
          ..strokeCap = StrokeCap.round,
      );
    }

    final windowRect = Rect.fromLTWH(
      dl + dw * 0.09,
      activeY - 12,
      dw * 0.82,
      24,
    );
    final windowRRect = RRect.fromRectAndRadius(
      windowRect,
      const Radius.circular(8),
    );

    canvas.drawRRect(
      windowRRect,
      Paint()
        ..color = accent.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      windowRRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.06 : 0.42),
            accent.withValues(alpha: isDark ? 0.15 : 0.18),
          ],
        ).createShader(windowRect),
    );
    canvas.drawRRect(
      windowRRect,
      Paint()
        ..color = accent.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final cursorX =
        windowRect.left + windowRect.width * (0.14 + easedScanT * 0.72);
    final cursorRect = Rect.fromCenter(
      center: Offset(cursorX, activeY),
      width: dw * 0.18,
      height: 7,
    );
    final cursorRRect = RRect.fromRectAndRadius(
      cursorRect,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      cursorRRect,
      Paint()
        ..color = accent.withValues(alpha: 0.58)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      cursorRRect,
      Paint()..color = accent.withValues(alpha: 0.78),
    );

    final chipX = dl + dw * 0.54;
    final chipY = db - dh * 0.24;
    final chipWidths = [dw * 0.26, dw * 0.20, dw * 0.30];
    for (var i = 0; i < chipWidths.length; i++) {
      final chipRect = Rect.fromLTWH(chipX, chipY + i * 8.5, chipWidths[i], 4);
      final resultAlpha = _clamp01((easedScanT - i * 0.18) / 0.34);
      canvas.drawRRect(
        RRect.fromRectAndRadius(chipRect, const Radius.circular(3)),
        Paint()
          ..color = accent.withValues(alpha: 0.20 + resultAlpha * 0.36)
          ..strokeCap = StrokeCap.round,
      );
    }

    final markCenter = Offset(dr - dw * 0.15, dt + dh * 0.16);
    canvas.drawCircle(
      markCenter,
      7.5,
      Paint()
        ..color = accent.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      markCenter,
      5.2,
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(markCenter.dx - 2.8 + i * 2.8, markCenter.dy),
        0.85,
        Paint()..color = accent.withValues(alpha: 0.74),
      );
    }
  }

  static double _easeInOut(double v) {
    if (v < 0.5) return 2 * v * v;
    final rest = -2 * v + 2;
    return 1 - (rest * rest) / 2;
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

  @override
  bool shouldRepaint(_OcrPainter old) => old.t != t || old.isDark != isDark;
}

// ─── Page 2: cloud sync painter ──────────────────────────────────────────────

class _CloudSyncPainter extends CustomPainter {
  final double t;
  final Color accent;
  final bool isDark;
  final bool uploadComplete;

  const _CloudSyncPainter({
    required this.t,
    required this.accent,
    required this.isDark,
    required this.uploadComplete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Radial gradient glow — no hard-edged circle
    final glowR = size.width * 0.70;
    canvas.drawCircle(
      Offset(cx, cy),
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.28 : 0.18),
            accent.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowR)),
    );

    final cw = size.width * 0.78;
    final ch = size.height * 0.48;
    final cloudCy = cy - size.height * 0.04;
    final cloudPath = _buildCloudPath(cx, cloudCy, cw, ch);

    final pulse = uploadComplete ? _pulse(t) : 0.0;
    final uploadT = uploadComplete
        ? 1.0
        : _easeInOut(_clamp01((t - 0.02) / 0.56));
    final documentAlpha = uploadComplete
        ? 0.0
        : _fadeWindow(t, 0.00, 0.78, 0.08, 0.16);
    final secureT = uploadComplete
        ? 1.0
        : _easeInOut(_clamp01((t - 0.54) / 0.24));
    final secureAlpha = secureT * (0.74 + pulse * 0.22);
    final cloudPulse = uploadComplete
        ? 0.38 + pulse * 0.42
        : _fadeWindow(t, 0.42, 1.0, 0.22, 0.18);

    final start = Offset(cx - size.width * 0.24, cy + size.height * 0.38);
    final end = Offset(cx - size.width * 0.04, cloudCy + ch * 0.18);
    final docCenter = Offset(
      _lerp(start.dx, end.dx, uploadT),
      _lerp(start.dy, end.dy, uploadT),
    );

    final trailAlpha = uploadComplete
        ? 0.0
        : _fadeWindow(t, 0.06, 0.70, 0.10, 0.16);
    final trailRect = Rect.fromPoints(
      Offset(end.dx - 5, end.dy - 4),
      Offset(start.dx + 5, start.dy + 8),
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: trailAlpha * 0.30),
            accent.withValues(alpha: 0),
          ],
        ).createShader(trailRect)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    for (var i = 0; i < 3; i++) {
      final dotStart = 0.08 + i * 0.06;
      final dotT = uploadComplete
          ? 1.0
          : _easeInOut(_clamp01((t - dotStart) / 0.42));
      final dotAlpha = uploadComplete
          ? 0.0
          : _fadeWindow(t, dotStart, 0.70 + i * 0.02, 0.08, 0.14);
      final dot = Offset(
        _lerp(start.dx, end.dx, dotT),
        _lerp(start.dy, end.dy, dotT),
      );
      canvas.drawCircle(
        dot,
        4.0,
        Paint()
          ..color = accent.withValues(alpha: dotAlpha * 0.24)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(
        dot,
        1.7,
        Paint()..color = accent.withValues(alpha: dotAlpha * 0.72),
      );
    }

    _drawMiniDocument(
      canvas,
      docCenter,
      size.width * 0.20,
      documentAlpha,
      _lerp(1.0, 0.78, uploadT),
    );

    // Cloud fill — radial gradient inner glow
    final fillRect = Rect.fromCenter(
      center: Offset(cx, cloudCy + ch * 0.08),
      width: cw * 1.1,
      height: ch * 1.2,
    );
    canvas.drawPath(
      cloudPath.shift(const Offset(0, 7)),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.20 : 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      cloudPath,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0.2),
          radius: 0.75,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.10 : 0.60),
            accent.withValues(
              alpha: (isDark ? 0.16 : 0.12) + cloudPulse * 0.12,
            ),
          ],
        ).createShader(fillRect),
    );

    // Cloud glow stroke (blurred outer halo)
    canvas.drawPath(
      cloudPath,
      Paint()
        ..color = accent.withValues(alpha: 0.28 + cloudPulse * 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Cloud crisp inner stroke
    canvas.drawPath(
      cloudPath,
      Paint()
        ..color = accent.withValues(alpha: 0.68 + cloudPulse * 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    _drawShieldCheck(
      canvas,
      Offset(cx, cloudCy - ch * 0.02),
      size.width * 0.23,
      secureAlpha,
      (0.90 + secureT * 0.08) + pulse * 0.07,
    );
  }

  // Cloud path built via Path.combine union so both fill and stroke are clean.
  static Path _buildCloudPath(double cx, double cy, double cw, double ch) {
    final bodyRect = Rect.fromCenter(
      center: Offset(cx, cy + ch * 0.14),
      width: cw * 0.85,
      height: ch * 0.52,
    );
    final bumpL = Rect.fromCenter(
      center: Offset(cx - cw * 0.22, cy - ch * 0.04),
      width: cw * 0.37,
      height: ch * 0.50,
    );
    final bumpC = Rect.fromCenter(
      center: Offset(cx, cy - ch * 0.20),
      width: cw * 0.44,
      height: ch * 0.56,
    );
    final bumpR = Rect.fromCenter(
      center: Offset(cx + cw * 0.22, cy - ch * 0.04),
      width: cw * 0.37,
      height: ch * 0.50,
    );

    final pBody = Path()
      ..addRRect(RRect.fromRectAndRadius(bodyRect, Radius.circular(ch * 0.22)));
    final pL = Path()..addOval(bumpL);
    final pC = Path()..addOval(bumpC);
    final pR = Path()..addOval(bumpR);

    return Path.combine(
      PathOperation.union,
      Path.combine(PathOperation.union, pBody, pL),
      Path.combine(PathOperation.union, pC, pR),
    );
  }

  void _drawMiniDocument(
    Canvas canvas,
    Offset center,
    double width,
    double alpha,
    double scale,
  ) {
    if (alpha <= 0) return;

    final height = width * 1.16;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-center.dx, -center.dy);

    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(width * 0.16));

    canvas.drawRRect(
      rrect.shift(Offset(0, width * 0.20)),
      Paint()
        ..color = Colors.black.withValues(alpha: alpha * 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.10 : 0.68),
            accent.withValues(alpha: isDark ? 0.16 : 0.16),
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = accent.withValues(alpha: alpha * 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    for (var i = 0; i < 3; i++) {
      final y = rect.top + height * (0.30 + i * 0.20);
      final lineEnd = rect.right - width * (i == 2 ? 0.42 : 0.18);
      canvas.drawLine(
        Offset(rect.left + width * 0.18, y),
        Offset(lineEnd, y),
        Paint()
          ..color = accent.withValues(alpha: alpha * (0.26 + i * 0.05))
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.restore();
  }

  void _drawShieldCheck(
    Canvas canvas,
    Offset center,
    double size,
    double alpha,
    double scale,
  ) {
    if (alpha <= 0) return;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-center.dx, -center.dy);

    final w = size * 0.72;
    final h = size * 0.86;
    final shield = Path()
      ..moveTo(center.dx, center.dy - h * 0.48)
      ..cubicTo(
        center.dx + w * 0.34,
        center.dy - h * 0.46,
        center.dx + w * 0.48,
        center.dy - h * 0.30,
        center.dx + w * 0.48,
        center.dy - h * 0.06,
      )
      ..cubicTo(
        center.dx + w * 0.46,
        center.dy + h * 0.30,
        center.dx + w * 0.18,
        center.dy + h * 0.48,
        center.dx,
        center.dy + h * 0.56,
      )
      ..cubicTo(
        center.dx - w * 0.18,
        center.dy + h * 0.48,
        center.dx - w * 0.46,
        center.dy + h * 0.30,
        center.dx - w * 0.48,
        center.dy - h * 0.06,
      )
      ..cubicTo(
        center.dx - w * 0.48,
        center.dy - h * 0.30,
        center.dx - w * 0.34,
        center.dy - h * 0.46,
        center.dx,
        center.dy - h * 0.48,
      )
      ..close();

    final bounds = Rect.fromCenter(center: center, width: w, height: h);

    canvas.drawPath(
      shield,
      Paint()
        ..color = accent.withValues(alpha: alpha * 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.08 : 0.34),
            accent.withValues(alpha: isDark ? 0.20 : 0.22),
          ],
        ).createShader(bounds),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..color = accent.withValues(alpha: alpha * 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    final check = Path()
      ..moveTo(center.dx - w * 0.20, center.dy + h * 0.02)
      ..lineTo(center.dx - w * 0.04, center.dy + h * 0.17)
      ..lineTo(center.dx + w * 0.24, center.dy - h * 0.15);

    canvas.drawPath(
      check,
      Paint()
        ..color = accent.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();
  }

  static double _easeInOut(double t) {
    if (t < 0.5) return 2 * t * t;
    final v = -2 * t + 2;
    return 1 - (v * v) / 2;
  }

  static double _pulse(double t) {
    final phase = t % 1.0;
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return _easeInOut(wave);
  }

  static double _fadeWindow(
    double t,
    double start,
    double end,
    double fadeIn,
    double fadeOut,
  ) {
    if (t < start || t > end) return 0;
    final inAlpha = _clamp01((t - start) / fadeIn);
    final outAlpha = _clamp01((end - t) / fadeOut);
    return _easeInOut(inAlpha < outAlpha ? inAlpha : outAlpha);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

  @override
  bool shouldRepaint(_CloudSyncPainter old) =>
      old.t != t ||
      old.isDark != isDark ||
      old.uploadComplete != uploadComplete;
}
