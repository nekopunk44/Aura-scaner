import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_ap/utils/error_messages.dart';

DioException _dio(DioExceptionType type, {int? status, Object? data}) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    type: type,
    response: (status != null || data != null)
        ? Response(requestOptions: req, statusCode: status, data: data)
        : null,
  );
}

void main() {
  group('friendlyError — сетевые ошибки', () {
    test('connectionError → нет интернета', () {
      expect(friendlyError(_dio(DioExceptionType.connectionError)),
          'Нет подключения к интернету.');
    });

    test('таймауты → превышено время ожидания', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(friendlyError(_dio(t)),
            'Превышено время ожидания. Проверьте соединение.');
      }
    });

    test('unknown → нет связи с сервером', () {
      expect(friendlyError(_dio(DioExceptionType.unknown)),
          'Нет связи с сервером. Попробуйте позже.');
    });
  });

  group('friendlyError — ответы сервера', () {
    test('сообщение сервера приоритетнее общих фраз', () {
      final e = _dio(DioExceptionType.badResponse,
          status: 400, data: {'message': 'Email уже занят'});
      expect(friendlyError(e), 'Email уже занят');
    });

    test('401 без тела → сессия истекла', () {
      expect(friendlyError(_dio(DioExceptionType.badResponse, status: 401)),
          'Сессия истекла. Войдите снова.');
    });

    test('500 → ошибка на сервере', () {
      expect(friendlyError(_dio(DioExceptionType.badResponse, status: 500)),
          'Ошибка на сервере. Попробуйте позже.');
    });

    test('нестандартный код → код в сообщении', () {
      expect(friendlyError(_dio(DioExceptionType.badResponse, status: 418)),
          contains('418'));
    });
  });

  group('friendlyError — прочее', () {
    test('голая String возвращается как есть', () {
      expect(friendlyError('Custom message'), 'Custom message');
    });

    test('Exception теряет префикс «Exception: »', () {
      expect(friendlyError(Exception('Файл повреждён')), 'Файл повреждён');
    });

    test('null → дефолтное сообщение', () {
      expect(friendlyError(null), 'Что-то пошло не так. Попробуйте ещё раз.');
    });
  });
}
