# REST API Documentation

The WebSocket Sync Server also provides a REST API for HTTP clients. All endpoints use server sequence numbers for synchronization.

## Base URL

```
http://localhost:8080/api
```

## Endpoints

### Health Check

Check server status and database connectivity.

**Request:**
```http
GET /api/health
```

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2025-01-25T20:00:00.000Z",
  "mongodb": "connected",
  "activeConnections": 3
}
```

---

### List Repositories

Get all available repositories with statistics.

**Request:**
```http
GET /api/repositories
```

**Response:**
```json
{
  "repositories": [
    {
      "name": "user",
      "eventCount": 15,
      "maxSequence": 15
    },
    {
      "name": "counter_log",
      "eventCount": 89,
      "maxSequence": 89
    },
    {
      "name": "session_counter",
      "eventCount": 42,
      "maxSequence": 42
    }
  ],
  "count": 3
}
```

---

### Get Events

Fetch events from a repository, optionally after a specific sequence number.

**Request:**
```http
GET /api/events/{repository}?afterSequence={n}&limit={m}
```

**Parameters:**
- `repository` (path, required) - Repository name (e.g., "user", "counter_log")
- `afterSequence` (query, optional) - Return only events with serverSequence > this value
- `limit` (query, optional) - Maximum number of events to return (default: 100)

**Examples:**

Get all events from "user" repository:
```bash
curl http://localhost:8080/api/events/user
```

Get events after sequence 42:
```bash
curl http://localhost:8080/api/events/user?afterSequence=42
```

Get up to 10 events:
```bash
curl http://localhost:8080/api/events/user?afterSequence=42&limit=10
```

**Response:**
```json
{
  "repository": "user",
  "events": [
    {
      "eventId": "evt_alice_1737629400000",
      "serverSequence": 15,
      "id": "alice",
      "username": "Alice",
      "avatarUrl": "https://...",
      "createdAt": "2025-01-23T10:00:00Z",
      "updatedAt": "2025-01-23T10:05:00Z"
    }
  ],
  "count": 1,
  "hasMore": false
}
```

---

### Get Event by ID

Fetch a specific event by its eventId.

**Request:**
```http
GET /api/events/{repository}/{eventId}
```

**Parameters:**
- `repository` (path, required) - Repository name
- `eventId` (path, required) - Event identifier

**Example:**
```bash
curl http://localhost:8080/api/events/user/evt_alice_1737629400000
```

**Response:**
```json
{
  "repository": "user",
  "event": {
    "eventId": "evt_alice_1737629400000",
    "serverSequence": 15,
    "id": "alice",
    "username": "Alice",
    "avatarUrl": "https://...",
    "createdAt": "2025-01-23T10:00:00Z",
    "updatedAt": "2025-01-23T10:05:00Z"
  }
}
```

**Error Response (404):**
```json
{
  "error": "Event not found",
  "statusCode": 404
}
```

---

### Create Event

Create a single event in a repository.

**Request:**
```http
POST /api/events/{repository}
Content-Type: application/json

{
  "eventId": "evt_bob_1737629500000",
  "id": "bob",
  "username": "Bob",
  "avatarUrl": "https://...",
  "createdAt": "2025-01-23T10:10:00Z",
  "updatedAt": "2025-01-23T10:10:00Z"
}
```

**Parameters:**
- `repository` (path, required) - Repository name
- `eventId` (body, required) - Unique event identifier
- Additional fields depend on your data model

**Example:**
```bash
curl -X POST http://localhost:8080/api/events/user \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "evt_bob_1737629500000",
    "id": "bob",
    "username": "Bob",
    "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Bob"
  }'
```

**Response:**
```json
{
  "status": "success",
  "repository": "user",
  "eventId": "evt_bob_1737629500000"
}
```

**Notes:**
- The server automatically assigns a `serverSequence` number
- If an event with the same `eventId` already exists, it returns the existing event (idempotent)
- The event is broadcasted to all connected WebSocket clients

---

### Create Events Batch

Create multiple events at once.

**Request:**
```http
POST /api/events/{repository}/batch
Content-Type: application/json

{
  "events": [
    {
      "eventId": "evt_carol_1",
      "id": "carol",
      "username": "Carol"
    },
    {
      "eventId": "evt_dave_2",
      "id": "dave",
      "username": "Dave"
    }
  ]
}
```

**Parameters:**
- `repository` (path, required) - Repository name
- `events` (body, required) - Array of event objects, each must have `eventId`

**Example:**
```bash
curl -X POST http://localhost:8080/api/events/user/batch \
  -H "Content-Type: application/json" \
  -d '{
    "events": [
      {
        "eventId": "evt_carol_1737629600000",
        "id": "carol",
        "username": "Carol",
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Carol"
      },
      {
        "eventId": "evt_dave_1737629700000",
        "id": "dave",
        "username": "Dave",
        "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=Dave"
      }
    ]
  }'
```

**Response:**
```json
{
  "status": "success",
  "repository": "user",
  "eventIds": [
    "evt_carol_1737629600000",
    "evt_dave_1737629700000"
  ],
  "count": 2
}
```

---

## Error Responses

All errors follow this format:

```json
{
  "error": "Error message description",
  "statusCode": 400
}
```

### Common Status Codes

- `200 OK` - Request successful
- `201 Created` - Event(s) created successfully
- `400 Bad Request` - Invalid request body or missing required fields
- `404 Not Found` - Resource not found
- `405 Method Not Allowed` - HTTP method not supported for this endpoint
- `500 Internal Server Error` - Server error
- `503 Service Unavailable` - Database not connected

---

## CORS

All endpoints support CORS with the following headers:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type, Authorization`

