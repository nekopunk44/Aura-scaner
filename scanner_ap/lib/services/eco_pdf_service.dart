import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../l10n/app_localizations.dart';
import '../models/eco_report.dart';

/// Собирает премиальный PDF-отчёт эко-сканера и отдаёт его в системный «Поделиться».
class EcoPdfService {
  static const _green = PdfColor.fromInt(0xFF16A34A);
  static const _amber = PdfColor.fromInt(0xFFD97706);
  static const _red = PdfColor.fromInt(0xFFDC2626);
  static const _ink = PdfColor.fromInt(0xFF1A1A2E);
  static const _muted = PdfColor.fromInt(0xFF6B7A99);

  Future<void> shareReport(
    EcoReport report,
    AppLocalizations l10n, {
    File? sourceImage,
  }) async {
    final bytes = await buildPdf(report, l10n, sourceImage: sourceImage);
    await Printing.sharePdf(bytes: bytes, filename: 'eco_report.pdf');
  }

  Future<Uint8List> buildPdf(
    EcoReport report,
    AppLocalizations l10n, {
    File? sourceImage,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();

    pw.MemoryImage? photo;
    if (sourceImage != null && await sourceImage.exists()) {
      photo = pw.MemoryImage(await sourceImage.readAsBytes());
    }

    PdfColor scoreColor(double s) =>
        s >= 7 ? _green : (s >= 4 ? _amber : _red);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        build: (context) => [
          // Шапка: заголовок + эко-балл.
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(l10n.ecoPdfTitle,
                        style: pw.TextStyle(font: bold, fontSize: 20, color: _ink)),
                    if (report.verdict.isNotEmpty) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(report.verdict,
                          style: pw.TextStyle(fontSize: 12, color: _muted)),
                    ],
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: pw.BoxDecoration(
                  color: scoreColor(report.clampedScore),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(report.clampedScore.toStringAsFixed(1),
                        style: pw.TextStyle(
                            font: bold, fontSize: 22, color: PdfColors.white)),
                    pw.Text('/ 10',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.white)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(l10n.ecoScoreLabel,
              style: pw.TextStyle(fontSize: 10, color: _muted)),
          pw.Divider(color: PdfColors.grey300, height: 24),

          if (photo != null) ...[
            pw.Center(
              child: pw.ClipRRect(
                horizontalRadius: 8,
                verticalRadius: 8,
                child: pw.Image(photo, height: 180, fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 16),
          ],

          if (report.summary.isNotEmpty) ...[
            pw.Text(report.summary,
                style: pw.TextStyle(fontSize: 12, color: _ink, lineSpacing: 2)),
            pw.SizedBox(height: 16),
          ],

          if (report.materials.isNotEmpty)
            _section(l10n.ecoSectionMaterials, [
              for (final m in report.materials)
                _bullet('${m.name}  (${_ratingLabel(m.rating, l10n)})'),
            ]),

          _section(l10n.ecoSectionRecyclable, [
            _bullet(
              '${_recyclableLabel(report.recyclableStatus, l10n)}'
              '${report.recyclableNote.isNotEmpty ? ' — ${report.recyclableNote}' : ''}',
            ),
          ]),

          if (report.composition.isNotEmpty)
            _section(l10n.ecoSectionComposition, [_bullet(report.composition)]),

          if (report.marks.isNotEmpty)
            _section(l10n.ecoSectionMarks, [
              for (final mk in report.marks)
                _bullet('${mk.code} — ${mk.meaning}'),
            ]),

          if (report.disposal.isNotEmpty)
            _section(l10n.ecoSectionDisposal, [
              for (final d in report.disposal) _bullet(d),
            ]),

          if (report.tips.isNotEmpty)
            _section(l10n.ecoSectionTips, [
              for (final t in report.tips) _bullet(t),
            ]),

          if (report.rawText != null && report.rawText!.isNotEmpty)
            pw.Text(report.rawText!,
                style: pw.TextStyle(fontSize: 12, color: _ink, lineSpacing: 2)),

          pw.SizedBox(height: 24),
          pw.Divider(color: PdfColors.grey300),
          pw.Text(l10n.ecoPdfFooter,
              style: pw.TextStyle(fontSize: 9, color: _muted)),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _section(String title, List<pw.Widget> children) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold, color: _green)),
        pw.SizedBox(height: 6),
        ...children,
        pw.SizedBox(height: 14),
      ],
    );
  }

  pw.Widget _bullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('•  ', style: pw.TextStyle(fontSize: 12, color: _muted)),
          pw.Expanded(
            child: pw.Text(text,
                style: pw.TextStyle(fontSize: 12, color: _ink, lineSpacing: 1.5)),
          ),
        ],
      ),
    );
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

  String _recyclableLabel(RecyclableStatus s, AppLocalizations l10n) {
    switch (s) {
      case RecyclableStatus.yes:
        return l10n.ecoRecyclableYes;
      case RecyclableStatus.partial:
        return l10n.ecoRecyclablePartial;
      case RecyclableStatus.no:
        return l10n.ecoRecyclableNo;
      case RecyclableStatus.unknown:
        return l10n.ecoRecyclableUnknown;
    }
  }
}
