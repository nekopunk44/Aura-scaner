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

  // Controls the fade-in of the CTA block on the last page
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
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
    final bg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white70 : const Color(0xFF6B7A99);
    final isLast = _currentPage == _pageCount - 1;

    final pages = [
      _OnboardingPage(
        icon: Icons.document_scanner_rounded,
        title: l10n.onboarding1Title,
        description: l10n.onboarding1Desc,
      ),
      _OnboardingPage(
        icon: Icons.auto_awesome_rounded,
        title: l10n.onboarding2Title,
        description: l10n.onboarding2Desc,
      ),
      _OnboardingPage(
        icon: Icons.backup_rounded,
        title: l10n.onboarding3Title,
        description: l10n.onboarding3Desc,
      ),
    ];

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button (top-right)
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
                itemBuilder: (_, i) => pages[i].build(textColor, subColor),
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

            // Bottom action area
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 320),
              crossFadeState: isLast
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              // Non-last: single "Next" button
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
              // Last page: Get Started / Log In / Sign Up block
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

// ─── CTA block shown on the last onboarding slide ───────────────────────────

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
    final subColor =
        isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF6B7A99);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFF2CA5E0).withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Get Started ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _accent,
                    _accentDark,
                  ],
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

          // ── Log In ─────────────────────────────────────────────────────
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

          // ── Sign Up hint ───────────────────────────────────────────────
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

// ─── Single onboarding page content ─────────────────────────────────────────

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  Widget build(Color textColor, Color subColor) {
    const accent = Color(0xFF2CA5E0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.22),
                  accent.withValues(alpha: 0.06),
                ],
                radius: 0.9,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: 0.20),
                width: 1.5,
              ),
            ),
            child: Icon(icon, size: 38, color: accent),
          ),

          const SizedBox(height: 28),

          Text(
            title,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.15,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 12),

          Text(
            description,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 15,
              height: 1.6,
              color: subColor,
            ),
          ),
        ],
      ),
    );
  }
}
