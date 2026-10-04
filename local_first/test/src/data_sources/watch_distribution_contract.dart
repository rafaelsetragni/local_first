// What a storage owes whoever watches it: a change is told to every watcher
// of what it changed — whoever wrote it, however many are watching, whenever
// they started, and whatever the sync strategies are doing.
//
// The contract is the same for every storage, so it is written once and run
// by each storage's own test file.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class Note {
  const Note(this.id, {required this.shelf, required this.text});

  final String id;
  final String shelf;
  final String text;

  factory Note.fromJson(JsonMap json) => Note(
    json['id'] as String,
    shelf: json['shelf'] as String,
    text: json['text'] as String,
  );

  JsonMap toJson() => {'id': id, 'shelf': shelf, 'text': text};
}

/// A strategy with nothing to start.
class _Idle extends DataSyncStrategy {}

/// A strategy whose start returns.
class _Starts extends DataSyncStrategy {
  bool started = false;

  Future<void> start() async => started = true;
}

/// A strategy whose start never returns: a connection attempt abandoned
/// mid-handshake that nobody completes.
class _NeverStarts extends DataSyncStrategy {
  bool asked = false;

  Future<void> start() {
    asked = true;
    return Completer<void>().future;
  }
}

/// What the sync strategies are doing while the storage is written and
/// watched. None of it may change what a watcher is told.
enum _Sync {
  none('with no sync strategy'),
  notStarted('with sync strategies that were not started'),
  started('with sync strategies started'),
  neverReturns('with a sync start that never returns');

  const _Sync(this.said);
  final String said;
}

/// A row as a round or a live event brings it.
JsonMap remoteNote(
  String id, {
  String shelf = 'a',
  String text = 'remote',
  int at = 1000,
  String? eventId,
}) => {
  LocalFirstEvent.kEventId: eventId ?? 'remote-$id-$at',
  LocalFirstEvent.kOperation: SyncOperation.insert.index,
  LocalFirstEvent.kSyncCreatedAt: DateTime.fromMillisecondsSinceEpoch(
    at,
    isUtc: true,
  ).toIso8601String(),
  LocalFirstEvent.kDataId: id,
  LocalFirstEvent.kData: {'id': id, 'shelf': shelf, 'text': text},
};

