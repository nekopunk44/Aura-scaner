import 'package:flutter/services.dart';
import 'package:aura_signature/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStorage {
  final Map<String, String> store = {};
  static const _channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return store[args['key'] as String];
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'containsKey':
          return store.containsKey(args['key'] as String);
      }
      return null;
    });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const signatureStorageKey = 'signature_image_base64';
  const transparentPngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+lm1cAAAAASUVORK5CYII=';
  late _FakeSecureStorage secure;

  Widget buildTestApp() {
    return const MaterialApp(home: HomeScreen());
  }

  setUp(() {
    secure = _FakeSecureStorage()..install();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => secure.uninstall());

  testWidgets('shows empty state when no saved signature exists', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Add your signature once to save it and reuse it later.'),
      findsOneWidget,
    );
    expect(find.text('Add Signature'), findsOneWidget);

    final deleteButton = tester.widget<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    expect(deleteButton.onPressed, isNull);
  });

  testWidgets('loads and clears a previously saved signature', (tester) async {
    secure.store[signatureStorageKey] = transparentPngBase64;

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Update Signature'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('Delete Signature'));
    await tester.pumpAndSettle();

    expect(find.text('Add Signature'), findsOneWidget);
    expect(
      find.text('Add your signature once to save it and reuse it later.'),
      findsOneWidget,
    );

    expect(secure.store[signatureStorageKey], isNull);
  });

  testWidgets('migrates legacy signature from shared preferences', (tester) async {
    SharedPreferences.setMockInitialValues({
      signatureStorageKey: transparentPngBase64,
    });

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Update Signature'), findsOneWidget);
    expect(secure.store[signatureStorageKey], transparentPngBase64);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(signatureStorageKey), isNull);
  });
}
