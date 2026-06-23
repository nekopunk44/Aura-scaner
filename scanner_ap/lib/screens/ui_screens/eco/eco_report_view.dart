import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/eco_report.dart';

/// Богатое представление структурированного [EcoReport]: эко-балл кольцом,
/// перерабатываемость, материалы, распознанные значки, утилизация и советы.
/// Переиспользуется на экране результата и в детале истории.
class EcoReportView extends StatelessWidget {
  final EcoReport report;

  const EcoReportView({super.key, required this.report});

  static Color scoreColor(double s) =>
      s >= 7 ? const Color(0xFF16A34A) : (s >= 4 ? const Color(0xFFD97706) : const Color(0xFFDC2626));

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
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);

    // Сырой текстовый фолбэк (модель не вернула JSON).
    if (!report.isStructured) {
      return _card(
        cardBg,
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
        // ── Шапка: эко-балл кольцом + вердикт/резюме ──
        _card(
          cardBg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 78,
                      height: 78,
                      child: CircularProgressIndicator(
                        value: score / 10,
                        strokeWidth: 7,
                        backgroundColor: color.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          score.toStringAsFixed(1),
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800, color: color),
                        ),
                        Text('/ 10',
                            style: TextStyle(fontSize: 10, color: subColor)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      report.verdict.isNotEmpty
                          ? report.verdict
                          : l10n.ecoVerdictDefault,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: textColor),
                    ),
                    Text(l10n.ecoScoreLabel,
                        style: TextStyle(fontSize: 12, color: subColor)),
                    if (report.summary.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(report.summary,
                          style: TextStyle(fontSize: 13, color: textColor, height: 1.45)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Перерабатываемость ──
        const SizedBox(height: 12),
        _card(
          cardBg,
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

        // ── Материалы ──
        if (report.materials.isNotEmpty)
          _sectionCard(
            cardBg, textColor, subColor,
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
            cardBg, textColor, subColor,
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
                            color: (mk.recyclable ? const Color(0xFF16A34A) : Colors.grey)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(mk.code,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: mk.recyclable ? const Color(0xFF16A34A) : subColor)),
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
                                    color: mk.recyclable ? const Color(0xFF16A34A) : subColor),
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
            cardBg, textColor, subColor,
            icon: Icons.inventory_2_outlined,
            title: l10n.ecoSectionComposition,
            child: Text(report.composition,
                style: TextStyle(fontSize: 13.5, color: textColor, height: 1.5)),
          ),

        // ── Утилизация (нумерованные шаги) ──
        if (report.disposal.isNotEmpty)
          _sectionCard(
            cardBg, textColor, subColor,
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
                            color: Color(0xFF16A34A), shape: BoxShape.circle),
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
            cardBg, textColor, subColor,
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
                        const Icon(Icons.eco, size: 16, color: Color(0xFF16A34A)),
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

  Widget _card(Color bg,
      {required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.18)),
      ),
      child: child,
    );
  }

  Widget _sectionCard(
    Color bg,
    Color textColor,
    Color subColor, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _card(
        bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF16A34A)),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
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
