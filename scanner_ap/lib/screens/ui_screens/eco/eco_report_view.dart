import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/eco_report.dart';
import 'eco_map_screen.dart';

/// Богатое представление структурированного [EcoReport]: эко-балл кольцом,
/// перерабатываемость, материалы, распознанные значки, утилизация, советы и
/// поиск ближайшего пункта приёма. Каждая секция — со своим акцентным цветом
/// (а не сплошной зелёный). Переиспользуется на экране результата и в истории.
class EcoReportView extends StatelessWidget {
  final EcoReport report;

  const EcoReportView({super.key, required this.report});

  // Палитра акцентов по секциям — чтобы экран не был «весь зелёный».
  static const _cMaterials = Color(0xFF2563EB); // синий
  static const _cMarks = Color(0xFF0D9488); // бирюзовый
  static const _cComposition = Color(0xFFD97706); // янтарный
  static const _cDisposal = Color(0xFF7C3AED); // фиолетовый
  static const _cTips = Color(0xFFF59E0B); // оранжевый
  static const _cNearby = Color(0xFF0EA5E9); // голубой

  static Color scoreColor(double s) => s >= 7
      ? const Color(0xFF16A34A)
      : (s >= 4 ? const Color(0xFFD97706) : const Color(0xFFDC2626));

  Color _ratingColor(EcoRating r) {
    switch (r) {
      case EcoRating.good:
        return const Color(0xFF16A34A);
      case EcoRating.medium:
        return const Color(0xFFD97706);
      case EcoRating.bad:
        return const Color(0xFFDC2626);
      case EcoRating.unknown:
        return Colors.grey;
    }
  }

  String _ratingLabel(EcoRating r, AppLocalizations l10n) {
    switch (r) {
      case EcoRating.good:
        return l10n.ecoRatingGood;
      case EcoRating.medium:
        return l10n.ecoRatingMedium;
      case EcoRating.bad:
        return l10n.ecoRatingBad;
      case EcoRating.unknown:
        return l10n.ecoRatingUnknown;
    }
  }

