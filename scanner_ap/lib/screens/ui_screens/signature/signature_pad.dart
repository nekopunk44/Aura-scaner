import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  static const List<double> _widths = [2, 3, 5, 8];
  double _strokeWidth = 3;

  late SignatureController _controller = _makeController();

  SignatureController _makeController({List<Point>? points}) {
    final c = SignatureController(
      penStrokeWidth: _strokeWidth,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
      points: points,
    );
    c.addListener(() {
      if (mounted) setState(() {});
    });
    return c;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setStrokeWidth(double w) {
    if (w == _strokeWidth) return;
    final preserved = List<Point>.from(_controller.points);
    _controller.dispose();
    setState(() {
      _strokeWidth = w;
      _controller = _makeController(points: preserved);
    });
  }

  Future<Uint8List?> _export() async {
    if (_controller.isEmpty) return null;
    return _controller.toPngBytes();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canUndo = _controller.points.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить подпись'),
        actions: [
          IconButton(
            tooltip: 'Отменить',
            onPressed: canUndo ? _controller.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Повторить',
            onPressed: _controller.redo,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Signature(
                      controller: _controller,
                      backgroundColor: scheme.surface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Толщина:', style: theme.textTheme.bodyMedium),
                const SizedBox(width: 8),
                for (final w in _widths)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(w.toStringAsFixed(0)),
                      selected: _strokeWidth == w,
                      onSelected: (_) => _setStrokeWidth(w),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton.icon(
                    onPressed: canUndo ? _controller.clear : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Очистить'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  Builder(builder: (btnContext) {
                    return FilledButton.icon(
                      onPressed: canUndo
                          ? () async {
                              final bytes = await _export();
                              if (bytes == null) return;
                              if (!btnContext.mounted) return;
                              Navigator.pop(btnContext, bytes);
                            }
                          : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Готово'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
