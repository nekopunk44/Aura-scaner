import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scanner_ap/l10n/app_localizations.dart';
import 'package:scanner_ap/screens/auth/login_screen.dart';

// Локаль форсим на ru, чтобы ассерты на русские строки оставались
// валидны после перевода экрана на AppLocalizations.
Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('ru'), Locale('en')],
      home: child,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LoginScreen — отрисовка', () {
    testWidgets('экран рендерится без ошибок', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('отображается заголовок Aura Scanner', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      expect(find.text('Aura Scanner'), findsOneWidget);
    });

    testWidgets('присутствует кнопка Войти', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      expect(find.text('Войти'), findsOneWidget);
    });

    testWidgets('присутствуют поля Email и Пароль', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Пароль'), findsOneWidget);
    });

    testWidgets('присутствует ссылка на регистрацию', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      expect(find.text('Зарегистрироваться'), findsOneWidget);
    });
  });

  group('LoginScreen — валидация формы', () {
    testWidgets('пустой email показывает ошибку', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.tap(find.text('Войти'));
      await tester.pump();
      expect(find.text('Введите email'), findsOneWidget);
    });

    testWidgets('некорректный email (без @) показывает ошибку', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'notanemail');
      await tester.tap(find.text('Войти'));
      await tester.pump();
      expect(find.text('Некорректный email'), findsOneWidget);
    });

    testWidgets('пустой пароль показывает ошибку', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'user@example.com');
      await tester.tap(find.text('Войти'));
      await tester.pump();
      expect(find.text('Введите пароль'), findsOneWidget);
    });

    testWidgets('пароль короче 6 символов показывает ошибку', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'user@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Пароль'), '123');
      await tester.tap(find.text('Войти'));
      await tester.pump();
      expect(find.text('Минимум 6 символов'), findsOneWidget);
    });

    testWidgets('валидная форма не показывает ошибок валидации', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), 'user@example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Пароль'), 'password123');
      await tester.pump();
      // Ошибок валидации не должно быть до нажатия на кнопку
      expect(find.text('Введите email'), findsNothing);
      expect(find.text('Введите пароль'), findsNothing);
    });
  });

  group('LoginScreen — переключение пароля', () {
    testWidgets('иконка глаза переключает видимость пароля', (tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));

      // Изначально есть иконка «показать пароль»
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();

      // После нажатия иконка меняется на «скрыть»
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });
  });
}