---

## Synchronization Strategy

The REST API uses the same **server sequence-based synchronization** as the WebSocket protocol:

1. **Server assigns sequences**: Each event gets a unique `serverSequence` number per repository
2. **Client tracks last sequence**: Store the highest `serverSequence` seen
3. **Incremental sync**: Request events using `afterSequence` parameter
4. **No time drift issues**: No need for synchronized clocks between client and server

### Example Sync Flow

1. **Initial sync** - Get all events:
   ```bash
   curl http://localhost:8080/api/events/user
   # Response includes events with serverSequence: 1, 2, 3, ..., 15
   # Client stores maxSequence = 15
   ```

2. **Incremental sync** - Get new events:
   ```bash
   curl http://localhost:8080/api/events/user?afterSequence=15
   # Response includes only events with serverSequence > 15
   # Client updates maxSequence to highest received
   ```

3. **Create event** - Push new data:
   ```bash
   curl -X POST http://localhost:8080/api/events/user \
     -H "Content-Type: application/json" \
     -d '{"eventId": "evt_new", "id": "user1", "username": "User1"}'
   # Server assigns serverSequence = 16
   ```

---

## Usage Examples

### JavaScript/TypeScript (fetch)

```typescript
// Health check
const health = await fetch('http://localhost:8080/api/health');
const healthData = await health.json();
console.log(healthData);

// Get events after sequence 42
const events = await fetch('http://localhost:8080/api/events/user?afterSequence=42');
const eventsData = await events.json();
console.log(eventsData.events);

// Create an event
const response = await fetch('http://localhost:8080/api/events/user', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    eventId: 'evt_' + Date.now(),
    id: 'alice',
    username: 'Alice',
    avatarUrl: 'https://api.dicebear.com/7.x/avataaars/svg?seed=Alice'
  })
});
const result = await response.json();
console.log(result);
```

### Dart (http package)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

// Health check
final healthResponse = await http.get(
  Uri.parse('http://localhost:8080/api/health'),
);
final health = jsonDecode(healthResponse.body);
print(health);

// Get events after sequence 42
final eventsResponse = await http.get(
  Uri.parse('http://localhost:8080/api/events/user?afterSequence=42'),
);
final eventsData = jsonDecode(eventsResponse.body);
print(eventsData['events']);

// Create an event
final createResponse = await http.post(
  Uri.parse('http://localhost:8080/api/events/user'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'eventId': 'evt_${DateTime.now().millisecondsSinceEpoch}',
    'id': 'alice',
    'username': 'Alice',
    'avatarUrl': 'https://api.dicebear.com/7.x/avataaars/svg?seed=Alice',
  }),
);
final result = jsonDecode(createResponse.body);
print(result);
```

### Python (requests)

```python
import requests
import json
import time

# Health check
health = requests.get('http://localhost:8080/api/health')
print(health.json())

# Get events after sequence 42
events = requests.get('http://localhost:8080/api/events/user', params={'afterSequence': 42})
print(events.json()['events'])

# Create an event
event_data = {
    'eventId': f'evt_{int(time.time() * 1000)}',
    'id': 'alice',
    'username': 'Alice',
    'avatarUrl': 'https://api.dicebear.com/7.x/avataaars/svg?seed=Alice'
}
response = requests.post(
    'http://localhost:8080/api/events/user',
    headers={'Content-Type': 'application/json'},
    data=json.dumps(event_data)
)
print(response.json())
```

---

## Testing with curl

### Complete Test Sequence

```bash
# 1. Check server health
curl http://localhost:8080/api/health

# 2. List repositories
curl http://localhost:8080/api/repositories

# 3. Get all events from user repository
curl http://localhost:8080/api/events/user

# 4. Create a new user event
curl -X POST http://localhost:8080/api/events/user \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "evt_test_user_1",
    "id": "testuser",
    "username": "Test User",
    "avatarUrl": "https://api.dicebear.com/7.x/avataaars/svg?seed=TestUser",
    "createdAt": "2025-01-25T20:00:00Z",
    "updatedAt": "2025-01-25T20:00:00Z"
  }'

# 5. Get the newly created event
curl http://localhost:8080/api/events/user/evt_test_user_1

# 6. Get events after a specific sequence
curl "http://localhost:8080/api/events/user?afterSequence=10&limit=5"

# 7. Create multiple events at once
curl -X POST http://localhost:8080/api/events/counter_log/batch \
  -H "Content-Type: application/json" \
  -d '{
    "events": [
      {
        "eventId": "evt_log_1",
        "id": "log_1",
        "username": "alice",
        "sessionId": "sess_alice_123",
        "increment": 1,
        "createdAt": "2025-01-25T20:00:00Z"
      },
      {
        "eventId": "evt_log_2",
        "id": "log_2",
        "username": "alice",
        "sessionId": "sess_alice_123",
        "increment": -1,
        "createdAt": "2025-01-25T20:01:00Z"
      }
    ]
  }'
```

---

## Integration with WebSocket

The REST API and WebSocket protocol work together seamlessly:

1. **REST clients** can push events via POST requests
2. **WebSocket clients** will receive those events in real-time via broadcast
3. Both use the same server sequence numbers for synchronization
4. Both support idempotent operations (duplicate eventId is handled gracefully)

This hybrid approach allows:
- **Web apps** to use REST API for simple request/response patterns
- **Mobile apps** to use WebSocket for real-time bidirectional sync
- **Backend services** to use REST API for batch operations
- All clients stay synchronized through server sequence numbers
