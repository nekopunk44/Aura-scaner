import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'compress_pdf_screen.dart';
import 'extract_pdf_pages_screen.dart';
import 'merge/merge_documents_screen.dart';
import 'reorder_pdf_pages_screen.dart';

class PdfToolsScreen extends StatelessWidget {
  final VoidCallback? onSaved;
  const PdfToolsScreen({super.key, this.onSaved});

  static const _darkBg = Color(0xFF0F1923);
  static const _darkSurface = Color(0xFF141E2B);
  static const _darkCard = Color(0xFF1E2A3A);
  static const _lightBg = Color(0xFFF2F6FC);
  static const _lightText = Color(0xFF1A1A2E);
  static const _mutedLight = Color(0xFF6B7A99);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? _darkBg : _lightBg;
    final textColor = isDark ? Colors.white : _lightText;

    final tools = [
      _PdfTool(
        icon: Icons.merge_type_rounded,
        color: const Color(0xFFB04BE8),
        title: l10n.featMerge,
        subtitle: l10n.featMergeSub,
        builder: () => MergeDocumentsScreen(onMergeComplete: onSaved),
      ),
      _PdfTool(
        icon: Icons.file_download_outlined,
        color: const Color(0xFF2CA5E0),
        title: l10n.featExtractPages,
        subtitle: l10n.featExtractPagesSub,
        builder: () => ExtractPdfPagesScreen(onPdfSaved: onSaved),
      ),
      _PdfTool(
        icon: Icons.swap_vert_rounded,
        color: const Color(0xFF11A69A),
        title: l10n.featReorderPages,
        subtitle: l10n.featReorderPagesSub,
        builder: () => ReorderPdfPagesScreen(onPdfSaved: onSaved),
      ),
      _PdfTool(
        icon: Icons.compress_rounded,
        color: const Color(0xFFE89012),
        title: l10n.featCompressPdf,
        subtitle: l10n.featCompressPdfSub,
        builder: () => CompressPdfScreen(onPdfSaved: onSaved),
      ),
    ];

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.featPdfTools),
        centerTitle: true,
        backgroundColor: isDark ? _darkSurface : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: [
                        for (final tool in tools) ...[
                          _PdfToolCard(tool: tool, isDark: isDark),
                          if (tool != tools.last) const SizedBox(height: 12),
                        ],
                      ],
                    ),
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

class _PdfToolCard extends StatelessWidget {
  final _PdfTool tool;
  final bool isDark;

  const _PdfToolCard({required this.tool, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? PdfToolsScreen._darkCard : Colors.white;
    final titleColor = isDark ? Colors.white : PdfToolsScreen._lightText;
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : PdfToolsScreen._mutedLight;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      elevation: isDark ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => tool.builder()),
        ),
        splashColor: tool.color.withValues(alpha: 0.14),
        highlightColor: tool.color.withValues(alpha: 0.07),
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        tool.color.withValues(alpha: isDark ? 0.18 : 0.10),
                        tool.color.withValues(alpha: isDark ? 0.04 : 0.03),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.42, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        tool.color.withValues(alpha: 0.4),
                        tool.color,
                        tool.color.withValues(alpha: 0.4),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Row(
                  children: [
                    _ToolIconTile(tool: tool, isDark: isDark),
                    const SizedBox(width: 15),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tool.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tool.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: subtitleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: tool.color.withValues(
                          alpha: isDark ? 0.16 : 0.10,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: tool.color.withValues(
                            alpha: isDark ? 0.14 : 0.10,
                          ),
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.72)
                            : tool.color,
                        size: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolIconTile extends StatelessWidget {
  final _PdfTool tool;
  final bool isDark;

  const _ToolIconTile({required this.tool, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tool.color.withValues(alpha: isDark ? 0.34 : 0.18),
            tool.color.withValues(alpha: isDark ? 0.18 : 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tool.color.withValues(alpha: isDark ? 0.34 : 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: tool.color.withValues(alpha: isDark ? 0.18 : 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.34),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Icon(tool.icon, color: tool.color, size: 27),
        ],
      ),
    );
  }
}

class _PdfTool {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget Function() builder;

  const _PdfTool({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.builder,
  });
}
