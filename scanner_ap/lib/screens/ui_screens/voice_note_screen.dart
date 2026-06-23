import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/app_localizations.dart';
import '../../services/voice_transcription_service.dart';

class VoiceNoteScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const VoiceNoteScreen({super.key, this.onSaved});

  @override
  State<VoiceNoteScreen> createState() => _VoiceNoteScreenState();
}

class _VoiceNoteScreenState extends State<VoiceNoteScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<Amplitude>? _amplitudeSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _playerPositionSubscription;
  StreamSubscription<Duration>? _playerDurationSubscription;

  bool _isRecording = false;
  bool _isRecorderBusy = false;
  bool _isPlaying = false;
  String? _currentPlayingPath;
  String? _recordingPath;

  int _secondsElapsed = 0;
  DateTime? _recordingStartedAt;
  Timer? _timer;
  double _voiceLevel = 0;
  List<double> _voiceHistory = List<double>.filled(48, 0);

  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  List<_VoiceNote> _notes = [];
  final Map<String, int> _durationMsByPath = {};
  final Map<String, String> _transcripts = {};
  final Set<String> _transcribingPaths = {};

  static const _prefsKey = 'voice_note_paths';
  static const _durationPrefsKey = 'voice_note_duration_ms';

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _currentPlayingPath = null;
            _playbackPosition = Duration.zero;
          }
        });
      }
    });
    _playerPositionSubscription = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _playbackPosition = position);
    });
    _playerDurationSubscription = _player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _playbackDuration = duration);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playerPositionSubscription?.cancel();
    _playerDurationSubscription?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_prefsKey) ?? [];
    final savedDurations = prefs.getString(_durationPrefsKey);
    if (savedDurations != null) {
      try {
        final decoded = jsonDecode(savedDurations);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is num && value > 0) {
              _durationMsByPath[entry.key] = value.round();
            }
          }
        }
      } catch (_) {}
    }

    final notes = <_VoiceNote>[];
    var durationsChanged = false;
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        final stat = await file.stat();
        final name = path.split('/').last.split('\\').last;
        var durationMs = _durationMsByPath[path] ?? 0;
        if (durationMs <= 0) {
          final duration = await _probeDuration(path);
          durationMs = duration.inMilliseconds;
          if (durationMs > 0) {
            _durationMsByPath[path] = durationMs;
            durationsChanged = true;
          }
        }
        notes.add(
          _VoiceNote(
            path: path,
            name: name,
            modifiedAt: stat.modified,
            sizeInBytes: stat.size,
            duration: Duration(milliseconds: durationMs),
          ),
        );
        final transcriptFile = File(_transcriptPath(path));
        if (await transcriptFile.exists()) {
          final transcript = (await transcriptFile.readAsString()).trim();
          if (transcript.isNotEmpty) _transcripts[path] = transcript;
        }
      }
    }
    final validPaths = notes.map((note) => note.path).toSet();
    final durationCount = _durationMsByPath.length;
    _durationMsByPath.removeWhere((path, _) => !validPaths.contains(path));
    if (_durationMsByPath.length != durationCount) durationsChanged = true;

    if (notes.length != paths.length || durationsChanged) {
      await Future.wait([
        prefs.setStringList(_prefsKey, notes.map((note) => note.path).toList()),
        prefs.setString(_durationPrefsKey, jsonEncode(_durationMsByPath)),
      ]);
    }
    if (mounted) setState(() => _notes = notes);
  }

  Future<void> _savePaths() async {
    final prefs = await SharedPreferences.getInstance();
    final validPaths = _notes.map((note) => note.path).toSet();
    _durationMsByPath.removeWhere((path, _) => !validPaths.contains(path));
    await Future.wait([
      prefs.setStringList(_prefsKey, _notes.map((note) => note.path).toList()),
      prefs.setString(_durationPrefsKey, jsonEncode(_durationMsByPath)),
    ]);
  }

  Future<Duration> _probeDuration(String path) async {
    final probe = AudioPlayer();
    try {
      await probe.setSource(DeviceFileSource(path));
      return await probe.getDuration() ?? Duration.zero;
    } catch (_) {
      return Duration.zero;
    } finally {
      await probe.dispose();
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecorderBusy) return;
    await HapticFeedback.mediumImpact();
    if (mounted) setState(() => _isRecorderBusy = true);
    try {
      if (_isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
    } finally {
      if (mounted) setState(() => _isRecorderBusy = false);
    }
  }

  Future<void> _startRecording() async {
    final l10n = AppLocalizations.of(context);
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.voiceNoMicPermission)));
      }
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _recordingPath = '${dir.path}/voice_note_$ts.m4a';

    await _recorder.start(const RecordConfig(), path: _recordingPath!);
    _secondsElapsed = 0;
    _recordingStartedAt = DateTime.now();
    _voiceLevel = 0;
    _voiceHistory = List<double>.filled(48, 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _recordingStartedAt;
      if (mounted && startedAt != null) {
        setState(() {
          _secondsElapsed = DateTime.now().difference(startedAt).inSeconds;
        });
      }
    });
    if (mounted) {
      setState(() => _isRecording = true);
    }
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 70))
        .listen(_handleAmplitude);
  }

  void _handleAmplitude(Amplitude amplitude) {
    if (!mounted || !_isRecording) return;

    const noiseFloorDb = -52.0;
    final currentDb = amplitude.current.isFinite
        ? amplitude.current
        : noiseFloorDb;
    final normalized = ((currentDb - noiseFloorDb) / -noiseFloorDb)
        .clamp(0.0, 1.0)
        .toDouble();
    final shaped = math.pow(normalized, 1.45).toDouble();
    final smoothing = shaped > _voiceLevel ? 0.72 : 0.24;
    final nextLevel = (_voiceLevel + (shaped - _voiceLevel) * smoothing)
        .clamp(0.0, 1.0)
        .toDouble();

    setState(() {
      _voiceLevel = nextLevel;
      _voiceHistory = [..._voiceHistory.skip(1), nextLevel];
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final startedAt = _recordingStartedAt;
    final recordedDuration = startedAt == null
        ? Duration(seconds: math.max(1, _secondsElapsed))
        : DateTime.now().difference(startedAt);
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final path = await _recorder.stop();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingStartedAt = null;
        _voiceLevel = 0;
        _voiceHistory = List<double>.filled(48, 0);
      });
    }

    if (path != null && await File(path).exists()) {
      final stat = await File(path).stat();
      final name = path.split('/').last.split('\\').last;
      final note = _VoiceNote(
        path: path,
        name: name,
        modifiedAt: stat.modified,
        sizeInBytes: stat.size,
        duration: recordedDuration,
      );
      setState(() {
        _notes.insert(0, note);
        _durationMsByPath[path] = recordedDuration.inMilliseconds;
      });
      await _savePaths();
      widget.onSaved?.call();
      if (mounted) _showNoteSavedSnackBar(note);
    }
  }

  void _showNoteSavedSnackBar(_VoiceNote note) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 7),
          backgroundColor: isDark
              ? const Color(0xFF243348)
              : const Color(0xFF172438),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: Color(0xFF52D79A),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.voiceNoteSaved,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 2,
                runSpacing: 0,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF55BDF0),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      messenger.hideCurrentSnackBar();
                      unawaited(_renameNote(note));
                    },
                    child: Text(l10n.dialogRename),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF55BDF0),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      messenger.hideCurrentSnackBar();
                      unawaited(_transcribeNote(note));
                    },
                    child: Text(l10n.voiceTranscribe),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _togglePlay(String path) async {
    if (_isPlaying && _currentPlayingPath == path) {
      await _player.stop();
      setState(() {
        _isPlaying = false;
        _currentPlayingPath = null;
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
      });
      return;
    }
    if (_isPlaying) await _player.stop();
    setState(() {
      _currentPlayingPath = path;
      _playbackPosition = Duration.zero;
      _playbackDuration = Duration.zero;
    });
    await _player.play(DeviceFileSource(path));
  }

  String _transcriptPath(String audioPath) => '$audioPath.transcript.txt';

  String _transcriptionErrorText(
    AppLocalizations l10n,
    VoiceTranscriptionErrorKind kind,
  ) {
    return switch (kind) {
      VoiceTranscriptionErrorKind.unavailable =>
        l10n.voiceTranscriptUnavailable,
      VoiceTranscriptionErrorKind.timeout => l10n.voiceTranscriptTimeout,
      VoiceTranscriptionErrorKind.tooLarge => l10n.voiceTranscriptTooLarge,
      VoiceTranscriptionErrorKind.noSpeech => l10n.voiceTranscriptNoSpeech,
      VoiceTranscriptionErrorKind.generic => l10n.voiceTranscriptError,
    };
  }

  Future<void> _transcribeNote(_VoiceNote note) async {
    final cachedTranscript = _transcripts[note.path];
    if (cachedTranscript != null) {
      await _showTranscript(note, cachedTranscript);
      return;
    }
    if (_transcribingPaths.contains(note.path)) return;

    setState(() => _transcribingPaths.add(note.path));
    try {
      final transcript = await VoiceTranscriptionService().transcribe(
        File(note.path),
      );
      await File(
        _transcriptPath(note.path),
      ).writeAsString(transcript, flush: true);
      if (!mounted) return;
      setState(() => _transcripts[note.path] = transcript);
      await _showTranscript(note, transcript);
    } on VoiceTranscriptionException catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_transcriptionErrorText(l10n, error.kind))),
        );
    } finally {
      if (mounted) {
        setState(() => _transcribingPaths.remove(note.path));
      }
    }
  }

  Future<void> _showTranscript(_VoiceNote note, String transcript) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1A283A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);
    const accent = Color(0xFF2CA5E0);
    var copied = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: 0.72,
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: subColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.subject_rounded,
                        color: accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.voiceTranscriptTitle,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _displayName(note, l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: subColor, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      tooltip: MaterialLocalizations.of(
                        sheetContext,
                      ).closeButtonTooltip,
                      icon: Icon(Icons.close_rounded, color: subColor),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.16)
                          : const Color(0xFFF5F8FC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        transcript,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: copied
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: transcript),
                            );
                            if (!sheetContext.mounted) return;
                            setSheetState(() => copied = true);
                          },
                    icon: Icon(
                      copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 20,
                    ),
                    label: Text(
                      copied ? l10n.voiceTranscriptCopied : l10n.copy,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.voiceFileExists)));
      return;
    }

    try {
      if (_currentPlayingPath == note.path) await _player.stop();
      await File(note.path).rename(newPath);
      final oldTranscriptFile = File(_transcriptPath(note.path));
      if (await oldTranscriptFile.exists()) {
        try {
          await oldTranscriptFile.rename(_transcriptPath(newPath));
        } catch (_) {
          final transcript = _transcripts[note.path];
          if (transcript != null) {
            await File(
              _transcriptPath(newPath),
            ).writeAsString(transcript, flush: true);
          }
          try {
            await oldTranscriptFile.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.voiceRenameError(e.toString()))),
      );
      return;
    }

    final renamed = _VoiceNote(
      path: newPath,
      name: '$sanitized$originalExt',
      modifiedAt: note.modifiedAt,
      sizeInBytes: note.sizeInBytes,
      duration: note.duration,
    );
    setState(() {
      final idx = _notes.indexOf(note);
      if (idx != -1) _notes[idx] = renamed;
      if (_currentPlayingPath == note.path) _currentPlayingPath = null;
      final transcript = _transcripts.remove(note.path);
      if (transcript != null) _transcripts[newPath] = transcript;
      final durationMs = _durationMsByPath.remove(note.path);
      if (durationMs != null) _durationMsByPath[newPath] = durationMs;
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            l10n.voiceDeleteTitle,
            style: TextStyle(color: textColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.actionCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.actionDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (_currentPlayingPath == note.path) await _player.stop();
    try {
      await File(note.path).delete();
    } catch (_) {}
    try {
      final transcriptFile = File(_transcriptPath(note.path));
      if (await transcriptFile.exists()) await transcriptFile.delete();
    } catch (_) {}
    setState(() {
      _notes.remove(note);
      _transcripts.remove(note.path);
      _durationMsByPath.remove(note.path);
    });
    await _savePaths();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatNoteDuration(Duration duration) {
    if (duration <= Duration.zero) return '';
    final seconds = math.max(1, (duration.inMilliseconds / 1000).ceil());
    return _formatDuration(seconds);
  }

  String _displayName(_VoiceNote note, AppLocalizations l10n) {
    final extensionIndex = note.name.lastIndexOf('.');
    final baseName = extensionIndex > 0
        ? note.name.substring(0, extensionIndex)
        : note.name;
    if (RegExp(r'^voice_note_\d+$').hasMatch(baseName)) {
      return l10n.featVoiceNote;
    }
    return baseName;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _noteMeta(BuildContext context, _VoiceNote note) {
    final localizations = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateFormat.yMd(locale).format(note.modifiedAt);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(note.modifiedAt),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final duration = _formatNoteDuration(note.duration);
    return [
      if (duration.isNotEmpty) duration,
      '$date, $time',
      _formatFileSize(note.sizeInBytes),
    ].join('  •  ');
  }

  double get _playbackProgress {
    if (_playbackDuration.inMilliseconds <= 0) return 0;
    return (_playbackPosition.inMilliseconds / _playbackDuration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  Widget _buildRecorderCard({
    required AppLocalizations l10n,
    required bool isDark,
    required Color textColor,
    required Color subColor,
  }) {
    const accent = Color(0xFF2CA5E0);
    const recordingColor = Color(0xFFFF5A63);
    final activeColor = _isRecording ? recordingColor : accent;
    final recordActionLabel = _isRecording ? l10n.voiceStop : l10n.voiceRecord;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF202E42), const Color(0xFF182638)]
              : [Colors.white, const Color(0xFFF7FBFF)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _isRecording
              ? recordingColor.withValues(alpha: 0.45)
              : accent.withValues(alpha: isDark ? 0.2 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: activeColor.withValues(alpha: isDark ? 0.12 : 0.14),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -26,
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 142,
              color: activeColor.withValues(alpha: isDark ? 0.035 : 0.045),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: activeColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: activeColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: activeColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRecording
                            ? l10n.voiceRecording
                            : l10n.voiceReadyToRecord,
                        style: TextStyle(
                          color: activeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 132,
                  height: 132,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: _isRecording ? _voiceLevel : 0),
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOutCubic,
                    builder: (context, level, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.scale(
                            scale: 0.88 + (level * 0.16),
                            child: Container(
                              width: 128,
                              height: 128,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: activeColor.withValues(
                                  alpha: 0.035 + (level * 0.09),
                                ),
                                border: Border.all(
                                  color: activeColor.withValues(
                                    alpha: 0.08 + (level * 0.22),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          CustomPaint(
                            size: const Size.square(132),
                            painter: _VoiceWavePainter(
                              samples: _voiceHistory,
                              level: level,
                              color: activeColor,
                              isRecording: _isRecording,
                            ),
                          ),
                          Transform.scale(
                            scale: 1 + (level * 0.08),
                            child: Tooltip(
                              message: recordActionLabel,
                              child: Semantics(
                                button: true,
                                enabled: !_isRecorderBusy,
                                label: recordActionLabel,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _isRecorderBusy
                                      ? null
                                      : _toggleRecording,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: activeColor.withValues(
                                        alpha: 0.14 + (level * 0.1),
                                      ),
                                      border: Border.all(
                                        color: activeColor.withValues(
                                          alpha: 0.28 + (level * 0.34),
                                        ),
                                      ),
                                      boxShadow: _isRecording
                                          ? [
                                              BoxShadow(
                                                color: activeColor.withValues(
                                                  alpha: 0.12 + (level * 0.24),
                                                ),
                                                blurRadius: 12 + (level * 20),
                                                spreadRadius: level * 4,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Transform.scale(
                                      scale: 1 + (level * 0.08),
                                      child: ExcludeSemantics(
                                        child: Icon(
                                          _isRecording
                                              ? Icons.mic_rounded
                                              : Icons.mic_none_rounded,
                                          size: 40,
                                          color: activeColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: _isRecording ? 42 : 30,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    letterSpacing: _isRecording ? -1.5 : -0.8,
                    color: _isRecording
                        ? recordingColor
                        : textColor.withValues(alpha: 0.58),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  child: Text(
                    _isRecording ? _formatDuration(_secondsElapsed) : '00:00',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _isRecorderBusy ? null : _toggleRecording,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        _isRecording
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded,
                        key: ValueKey(_isRecording),
                        size: 21,
                      ),
                    ),
                    label: Text(
                      recordActionLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: activeColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required AppLocalizations l10n,
    required Color cardBg,
    required Color textColor,
    required Color subColor,
    required bool isDark,
  }) {
    const accent = Color(0xFF2CA5E0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black12,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.multitrack_audio_rounded,
              size: 32,
              color: accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.voiceEmpty,
            style: TextStyle(
              color: textColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.voicePressToRecord,
            textAlign: TextAlign.center,
            style: TextStyle(color: subColor, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard({
    required _VoiceNote note,
    required AppLocalizations l10n,
    required Color cardBg,
    required Color textColor,
    required Color subColor,
    required bool isDark,
  }) {
    const accent = Color(0xFF2CA5E0);
    final isCurrentlyPlaying = _isPlaying && _currentPlayingPath == note.path;
    final isTranscribing = _transcribingPaths.contains(note.path);
    final isActive = isCurrentlyPlaying || isTranscribing;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _togglePlay(note.path),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isActive
                    ? accent.withValues(alpha: 0.7)
                    : isDark
                    ? Colors.white.withValues(alpha: 0.055)
                    : Colors.black.withValues(alpha: 0.055),
                width: isActive ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _togglePlay(note.path),
                  tooltip: isCurrentlyPlaying
                      ? l10n.voiceStop
                      : l10n.voicePlaying,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    backgroundColor: accent.withValues(
                      alpha: isCurrentlyPlaying ? 0.2 : 0.1,
                    ),
                    foregroundColor: accent,
                  ),
                  icon: Icon(
                    isCurrentlyPlaying
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName(note, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: textColor,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          isTranscribing
                              ? l10n.voiceTranscribing
                              : isCurrentlyPlaying
                              ? l10n.voicePlaying
                              : _noteMeta(context, note),
                          key: ValueKey((isTranscribing, isCurrentlyPlaying)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isActive ? accent : subColor,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(height: 9),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: isTranscribing ? null : _playbackProgress,
                            minHeight: 3,
                            backgroundColor: accent.withValues(alpha: 0.13),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<_NoteAction>(
                  color: cardBg,
                  surfaceTintColor: Colors.transparent,
                  iconColor: subColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _NoteAction.transcribe:
                        _transcribeNote(note);
                        break;
                      case _NoteAction.rename:
                        _renameNote(note);
                        break;
                      case _NoteAction.delete:
                        _deleteNote(note);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _NoteAction.transcribe,
                      enabled: !isTranscribing,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: isTranscribing
                                ? const CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: accent,
                                  )
                                : const Icon(
                                    Icons.subject_rounded,
                                    size: 20,
                                    color: accent,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _transcripts.containsKey(note.path)
                                ? l10n.voiceViewTranscript
                                : l10n.voiceTranscribe,
                            style: TextStyle(
                              color: isTranscribing ? subColor : textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _NoteAction.rename,
                      enabled: !isTranscribing,
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 20, color: subColor),
                          const SizedBox(width: 12),
                          Text(
                            l10n.dialogRename,
                            style: TextStyle(color: textColor),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: _NoteAction.delete,
                      enabled: !isTranscribing,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: Color(0xFFFF6B72),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l10n.actionDelete,
                            style: const TextStyle(color: Color(0xFFFF6B72)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF0F1923)
        : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 4,
        title: Text(
          l10n.voiceNotesTitle,
          style: TextStyle(
            color: textColor,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
          ),
        ),
        backgroundColor: appBarBg,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _buildRecorderCard(
                l10n: l10n,
                isDark: isDark,
                textColor: textColor,
                subColor: subColor,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    l10n.voiceNoteCount(_notes.length),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_notes.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverToBoxAdapter(
                child: _buildEmptyState(
                  l10n: l10n,
                  cardBg: cardBg,
                  textColor: textColor,
                  subColor: subColor,
                  isDark: isDark,
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList.builder(
                itemCount: _notes.length,
                itemBuilder: (context, index) => _buildNoteCard(
                  note: _notes[index],
                  l10n: l10n,
                  cardBg: cardBg,
                  textColor: textColor,
                  subColor: subColor,
                  isDark: isDark,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  final List<double> samples;
  final double level;
  final Color color;
  final bool isRecording;

  const _VoiceWavePainter({
    required this.samples,
    required this.level,
    required this.color,
    required this.isRecording,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isRecording || samples.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.shortestSide * 0.35;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < samples.length; index++) {
      final sample = math.max(samples[index], level * 0.16);
      final angle = (math.pi * 2 * index / samples.length) - (math.pi / 2);
      final waveLength = 2.5 + (sample * 13);
      final startRadius = baseRadius + 2;
      final endRadius = startRadius + waveLength;
      final direction = Offset(math.cos(angle), math.sin(angle));

      paint
        ..color = color.withValues(alpha: 0.18 + (sample * 0.66))
        ..strokeWidth = 1.8 + (sample * 1.4);
      canvas.drawLine(
        center + (direction * startRadius),
        center + (direction * endRadius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) {
    return oldDelegate.level != level ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.color != color ||
        !identical(oldDelegate.samples, samples);
  }
}

enum _NoteAction { transcribe, rename, delete }

class _VoiceNote {
  final String path;
  final String name;
  final DateTime modifiedAt;
  final int sizeInBytes;
  final Duration duration;

  const _VoiceNote({
    required this.path,
    required this.name,
    required this.modifiedAt,
    required this.sizeInBytes,
    required this.duration,
  });
}
