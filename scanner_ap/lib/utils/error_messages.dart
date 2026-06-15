import 'package:dio/dio.dart';

/// Единая точка преобразования любого пойманного исключения в понятное
/// пользователю русское сообщение. Используется и в сервисах
/// (`_parseError`), и на экранах вместо сырого `e.toString()`.
///
/// Покрывает все типы [DioException] — в т.ч. `connectionError` (нет
/// интернета вообще), который раньше выпадал в «Неизвестная ошибка».
String friendlyError(Object? error) {
  if (error is DioException) return _fromDio(error);

  // Часть кода бросает голую String как сообщение — отдаём как есть.
  if (error is String) return error;

  // Exception('текст') → «текст» без префикса «Exception: ».
  final text = error?.toString() ?? '';
  return text.replaceFirst(RegExp(r'^Exception:\s*'), '').trim().isEmpty
      ? 'Что-то пошло не так. Попробуйте ещё раз.'
      : text.replaceFirst(RegExp(r'^Exception:\s*'), '');
}

String _fromDio(DioException e) {
  // Сервер прислал осмысленное сообщение — оно приоритетнее общих фраз.
  final data = e.response?.data;
  if (data is Map && data['message'] is String) {
    return data['message'] as String;
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'Превышено время ожидания. Проверьте соединение.';
    case DioExceptionType.connectionError:
      return 'Нет подключения к интернету.';
    case DioExceptionType.badCertificate:
      return 'Не удалось установить защищённое соединение.';
    case DioExceptionType.cancel:
      return 'Запрос отменён.';
    case DioExceptionType.badResponse:
      return _fromStatus(e.response?.statusCode);
    case DioExceptionType.unknown:
      return 'Нет связи с сервером. Попробуйте позже.';
  }
}

String _fromStatus(int? status) {
  switch (status) {
    case 400:
      return 'Некорректный запрос.';
    case 401:
      return 'Сессия истекла. Войдите снова.';
    case 403:
      return 'Доступ запрещён.';
    case 404:
      return 'Не найдено.';
    case 409:
      return 'Конфликт данных.';
    case 413:
      return 'Файл слишком большой.';
    case 429:
      return 'Слишком много запросов. Попробуйте позже.';
  }
  if (status != null && status >= 500) {
    return 'Ошибка на сервере. Попробуйте позже.';
  }
  return 'Не удалось выполнить запрос${status != null ? ' (код $status)' : ''}.';
}
