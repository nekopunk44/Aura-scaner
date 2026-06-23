import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/eco_history_service.dart';
import '../../../services/eco_pdf_service.dart';
import 'eco_report_view.dart';

/// История премиального эко-сканера: список прошлых анализов упаковки.
class EcoHistoryScreen extends StatefulWidget {
  const EcoHistoryScreen({super.key});

  @override
  State<EcoHistoryScreen> createState() => _EcoHistoryScreenState();
}

class _EcoHistoryScreenState extends State<EcoHistoryScreen> {
  final _service = EcoHistoryService();
  List<EcoHistoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.loadAll();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _delete(EcoHistoryEntry entry) async {
    await _service.remove(entry.id);
    await _load();
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.ecoHistoryTitle),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF16A34A)))
          : _entries.isEmpty
              ? _empty(l10n, subColor)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final entry = _entries[i];
                    final report = entry.report;
                    final score = report.clampedScore;
                    final color = EcoReportView.scoreColor(score);
                    Uint8List? thumb;
                    if (entry.thumbnailBase64.isNotEmpty) {
                      try {
                        thumb = base64Decode(entry.thumbnailBase64);
                      } catch (_) {}
                    }
                    return Dismissible(
                      key: ValueKey(entry.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _delete(entry),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _EcoHistoryDetailScreen(entry: entry),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFF16A34A).withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: thumb != null
                                    ? Image.memory(thumb,
                                        width: 56, height: 56, fit: BoxFit.cover)
                                    : Container(
                                        width: 56, height: 56,
                                        color: color.withValues(alpha: 0.12),
                                        child: Icon(Icons.eco, color: color),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      report.verdict.isNotEmpty
                                          ? report.verdict
                                          : l10n.ecoVerdictDefault,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: textColor),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(_formatDate(entry.createdAt),
                                        style: TextStyle(fontSize: 12, color: subColor)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  score.toStringAsFixed(1),
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: color),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _empty(AppLocalizations l10n, Color subColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco_outlined, size: 64, color: subColor),
            const SizedBox(height: 16),
            Text(l10n.ecoHistoryEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: subColor, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

/// Деталь одной записи истории: полный отчёт + экспорт в PDF.
class _EcoHistoryDetailScreen extends StatefulWidget {
  final EcoHistoryEntry entry;
  const _EcoHistoryDetailScreen({required this.entry});

  @override
  State<_EcoHistoryDetailScreen> createState() => _EcoHistoryDetailScreenState();
}

class _EcoHistoryDetailScreenState extends State<_EcoHistoryDetailScreen> {
  bool _exporting = false;

  Future<void> _exportPdf() async {
    if (_exporting) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _exporting = true);
    try {
      await EcoPdfService().shareReport(widget.entry.report, l10n);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.aiErrorGeneric)),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.ecoTitle),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EcoReportView(report: widget.entry.report),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exporting ? null : _exportPdf,
              icon: _exporting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF16A34A)),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(l10n.ecoExportPdf),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF16A34A),
                side: const BorderSide(color: Color(0xFF16A34A)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
