import 'package:flutter/material.dart';

Widget buildFeatureTile(
    BuildContext context, {
      required String title,
      required IconData icon,
      required VoidCallback onTap,
      bool isPremium = false,
      String? subtitle,
      Color iconColor = Colors.blue,
    }) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
  final cardBorder = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8EDF5);
  final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
  final subtitleColor = isDark ? Colors.white38 : Colors.grey.shade500;
  final effectiveIconColor = isPremium ? Colors.amber.shade600 : iconColor;

  return AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: cardBorder, width: 1),
      boxShadow: isDark
          ? null
          : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: effectiveIconColor.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 26, color: effectiveIconColor),
                  const Spacer(),
                  if (isPremium)
                    Icon(Icons.workspace_premium, size: 16, color: Colors.amber.shade600),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: subtitleColor, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
