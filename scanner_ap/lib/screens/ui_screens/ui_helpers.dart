import 'package:flutter/material.dart';

/// Карточка инструмента для AllActionsScreen.
///
/// Структура:
/// - Левый верхний угол: квадратный icon-tile с заливкой полупрозрачного
///   акцента (цвет диктует `iconColor`). Premium-карточки используют
///   amber-палитру независимо от `iconColor`.
/// - Под иконкой — заголовок (15px w700) + subtitle (12px subtle).
/// - В правом верхнем углу Premium-бейдж в виде золотой пилюли с
///   корoной — выделяется на белом фоне карточки.
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
  final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
  final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
  final subtitleColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
  final effectiveIconColor = isPremium ? const Color(0xFFE8A317) : iconColor;
  final iconBg = effectiveIconColor.withValues(alpha: isDark ? 0.22 : 0.13);

  return Material(
    color: cardBg,
    borderRadius: BorderRadius.circular(18),
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      splashColor: effectiveIconColor.withValues(alpha: 0.12),
      highlightColor: effectiveIconColor.withValues(alpha: 0.06),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: effectiveIconColor),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: subtitleColor,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
            if (isPremium)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFC56B), Color(0xFFE8A317)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium,
                          size: 11, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'PRO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
