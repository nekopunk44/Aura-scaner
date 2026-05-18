import 'dart:io';
import 'package:dio/dio.dart';
import 'api_service.dart';

class RemoteDocument {
  final String id;
  final String name;
  final String format;
  final int fileSize;
  final DateTime createdAt;

  const RemoteDocument({
    required this.id,
    required this.name,
    required this.format,
    required this.fileSize,
    required this.createdAt,
  });

  factory RemoteDocument.fromJson(Map<String, dynamic> json) => RemoteDocument(
        id: json['_id'] as String,
        name: json['name'] as String,
        format: json['format'] as String,
        fileSize: json['fileSize'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class DocumentSyncService {
  final _api = ApiService();

  Future<RemoteDocument> upload(File file, {String? name}) async {
    final fileName = name ?? file.uri.pathSegments.last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      if (name != null) 'name': name,
    });
    try {
      await _api.syncBaseUrl();
      final response = await _api.dio.post('/documents/upload', data: formData);
      return RemoteDocument.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<RemoteDocument>> list() async {
    try {
      await _api.syncBaseUrl();
      final response = await _api.dio.get('/documents');
      return (response.data as List)
          .map((e) => RemoteDocument.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> download(String id, String savePath) async {
    try {
      await _api.syncBaseUrl();
      await _api.dio.download('/documents/$id/download', savePath);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<RemoteDocument> rename(String id, String newName) async {
    try {
      await _api.syncBaseUrl();
      final response = await _api.dio.patch('/documents/$id', data: {'name': newName});
      return RemoteDocument.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _api.syncBaseUrl();
      await _api.dio.delete('/documents/$id');
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  String _parseError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) return data['message'] as String;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Нет соединения с сервером';
    }
    return 'Ошибка сети';
  }
}
