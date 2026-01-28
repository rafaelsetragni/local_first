import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:chat_app/services/repository_service.dart';
import 'package:chat_app/services/navigator_service.dart';
import 'package:chat_app/services/sync_state_manager.dart';
import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/models/chat_model.dart';
import 'package:chat_app/models/message_model.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';
import 'package:local_first_periodic_strategy/local_first_periodic_strategy.dart';

// Mock classes
class MockUserRepository extends Mock
    implements LocalFirstRepository<UserModel> {}

class MockChatRepository extends Mock
    implements LocalFirstRepository<ChatModel> {}

class MockMessageRepository extends Mock
    implements LocalFirstRepository<MessageModel> {}

class MockWebSocketStrategy extends Mock implements WebSocketSyncStrategy {}

class MockPeriodicStrategy extends Mock implements PeriodicSyncStrategy {}

class MockHttpClient extends Mock implements http.Client {}

class MockNavigatorService extends Mock implements NavigatorService {}

class MockLocalFirstStorage extends Mock implements LocalFirstStorage {}

class MockResponse extends Mock implements http.Response {}

class MockLocalFirstQuery<T> extends Mock implements LocalFirstQuery<T> {}

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

class MockSyncStateManager extends Mock implements SyncStateManager {}

// Fake classes for fallback values
class FakeUri extends Fake implements Uri {}

class FakeUserModel extends Fake implements UserModel {}

class FakeChatModel extends Fake implements ChatModel {}