/// Everything one screen may be watching of the notes: one by its id, some by
/// their ids, a shelf, all of them, and the bare signal that something
/// changed.
class Watchers {
  Watchers(LocalFirstRepository<Note> notes, {String id = 'n1'}) {
    _subscriptions.addAll([
      notes.query().where('id', isEqualTo: id).watch().listen(byId.add),
      notes
          .query()
          .where('id', whereIn: [id, 'n2', 'n3'])
          .watch()
          .listen(byIds.add),
      notes.query().where('shelf', isEqualTo: 'a').watch().listen(byShelf.add),
      notes.query().watch().listen(all.add),
      notes.watchChanges().listen((_) => signals++),
    ]);
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<List<LocalFirstEvent<Note>>> byId = [];
  final List<List<LocalFirstEvent<Note>>> byIds = [];
  final List<List<LocalFirstEvent<Note>>> byShelf = [];
  final List<List<LocalFirstEvent<Note>>> all = [];
  int signals = 0;

  List<List<List<LocalFirstEvent<Note>>>> get everyQuery => [
    byId,
    byIds,
    byShelf,
    all,
  ];

  /// How many times each was told, in the order above, then the signal.
  List<int> get told => [for (final seen in everyQuery) seen.length, signals];

  Future<void> leave() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}

/// The texts a watcher last saw, by id.
Map<String, String> textsOf(List<LocalFirstEvent<Note>> events) => {
  for (final event in events)
    if (!event.isDeleted && event.data != null)
      event.data!.id: event.data!.text,
};

/// Runs the contract against the storage [create] answers; [destroy] removes
/// what it left on the disk, when it left anything.
void watchDistributionContract(
  String storageName, {
  required Future<LocalFirstStorage> Function() create,
  Future<void> Function(LocalFirstStorage storage)? destroy,
}) {
  late LocalFirstStorage storage;
  late LocalFirstClient client;
  late LocalFirstRepository<Note> notes;
  late List<DataSyncStrategy> strategies;

  LocalFirstRepository<Note> repository() => LocalFirstRepository<Note>.create(
    name: 'notes',
    getId: (note) => note.id,
    toJson: (note) => note.toJson(),
    fromJson: Note.fromJson,
    schema: const {'shelf': LocalFieldType.text},
  );

  Future<void> open(_Sync sync) async {
    storage = await create();
    notes = repository();
    strategies = switch (sync) {
      _Sync.none => [],
      _Sync.notStarted => [_Starts(), _Idle()],
      _Sync.started => [_Starts(), _Idle()],
      _Sync.neverReturns => [_NeverStarts(), _Starts()],
    };
    client = LocalFirstClient(
      repositories: [notes],
      localStorage: storage,
      syncStrategies: strategies,
    );
    await client.initialize();
    if (sync == _Sync.started) await client.startAllStrategies();
    if (sync == _Sync.neverReturns) unawaited(client.startAllStrategies());
  }

  /// The stream events already on their way are delivered.
  Future<void> delivered() => pumpEventQueue();

  tearDown(() async {
    await client.dispose();
    await destroy?.call(storage);
  });

  group('$storageName — what a watcher is owed', () {
    for (final sync in _Sync.values) {
      group(sync.said, () {
        setUp(() => open(sync));

        test('the strategies are where the case says they are', () {
          switch (sync) {
            case _Sync.none:
              expect(strategies, isEmpty);
            case _Sync.notStarted:
              expect((strategies.first as _Starts).started, isFalse);
            case _Sync.started:
              expect((strategies.first as _Starts).started, isTrue);
            case _Sync.neverReturns:
              expect((strategies.first as _NeverStarts).asked, isTrue);
              // the one after it was never reached
              expect((strategies.last as _Starts).started, isFalse);
          }
        });

        test('a local write reaches every watcher of what it changed: by id, '
            'by ids, by a field, all of them, and the signal', () async {
          final watching = Watchers(notes);
          await delivered();
          expect(watching.told, [1, 1, 1, 1, 1]);
          expect(watching.all.last, isEmpty);

          await notes.upsert(const Note('n1', shelf: 'a', text: 'written'));
          await delivered();

          for (final seen in watching.everyQuery) {
            expect(textsOf(seen.last), {'n1': 'written'});
          }
          expect(watching.signals, greaterThan(1));
          await watching.leave();
        });

        test('a change and a removal reach them too', () async {
          await notes.upsert(const Note('n1', shelf: 'a', text: 'first'));
          final watching = Watchers(notes);
          await delivered();

          await notes.upsert(const Note('n1', shelf: 'a', text: 'changed'));
          await delivered();
          for (final seen in watching.everyQuery) {
            expect(textsOf(seen.last), {'n1': 'changed'});
          }

          await notes.delete('n1', needSync: true);
          await delivered();
          for (final seen in watching.everyQuery) {
            expect(textsOf(seen.last), isEmpty);
          }
          await watching.leave();
        });

        test(
          'a write that takes a row out of a watcher\'s answer tells it',
          () async {
            await notes.upsert(const Note('n1', shelf: 'a', text: 'first'));
            final watching = Watchers(notes);
            await delivered();
            expect(textsOf(watching.byShelf.last), {'n1': 'first'});

            await notes.upsert(const Note('n1', shelf: 'b', text: 'moved'));
            await delivered();

            expect(textsOf(watching.byShelf.last), isEmpty);
            expect(textsOf(watching.byId.last), {'n1': 'moved'});
            await watching.leave();
          },
        );

        test('rows applied from the server reach the same watchers, once the '
            'batch is over and once for the whole of it', () async {
          final watching = Watchers(notes);
          await delivered();
          final before = watching.told;

          await client.pullChanges(
            repositoryName: 'notes',
            changes: [
              remoteNote('n1'),
              remoteNote('n2'),
              remoteNote('n3', shelf: 'b'),
            ],
          );
          await delivered();

          expect(textsOf(watching.byId.last).keys, ['n1']);
          expect(textsOf(watching.byIds.last).keys.toSet(), {'n1', 'n2', 'n3'});
          expect(textsOf(watching.byShelf.last).keys.toSet(), {'n1', 'n2'});
          expect(textsOf(watching.all.last).keys.toSet(), {'n1', 'n2', 'n3'});
          // one telling per watcher for the batch, never one per row
          expect(watching.told, [for (final count in before) count + 1]);
          // and nobody was shown half of it
          for (final seen in watching.all) {
            expect(seen.length, anyOf(0, 3));
          }
          await watching.leave();
        });

        test(
          'a row of the server over a row written here reaches them too',
          () async {
            await notes.upsert(
              const Note('n1', shelf: 'a', text: 'local'),
              needSync: false,
            );
            final watching = Watchers(notes);
            await delivered();

            await client.pullChanges(
              repositoryName: 'notes',
              changes: [remoteNote('n1', text: 'from the server')],
            );
            await delivered();

            for (final seen in watching.everyQuery) {
              expect(textsOf(seen.last), {'n1': 'from the server'});
            }
            await watching.leave();
          },
        );
      });
    }

    group('whenever the watcher started', () {
      test('one attached before the sync started and one attached after are '
          'both told', () async {
        await open(_Sync.notStarted);
        final early = Watchers(notes);
        await delivered();

        await client.startAllStrategies();
        final late = Watchers(notes);
        await delivered();

        await notes.upsert(const Note('n1', shelf: 'a', text: 'written'));
        await client.pullChanges(
          repositoryName: 'notes',
          changes: [remoteNote('n2')],
        );
        await delivered();

        for (final watching in [early, late]) {
          for (final seen in [watching.byIds, watching.byShelf, watching.all]) {
            expect(textsOf(seen.last).keys.toSet(), {'n1', 'n2'});
          }
        }
        await early.leave();
        await late.leave();
      });

      test('one attached before the namespace changed — before anybody signed '
          'in — is told what the new namespace holds, and what is written '
          'there', () async {
        await open(_Sync.none);
        await notes.upsert(const Note('n1', shelf: 'a', text: 'nobody\'s'));
        final early = Watchers(notes);
        await delivered();
        expect(textsOf(early.all.last), {'n1': 'nobody\'s'});

        await client.useNamespace('account');
        await delivered();
        // the account's own store holds nothing yet, and says so
        for (final seen in early.everyQuery) {
          expect(textsOf(seen.last), isEmpty);
        }

        final late = Watchers(notes);
        await delivered();
        await notes.upsert(
          const Note('n1', shelf: 'a', text: 'the account\'s'),
        );
        await client.pullChanges(
          repositoryName: 'notes',
          changes: [remoteNote('n2')],
        );
        await delivered();

        for (final watching in [early, late]) {
          expect(textsOf(watching.byId.last), {'n1': 'the account\'s'});
          expect(textsOf(watching.all.last).keys.toSet(), {'n1', 'n2'});
        }

        // signing out: the same watchers follow the store back
        await client.useNamespace('default');
        await delivered();
        expect(textsOf(early.all.last), {'n1': 'nobody\'s'});
        expect(textsOf(late.all.last), {'n1': 'nobody\'s'});
        await early.leave();
        await late.leave();
      });
    });

    group('however many are watching', () {
      setUp(() => open(_Sync.none));

      test('several watches of the same question are all told', () async {
        final seen = [for (var i = 0; i < 3; i++) <Map<String, String>>[]];
        final subscriptions = [
          for (final one in seen)
            notes
                .query()
                .where('shelf', isEqualTo: 'a')
                .watch()
                .listen((events) => one.add(textsOf(events))),
        ];
        await delivered();

        await notes.upsert(const Note('n1', shelf: 'a', text: 'written'));
        await delivered();

        for (final one in seen) {
          expect(one.last, {'n1': 'written'});
        }
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });

      test('several listeners of one watch are all told, and one leaving does '
          'not stop the others', () async {
        final stream = notes.query().watch();
        final first = <Map<String, String>>[];
        final second = <Map<String, String>>[];
        final one = stream.listen((events) => first.add(textsOf(events)));
        final other = stream.listen((events) => second.add(textsOf(events)));
        await delivered();

        await notes.upsert(const Note('n1', shelf: 'a', text: 'written'));
        await delivered();
        expect(first.last, {'n1': 'written'});
        expect(second.last, {'n1': 'written'});

        await one.cancel();
        await notes.upsert(const Note('n1', shelf: 'a', text: 'again'));
        await delivered();

        expect(first.last, {'n1': 'written'});
        expect(second.last, {'n1': 'again'});
        await other.cancel();
      });

      test('a listener that was paused — a screen under another — is told '
          'what it missed when it resumes', () async {
        final seen = <Map<String, String>>[];
        final subscription = notes.query().watch().listen(
          (events) => seen.add(textsOf(events)),
        );
        await delivered();

        subscription.pause();
        await notes.upsert(const Note('n1', shelf: 'a', text: 'while paused'));
        await delivered();
        expect(seen.last, isEmpty);

        subscription.resume();
        await delivered();

        expect(seen.last, {'n1': 'while paused'});
        await subscription.cancel();
      });

      test('a watch that is listened to again after everybody left is told '
          'again', () async {
        final stream = notes.query().watch();
        final first = await stream.first;
        expect(first, isEmpty);
        await delivered();

        final seen = <Map<String, String>>[];
        final subscription = stream.listen(
          (events) => seen.add(textsOf(events)),
        );
        await delivered();
        expect(seen.last, isEmpty);

        await notes.upsert(const Note('n1', shelf: 'a', text: 'written'));
        await delivered();

        expect(seen.last, {'n1': 'written'});
        await subscription.cancel();
      });

      test('the bare signal listened to again after everybody left is told '
          'again', () async {
        final stream = notes.watchChanges();
        await stream.first;
        await delivered();

        var signals = 0;
        final subscription = stream.listen((_) => signals++);
        await delivered();
        final onListen = signals;

        await notes.upsert(const Note('n1', shelf: 'a', text: 'written'));
        await delivered();

        expect(signals, greaterThan(onListen));
        await subscription.cancel();
      });

      test(
        'a watch somebody listens to late answers with what is held then',
        () async {
          final stream = notes.query().watch();
          await notes.upsert(const Note('n1', shelf: 'a', text: 'written'));

          expect(textsOf(await stream.first), {'n1': 'written'});
        },
      );
    });

    group('a write made here while rows of the server are being applied', () {
      setUp(() => open(_Sync.none));

      test('is kept, and told to its watchers', () async {
        final watching = Watchers(notes);
        await delivered();
        final applying = Completer<void>();
        final entered = Completer<void>();

        final round = storage.runInTransaction(() async {
          await notes.mergeRemoteEvent(
            remoteEvent: notes.createEventFromRemote(remoteNote('n2')),
          );
          entered.complete();
          await applying.future;
        });
        await entered.future;

        // the person acts while the batch is open
        final written = notes.upsert(
          const Note('n1', shelf: 'a', text: 'written meanwhile'),
        );
        await delivered();
        applying.complete();
        await round;
        await written;
        await delivered();

        expect(textsOf(watching.all.last), {
          'n1': 'written meanwhile',
          'n2': 'remote',
        });
        expect(textsOf(watching.byId.last), {'n1': 'written meanwhile'});
        expect((await notes.getById('n1'))?.text, 'written meanwhile');
        await watching.leave();
      });

      test('a question asked meanwhile is answered with what the batch '
          'committed, and does not hold the batch up', () async {
        final applying = Completer<void>();
        final entered = Completer<void>();
        final round = storage.runInTransaction(() async {
          await notes.mergeRemoteEvent(
            remoteEvent: notes.createEventFromRemote(remoteNote('n2')),
          );
          entered.complete();
          await applying.future;
        });
        await entered.future;

        // a screen opens while the batch is open: it reads, and it watches
        final asked = notes.getById('n2');
        final seen = <Map<String, String>>[];
        final subscription = notes.query().watch().listen(
          (events) => seen.add(textsOf(events)),
        );
        await delivered();
        applying.complete();
        await round;
        await delivered();

        expect((await asked)?.text, 'remote');
        expect(seen.last, {'n2': 'remote'});
        await subscription.cancel();
      });

      test('is kept when that batch fails: what failed was the server\'s rows, '
          'not what the person did', () async {
        final watching = Watchers(notes);
        await delivered();
        final applying = Completer<void>();
        final entered = Completer<void>();

        final round = storage.runInTransaction(() async {
          await notes.mergeRemoteEvent(
            remoteEvent: notes.createEventFromRemote(remoteNote('n2')),
          );
          entered.complete();
          await applying.future;
          throw const FormatException('a row of the batch is malformed');
        });
        final failed = expectLater(round, throwsFormatException);
        await entered.future;

        final written = notes.upsert(
          const Note('n1', shelf: 'a', text: 'written meanwhile'),
        );
        await delivered();
        applying.complete();
        await failed;
        await written;
        await delivered();

        expect((await notes.getById('n1'))?.text, 'written meanwhile');
        expect(textsOf(watching.byId.last), {'n1': 'written meanwhile'});
        expect(await notes.getPendingEvents(), hasLength(1));
        await watching.leave();
      });

      test('none is lost however the two interleave', () async {
        final watching = Watchers(notes);
        await delivered();

        final work = <Future<void>>[];
        for (var turn = 0; turn < 40; turn++) {
          work.add(
            client.pullChanges(
              repositoryName: 'notes',
              changes: [
                for (var row = 0; row < 3; row++)
                  remoteNote('r$turn-$row', shelf: 'b', at: 1000 + turn),
              ],
            ),
          );
          work.add(
            notes.upsert(Note('w$turn', shelf: 'a', text: 'written $turn')),
          );
          // a different point of the batch each turn
          for (var hop = 0; hop < turn % 7; hop++) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        await Future.wait(work);
        await delivered();

        final held = textsOf(await notes.query().getAll());
        expect(
          [
            for (var turn = 0; turn < 40; turn++)
              if (held['w$turn'] != 'written $turn') 'w$turn',
          ],
          isEmpty,
          reason: 'every write made here is held',
        );
        expect(held.length, 40 + 40 * 3);
        expect(textsOf(watching.all.last).length, held.length);
        expect(textsOf(watching.byShelf.last).length, 40);
        expect(await notes.getPendingEvents(), hasLength(40));
        await watching.leave();
      });
    });
  });
}