  ({String label, Color color, IconData icon}) _recyclable(
      RecyclableStatus s, AppLocalizations l10n) {
    switch (s) {
      case RecyclableStatus.yes:
        return (label: l10n.ecoRecyclableYes, color: const Color(0xFF16A34A), icon: Icons.recycling);
      case RecyclableStatus.partial:
        return (label: l10n.ecoRecyclablePartial, color: const Color(0xFFD97706), icon: Icons.change_circle_outlined);
      case RecyclableStatus.no:
        return (label: l10n.ecoRecyclableNo, color: const Color(0xFFDC2626), icon: Icons.do_not_disturb_on_outlined);
      case RecyclableStatus.unknown:
        return (label: l10n.ecoRecyclableUnknown, color: Colors.grey, icon: Icons.help_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : const Color(0xFFE8EDF5);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);

    // Сырой текстовый фолбэк (модель не вернула JSON).
    if (!report.isStructured) {
      return _card(
        cardBg, border,
        child: Text(
          report.rawText ?? '',
          style: TextStyle(fontSize: 14, color: textColor, height: 1.55),
        ),
      );
    }

    final score = report.clampedScore;
    final color = scoreColor(score);
    final rec = _recyclable(report.recyclableStatus, l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Шапка: эко-балл кольцом + вердикт ──
        _card(
          cardBg, border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 70,
                          height: 70,
                          child: CircularProgressIndicator(
                            value: score / 10,
                            strokeWidth: 8,
                            strokeCap: StrokeCap.round,
                            backgroundColor: color.withValues(alpha: 0.14),
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                        Text(
                          score.toStringAsFixed(1),
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w800, color: color),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.ecoScoreLabel.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: subColor),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          report.verdict.isNotEmpty
                              ? report.verdict
                              : l10n.ecoVerdictDefault,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                              height: 1.2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (report.summary.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(report.summary,
                    style: TextStyle(fontSize: 13, color: textColor, height: 1.45)),
              ],
            ],
          ),
        ),

        // ── Перерабатываемость ──
        const SizedBox(height: 12),
        _card(
          cardBg, border,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: rec.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(rec.icon, color: rec.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.ecoSectionRecyclable,
                        style: TextStyle(fontSize: 12, color: subColor)),
                    Text(rec.label,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: rec.color)),
                    if (report.recyclableNote.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(report.recyclableNote,
                          style: TextStyle(fontSize: 12.5, color: textColor, height: 1.35)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Где сдать на переработку (карта) ──
        const SizedBox(height: 12),
        _tappableCard(
          cardBg, border,
          accent: _cNearby,
          icon: Icons.location_on_outlined,
          title: l10n.ecoFindNearby,
          subtitle: l10n.ecoFindNearbySub,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EcoMapScreen()),
          ),
        ),

        // ── Материалы ──
        if (report.materials.isNotEmpty)
          _sectionCard(
            cardBg, border, textColor,
            accent: _cMaterials,
            icon: Icons.layers_outlined,
            title: l10n.ecoSectionMaterials,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in report.materials)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _ratingColor(m.rating).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _ratingColor(m.rating).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: _ratingColor(m.rating), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(m.name,
                            style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w600)),
                        Text('  · ${_ratingLabel(m.rating, l10n)}',
                            style: TextStyle(fontSize: 12, color: _ratingColor(m.rating))),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        // ── Распознанные значки маркировки ──
        if (report.marks.isNotEmpty)
          _sectionCard(
            cardBg, border, textColor,
            accent: _cMarks,
            icon: Icons.recycling,
            title: l10n.ecoSectionMarks,
            child: Column(
              children: [
                for (final mk in report.marks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: (mk.recyclable ? _cMarks : Colors.grey)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(mk.code,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: mk.recyclable ? _cMarks : subColor)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(mk.meaning,
                                  style: TextStyle(fontSize: 13, color: textColor, height: 1.35)),
                              Text(
                                mk.recyclable
                                    ? l10n.ecoMarkRecyclable
                                    : l10n.ecoMarkNotRecyclable,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: mk.recyclable ? _cMarks : subColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        // ── Состав ──
        if (report.composition.isNotEmpty)
          _sectionCard(
            cardBg, border, textColor,
            accent: _cComposition,
            icon: Icons.inventory_2_outlined,
            title: l10n.ecoSectionComposition,
            child: Text(report.composition,
                style: TextStyle(fontSize: 13.5, color: textColor, height: 1.5)),
          ),

        // ── Утилизация (нумерованные шаги) ──
        if (report.disposal.isNotEmpty)
          _sectionCard(
            cardBg, border, textColor,
            accent: _cDisposal,
            icon: Icons.delete_sweep_outlined,
            title: l10n.ecoSectionDisposal,
            child: Column(
              children: [
                for (var i = 0; i < report.disposal.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22, height: 22,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: _cDisposal, shape: BoxShape.circle),
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(report.disposal[i],
                              style: TextStyle(fontSize: 13.5, color: textColor, height: 1.45)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

        // ── Советы ──
        if (report.tips.isNotEmpty)
          _sectionCard(
            cardBg, border, textColor,
            accent: _cTips,
            icon: Icons.lightbulb_outline,
            title: l10n.ecoSectionTips,
            child: Column(
              children: [
                for (final t in report.tips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 16, color: _cTips),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(t,
                              style: TextStyle(fontSize: 13.5, color: textColor, height: 1.45)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _card(Color bg, Color border,
      {required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }

  Widget _tappableCard(
    Color bg,
    Color border, {
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: _card(
          bg, border,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700, color: accent)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: accent.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: accent.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(
    Color bg,
    Color border,
    Color textColor, {
    required Color accent,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _card(
        bg, border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: accent),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: textColor)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
