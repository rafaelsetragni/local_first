import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _Dummy {
  _Dummy(this.id);
  final String id;

  JsonMap<dynamic> toJson() => {'id': id};
  factory _Dummy.fromJson(JsonMap<dynamic> json) => _Dummy(json['id'] as String);
}

LocalFirstRepository<_Dummy> _buildRepo() {
  return LocalFirstRepository.create(
    name: 'dummy',
    getId: (d) => d.id,
    toJson: (d) => d.toJson(),
    fromJson: _Dummy.fromJson,
    schema: const {'id': LocalFieldType.text},
  );
}

LocalFirstClient _buildClient() => LocalFirstClient(
      repositories: [_buildRepo()],
      localStorage: LocalFirstMemoryStorage(),
      keyValueStorage: LocalFirstMemoryKeyValueStorage(),
    );

void main() {
  group('LocalFirstClient namespace/open', () {
    test('openDocumentDatabase throws before initialize', () async {
      final client = _buildClient();
      expect(
        () => client.openDocumentDatabase(),
        throwsA(isA<StateError>()),
      );
    });

    test('openKeyValueDatabase throws before initialize', () async {
      final client = _buildClient();
      expect(
        () => client.openKeyValueDatabase(),
        throwsA(isA<StateError>()),
      );
    });

    test('document namespace isolation via openDocumentDatabase', () async {
      final client = _buildClient();
      await client.initialize();

      final repo = client.getRepositoryByName('dummy') as LocalFirstRepository<_Dummy>;

      await client.openDocumentDatabase(namespace: 'ns1');
      await repo.upsert(_Dummy('a'));
      final ns1Items = await repo.query().getAll();
      expect(ns1Items.map((e) => e.id), ['a']);

      await client.openDocumentDatabase(namespace: 'ns2');
      final ns2ItemsBefore = await repo.query().getAll();
      expect(ns2ItemsBefore, isEmpty);
      await repo.upsert(_Dummy('b'));
      final ns2Items = await repo.query().getAll();
      expect(ns2Items.map((e) => e.id), ['b']);

      await client.openDocumentDatabase(namespace: 'ns1');
      final ns1ItemsAgain = await repo.query().getAll();
      expect(ns1ItemsAgain.map((e) => e.id), ['a']);
    });

    test('key/value namespace isolation via openKeyValueDatabase', () async {
      final client = _buildClient();
      await client.initialize();

      await client.openKeyValueDatabase(namespace: 'a');
      await client.setKeyValue('k', 'va');
      expect(await client.getKeyValue<String>('k'), 'va');

      await client.openKeyValueDatabase(namespace: 'b');
      expect(await client.getKeyValue<String>('k'), isNull);
      await client.setKeyValue('k', 'vb');
      expect(await client.getKeyValue<String>('k'), 'vb');

      await client.openKeyValueDatabase(namespace: 'a');
      expect(await client.getKeyValue<String>('k'), 'va');
    });
  });
}
