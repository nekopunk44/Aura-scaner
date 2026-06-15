import 'package:flutter/material.dart';

import 'premium_screen.dart';

/// Bottom-sheet «функция только для Premium». Показывается, когда
/// пользователь без подписки тапает по платной функции.
void showPremiumPaywall(BuildContext context, String featureName) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
  final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
  final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.workspace_premium, size: 32, color: Colors.amber.shade600),
          ),
          const SizedBox(height: 16),
          Text(
            'Функция только для Premium',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor),
          ),
          const SizedBox(height: 8),
          Text(
            '«$featureName» доступна в подписке.\nОформите Premium чтобы разблокировать её.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: subColor, height: 1.45),
          ),
          const SizedBox(height: 24),
          _PremiumBenefitRow(icon: Icons.library_books, label: 'Пакетное сканирование (+10 страниц)', isDark: isDark),
          _PremiumBenefitRow(icon: Icons.auto_fix_high, label: 'Восстановление фото и выделение текста', isDark: isDark),
          _PremiumBenefitRow(icon: Icons.lock, label: 'Защита паролем и удаление водяных знаков', isDark: isDark),
          _PremiumBenefitRow(icon: Icons.voice_chat, label: 'Голосовые заметки и Эко-сканер', isDark: isDark, isLast: true),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()));
              },
              child: const Text('Оформить Premium',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Не сейчас', style: TextStyle(color: subColor, fontSize: 14)),
          ),
        ],
      ),
    ),
  );
}

class _PremiumBenefitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool isLast;

  const _PremiumBenefitRow({
    required this.icon,
    required this.label,
    required this.isDark,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final dividerColor = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: Colors.amber.shade600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF3A4558),
                  ),
                ),
              ),
              Icon(Icons.check, size: 16, color: Colors.green.shade400),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: dividerColor),
      ],
    );
  }
}
