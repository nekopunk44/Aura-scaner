import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/app_localizations.dart';

class VoiceNoteScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const VoiceNoteScreen({super.key, this.onSaved});

  @override
  State<VoiceNoteScreen> createState() => _VoiceNoteScreenState();
}

class _VoiceNoteScreenState extends State<VoiceNoteScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentPlayingPath;
  String? _recordingPath;

  int _secondsElapsed = 0;
  Timer? _timer;

  List<_VoiceNote> _notes = [];

  static const _prefsKey = 'voice_note_paths';

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
        if (state == PlayerState.completed) {
          setState(() => _currentPlayingPath = null);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_prefsKey) ?? [];
    final notes = <_VoiceNote>[];
    for (final path in paths) {
      if (await File(path).exists()) {
        final name = path.split('/').last.split('\\').last;
        notes.add(_VoiceNote(path: path, name: name));
      }
    }
    if (notes.length != paths.length) {
      await prefs.setStringList(_prefsKey, notes.map((n) => n.path).toList());
    }
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _savePaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _notes.map((n) => n.path).toList());
  }

  Future<void> _startRecording() async {
    final l10n = AppLocalizations.of(context);
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.voiceNoMicPermission)),
        );
      }
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _recordingPath = '${dir.path}/voice_note_$ts.m4a';

    await _recorder.start(const RecordConfig(), path: _recordingPath!);
    _secondsElapsed = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (mounted) setState(() => _isRecording = false);

    if (path != null && await File(path).exists()) {
      final name = path.split('/').last.split('\\').last;
      final note = _VoiceNote(path: path, name: name);
      setState(() => _notes.insert(0, note));
      await _savePaths();
      widget.onSaved?.call();
    }
  }

  Future<void> _togglePlay(String path) async {
    if (_isPlaying && _currentPlayingPath == path) {
      await _player.stop();
      setState(() { _isPlaying = false; _currentPlayingPath = null; });
      return;
    }
    if (_isPlaying) await _player.stop();
    setState(() => _currentPlayingPath = path);
    await _player.play(DeviceFileSource(path));
  }

  Future<void> _renameNote(_VoiceNote note) async {
    final l10n = AppLocalizations.of(context);
    final originalExt = note.name.contains('.')
        ? note.name.substring(note.name.lastIndexOf('.'))
        : '';
    final originalBase = originalExt.isEmpty
        ? note.name
        : note.name.substring(0, note.name.length - originalExt.length);
    final controller = TextEditingController(text: originalBase);

    final newBase = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
        return AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.dialogRename, style: TextStyle(color: textColor)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.voiceNewName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l10n.actionSave),
            ),
          ],
        );
      },
    );

    if (newBase == null || newBase.isEmpty || newBase == originalBase) return;

    final sanitized = newBase.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (sanitized.isEmpty) return;

    final dirSep = note.path.contains('\\') ? '\\' : '/';
    final dir = note.path.substring(0, note.path.lastIndexOf(dirSep));
    final newPath = '$dir$dirSep$sanitized$originalExt';

    if (newPath == note.path) return;
    if (await File(newPath).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.voiceFileExists)),
      );
      return;
    }

    try {
      if (_currentPlayingPath == note.path) await _player.stop();
      await File(note.path).rename(newPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.voiceRenameError(e.toString()))),
      );
      return;
    }

    final renamed = _VoiceNote(path: newPath, name: '$sanitized$originalExt');
    setState(() {
      final idx = _notes.indexOf(note);
      if (idx != -1) _notes[idx] = renamed;
      if (_currentPlayingPath == note.path) _currentPlayingPath = null;
    });
    await _savePaths();
  }

  Future<void> _deleteNote(_VoiceNote note) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
        return AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.voiceDeleteTitle, style: TextStyle(color: textColor)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.actionCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: Text(l10n.actionDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (_currentPlayingPath == note.path) await _player.stop();
    try { await File(note.path).delete(); } catch (_) {}
    setState(() => _notes.remove(note));
    await _savePaths();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.voiceNotesTitle,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: isDark ? null : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 3)),
              ],
            ),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? Colors.red.withValues(alpha: 0.15)
                        : const Color(0xFF2CA5E0).withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    size: 44,
                    color: _isRecording ? Colors.red : const Color(0xFF2CA5E0),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isRecording ? _formatDuration(_secondsElapsed) : '00:00',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: _isRecording ? Colors.red : textColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isRecording ? l10n.voiceRecording : l10n.voicePressToRecord,
                  style: TextStyle(fontSize: 13, color: subColor),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 160,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                    icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record, size: 20),
                    label: Text(_isRecording ? l10n.voiceStop : l10n.voiceRecord),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red : const Color(0xFF2CA5E0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(l10n.voiceNoteCount(_notes.length),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: subColor, letterSpacing: 0.5)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _notes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.voice_chat, size: 48, color: subColor),
                        const SizedBox(height: 12),
                        Text(l10n.voiceEmpty, style: TextStyle(color: subColor, fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: _notes.length,
                    itemBuilder: (_, i) {
                      final note = _notes[i];
                      final isCurrentlyPlaying = _isPlaying && _currentPlayingPath == note.path;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: isCurrentlyPlaying
                              ? Border.all(color: const Color(0xFF2CA5E0), width: 1.5)
                              : null,
                          boxShadow: isDark ? null : [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => _togglePlay(note.path),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2CA5E0).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isCurrentlyPlaying ? Icons.stop : Icons.play_arrow,
                                  color: const Color(0xFF2CA5E0),
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(note.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: FontWeight.w500, color: textColor, fontSize: 14)),
                                  if (isCurrentlyPlaying)
                                    Text(l10n.voicePlaying,
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF2CA5E0))),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.drive_file_rename_outline, color: subColor, size: 20),
                              tooltip: l10n.dialogRename,
                              onPressed: () => _renameNote(note),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
                              tooltip: l10n.actionDelete,
                              onPressed: () => _deleteNote(note),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _VoiceNote {
  final String path;
  final String name;
  _VoiceNote({required this.path, required this.name});
}
