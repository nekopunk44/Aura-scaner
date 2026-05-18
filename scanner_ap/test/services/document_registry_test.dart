import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scanner_ap/services/document_registry.dart';

DocumentRegistry get reg => DocumentRegistry();

Future<void> freshRegistry() async {
  SharedPreferences.setMockInitialValues({});
  // Reset singleton state via load() on an empty store
  await reg.load();
}

void main() {
  group('DocumentRegistry — базовые операции', () {
    setUp(freshRegistry);

    test('пустой после инициализации', () {
      expect(reg.entries, isEmpty);
    });

    test('add сохраняет запись', () async {
      await reg.add(const DocEntry(localPath: '/a/doc.pdf', name: 'doc'));
      expect(reg.entries.length, 1);
      expect(reg.entries.first.localPath, '/a/doc.pdf');
    });

    test('add заменяет запись с тем же localPath', () async {
      await reg.add(const DocEntry(localPath: '/a/doc.pdf', name: 'old'));
      await reg.add(const DocEntry(localPath: '/a/doc.pdf', remoteId: 'r1', name: 'new'));
      expect(reg.entries.length, 1);
      expect(reg.entries.first.name, 'new');
    });

    test('remove удаляет запись', () async {
      await reg.add(const DocEntry(localPath: '/a/doc.pdf', name: 'doc'));
      await reg.remove('/a/doc.pdf');
      expect(reg.entries, isEmpty);
    });

    test('remove несуществующего пути не бросает', () async {
      await expectLater(reg.remove('/no/such.pdf'), completes);
    });
  });

  group('DocumentRegistry — remoteId', () {
    setUp(freshRegistry);

    test('getRemoteId возвращает null для неизвестного пути', () {
      expect(reg.getRemoteId('/x.pdf'), isNull);
    });

    test('updateRemoteId обновляет запись', () async {
      await reg.add(const DocEntry(localPath: '/a/doc.pdf', name: 'doc'));
      await reg.updateRemoteId('/a/doc.pdf', 'remote123');
      expect(reg.getRemoteId('/a/doc.pdf'), 'remote123');
    });

    test('updateRemoteId для несуществующего пути не бросает', () async {
      await expectLater(reg.updateRemoteId('/ghost.pdf', 'r1'), completes);
    });
  });

  group('DocumentRegistry — переименование', () {
    setUp(freshRegistry);

    test('updateLocalPath меняет путь и имя, сохраняет remoteId', () async {
      await reg.add(const DocEntry(
          localPath: '/a/old.pdf', remoteId: 'r1', name: 'old'));
      await reg.updateLocalPath('/a/old.pdf', '/a/new.pdf', 'new');
      expect(reg.entries.length, 1);
      expect(reg.entries.first.localPath, '/a/new.pdf');
      expect(reg.entries.first.name, 'new');
      expect(reg.entries.first.remoteId, 'r1');
    });

    test('updateLocalPath для несуществующего пути не бросает', () async {
      await expectLater(
          reg.updateLocalPath('/ghost.pdf', '/new.pdf', 'new'), completes);
    });
  });

  group('DocumentRegistry — персистентность', () {
    test('данные сохраняются и восстанавливаются', () async {
      SharedPreferences.setMockInitialValues({});
      await reg.load();
      await reg.add(const DocEntry(
          localPath: '/a/doc.pdf', remoteId: 'r1', name: 'doc'));

      // Simulate app restart: load() reads from prefs
      await reg.load();
      expect(reg.entries.length, 1);
      expect(reg.entries.first.remoteId, 'r1');
    });
  });

  group('DocumentRegistry — миграция из legacy формата', () {
    test('мигрирует старый saved_document_paths в v2', () async {
      SharedPreferences.setMockInitialValues({
        'saved_document_paths': ['/x/a.pdf', '/x/b.pdf'],
      });
      await reg.load();
      expect(reg.entries.length, 2);
      expect(reg.entries.map((e) => e.localPath),
          containsAll(['/x/a.pdf', '/x/b.pdf']));
      // remoteId должен быть null после миграции
      expect(reg.entries.every((e) => e.remoteId == null), isTrue);
    });
  });

  group('DocumentRegistry — nameFromPath', () {
    test('извлекает имя без расширения', () {
      expect(DocumentRegistry.nameFromPath('/docs/report.pdf'), 'report');
    });

    test('файл без расширения — возвращает имя как есть', () {
      expect(DocumentRegistry.nameFromPath('/docs/readme'), 'readme');
    });

    test('файл с несколькими точками — берёт последний сегмент до последней точки', () {
      expect(DocumentRegistry.nameFromPath('/x/my.scan.pdf'), 'my.scan');
    });
  });
}