class FakeMessageModel extends Fake implements MessageModel {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeUri());
    registerFallbackValue(FakeUserModel());
    registerFallbackValue(FakeChatModel());
    registerFallbackValue(FakeMessageModel());
  });

  group('RepositoryService', () {
    tearDown(() {
      RepositoryService.instance = null;
    });

    test('is a singleton', () {
      final instance1 = RepositoryService();
      final instance2 = RepositoryService();

      expect(identical(instance1, instance2), true);

      RepositoryService.instance = null;
    });

    test('has correct initial namespace', () {
      final service = RepositoryService();
      expect(service.namespace, 'default');

      RepositoryService.instance = null;
    });

    test('has no authenticated user initially', () {
      final service = RepositoryService();
      expect(service.authenticatedUser, isNull);

      RepositoryService.instance = null;
    });

    test('has repositories configured', () {
      final service = RepositoryService();
      expect(service.userRepository, isNotNull);
      expect(service.chatRepository, isNotNull);
      expect(service.messageRepository, isNotNull);

      RepositoryService.instance = null;
    });

    group('with full dependency injection', () {
      late MockUserRepository mockUserRepo;
      late MockChatRepository mockChatRepo;
      late MockMessageRepository mockMessageRepo;
      late MockWebSocketStrategy mockWsStrategy;
      late MockPeriodicStrategy mockPeriodicStrategy;
      late MockHttpClient mockHttpClient;
      late MockNavigatorService mockNavigatorService;
      late MockLocalFirstStorage mockStorage;
      late MockLocalFirstClient mockClient;
      late RepositoryService service;

      setUp(() {
        mockUserRepo = MockUserRepository();
        mockChatRepo = MockChatRepository();
        mockMessageRepo = MockMessageRepository();
        mockWsStrategy = MockWebSocketStrategy();
        mockPeriodicStrategy = MockPeriodicStrategy();
        mockHttpClient = MockHttpClient();
        mockNavigatorService = MockNavigatorService();
        mockStorage = MockLocalFirstStorage();
        mockClient = MockLocalFirstClient();

        // Setup common repository stubs
        when(() => mockUserRepo.idFieldName).thenReturn('id');
        when(() => mockUserRepo.name).thenReturn('user');
        when(() => mockChatRepo.idFieldName).thenReturn('id');
        when(() => mockChatRepo.name).thenReturn('chat');
        when(() => mockMessageRepo.idFieldName).thenReturn('id');
        when(() => mockMessageRepo.name).thenReturn('message');

        // Setup client stubs
        when(() => mockClient.localStorage).thenReturn(mockStorage);
        when(() => mockClient.initialize()).thenAnswer((_) async => {});
        when(() => mockClient.startAllStrategies()).thenAnswer((_) async => {});
        when(() => mockClient.stopAllStrategies()).thenReturn(null);

        // Setup storage stubs
        when(() => mockStorage.useNamespace(any())).thenAnswer((_) async => {});

        service = RepositoryService.test(
          userRepo: mockUserRepo,
          chatRepo: mockChatRepo,
          messageRepo: mockMessageRepo,
          wsStrategy: mockWsStrategy,
          periodicStrat: mockPeriodicStrategy,
          httpClient: mockHttpClient,
          navigator: mockNavigatorService,
        );
      });

      group('initialize', () {
        test('initializes LocalFirstClient successfully', () async {
          service.localFirst = mockClient;

          // Mock restoreLastUser to return null (no previous user)
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');

          final result = await service.initialize();

          expect(result, isNull);
          verify(() => mockClient.initialize()).called(1);
        });

        test('restores last user if available', () async {
          service.localFirst = mockClient;

          final testUser = UserModel(username: 'testuser', avatarUrl: null);
          final mockQuery = MockLocalFirstQuery<UserModel>();
          final testEvent = LocalFirstEvent.createNewInsertEvent<UserModel>(
            repository: mockUserRepo,
            needSync: false,
            data: testUser,
          );

          // Mock getConfigValue to return username
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => 'testuser');

          // Mock namespace switching
          when(() => mockStorage.useNamespace('default'))
              .thenAnswer((_) async => {});
          when(() => mockStorage.useNamespace('user_testuser'))
              .thenAnswer((_) async => {});

          // Mock user query
          when(() => mockUserRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo')))
              .thenReturn(mockQuery);
          when(() => mockQuery.getAll()).thenAnswer((_) async => [testEvent]);

          final result = await service.initialize();

          expect(result, isNotNull);
          expect(result?.username, 'testuser');
          verify(() => mockClient.initialize()).called(1);
          verify(() => mockClient.startAllStrategies()).called(1);
        });
      });

      group('signIn', () {
        test('signs in new user that does not exist on server', () async {
          service.localFirst = mockClient;

          // Mock HTTP 404 response (user doesn't exist)
          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(404);
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          // Mock namespace switching
          when(() => mockStorage.useNamespace(any()))
              .thenAnswer((_) async => {});

          // Mock user upsert
          when(() =>
                  mockUserRepo.upsert(any(), needSync: any(named: 'needSync')))
              .thenAnswer((_) async => {});

          // Mock config operations
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');
          when(() => mockClient.setConfigValue(any(), any()))
              .thenAnswer((_) async => true);

          // Mock navigation
          when(() => mockNavigatorService.navigateToHome()).thenReturn(null);

          await service.signIn(username: 'newuser');

          expect(service.authenticatedUser, isNotNull);
          expect(service.authenticatedUser?.username, 'newuser');
          verify(() => mockUserRepo.upsert(any(), needSync: true)).called(1);
          verify(() => mockClient.startAllStrategies()).called(1);
          verify(() => mockNavigatorService.navigateToHome()).called(1);
        });

        test('signs in existing user from server', () async {
          service.localFirst = mockClient;

          final existingUser = UserModel(
            username: 'existinguser',
            avatarUrl: 'https://example.com/avatar.png',
          );

          // Mock HTTP 200 response with user data
          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(200);
          when(() => mockResponse.body).thenReturn(jsonEncode({
            'event': {
              'data': existingUser.toJson(),
            }
          }));
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          // Mock namespace switching
          when(() => mockStorage.useNamespace(any()))
              .thenAnswer((_) async => {});

          // Mock config operations
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');
          when(() => mockClient.setConfigValue(any(), any()))
              .thenAnswer((_) async => true);

          // Mock navigation
          when(() => mockNavigatorService.navigateToHome()).thenReturn(null);

          await service.signIn(username: 'existinguser');

          expect(service.authenticatedUser, isNotNull);
          expect(service.authenticatedUser?.username, 'existinguser');
          expect(service.authenticatedUser?.avatarUrl,
              'https://example.com/avatar.png');
          verify(() => mockClient.startAllStrategies()).called(1);
          verify(() => mockNavigatorService.navigateToHome()).called(1);
          // Should NOT upsert remote user - WebSocket sync handles it
          verifyNever(
              () => mockUserRepo.upsert(any(), needSync: any(named: 'needSync')));
        });

        test('throws when HTTP request fails with non-404 error', () async {
          service.localFirst = mockClient;

          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(500);
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          // Mock namespace switching
          when(() => mockStorage.useNamespace(any()))
              .thenAnswer((_) async => {});

          // Mock config operations for hidden chats
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');

          await expectLater(
            service.signIn(username: 'testuser'),
            throwsA(isA<Exception>()),
          );
        });

        test('throws when HTTP request times out', () async {
          service.localFirst = mockClient;

          when(() => mockHttpClient.get(any()))
              .thenThrow(Exception('Timeout'));

          // Mock namespace switching
          when(() => mockStorage.useNamespace(any()))
              .thenAnswer((_) async => {});

          // Mock config operations for hidden chats
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');

          await expectLater(
            service.signIn(username: 'testuser'),
            throwsA(isA<Exception>()),
          );
        });

        test('stops strategies before signing in', () async {
          service.localFirst = mockClient;

          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(404);
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          when(() => mockStorage.useNamespace(any()))
              .thenAnswer((_) async => {});
          when(() =>
                  mockUserRepo.upsert(any(), needSync: any(named: 'needSync')))
              .thenAnswer((_) async => {});
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');
          when(() => mockClient.setConfigValue(any(), any()))
              .thenAnswer((_) async => true);

          when(() => mockNavigatorService.navigateToHome()).thenReturn(null);

          await service.signIn(username: 'newuser');

          verify(() => mockClient.stopAllStrategies()).called(1);
        });
      });

      group('signOut', () {
        test('clears authentication and navigates to sign in', () async {
          service.localFirst = mockClient;
          service.authenticatedUser =
              UserModel(username: 'testuser', avatarUrl: null);

          // Mock config operations for clearing last username
          when(() => mockStorage.useNamespace('default'))
              .thenAnswer((_) async => {});
          when(() => mockStorage.useNamespace(any()))
              .thenAnswer((_) async => {});
          when(() => mockClient.setConfigValue(any(), any()))
              .thenAnswer((_) async => true);

          when(() => mockNavigatorService.navigateToSignIn()).thenReturn(null);

          await service.signOut();

          expect(service.authenticatedUser, isNull);
          verify(() => mockClient.stopAllStrategies()).called(1);
          verify(() => mockStorage.useNamespace('default'))
              .called(greaterThan(0));
          verify(() => mockNavigatorService.navigateToSignIn()).called(1);
        });
      });

      group('restoreLastUser', () {
        test('restores user from database and starts strategies', () async {
          service.localFirst = mockClient;

          final testUser = UserModel(username: 'testuser', avatarUrl: null);
          final mockQuery = MockLocalFirstQuery<UserModel>();
          final testEvent = LocalFirstEvent.createNewInsertEvent<UserModel>(
            repository: mockUserRepo,
            needSync: false,
            data: testUser,
          );

          // Mock namespace switching
          when(() => mockStorage.useNamespace(any()))
              .thenAnswer((_) async => {});

          // Mock user query
          when(() => mockUserRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo')))
              .thenReturn(mockQuery);
          when(() => mockQuery.getAll()).thenAnswer((_) async => [testEvent]);

          // Mock config operations
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => 'testuser');
          when(() => mockClient.setConfigValue(any(), any()))
              .thenAnswer((_) async => true);

          final result = await service.restoreLastUser();

          expect(result, isNotNull);
          expect(result?.username, 'testuser');
          expect(service.authenticatedUser?.username, 'testuser');
          verify(() => mockClient.startAllStrategies()).called(1);
        });

        test('returns null when no last username stored', () async {
          service.localFirst = mockClient;

          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');

          final result = await service.restoreLastUser();

          expect(result, isNull);
        });

        test('returns null when user not found in database', () async {
          service.localFirst = mockClient;

          final mockQuery = MockLocalFirstQuery<UserModel>();

          when(() => mockStorage.useNamespace(any()))
              .thenAnswer((_) async => {});
          when(() => mockUserRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo')))
              .thenReturn(mockQuery);
          when(() => mockQuery.getAll()).thenAnswer((_) async => []);

          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => 'nonexistent');

          final result = await service.restoreLastUser();

          expect(result, isNull);
        });
      });

      group('updateAvatarUrl', () {
        test('updates avatar for authenticated user', () async {
          final testUser = UserModel(username: 'testuser', avatarUrl: null);
          service.authenticatedUser = testUser;

          when(() =>
                  mockUserRepo.upsert(any(), needSync: any(named: 'needSync')))
              .thenAnswer((_) async => {});

          final result =
              await service.updateAvatarUrl('https://example.com/avatar.png');

          expect(result.avatarUrl, 'https://example.com/avatar.png');
          expect(service.authenticatedUser?.avatarUrl,
              'https://example.com/avatar.png');
          verify(() => mockUserRepo.upsert(any(), needSync: true)).called(1);
        });

        test('handles empty avatar URL', () async {
          final testUser = UserModel(
            username: 'testuser',
            avatarUrl: 'https://old.com/avatar.png',
          );
          service.authenticatedUser = testUser;

          when(() =>
                  mockUserRepo.upsert(any(), needSync: any(named: 'needSync')))
              .thenAnswer((_) async => {});

          final result = await service.updateAvatarUrl('');

          expect(result.avatarUrl, isNull);
          verify(() => mockUserRepo.upsert(any(), needSync: true)).called(1);
        });

        test('throws when user not authenticated', () async {
          service.authenticatedUser = null;

          await expectLater(
            service.updateAvatarUrl('https://example.com/avatar.png'),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('User not authenticated'),
              ),
            ),
          );
        });
      });

      group('chat operations', () {
        test('createChat creates chat with authenticated user', () async {
          service.authenticatedUser =
              UserModel(username: 'testuser', avatarUrl: null);

          when(() =>
                  mockChatRepo.upsert(any(), needSync: any(named: 'needSync')))
              .thenAnswer((_) async => {});

          await service.createChat(chatName: 'New Chat');

          verify(() => mockChatRepo.upsert(any(), needSync: true)).called(1);
        });

        test('createChat throws when user not authenticated', () async {
          service.authenticatedUser = null;

          await expectLater(
            service.createChat(chatName: 'New Chat'),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('User not authenticated'),
              ),
            ),
          );
        });

        test('getChats returns chats ordered by updatedAt', () async {
          final mockQuery = MockLocalFirstQuery<ChatModel>();
          final chat1 = ChatModel(
              id: 'chat1', name: 'Chat 1', createdBy: 'user1');
          final chat2 = ChatModel(
              id: 'chat2', name: 'Chat 2', createdBy: 'user2');

          final event1 = LocalFirstEvent.createNewInsertEvent<ChatModel>(
            repository: mockChatRepo,
            needSync: false,
            data: chat1,
          );
          final event2 = LocalFirstEvent.createNewInsertEvent<ChatModel>(
            repository: mockChatRepo,
            needSync: false,
            data: chat2,
          );

          when(() => mockChatRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.orderBy(any(), descending: any(named: 'descending')))
              .thenReturn(mockQuery);
          when(() => mockQuery.getAll())
              .thenAnswer((_) async => [event1, event2]);

          final chats = await service.getChats();

          expect(chats.length, 2);
          expect(chats[0].name, 'Chat 1');
          expect(chats[1].name, 'Chat 2');
        });

        test('watchChats returns stream of chats', () {
          final mockQuery = MockLocalFirstQuery<ChatModel>();
          final streamController =
              StreamController<List<LocalFirstEvent<ChatModel>>>();

          when(() => mockChatRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.orderBy(any(), descending: any(named: 'descending')))
              .thenReturn(mockQuery);
          when(() => mockQuery.watch())
              .thenAnswer((_) => streamController.stream);

          final stream = service.watchChats();

          expect(stream, isA<Stream<List<ChatModel>>>());

          streamController.close();
        });

        test('updateChatAvatar updates chat', () async {
          final mockQuery = MockLocalFirstQuery<ChatModel>();
          final chat = ChatModel(
            id: 'chat1',
            name: 'Test Chat',
            createdBy: 'user1',
          );
          final chatEvent = LocalFirstEvent.createNewInsertEvent<ChatModel>(
            repository: mockChatRepo,
            needSync: false,
            data: chat,
          );

          when(() => mockChatRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo')))
              .thenReturn(mockQuery);
          when(() => mockQuery.getAll())
              .thenAnswer((_) async => [chatEvent]);
          when(() =>
                  mockChatRepo.upsert(any(), needSync: any(named: 'needSync')))
              .thenAnswer((_) async => {});

          final result = await service.updateChatAvatar(
              'chat1', 'https://avatar.com/img.png');

          expect(result.avatarUrl, 'https://avatar.com/img.png');
          verify(() => mockChatRepo.upsert(any(), needSync: true)).called(1);
        });

        test('updateChatAvatar throws when chat not found', () async {
          final mockQuery = MockLocalFirstQuery<ChatModel>();

          when(() => mockChatRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo')))
              .thenReturn(mockQuery);
          when(() => mockQuery.getAll()).thenAnswer((_) async => []);

          await expectLater(
            service.updateChatAvatar('nonexistent', 'https://avatar.com'),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('Chat not found'),
              ),
            ),
          );
        });
      });

      group('message operations', () {
        test('sendMessage creates message and updates chat', () async {
          service.authenticatedUser =
              UserModel(username: 'testuser', avatarUrl: null);

          final mockChatQuery = MockLocalFirstQuery<ChatModel>();
          final chat = ChatModel(
            id: 'chat1',
            name: 'Test Chat',
            createdBy: 'user1',
          );
          final chatEvent = LocalFirstEvent.createNewInsertEvent<ChatModel>(
            repository: mockChatRepo,
            needSync: false,
            data: chat,
          );

          when(() => mockChatRepo.query()).thenReturn(mockChatQuery);
          when(() => mockChatQuery.where(any(),
                  isEqualTo: any(named: 'isEqualTo')))
              .thenReturn(mockChatQuery);
          when(() => mockChatQuery.getAll())
              .thenAnswer((_) async => [chatEvent]);
          when(() => mockMessageRepo.upsert(any(),
                  needSync: any(named: 'needSync')))
              .thenAnswer((_) async => {});
          when(() =>
                  mockChatRepo.upsert(any(), needSync: any(named: 'needSync')))
              .thenAnswer((_) async => {});

          await service.sendMessage(chatId: 'chat1', text: 'Hello');

          verify(() => mockMessageRepo.upsert(any(), needSync: true)).called(1);
          verify(() => mockChatRepo.upsert(any(), needSync: true)).called(1);
        });

        test('sendMessage does nothing for empty text', () async {
          service.authenticatedUser =
              UserModel(username: 'testuser', avatarUrl: null);

          await service.sendMessage(chatId: 'chat1', text: '');

          verifyNever(() =>
              mockMessageRepo.upsert(any(), needSync: any(named: 'needSync')));
        });

        test('sendMessage throws when user not authenticated', () async {
          service.authenticatedUser = null;

          await expectLater(
            service.sendMessage(chatId: 'chat1', text: 'Hello'),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('User not authenticated'),
              ),
            ),
          );
        });

        test('getMessages returns messages with pagination', () async {
          final mockQuery = MockLocalFirstQuery<MessageModel>();
          final msg = MessageModel(
            id: 'msg1',
            chatId: 'chat1',
            senderId: 'user1',
            text: 'Hello',
          );
          final msgEvent = LocalFirstEvent.createNewInsertEvent<MessageModel>(
            repository: mockMessageRepo,
            needSync: false,
            data: msg,
          );

          when(() => mockMessageRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo')))
              .thenReturn(mockQuery);
          when(() =>
                  mockQuery.orderBy(any(), descending: any(named: 'descending')))
              .thenReturn(mockQuery);
          when(() => mockQuery.startAfter(any())).thenReturn(mockQuery);
          when(() => mockQuery.limitTo(any())).thenReturn(mockQuery);
          when(() => mockQuery.getAll()).thenAnswer((_) async => [msgEvent]);

          final messages =
              await service.getMessages('chat1', limit: 10, offset: 0);

          expect(messages.length, 1);
          expect(messages.first.text, 'Hello');
        });

        test('watchMessages returns stream of messages', () {
          final mockQuery = MockLocalFirstQuery<MessageModel>();
          final streamController =
              StreamController<List<LocalFirstEvent<MessageModel>>>();

          when(() => mockMessageRepo.query()).thenReturn(mockQuery);
          when(() =>
                  mockQuery.where(any(), isEqualTo: any(named: 'isEqualTo')))
              .thenReturn(mockQuery);
          when(() =>
                  mockQuery.orderBy(any(), descending: any(named: 'descending')))
              .thenReturn(mockQuery);
          when(() => mockQuery.watch())
              .thenAnswer((_) => streamController.stream);

          final stream = service.watchMessages('chat1');

          expect(stream, isA<Stream<List<MessageModel>>>());

          streamController.close();
        });
      });

      group('connection state', () {
        test('connectionState returns stream from webSocketStrategy', () {
          final streamController = StreamController<bool>();
          when(() => mockWsStrategy.connectionChanges)
              .thenAnswer((_) => streamController.stream);

          final stream = service.connectionState;

          expect(stream, isA<Stream<bool>>());

          streamController.close();
        });

        test('isConnected returns value from webSocketStrategy', () {
          when(() => mockWsStrategy.latestConnectionState).thenReturn(true);

          expect(service.isConnected, true);

          when(() => mockWsStrategy.latestConnectionState).thenReturn(false);

          expect(service.isConnected, false);
        });

        test('isConnected handles null state', () {
          when(() => mockWsStrategy.latestConnectionState).thenReturn(null);

          expect(service.isConnected, false);
        });
      });

      test('namespace returns current namespace', () {
        expect(service.namespace, 'default');
      });

      test('setCurrentOpenChat sets chat id', () {
        service.setCurrentOpenChat('chat1');
        // No direct way to verify, but should not throw

        service.setCurrentOpenChat(null);
        // Should allow null
      });
    });

    group('private methods via TestHelper', () {
      late MockUserRepository mockUserRepo;
      late MockChatRepository mockChatRepo;
      late MockMessageRepository mockMessageRepo;
      late MockWebSocketStrategy mockWsStrategy;
      late MockPeriodicStrategy mockPeriodicStrategy;
      late MockHttpClient mockHttpClient;
      late MockNavigatorService mockNavigatorService;
      late MockLocalFirstStorage mockStorage;
      late MockLocalFirstClient mockClient;
      late RepositoryService service;
      late TestRepositoryServiceHelper helper;

      setUp(() {
        mockUserRepo = MockUserRepository();
        mockChatRepo = MockChatRepository();
        mockMessageRepo = MockMessageRepository();
        mockWsStrategy = MockWebSocketStrategy();
        mockPeriodicStrategy = MockPeriodicStrategy();
        mockHttpClient = MockHttpClient();
        mockNavigatorService = MockNavigatorService();
        mockStorage = MockLocalFirstStorage();
        mockClient = MockLocalFirstClient();

        when(() => mockUserRepo.idFieldName).thenReturn('id');
        when(() => mockUserRepo.name).thenReturn('user');
        when(() => mockChatRepo.idFieldName).thenReturn('id');
        when(() => mockChatRepo.name).thenReturn('chat');
        when(() => mockMessageRepo.idFieldName).thenReturn('id');
        when(() => mockMessageRepo.name).thenReturn('message');

        when(() => mockClient.localStorage).thenReturn(mockStorage);
        when(() => mockClient.initialize()).thenAnswer((_) async => {});
        when(() => mockClient.startAllStrategies()).thenAnswer((_) async => {});
        when(() => mockClient.stopAllStrategies()).thenReturn(null);

        when(() => mockStorage.useNamespace(any())).thenAnswer((_) async => {});

        service = RepositoryService.test(
          userRepo: mockUserRepo,
          chatRepo: mockChatRepo,
          messageRepo: mockMessageRepo,
          wsStrategy: mockWsStrategy,
          periodicStrat: mockPeriodicStrategy,
          httpClient: mockHttpClient,
          navigator: mockNavigatorService,
        );

        helper = TestRepositoryServiceHelper(service);
      });

      group('_sanitizeNamespace', () {
        test('returns default for empty string', () {
          expect(helper.sanitizeNamespace(''), 'default');
        });

        test('converts to lowercase and adds prefix', () {
          expect(helper.sanitizeNamespace('TestUser'), 'user_testuser');
        });

        test('replaces special characters with underscore', () {
          expect(helper.sanitizeNamespace('user@test.com'), 'user_user_test_com');
        });

        test('replaces spaces with underscore', () {
          expect(helper.sanitizeNamespace('test user'), 'user_test_user');
        });

        test('keeps valid characters', () {
          expect(helper.sanitizeNamespace('user_123'), 'user_user_123');
        });
      });

      group('_usersFromEvents', () {
        test('filters and maps state events to users', () {
          final user1 = UserModel(username: 'user1', avatarUrl: null);
          final user2 = UserModel(username: 'user2', avatarUrl: null);

          final event1 = LocalFirstEvent.createNewInsertEvent<UserModel>(
            repository: mockUserRepo,
            needSync: false,
            data: user1,
          );

          final event2 = LocalFirstEvent.createNewInsertEvent<UserModel>(
            repository: mockUserRepo,
            needSync: false,
            data: user2,
          );

          final deleteEvent = LocalFirstEvent.createNewDeleteEvent<UserModel>(
            repository: mockUserRepo,
            needSync: false,
            dataId: 'deleted',
          );

          final users = helper.usersFromEvents([event1, event2, deleteEvent]);

          expect(users.length, 2);
          expect(users[0].username, 'user1');
          expect(users[1].username, 'user2');
        });

        test('returns empty list for no state events', () {
          final deleteEvent = LocalFirstEvent.createNewDeleteEvent<UserModel>(
            repository: mockUserRepo,
            needSync: false,
            dataId: 'deleted',
          );

          final users = helper.usersFromEvents([deleteEvent]);

          expect(users, isEmpty);
        });
      });

      group('_chatsFromEvents', () {
        test('filters and maps state events to chats', () {
          final chat1 =
              ChatModel(id: 'chat1', name: 'Chat 1', createdBy: 'user1');
          final chat2 =
              ChatModel(id: 'chat2', name: 'Chat 2', createdBy: 'user2');

          final event1 = LocalFirstEvent.createNewInsertEvent<ChatModel>(
            repository: mockChatRepo,
            needSync: false,
            data: chat1,
          );

          final event2 = LocalFirstEvent.createNewInsertEvent<ChatModel>(
            repository: mockChatRepo,
            needSync: false,
            data: chat2,
          );

          final chats = helper.chatsFromEvents([event1, event2]);

          expect(chats.length, 2);
          expect(chats[0].name, 'Chat 1');
          expect(chats[1].name, 'Chat 2');
        });
      });

      group('_messagesFromEvents', () {
        test('filters and maps state events to messages', () {
          final msg1 = MessageModel(
            id: 'msg1',
            chatId: 'chat1',
            senderId: 'user1',
            text: 'Hello',
          );
          final msg2 = MessageModel(
            id: 'msg2',
            chatId: 'chat1',
            senderId: 'user2',
            text: 'Hi',
          );

          final event1 = LocalFirstEvent.createNewInsertEvent<MessageModel>(
            repository: mockMessageRepo,
            needSync: false,
            data: msg1,
          );

          final event2 = LocalFirstEvent.createNewInsertEvent<MessageModel>(
            repository: mockMessageRepo,
            needSync: false,
            data: msg2,
          );

          final messages = helper.messagesFromEvents([event1, event2]);

          expect(messages.length, 2);
          expect(messages[0].text, 'Hello');
          expect(messages[1].text, 'Hi');
        });
      });

      group('_fetchRemoteUser', () {
        test('returns user when found on server', () async {
          final existingUser =
              UserModel(username: 'existinguser', avatarUrl: 'https://example.com');

          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(200);
          when(() => mockResponse.body).thenReturn(jsonEncode({
            'event': {
              'data': existingUser.toJson(),
            }
          }));
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          final result = await helper.fetchRemoteUser('existinguser');

          expect(result, isNotNull);
          expect(result?.username, 'existinguser');
          expect(result?.avatarUrl, 'https://example.com');
        });

        test('returns null for 404 response', () async {
          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(404);
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          final result = await helper.fetchRemoteUser('nonexistent');

          expect(result, isNull);
        });

        test('throws exception for non-200/404 status code', () async {
          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(500);
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          await expectLater(
            helper.fetchRemoteUser('testuser'),
            throwsA(isA<Exception>()),
          );
        });

        test('throws exception on network error', () async {
          when(() => mockHttpClient.get(any()))
              .thenThrow(Exception('Network error'));

          await expectLater(
            helper.fetchRemoteUser('testuser'),
            throwsA(isA<Exception>()),
          );
        });
      });

      group('_fetchEvents', () {
        test('fetches events without filter', () async {
          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(200);
          when(() => mockResponse.bodyBytes).thenReturn(utf8.encode(jsonEncode({
            'events': [
              {'id': '1', 'data': {'name': 'Chat 1'}},
              {'id': '2', 'data': {'name': 'Chat 2'}},
            ],
          })));
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          final events = await helper.fetchEvents('chat');

          expect(events.length, 2);
          expect(events[0]['id'], '1');
          expect(events[1]['id'], '2');
        });

        test('returns empty list on HTTP error', () async {
          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(500);
          when(() => mockHttpClient.get(any()))
              .thenAnswer((_) async => mockResponse);

          final events = await helper.fetchEvents('chat');

          expect(events, isEmpty);
        });

        test('returns empty list on exception', () async {
          when(() => mockHttpClient.get(any()))
              .thenThrow(Exception('Network error'));

          final events = await helper.fetchEvents('chat');

          expect(events, isEmpty);
        });
      });

      group('_pushEvents', () {
        test('returns true for empty events list', () async {
          final result = await helper.pushEvents('chat', []);

          expect(result, true);
        });

        test('returns false on HTTP error', () async {
          final chat = ChatModel(
            id: 'chat1',
            name: 'Test',
            createdBy: 'user1',
          );

          when(() => mockChatRepo.toJson(any())).thenReturn(chat.toJson());
          when(() => mockChatRepo.getId(any())).thenReturn(chat.id);

          final event = LocalFirstEvent.createNewInsertEvent<ChatModel>(
            repository: mockChatRepo,
            needSync: true,
            data: chat,
          );

          final mockResponse = MockResponse();
          when(() => mockResponse.statusCode).thenReturn(500);
          when(() => mockHttpClient.post(
                any(),
                headers: any(named: 'headers'),
                body: any(named: 'body'),
              )).thenAnswer((_) => Future.value(mockResponse));

          final result = await helper.pushEvents('chat', [event]);

          expect(result, false);
        });

        test('returns false on exception', () async {
          final chat = ChatModel(
            id: 'chat1',
            name: 'Test',
            createdBy: 'user1',
          );

          when(() => mockChatRepo.toJson(any())).thenReturn(chat.toJson());
          when(() => mockChatRepo.getId(any())).thenReturn(chat.id);

          final event = LocalFirstEvent.createNewInsertEvent<ChatModel>(
            repository: mockChatRepo,
            needSync: true,
            data: chat,
          );

          when(() => mockHttpClient.post(
                any(),
                headers: any(named: 'headers'),
                body: any(named: 'body'),
              )).thenThrow(Exception('Network error'));

          final result = await helper.pushEvents('chat', [event]);

          expect(result, false);
        });
      });

      group('_switchUserDatabase', () {
        test('switches to user namespace', () async {
          service.localFirst = mockClient;

          // Mock config operations for hidden chats
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');

          await helper.switchUserDatabase('testuser');

          verify(() => mockStorage.useNamespace('user_testuser')).called(1);
        });

        test('does nothing when namespace already matches', () async {
          service.localFirst = mockClient;

          // Mock config operations for hidden chats
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');

          await helper.switchUserDatabase('testuser');
          clearInteractions(mockStorage);

          await helper.switchUserDatabase('testuser');

          verifyNever(() => mockStorage.useNamespace(any()));
        });

        test('handles empty userId as default', () async {
          service.localFirst = mockClient;

          // Mock config operations for hidden chats
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');

          // First switch to a different namespace
          await helper.switchUserDatabase('testuser');
          clearInteractions(mockStorage);

          // Now switch back to default with empty string
          await helper.switchUserDatabase('');

          verify(() => mockStorage.useNamespace('default')).called(1);
        });
      });

      group('_buildSyncFilter', () {
        test('returns null when sync state manager is null', () async {
          final result = await helper.buildSyncFilter('chat');
          expect(result, isNull);
        });

        test('returns null when initialized with no previous sync', () async {
          service.localFirst = mockClient;

          // Mock getConfigValue for initialize() restoreLastUser call
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => null);

          await service.initialize();

          final result = await helper.buildSyncFilter('chat');

          // With fresh initialization, sync manager exists but has no sequences
          expect(result, isNull);
        });
      });

      group('_onSyncCompleted', () {
        test('does nothing when sync state manager is null', () async {
          await helper.onSyncCompleted('chat', []);
          // Should complete without error
          expect(true, true);
        });

        test('does nothing when events list is empty', () async {
          service.localFirst = mockClient;

          // Mock getConfigValue for initialize() restoreLastUser call
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => null);

          await service.initialize();

          await helper.onSyncCompleted('chat', []);
          // Should complete without error
          expect(true, true);
        });

        test('completes when events have data', () async {
          service.localFirst = mockClient;

          // Mock getConfigValue for initialize() restoreLastUser call
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => null);

          await service.initialize();

          final events = [
            {'sequence': 10},
            {'sequence': 20},
            {'sequence': 15},
          ];

          // We can't easily inject the sync manager, but we can verify the method completes
          await helper.onSyncCompleted('chat', events);
          expect(true, true);
        });
      });

      group('_withGlobalString', () {
        test('executes action when storage is null', () async {
          final serviceWithoutStorage = RepositoryService.test(
            userRepo: mockUserRepo,
            chatRepo: mockChatRepo,
            messageRepo: mockMessageRepo,
            wsStrategy: mockWsStrategy,
            periodicStrat: mockPeriodicStrategy,
            httpClient: mockHttpClient,
            navigator: mockNavigatorService,
          );

          serviceWithoutStorage.localFirst = null;

          final helperWithoutStorage =
              TestRepositoryServiceHelper(serviceWithoutStorage);

          var executed = false;
          final result = await helperWithoutStorage.withGlobalString(() async {
            executed = true;
            return 'test-result';
          });

          expect(executed, true);
          expect(result, 'test-result');
        });

        test('switches to default namespace and back', () async {
          service.localFirst = mockClient;

          when(() => mockStorage.useNamespace('default'))
              .thenAnswer((_) async => {});
          when(() => mockStorage.useNamespace('user_testuser'))
              .thenAnswer((_) async => {});

          // Mock config operations for hidden chats
          when(() => mockClient.getConfigValue(any()))
              .thenAnswer((_) async => '');

          // First switch to a user namespace
          await helper.switchUserDatabase('testuser');
          clearInteractions(mockStorage);

          // Execute withGlobalString which should switch to default and back
          await helper.withGlobalString(() async => 'result');

          verify(() => mockStorage.useNamespace('default')).called(1);
          verify(() => mockStorage.useNamespace('user_testuser')).called(1);
        });
      });

      group('TestHelper getters', () {
        test('currentNamespace getter returns namespace', () {
          expect(helper.currentNamespace, 'default');
        });

        test('syncStateManager getter returns null initially', () {
          expect(helper.syncStateManager, isNull);
        });

        test('readStateManager getter returns null initially', () {
          expect(helper.readStateManager, isNull);
        });

        test('currentOpenChatId getter returns null initially', () {
          expect(helper.currentOpenChatId, isNull);
        });

        test('hiddenChatIds getter returns empty set initially', () {
          expect(helper.hiddenChatIds, isEmpty);
        });

        test('isChatHidden returns false for non-hidden chat', () {
          expect(helper.isChatHidden('chat1'), false);
        });

        test('persistLastUsername sets global string', () async {
          service.localFirst = mockClient;

          when(() => mockClient.setConfigValue(any(), any()))
              .thenAnswer((_) async => true);

          await helper.persistLastUsername('testuser');

          verify(() =>
                  mockClient.setConfigValue('__last_username__', 'testuser'))
              .called(1);
        });

        test('getGlobalString retrieves value', () async {
          service.localFirst = mockClient;

          when(() => mockClient.getConfigValue('test_key'))
              .thenAnswer((_) async => 'test_value');

          final value = await helper.getGlobalString('test_key');

          expect(value, 'test_value');
        });

        test('getGlobalString returns null when client is null', () async {
          service.localFirst = null;

          final value = await helper.getGlobalString('test_key');

          expect(value, isNull);
        });

        test('setGlobalString sets value', () async {
          service.localFirst = mockClient;

          when(() => mockClient.setConfigValue('test_key', 'test_value'))
              .thenAnswer((_) async => true);

          await helper.setGlobalString('test_key', 'test_value');

          verify(() => mockClient.setConfigValue('test_key', 'test_value'))
              .called(1);
        });

        test('setGlobalString does nothing when client is null', () async {
          service.localFirst = null;

          await helper.setGlobalString('test_key', 'test_value');

          // Should complete without error
          expect(true, true);
        });
      });
    });
  });

  group('Model operations', () {
    tearDown(() {
      RepositoryService.instance = null;
    });

    group('ChatModel operations', () {
      test('ChatModel factory creates with UUID V7', () {
        final chat = ChatModel(
          name: 'Test Chat',
          createdBy: 'testuser',
        );

        // UUID V7 has 36 characters with hyphens
        expect(chat.id.length, 36);
        expect(chat.id.contains('-'), true);
      });

      test('ChatModel isClosed returns correct value', () {
        final openChat = ChatModel(
          name: 'Open Chat',
          createdBy: 'user1',
        );

        final closedChat = ChatModel(
          name: 'Closed Chat',
          createdBy: 'user1',
          closedBy: 'admin',
        );

        expect(openChat.isClosed, false);
        expect(closedChat.isClosed, true);
      });
    });

    group('MessageModel operations', () {
      test('MessageModel factory creates with UUID V7', () {
        final message = MessageModel(
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Hello',
        );

        // UUID V7 has 36 characters with hyphens
        expect(message.id.length, 36);
        expect(message.id.contains('-'), true);
      });

      test('MessageModel.system creates system message', () {
        final message = MessageModel.system(
          chatId: 'chat1',
          text: 'Chat closed',
        );

        expect(message.isSystemMessage, true);
        expect(message.senderId, MessageModel.systemSenderId);
        expect(message.senderId, '_system_');
      });
    });
  });

  group('Conflict resolution', () {
    group('UserModel conflict resolution', () {
      test('prefers local when local is newer', () {
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localUser = UserModel(
          username: 'testuser',
          avatarUrl: 'https://local.com',
          updatedAt: newTime,
        );

        final remoteUser = UserModel(
          username: 'testuser',
          avatarUrl: 'https://remote.com',
          updatedAt: oldTime,
        );

        final result = UserModel.resolveConflict(localUser, remoteUser);

        expect(result.avatarUrl, 'https://local.com');
      });

      test('prefers remote when remote is newer', () {
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localUser = UserModel(
          username: 'testuser',
          avatarUrl: 'https://local.com',
          updatedAt: oldTime,
        );

        final remoteUser = UserModel(
          username: 'testuser',
          avatarUrl: 'https://remote.com',
          updatedAt: newTime,
        );

        final result = UserModel.resolveConflict(localUser, remoteUser);

        expect(result.avatarUrl, 'https://remote.com');
      });

      test('merges non-null avatar from older version', () {
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localUser = UserModel(
          username: 'testuser',
          avatarUrl: null,
          updatedAt: newTime,
        );

        final remoteUser = UserModel(
          username: 'testuser',
          avatarUrl: 'https://remote.com',
          updatedAt: oldTime,
        );

        final result = UserModel.resolveConflict(localUser, remoteUser);

        expect(result.avatarUrl, 'https://remote.com');
      });
    });

    group('ChatModel conflict resolution', () {
      test('prefers local when local is newer', () {
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localChat = ChatModel(
          id: 'chat1',
          name: 'Local Chat',
          createdBy: 'user1',
          updatedAt: newTime,
        );

        final remoteChat = ChatModel(
          id: 'chat1',
          name: 'Remote Chat',
          createdBy: 'user1',
          updatedAt: oldTime,
        );

        final result = ChatModel.resolveConflict(localChat, remoteChat);

        expect(result.name, 'Local Chat');
      });

      test('merges lastMessageAt taking later timestamp', () {
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);
        final laterMsgTime = DateTime.utc(2025, 1, 1, 14, 0);

        final localChat = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newTime,
          lastMessageAt: oldTime,
          lastMessageText: 'Old',
        );

        final remoteChat = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: oldTime,
          lastMessageAt: laterMsgTime,
          lastMessageText: 'New',
        );

        final result = ChatModel.resolveConflict(localChat, remoteChat);

        expect(result.lastMessageAt, laterMsgTime);
        expect(result.lastMessageText, 'New');
      });

      test('preserves closedBy once set', () {
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localChat = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newTime,
          closedBy: null,
        );

        final remoteChat = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: oldTime,
          closedBy: 'admin',
        );

        final result = ChatModel.resolveConflict(localChat, remoteChat);

        expect(result.closedBy, 'admin');
      });

      test('merges avatar from fallback', () {
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localChat = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newTime,
          avatarUrl: null,
        );

        final remoteChat = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: oldTime,
          avatarUrl: 'https://avatar.com',
        );

        final result = ChatModel.resolveConflict(localChat, remoteChat);

        expect(result.avatarUrl, 'https://avatar.com');
      });
    });

    group('MessageModel conflict resolution', () {
      test('prefers local when local is newer', () {
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Local',
          updatedAt: newTime,
        );

        final remoteMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Remote',
          updatedAt: oldTime,
        );

        final result = MessageModel.resolveConflict(localMsg, remoteMsg);

        expect(result.text, 'Local');
      });

      test('prefers remote when timestamps equal', () {
        final sameTime = DateTime.utc(2025, 1, 1, 12, 0);

        final localMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Local',
          updatedAt: sameTime,
        );

        final remoteMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Remote',
          updatedAt: sameTime,
        );

        final result = MessageModel.resolveConflict(localMsg, remoteMsg);

        expect(result.text, 'Remote');
      });
    });
  });
}
