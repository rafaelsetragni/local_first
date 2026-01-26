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
- ✅ Get event by dataId (`GET /api/events/{repository}/byDataId/{dataId}`)

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
- ✅ First event in new repository (ObjectId bug regression test)

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

### Test Determinism

The test suite ensures deterministic behavior by:
- **Dropping the entire test database** before all tests (`setUpAll`)
- Using a separate test database (`remote_counter_db_test`)
- Cleaning up after all tests (`tearDownAll`)

This approach ensures:
- No state leakage between test runs
- Each test suite starts with a completely clean database
- Tests can be run multiple times with consistent results
- Critical bugs (like ObjectId type casting) are reliably detected

### Database Safety Protections

**CRITICAL**: The test suite has multiple layers of protection to prevent accidental production data corruption:

1. **Database Name Validation** (startup):
   - Test DB name MUST be different from production DB name
   - Test DB name MUST contain the word "test"
   - Tests FAIL immediately if validation fails

2. **Runtime Database Verification** (after server start):
   - Queries MongoDB to verify which databases exist
   - Ensures production database is not being used
   - Fails if `remote_counter_db` is found without `remote_counter_db_test`

3. **Environment Variable Isolation**:
   - Server started with explicit `MONGO_DB=remote_counter_db_test`
   - Production database: `remote_counter_db`
   - Test database: `remote_counter_db_test`

**Never disable or bypass these safety checks!**

### CRITICAL: Stop Docker Server Before Running Tests

**IMPORTANT**: If the Docker WebSocket server is running on port 8080, tests may connect to it instead of starting their own test server. This causes tests to use the **PRODUCTION** database!

Before running tests, **ALWAYS**:

```bash
# Stop the Docker server
docker stop local_first_websocket_server

# Then run tests
dart test
```

**Symptoms of this issue:**
- Test collections appear in production database (`remote_counter_db`)
- Collections named `test_*` in production
- Safety check fails with "Production database detected"

**Protection**:
The test suite now includes a port check that will fail if port 8080 is already in use, preventing accidental connection to the production server.

## Regression Tests

### ObjectId Type Cast Bug

The test "Creating first event in new repository initializes sequence counter correctly" specifically guards against a critical bug where MongoDB's automatic ObjectId casting caused failures.

**The Bug:**
- When creating the first event in a new repository, the sequence counter was initialized using `where.eq('_id', repositoryName)`
- MongoDB automatically treats `_id` fields as ObjectIds
- Passing a String repository name caused: `type 'String' is not a subtype of type 'ObjectId?'`

**The Fix:**
- Changed to use `'repository'` field instead of `'_id'` in the sequence counter
- This avoids MongoDB's automatic ObjectId type casting

**Why Tests Didn't Catch It Initially:**
1. Tests only cleaned specific collections, not `_sequence_counters`
2. Once created in the first test, the counter persisted for all subsequent tests
3. The bug only occurred when creating a counter for the first time

**Current Protection:**
- Test database is completely dropped before and after test suite
- Specific test creates events in a unique repository each run
- Ensures the "first time" code path is always tested

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
