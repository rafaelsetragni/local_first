# WebSocket Server Tests

Integration tests for the hybrid WebSocket + REST API server.

## Prerequisites

The tests require a running MongoDB instance. The easiest way is to use Docker Compose:

```bash
# Start MongoDB + WebSocket server (from monorepo root)
melos websocket:server
```

Or start just MongoDB:

```bash
docker run -d --name local_first_mongodb -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
```

## Running Tests

### Run all tests

```bash
cd server
dart test
```

### Run with coverage

```bash
cd server
dart test --coverage=coverage
dart pub global activate coverage
dart pub global run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --report-on=lib
```

### Run specific test group

```bash
dart test --name "REST API"
dart test --name "WebSocket"
dart test --name "Integration"
```

### Run with verbose output

```bash
dart test --reporter expanded
```

## Test Coverage

The test suite covers:

### REST API Endpoints
- ✅ Health check (`GET /api/health`)
- ✅ List repositories (`GET /api/repositories`)
- ✅ Create single event (`POST /api/events/{repository}`)
- ✅ Create batch events (`POST /api/events/{repository}/batch`)
- ✅ Get all events (`GET /api/events/{repository}`)
- ✅ Get events by sequence (`GET /api/events/{repository}?afterSequence={n}`)
- ✅ Get specific event (`GET /api/events/{repository}/{eventId}`)

### Error Handling
- ✅ Missing required fields (400)
- ✅ Invalid endpoints (404)
- ✅ Wrong HTTP methods (405)
- ✅ Proper error messages

### Features
- ✅ CORS headers
- ✅ Idempotency (duplicate events)
- ✅ Server sequence assignment
- ✅ Sequential ordering

### WebSocket Protocol
- ✅ Connection establishment
- ✅ Authentication
- ✅ Ping/pong heartbeat
- ✅ Event broadcasting (integration with REST)

## Test Structure

```
test/
├── README.md                      # This file
└── websocket_server_test.dart    # Main test file
```

Each test group follows this pattern:
1. **Setup** - Create test data
2. **Execute** - Call API endpoint or WebSocket action
3. **Assert** - Verify response and behavior
4. **Cleanup** - Automatic via tearDown

## Troubleshooting

### "MongoDB container not found"

Start MongoDB:
```bash
melos websocket:server
# Or directly:
docker run -d --name local_first_mongodb -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
```

### "Server failed to start"

Check if port 8080 is available:
```bash
lsof -i :8080
```

Kill any process using the port:
```bash
kill -9 <PID>
```

### Tests hang or timeout

- Check MongoDB is accessible: `docker ps | grep mongo`
- Check server logs: `docker compose logs websocket_server`
- Increase timeout in test code if needed

### Clean test data

Test data is automatically cleaned up, but you can manually clean:
```bash
docker exec local_first_mongodb mongosh \
  -u admin -p admin --authenticationDatabase admin \
  remote_counter_db \
  --eval "db.test_users.drop(); db.test_sequence.drop();"
```

## Continuous Integration

To run tests in CI:

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      mongodb:
        image: mongo:7
        ports:
          - 27017:27017
        env:
          MONGO_INITDB_ROOT_USERNAME: admin
          MONGO_INITDB_ROOT_PASSWORD: admin
    steps:
      - uses: actions/checkout@v3
      - uses: dart-lang/setup-dart@v1
      - run: cd server && dart pub get
      - run: cd server && dart test
```

## Writing New Tests

Example test structure:

```dart
test('Description of what is being tested', () async {
  // Setup: Prepare test data
  final testEvent = {
    'eventId': 'test_${DateTime.now().millisecondsSinceEpoch}',
    'data': 'test data',
  };

  // Execute: Call the API
  final response = await http.post(
    Uri.parse('$baseUrl/api/events/test_repo'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(testEvent),
  );

  // Assert: Verify behavior
  expect(response.statusCode, 201);
  final data = jsonDecode(response.body);
  expect(data['status'], 'success');

  // Cleanup is automatic via tearDown
});
```

## Performance Tests

To add performance tests:

```dart
test('Performance: Create 1000 events', () async {
  final stopwatch = Stopwatch()..start();

  for (var i = 0; i < 1000; i++) {
    await http.post(
      Uri.parse('$baseUrl/api/events/perf_test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'eventId': 'perf_$i'}),
    );
  }

  stopwatch.stop();
  print('Created 1000 events in ${stopwatch.elapsedMilliseconds}ms');
  expect(stopwatch.elapsedMilliseconds, lessThan(10000)); // < 10s
});
```

## Test Reports

Generate HTML test report:

```bash
dart test --reporter json > test_results.json
dart pub global activate test_report_generator
dart pub global run test_report_generator test_results.json
```
