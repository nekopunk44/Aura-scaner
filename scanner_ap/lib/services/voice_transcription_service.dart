import 'dart:io';

import 'package:dio/dio.dart';

import 'api_service.dart';

enum VoiceTranscriptionErrorKind {
  unavailable,
  timeout,
  tooLarge,
  noSpeech,
  generic,
}

class VoiceTranscriptionException implements Exception {
  final VoiceTranscriptionErrorKind kind;

  const VoiceTranscriptionException(this.kind);
}

class VoiceTranscriptionService {
  static final VoiceTranscriptionService _instance =
      VoiceTranscriptionService._internal();

  factory VoiceTranscriptionService() => _instance;

  VoiceTranscriptionService._internal();

  Future<String> transcribe(File audioFile) async {
    try {
      final fileName = audioFile.path.split(RegExp(r'[/\\]')).last;
      final response = await ApiService().dio.post(
        '/ai/transcribe',
        data: FormData.fromMap({
          'audio': await MultipartFile.fromFile(
            audioFile.path,
            filename: fileName,
          ),
        }),
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: const Duration(seconds: 210),
        ),
      );
      final text = response.data?['text'];
      if (text is! String || text.trim().isEmpty) {
        throw const VoiceTranscriptionException(
          VoiceTranscriptionErrorKind.noSpeech,
        );
      }
      return text.trim();
    } on VoiceTranscriptionException {
      rethrow;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const VoiceTranscriptionException(
          VoiceTranscriptionErrorKind.timeout,
        );
      }

      final status = error.response?.statusCode ?? 0;
      if (status == 413) {
        throw const VoiceTranscriptionException(
          VoiceTranscriptionErrorKind.tooLarge,
        );
      }
      if (status == 422) {
        throw const VoiceTranscriptionException(
          VoiceTranscriptionErrorKind.noSpeech,
        );
      }
      if (status == 0 || status >= 500) {
        throw const VoiceTranscriptionException(
          VoiceTranscriptionErrorKind.unavailable,
        );
      }
      throw const VoiceTranscriptionException(
        VoiceTranscriptionErrorKind.generic,
      );
    } catch (_) {
      throw const VoiceTranscriptionException(
        VoiceTranscriptionErrorKind.generic,
      );
    }
  }
}
