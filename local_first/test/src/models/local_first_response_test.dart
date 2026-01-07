import 'package:flutter_test/flutter_test.dart';

import 'package:local_first/local_first.dart';

class _DummyModel {
  _DummyModel(this.id);
  final String id;

  Map<String, dynamic> toJson() => {'id': id};
}

class _DummyRepo extends LocalFirstRepository<_DummyModel> {
  _DummyRepo()
    : super(
        name: 'dummy',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: (json) => _DummyModel(json['id'] as String),
        onConflict: (l, r) => l,
      );
}

void main() {
  group('LocalFirstResponse', () {
    test('stores changes map and timestamp', () {
      final repo = _DummyRepo();
      final model = LocalFirstEvent(payload: _DummyModel('1'));

      final response = LocalFirstResponse(
        changes: {
          repo: [model],
        },
        timestamp: DateTime.utc(2024, 1, 1),
      );

      expect(response.timestamp, DateTime.utc(2024, 1, 1));
      expect(response.changes.length, 1);
      expect(response.changes[repo], isNotNull);
      expect(response.changes[repo], contains(model));
    });
  });
}
