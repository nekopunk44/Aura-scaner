import 'package:flutter/material.dart';

const _darkCardTop = Color(0xFF25364B);
const _darkCardBottom = Color(0xFF192637);
const _lightCardTop = Color(0xFFFFFFFF);
const _lightCardBottom = Color(0xFFF4F8FF);
const _premiumAccent = Color(0xFFE8A317);

Color _accentFor({required bool isPremium, required Color iconColor}) {
  return isPremium ? _premiumAccent : iconColor;
}

List<BoxShadow>? _cardShadow(bool isDark, Color accent) {
  if (isDark) {
    return [
      BoxShadow(
        color: accent.withValues(alpha: 0.07),
        blurRadius: 12,
        offset: const Offset(0, 5),
      ),
    ];
  }
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ];
}

BoxDecoration _cardDecoration({
  required bool isDark,
  required Color accent,
  required double radius,
}) {
  final accentWash = Color.lerp(
    isDark ? _darkCardBottom : _lightCardBottom,
    accent,
    isDark ? 0.12 : 0.08,
  )!;

  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: accent.withValues(alpha: isDark ? 0.18 : 0.14)),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        isDark ? _darkCardTop : _lightCardTop,
        isDark ? _darkCardBottom : _lightCardBottom,
        accentWash,
      ],
      stops: const [0, 0.64, 1],
    ),
  );
}

Widget _accentRail(Color accent, {bool horizontal = false}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: [
          accent.withValues(alpha: 0.95),
          accent.withValues(alpha: 0.08),
        ],
      ),
    ),
  );
}

Widget _iconTile(IconData icon, Color accent, bool isDark, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size >= 58 ? 18 : 15),
      border: Border.all(color: accent.withValues(alpha: 0.26)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: isDark ? 0.34 : 0.20),
          accent.withValues(alpha: isDark ? 0.16 : 0.10),
        ],
      ),
    ),
    child: Icon(icon, size: size >= 58 ? 30 : 24, color: accent),
  );
}

Widget _proBadge() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFC56B), _premiumAccent],
      ),
      borderRadius: BorderRadius.circular(999),
      boxShadow: [
        BoxShadow(
          color: _premiumAccent.withValues(alpha: 0.26),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.workspace_premium, size: 10, color: Colors.white),
        SizedBox(width: 3),
        Text(
          'PRO',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0,
          ),
        ),
      ],
    ),
  );
}

Widget _arrowChip(Color accent, bool isDark) {
  return Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: accent.withValues(alpha: isDark ? 0.15 : 0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withValues(alpha: 0.20)),
    ),
    child: Icon(Icons.arrow_forward_rounded, size: 18, color: accent),
  );
}

/// Широкая карточка-хедлайнер категории.
Widget buildFeatureTileWide(
  BuildContext context, {
  required String title,
  required IconData icon,
  required VoidCallback onTap,
  bool isPremium = false,
  String? subtitle,
  Color iconColor = const Color(0xFF2CA5E0),
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = _accentFor(isPremium: isPremium, iconColor: iconColor);
  final titleColor = isDark ? Colors.white : const Color(0xFF172033);
  final subtitleColor = isDark ? Colors.white70 : const Color(0xFF667085);
  const radius = 18.0;

  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: _cardShadow(isDark, accent),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: _cardDecoration(
          isDark: isDark,
          accent: accent,
          radius: radius,
        ),
        child: InkWell(
          onTap: onTap,
          splashColor: accent.withValues(alpha: 0.14),
          highlightColor: accent.withValues(alpha: 0.07),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 14,
                bottom: 14,
                width: 4,
                child: _accentRail(accent),
              ),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    _iconTile(icon, accent, isDark, 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: titleColor,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              if (isPremium) ...[
                                const SizedBox(width: 8),
                                _proBadge(),
                              ],
                            ],
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: subtitleColor,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _arrowChip(accent, isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Карточка инструмента для двухколоночной сетки.
Widget buildFeatureTile(
  BuildContext context, {
  required String title,
  required IconData icon,
  required VoidCallback onTap,
  bool isPremium = false,
  String? subtitle,
  Color iconColor = const Color(0xFF2CA5E0),
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = _accentFor(isPremium: isPremium, iconColor: iconColor);
  final titleColor = isDark ? Colors.white : const Color(0xFF172033);
  final subtitleColor = isDark ? Colors.white60 : const Color(0xFF6B7280);
  const radius = 16.0;

  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: _cardShadow(isDark, accent),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: _cardDecoration(
          isDark: isDark,
          accent: accent,
          radius: radius,
        ),
        child: InkWell(
          onTap: onTap,
          splashColor: accent.withValues(alpha: 0.14),
          highlightColor: accent.withValues(alpha: 0.07),
          child: Container(
            constraints: const BoxConstraints(minHeight: 112),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 14,
                  right: 14,
                  height: 3,
                  child: _accentRail(accent, horizontal: true),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _iconTile(icon, accent, isDark, 40),
                          const Spacer(),
                          if (isPremium) _proBadge(),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                          height: 1.08,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.2,
                            color: subtitleColor,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
